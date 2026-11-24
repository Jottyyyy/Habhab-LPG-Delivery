/**
 * Database schema (Drizzle). Rules:
 * - Money is integer centavos (₱ 1.00 = 100).
 * - Every table has id (uuid), created_at, updated_at, created_by, device.
 * - Business rows are never hard-deleted: orders are cancelled, payments rejected, people turned off.
 * - Migrations only ADD tables/columns. Never drop or rewrite business data.
 *
 * Utang balance of a customer (one formula everywhere, see api/_lib/ledger.ts):
 *   opening_balance + Σ total of DELIVERED orders − Σ CONFIRMED payments
 */
import { sql } from "drizzle-orm";
import {
  boolean,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

const ts = (name: string) => timestamp(name, { withTimezone: true, mode: "date" });

/** Columns shared by every table. */
export const baseColumns = () => ({
  id: uuid("id").primaryKey().defaultRandom(),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
  createdBy: uuid("created_by"),
  device: text("device").notNull().default("System"),
});

// ---------------------------------------------------------------- accounts

/** customer = buys gasul in the app; staff = rider/helper; owner = Sir Habhab (everything). */
export const userRole = pgEnum("user_role", ["customer", "staff", "owner"]);

export const users = pgTable(
  "users",
  {
    ...baseColumns(),
    name: text("name").notNull(),
    /** Normalized mobile number "09XXXXXXXXX" — this is the sign-in name. */
    phone: text("phone").notNull(),
    passwordHash: text("password_hash").notNull(),
    role: userRole("role").notNull().default("customer"),
    active: boolean("active").notNull().default(true),
    /** Temporary password (made by the owner or a script): ask for a new one after sign-in. */
    mustChangePassword: boolean("must_change_password").notNull().default(false),
  },
  (t) => [uniqueIndex("users_phone_unique").on(t.phone)],
);

/**
 * Sign-in sessions (one per signed-in phone). `token_hash` is the SHA-256 of the current
 * refresh token; it rotates on every refresh. The previous hash is kept briefly so a phone
 * that lost the refresh response (bad signal) can still recover.
 */
export const sessions = pgTable(
  "sessions",
  {
    ...baseColumns(),
    tokenHash: text("token_hash").notNull(),
    prevTokenHash: text("prev_token_hash"),
    rotatedAt: ts("rotated_at"),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id),
    expiresAt: ts("expires_at").notNull(),
    lastSeenAt: ts("last_seen_at").notNull().defaultNow(),
    revokedAt: ts("revoked_at"),
  },
  (t) => [
    uniqueIndex("sessions_token_hash_unique").on(t.tokenHash),
    index("sessions_prev_token_hash_idx").on(t.prevTokenHash),
    index("sessions_user_idx").on(t.userId),
  ],
);

/** Sign-in and sign-up attempts for rate limiting. `login_key` is the phone (or a marker); IP only as a hash. */
export const loginAttempts = pgTable(
  "login_attempts",
  {
    ...baseColumns(),
    loginKey: text("login_key").notNull(),
    ipHash: text("ip_hash").notNull(),
    success: boolean("success").notNull(),
    at: ts("at").notNull().defaultNow(),
  },
  (t) => [index("login_attempts_key_at_idx").on(t.loginKey, t.at), index("login_attempts_ip_at_idx").on(t.ipHash, t.at)],
);

// ---------------------------------------------------------------- customers (listahan)

export const customers = pgTable(
  "customers",
  {
    ...baseColumns(),
    /** The app account, or null for a walk-in suki the seller added by hand. */
    userId: uuid("user_id").references(() => users.id),
    name: text("name").notNull(),
    phone: text("phone"),
    address: text("address"),
    landmark: text("landmark"),
    lat: doublePrecision("lat"),
    lng: doublePrecision("lng"),
    notes: text("notes"),
    /** Off by default: the owner decides who may order on utang. */
    utangAllowed: boolean("utang_allowed").notNull().default(false),
    /** Max utang balance (centavos); null = no limit. */
    creditLimit: integer("credit_limit"),
    /** Balance carried over from the old paper listahan (centavos). */
    openingBalance: integer("opening_balance").notNull().default(0),
    blocked: boolean("blocked").notNull().default(false),
    /** False once merged into another record (see `merged_into`). */
    active: boolean("active").notNull().default(true),
    mergedInto: uuid("merged_into"),
  },
  (t) => [
    uniqueIndex("customers_user_unique").on(t.userId),
    index("customers_name_idx").on(sql`lower(${t.name})`),
    index("customers_phone_idx").on(t.phone),
  ],
);

// ---------------------------------------------------------------- products

export const productKind = pgEnum("product_kind", ["refill", "new_tank", "accessory", "other"]);

export const products = pgTable("products", {
  ...baseColumns(),
  name: text("name").notNull(),
  kind: productKind("kind").notNull().default("refill"),
  description: text("description"),
  /** Centavos; null = no price yet (cannot be ordered). */
  price: integer("price"),
  /** Full tanks / pieces on hand; null = not counted. */
  stock: integer("stock"),
  /** Shown to customers and in the POS. */
  active: boolean("active").notNull().default(false),
  sort: integer("sort").notNull().default(0),
});

// ---------------------------------------------------------------- orders

export const orderChannel = pgEnum("order_channel", ["app", "walkin"]);
export const orderStatus = pgEnum("order_status", ["pending", "confirmed", "on_the_way", "delivered", "cancelled"]);
export const paymentMethod = pgEnum("payment_method", ["cash", "gcash", "utang"]);

export const orders = pgTable(
  "orders",
  {
    ...baseColumns(),
    /** O-0001 (app order) or W-0001 (walk-in sale). */
    ref: text("ref").notNull(),
    channel: orderChannel("channel").notNull(),
    customerId: uuid("customer_id").references(() => customers.id),
    /** Snapshot for receipts (walk-in sales may have no customer record). */
    customerName: text("customer_name").notNull(),
    customerPhone: text("customer_phone"),
    status: orderStatus("status").notNull().default("pending"),
    paymentMethod: paymentMethod("payment_method").notNull(),
    address: text("address"),
    landmark: text("landmark"),
    lat: doublePrecision("lat"),
    lng: doublePrecision("lng"),
    notes: text("notes"),
    subtotal: integer("subtotal").notNull(),
    deliveryFee: integer("delivery_fee").notNull().default(0),
    total: integer("total").notNull(),
    riderId: uuid("rider_id").references(() => users.id),
    riderLat: doublePrecision("rider_lat"),
    riderLng: doublePrecision("rider_lng"),
    riderLocAt: ts("rider_loc_at"),
    confirmedAt: ts("confirmed_at"),
    outAt: ts("out_at"),
    deliveredAt: ts("delivered_at"),
    cancelledAt: ts("cancelled_at"),
    cancelReason: text("cancel_reason"),
    cancelledBy: uuid("cancelled_by"),
  },
  (t) => [
    uniqueIndex("orders_ref_unique").on(t.ref),
    index("orders_customer_idx").on(t.customerId),
    index("orders_status_idx").on(t.status),
    index("orders_delivered_idx").on(t.deliveredAt),
    index("orders_updated_idx").on(t.updatedAt),
  ],
);

export const orderItems = pgTable(
  "order_items",
  {
    ...baseColumns(),
    orderId: uuid("order_id")
      .notNull()
      .references(() => orders.id),
    productId: uuid("product_id").references(() => products.id),
    /** Name and price at the time of the order. */
    name: text("name").notNull(),
    unitPrice: integer("unit_price").notNull(),
    qty: integer("qty").notNull(),
    lineTotal: integer("line_total").notNull(),
  },
  (t) => [index("order_items_order_idx").on(t.orderId)],
);

// ---------------------------------------------------------------- payments

export const payMethod = pgEnum("pay_method", ["cash", "gcash"]);
export const paymentStatus = pgEnum("payment_status", ["pending", "confirmed", "rejected"]);

/**
 * Money received. Cash recorded by the seller is confirmed at once. GCash sent by a customer
 * stays "pending" until the seller checks it in his GCash app, then becomes confirmed or rejected.
 */
export const payments = pgTable(
  "payments",
  {
    ...baseColumns(),
    /** P-0001 */
    ref: text("ref").notNull(),
    customerId: uuid("customer_id").references(() => customers.id),
    orderId: uuid("order_id").references(() => orders.id),
    amount: integer("amount").notNull(),
    method: payMethod("method").notNull(),
    gcashRef: text("gcash_ref"),
    proofPath: text("proof_path"),
    proofSize: integer("proof_size"),
    status: paymentStatus("status").notNull(),
    note: text("note"),
    reviewedBy: uuid("reviewed_by"),
    reviewedAt: ts("reviewed_at"),
    rejectReason: text("reject_reason"),
  },
  (t) => [
    uniqueIndex("payments_ref_unique").on(t.ref),
    index("payments_customer_idx").on(t.customerId),
    index("payments_order_idx").on(t.orderId),
    index("payments_status_idx").on(t.status),
  ],
);

// ---------------------------------------------------------------- store settings

/** One row (key = "main"). */
export const settings = pgTable("settings", {
  key: text("key").primaryKey(),
  storeName: text("store_name").notNull().default("Habhab LPG Trading"),
  storePhone: text("store_phone"),
  storeAddress: text("store_address"),
  gcashName: text("gcash_name"),
  gcashNumber: text("gcash_number"),
  gcashQrPath: text("gcash_qr_path"),
  deliveryFee: integer("delivery_fee").notNull().default(0),
  isOpen: boolean("is_open").notNull().default(true),
  closedMessage: text("closed_message"),
  apkUrl: text("apk_url"),
  apkVersion: text("apk_version"),
  minAppVersion: text("min_app_version"),
  updatedAt: ts("updated_at").notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

// ---------------------------------------------------------------- refs + audit

/** Gap-free human refs (O-0001, W-0001, P-0001). */
export const refCounters = pgTable("ref_counters", {
  prefix: text("prefix").primaryKey(),
  nextValue: integer("next_value").notNull().default(1),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

/** Who did what and when (orders, payments, prices, settings, accounts). */
export const auditLog = pgTable(
  "audit_log",
  {
    ...baseColumns(),
    actorId: uuid("actor_id"),
    entity: text("entity").notNull(),
    entityId: uuid("entity_id"),
    action: text("action").notNull(),
    summary: text("summary").notNull(),
    before: jsonb("before"),
    after: jsonb("after"),
    at: ts("at").notNull().defaultNow(),
  },
  (t) => [index("audit_at_idx").on(t.at), index("audit_entity_idx").on(t.entity, t.entityId)],
);
