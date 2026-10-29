import 'package:barbershop_app/core/utils/money.dart';

/// A service that can be sold (`GET /pos/catalog`).
class CatalogService {
  const CatalogService({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.imageUrl,
  });

  factory CatalogService.fromJson(Map<String, dynamic> j) => CatalogService(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    price: Money.parse(j['price']),
    durationMinutes: (j['duration'] as num?)?.toInt() ?? 0,
    imageUrl: j['image_url']?.toString(),
  );

  final int id;
  final String name;
  final Money price;
  final int durationMinutes;
  final String? imageUrl;
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.services,
  });

  factory CatalogCategory.fromJson(Map<String, dynamic> j) => CatalogCategory(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    services: [
      for (final s in (j['services'] as List? ?? const []))
        CatalogService.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );

  final int id;
  final String name;
  final List<CatalogService> services;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    this.imageUrl,
  });

  factory CatalogProduct.fromJson(Map<String, dynamic> j) => CatalogProduct(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    price: Money.parse(j['price']),
    stock: (j['stock'] as num?)?.toInt(),
    imageUrl: j['image_url']?.toString(),
  );

  final int id;
  final String name;
  final Money price;
  final int? stock;
  final String? imageUrl;
}

class StaffOption {
  const StaffOption(this.id, this.name);

  final int id;
  final String name;
}

/// Everything the invoice form can choose from.
class PosCatalog {
  const PosCatalog({
    required this.categories,
    required this.products,
    required this.staff,
    required this.paymentMethods,
    required this.defaultPayment,
    required this.taxLabel,
  });

  factory PosCatalog.fromJson(Map<String, dynamic> j) {
    final gst = j['gst'];
    String tax = '';
    if (gst is Map) {
      final inc = gst['tax_type'].toString() != 'exclude';
      tax = 'GST ${gst['rate']}% ${inc ? 'included' : 'added'}';
    }
    return PosCatalog(
      categories: [
        for (final c in (j['categories'] as List? ?? const []))
          CatalogCategory.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      products: [
        for (final p in (j['products'] as List? ?? const []))
          CatalogProduct.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
      staff: [
        for (final s in (j['staff'] as List? ?? const []))
          StaffOption((s['id'] as num).toInt(), (s['name'] ?? '').toString()),
      ],
      paymentMethods: [
        for (final m in (j['payment_methods'] as List? ?? const []))
          (m['name'] ?? '').toString(),
      ],
      defaultPayment: (j['default_payment_method'] ?? 'Cash').toString(),
      taxLabel: tax,
    );
  }

  final List<CatalogCategory> categories;
  final List<CatalogProduct> products;
  final List<StaffOption> staff;
  final List<String> paymentMethods;
  final String defaultPayment;

  /// "GST 5% included".
  final String taxLabel;
}

enum LineType { service, product }

/// One row of the invoice: a service or a product, who did it, how many.
class InvoiceLine {
  const InvoiceLine({
    required this.type,
    required this.id,
    required this.name,
    required this.price,
    required this.qty,
    this.staffId,
    this.uid,
  });

  final LineType type;
  final int id;
  final String name;
  final Money price;
  final int qty;

  /// Null until a barber is chosen ("Select Staff Members").
  final int? staffId;

  /// Set when the same item sits on the invoice twice (done by two barbers).
  final String? uid;

  String get key => uid ?? '${type.name}:$id';

  InvoiceLine copyWith({int? qty, Object? staffId = _keep}) => InvoiceLine(
    type: type,
    id: id,
    name: name,
    price: price,
    qty: qty ?? this.qty,
    staffId: identical(staffId, _keep) ? this.staffId : staffId as int?,
    uid: uid,
  );

  static const _keep = Object();

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'id': id,
    'staff_id': staffId,
    'qty': qty,
  };
}

/// What the user has entered. The server turns it into money (`preview`).
class InvoiceDraft {
  const InvoiceDraft({
    this.customerName = '',
    this.customerPhone = '',
    this.customerEmail = '',
    this.lines = const [],
    this.serviceDiscount = 0,
    this.productDiscount = 0,
    this.tip = Money.zero,
    this.paymentMethod = 'Cash',
    this.notes = '',
  });

  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final List<InvoiceLine> lines;
  final double serviceDiscount;
  final double productDiscount;
  final Money tip;
  final String paymentMethod;
  final String notes;

  bool get hasServices => lines.any((l) => l.type == LineType.service);
  bool get hasProducts => lines.any((l) => l.type == LineType.product);
  bool get allHaveStaff => lines.every((l) => l.staffId != null);

  InvoiceDraft copyWith({
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    List<InvoiceLine>? lines,
    double? serviceDiscount,
    double? productDiscount,
    Money? tip,
    String? paymentMethod,
    String? notes,
  }) => InvoiceDraft(
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    customerEmail: customerEmail ?? this.customerEmail,
    lines: lines ?? this.lines,
    serviceDiscount: serviceDiscount ?? this.serviceDiscount,
    productDiscount: productDiscount ?? this.productDiscount,
    tip: tip ?? this.tip,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    notes: notes ?? this.notes,
  );

  /// The cart as the API takes it. [withCustomer] is false when completing an
  /// appointment (the server keeps the appointment's customer).
  Map<String, dynamic> toCart({bool withCustomer = true}) => {
    'items': [for (final l in lines) l.toJson()],
    'service_discount': serviceDiscount,
    'product_discount': productDiscount,
    'tip': tip.toApi(),
    'payment_method': paymentMethod,
    if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    if (withCustomer &&
        (customerName.trim().isNotEmpty ||
            customerPhone.trim().isNotEmpty ||
            customerEmail.trim().isNotEmpty))
      'customer': {
        if (customerName.trim().isNotEmpty) 'name': customerName.trim(),
        if (customerPhone.trim().isNotEmpty) 'phone': customerPhone.trim(),
        if (customerEmail.trim().isNotEmpty) 'email': customerEmail.trim(),
      },
  };
}

/// The server's arithmetic for the current draft (`POST /invoices/preview`).
class InvoiceTotals {
  const InvoiceTotals({
    required this.serviceTotal,
    required this.serviceDiscountPercent,
    required this.serviceDiscountAmount,
    required this.productTotal,
    required this.productDiscountPercent,
    required this.productDiscountAmount,
    required this.subtotal,
    required this.tax,
    required this.taxRate,
    required this.taxIncluded,
    required this.tip,
    required this.finalTotal,
  });

  factory InvoiceTotals.fromJson(Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from((j['totals'] as Map?) ?? const {});
    return InvoiceTotals(
      serviceTotal: Money.parse(t['service_total']),
      serviceDiscountPercent:
          double.tryParse('${t['service_discount_percent']}') ?? 0,
      serviceDiscountAmount: Money.parse(t['service_discount_amount']),
      productTotal: Money.parse(t['product_total']),
      productDiscountPercent:
          double.tryParse('${t['product_discount_percent']}') ?? 0,
      productDiscountAmount: Money.parse(t['product_discount_amount']),
      subtotal: Money.parse(t['subtotal']),
      tax: Money.parse(t['tax']),
      taxRate: double.tryParse('${t['tax_rate']}') ?? 0,
      taxIncluded: t['tax_type'].toString() != 'exclude',
      tip: Money.parse(t['tip']),
      finalTotal: Money.parse(t['final_total']),
    );
  }

  final Money serviceTotal;
  final double serviceDiscountPercent;
  final Money serviceDiscountAmount;
  final Money productTotal;
  final double productDiscountPercent;
  final Money productDiscountAmount;
  final Money subtotal;
  final Money tax;
  final double taxRate;
  final bool taxIncluded;
  final Money tip;
  final Money finalTotal;
}
