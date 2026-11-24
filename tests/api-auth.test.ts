import { beforeAll, describe, expect, it } from "vitest";
import { call, freshDb, makeStaff, nextIp, signUp, type TestDb } from "./helpers.js";
import { normalizePhone } from "../api/_lib/phone.js";

let d: TestDb;
beforeAll(async () => {
  d = await freshDb();
});

describe("phone numbers", () => {
  it("normalizes PH mobile formats", () => {
    expect(normalizePhone("0997 804 9635")).toBe("09978049635");
    expect(normalizePhone("+63 997-804-9635")).toBe("09978049635");
    expect(normalizePhone("639978049635")).toBe("09978049635");
    expect(normalizePhone("9978049635")).toBe("09978049635");
    expect(normalizePhone("12345")).toBeNull();
    expect(normalizePhone("0297804963")).toBeNull();
  });
});

describe("sign up / sign in", () => {
  it("registers a customer with a customer profile and signs in with the number", async () => {
    const token = await signUp("0917 111 2222", "Maria");
    const me = await call("GET", "/auth/me", { token });
    expect(me.body.user).toMatchObject({ name: "Maria", phone: "09171112222", role: "customer" });
    const profile = await call("GET", "/me/profile", { token });
    expect(profile.body.profile).toMatchObject({ name: "Maria", balance: 0, utangAllowed: false, hasApp: true, lat: 14.6 });

    const login = await call("POST", "/auth/login", { body: { phone: "+639171112222", password: "secret-77" } });
    expect(login.status).toBe(200);
    expect(login.body.user.role).toBe("customer");
  });

  it("refuses a duplicate number, a short password and a bad number", async () => {
    await signUp("09171112223");
    const dup = await call("POST", "/auth/register", { ip: nextIp(), body: { name: "X", phone: "09171112223", password: "secret-77", address: "Somewhere 123" } });
    expect(dup.status).toBe(400); // name too short first
    const dup2 = await call("POST", "/auth/register", { ip: nextIp(), body: { name: "Xavier", phone: "09171112223", password: "secret-77", address: "Somewhere 123" } });
    expect(dup2.status).toBe(409);
    const short = await call("POST", "/auth/register", { ip: nextIp(), body: { name: "Xavier", phone: "09171112299", password: "123", address: "Somewhere 123" } });
    expect(short.status).toBe(400);
    expect(short.body.error).toMatch(/6 characters/);
    const bad = await call("POST", "/auth/register", { ip: nextIp(), body: { name: "Xavier", phone: "12345", password: "secret-77", address: "Somewhere 123" } });
    expect(bad.status).toBe(400);
    expect(bad.body.error).toMatch(/mobile number/);
  });

  it("limits sign-ups per connection", async () => {
    const ip = "10.9.9.9";
    for (let i = 0; i < 5; i++) {
      const r = await call("POST", "/auth/register", { ip, body: { name: `Person ${i}`, phone: `0918000000${i}`, password: "secret-77", address: "Somewhere 123" } });
      expect(r.status).toBe(201);
    }
    const r = await call("POST", "/auth/register", { ip, body: { name: "Person 6", phone: "09180000009", password: "secret-77", address: "Somewhere 123" } });
    expect(r.status).toBe(429);
  });

  it("locks the number after 5 wrong passwords", async () => {
    await signUp("09172223333");
    for (let i = 0; i < 5; i++) {
      const r = await call("POST", "/auth/login", { ip: "10.5.5.5", body: { phone: "09172223333", password: "wrong-pass" } });
      expect(r.status).toBe(401);
    }
    const locked = await call("POST", "/auth/login", { ip: "10.5.5.5", body: { phone: "09172223333", password: "secret-77" } });
    expect(locked.status).toBe(429);
  });

  it("rotates refresh tokens and signs out", async () => {
    const r = await call("POST", "/auth/register", { ip: nextIp(), body: { name: "Rotate Me", phone: "09173334444", password: "secret-77", address: "Somewhere 123" } });
    const refreshed = await call("POST", "/auth/refresh", { body: { refreshToken: r.body.refreshToken } });
    expect(refreshed.status).toBe(200);
    expect(refreshed.body.refreshToken).not.toBe(r.body.refreshToken);
    const out = await call("POST", "/auth/logout", { token: refreshed.body.accessToken });
    expect(out.status).toBe(200);
    const after = await call("GET", "/me/profile", { token: refreshed.body.accessToken });
    expect(after.status).toBe(401);
  });

  it("changes the password and clears the temporary flag", async () => {
    const owner = await makeStaff(d, "owner", "09990000001");
    const add = await call("POST", "/users", { token: owner, body: { name: "Rider Ben", phone: "09175556666" } });
    expect(add.status).toBe(201);
    const temp = add.body.temporaryPassword as string;
    const login = await call("POST", "/auth/login", { body: { phone: "09175556666", password: temp } });
    expect(login.body.user).toMatchObject({ role: "staff", mustChangePassword: true });
    const change = await call("POST", "/auth/password", { token: login.body.accessToken, body: { current: temp, next: "rider-new-pass" } });
    expect(change.status).toBe(200);
    expect(change.body.user.mustChangePassword).toBe(false);
  });
});
