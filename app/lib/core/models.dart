/// Data the app reads from the API. Money is integer centavos; dates are local DateTimes.
library;

import 'api.dart';

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
double? _double(Object? v) => v is num ? v.toDouble() : null;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

enum Role { customer, staff, owner }

class AppUser {
  AppUser({required this.id, required this.name, required this.phone, required this.role, required this.mustChangePassword});
  final String id;
  final String name;
  final String phone;
  final Role role;
  final bool mustChangePassword;

  bool get isSeller => role != Role.customer;
  bool get isOwner => role == Role.owner;

  factory AppUser.fromJson(Json j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        role: Role.values.firstWhere((r) => r.name == j['role'], orElse: () => Role.customer),
        mustChangePassword: j['mustChangePassword'] == true,
      );
  Json toJson() => {'id': id, 'name': name, 'phone': phone, 'role': role.name, 'mustChangePassword': mustChangePassword};
}

class StoreInfo {
  StoreInfo.fromJson(Json j)
      : name = j['name'] as String? ?? 'Habhab LPG Trading',
        phone = _str(j['phone']),
        address = _str(j['address']),
        isOpen = j['isOpen'] != false,
        closedMessage = _str(j['closedMessage']),
        deliveryFee = _int(j['deliveryFee']),
        gcashName = _str(j['gcashName']),
        gcashNumber = _str(j['gcashNumber']),
        hasGcashQr = j['hasGcashQr'] == true;
  final String name;
  final String? phone;
  final String? address;
  final bool isOpen;
  final String? closedMessage;
  final int deliveryFee;
  final String? gcashName;
  final String? gcashNumber;
  final bool hasGcashQr;
}

class Product {
  Product.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        kind = j['kind'] as String? ?? 'other',
        description = _str(j['description']),
        price = _intOrNull(j['price']),
        stock = _intOrNull(j['stock']),
        active = j['active'] == true,
        sort = _int(j['sort']);
  final String id;
  final String name;
  final String kind;
  final String? description;
  final int? price;
  final int? stock;
  final bool active;
  final int sort;

  bool get outOfStock => stock != null && stock! <= 0;
  String get kindLabel => switch (kind) {
        'refill' => 'Refill',
        'new_tank' => 'New tank',
        'accessory' => 'Accessory',
        _ => 'Other',
      };
}

class OrderItem {
  OrderItem.fromJson(Json j)
      : productId = _str(j['productId']),
        name = j['name'] as String,
        unitPrice = _int(j['unitPrice']),
        qty = _int(j['qty']),
        lineTotal = _int(j['lineTotal']);
  final String? productId;
  final String name;
  final int unitPrice;
  final int qty;
  final int lineTotal;
}

class RiderSpot {
  RiderSpot(this.lat, this.lng, this.at);
  final double lat;
  final double lng;
  final DateTime? at;
}

enum OrderStatus {
  pending,
  confirmed,
  onTheWay,
  delivered,
  cancelled;

  /// The name the API uses ("on_the_way").
  String get api => this == OrderStatus.onTheWay ? 'on_the_way' : name;
}

class Order {
  Order.fromJson(Json j)
      : id = j['id'] as String,
        ref = j['ref'] as String,
        channel = j['channel'] as String? ?? 'app',
        status = OrderStatus.values.firstWhere((s) => s.api == j['status'], orElse: () => OrderStatus.pending),
        paymentMethod = j['paymentMethod'] as String? ?? 'cash',
        customerId = _str(j['customerId']),
        customerName = j['customerName'] as String? ?? '',
        customerPhone = _str(j['customerPhone']),
        address = _str(j['address']),
        landmark = _str(j['landmark']),
        lat = _double(j['lat']),
        lng = _double(j['lng']),
        notes = _str(j['notes']),
        subtotal = _int(j['subtotal']),
        deliveryFee = _int(j['deliveryFee']),
        total = _int(j['total']),
        paid = _int(j['paid']),
        pendingPaid = _int(j['pendingPaid']),
        riderId = _str(j['riderId']),
        riderName = _str(j['riderName']),
        riderPhone = _str(j['riderPhone']),
        rider = j['rider'] is Map
            ? RiderSpot(_double((j['rider'] as Map)['lat'])!, _double((j['rider'] as Map)['lng'])!, _date((j['rider'] as Map)['at']))
            : null,
        createdAt = _date(j['createdAt']) ?? DateTime.now(),
        updatedAt = _date(j['updatedAt']),
        confirmedAt = _date(j['confirmedAt']),
        outAt = _date(j['outAt']),
        deliveredAt = _date(j['deliveredAt']),
        cancelledAt = _date(j['cancelledAt']),
        cancelReason = _str(j['cancelReason']),
        items = ((j['items'] as List?) ?? const []).map((e) => OrderItem.fromJson(e as Json)).toList();

  final String id;
  final String ref;
  final String channel;
  final OrderStatus status;
  final String paymentMethod;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String? address;
  final String? landmark;
  final double? lat;
  final double? lng;
  final String? notes;
  final int subtotal;
  final int deliveryFee;
  final int total;
  final int paid;
  final int pendingPaid;
  final String? riderId;
  final String? riderName;
  final String? riderPhone;
  final RiderSpot? rider;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? confirmedAt;
  final DateTime? outAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final List<OrderItem> items;

  bool get isOpen => status == OrderStatus.pending || status == OrderStatus.confirmed || status == OrderStatus.onTheWay;
  bool get isWalkin => channel == 'walkin';
  bool get hasPin => lat != null && lng != null;
  int get unpaid => (total - paid).clamp(0, total);
  String get itemsSummary => items.map((i) => '${i.qty}× ${i.name}').join(', ');
}

class Payment {
  Payment.fromJson(Json j)
      : id = j['id'] as String,
        ref = j['ref'] as String? ?? '',
        customerId = _str(j['customerId']),
        customerName = _str(j['customerName']),
        orderId = _str(j['orderId']),
        orderRef = _str(j['orderRef']),
        amount = _int(j['amount']),
        method = j['method'] as String? ?? 'cash',
        gcashRef = _str(j['gcashRef']),
        hasProof = j['hasProof'] == true,
        status = j['status'] as String? ?? 'pending',
        note = _str(j['note']),
        rejectReason = _str(j['rejectReason']),
        createdAt = _date(j['createdAt']) ?? DateTime.now();
  final String id;
  final String ref;
  final String? customerId;
  final String? customerName;
  final String? orderId;
  final String? orderRef;
  final int amount;
  final String method;
  final String? gcashRef;
  final bool hasProof;
  final String status;
  final String? note;
  final String? rejectReason;
  final DateTime createdAt;
}

class Customer {
  Customer.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        phone = _str(j['phone']),
        address = _str(j['address']),
        landmark = _str(j['landmark']),
        lat = _double(j['lat']),
        lng = _double(j['lng']),
        notes = _str(j['notes']),
        hasApp = j['hasApp'] == true,
        utangAllowed = j['utangAllowed'] == true,
        creditLimit = _intOrNull(j['creditLimit']),
        openingBalance = _int(j['openingBalance']),
        blocked = j['blocked'] == true,
        balance = _int(j['balance']);
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? landmark;
  final double? lat;
  final double? lng;
  final String? notes;
  final bool hasApp;
  final bool utangAllowed;
  final int? creditLimit;
  final int openingBalance;
  final bool blocked;
  final int balance;
  bool get hasPin => lat != null && lng != null;
}

class LedgerEntry {
  LedgerEntry.fromJson(Json j)
      : kind = j['kind'] as String,
        id = _str(j['id']),
        ref = _str(j['ref']),
        at = _date(j['at']) ?? DateTime.now(),
        label = j['label'] as String? ?? '',
        amount = _int(j['amount']),
        status = _str(j['status']),
        balance = _int(j['balance']);
  final String kind;
  final String? id;
  final String? ref;
  final DateTime at;
  final String label;
  final int amount;
  final String? status;
  final int balance;
}

class StaffUser {
  StaffUser.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        phone = j['phone'] as String? ?? '',
        role = j['role'] as String? ?? 'staff',
        active = j['active'] != false;
  final String id;
  final String name;
  final String phone;
  final String role;
  final bool active;
}
