import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';

/// The placeholder address the web gives a guest; mail to it is never sent.
const guestEmail = 'info@bluecrownbarbers.com';

/// One row of the Invoices list (web: Invoice, Customer, Staff, Date, Status, Amount).
class InvoiceRow {
  const InvoiceRow({
    required this.id,
    required this.number,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.staffNames,
    required this.invoicedAt,
    required this.date,
    required this.paymentMethod,
    required this.total,
    required this.canEdit,
  });

  factory InvoiceRow.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['customer'] as Map?) ?? const {});
    return InvoiceRow(
      id: (j['id'] as num).toInt(),
      number: (j['invoice_number'] ?? '').toString(),
      customerName: (c['name'] ?? '').toString(),
      customerPhone: c['phone']?.toString(),
      customerEmail: c['email']?.toString(),
      staffNames: (j['staff_names'] ?? '').toString(),
      invoicedAt: j['invoiced_at']?.toString(),
      date: j['date']?.toString(),
      paymentMethod: j['payment_method']?.toString(),
      total: Money.parse(j['total']),
      canEdit: j['can_edit'] == true,
    );
  }

  final int id;
  final String number;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String staffNames;

  /// `yyyy-MM-dd HH:mm:ss`: when the invoice was saved (the web's Date column).
  final String? invoicedAt;

  /// `yyyy-MM-dd` of the booking.
  final String? date;
  final String? paymentMethod;
  final Money total;
  final bool canEdit;

  /// `yyyy-MM-dd` of [invoicedAt], falling back to the booking date.
  String? get day {
    final at = invoicedAt;
    if (at != null && at.length >= 10) return at.substring(0, 10);
    return date;
  }

  bool get isGuest => customerName.trim().toLowerCase() == 'guest customer';

  /// An address the mail can really go to (not empty, not the guest placeholder).
  bool get hasRealEmail {
    final e = (customerEmail ?? '').trim();
    return e.isNotEmpty && e.toLowerCase() != guestEmail;
  }
}

/// One line printed on the invoice (a service or a product).
class InvoiceReceiptLine {
  const InvoiceReceiptLine({
    required this.type,
    required this.name,
    required this.staffName,
    required this.price,
  });

  factory InvoiceReceiptLine.fromJson(Map<String, dynamic> j) =>
      InvoiceReceiptLine(
        type: j['type'] == 'product' ? LineType.product : LineType.service,
        name: (j['name'] ?? '').toString(),
        staffName: j['staff_name']?.toString(),
        price: Money.parse(j['price']),
      );

  final LineType type;
  final String name;
  final String? staffName;
  final Money price;
}

/// What the cart of the invoice looks like, as the edit form takes it.
class InvoiceCartItem {
  const InvoiceCartItem({
    required this.type,
    required this.id,
    required this.staffId,
    required this.qty,
  });

  factory InvoiceCartItem.fromJson(Map<String, dynamic> j) => InvoiceCartItem(
    type: j['type'] == 'product' ? LineType.product : LineType.service,
    id: (j['id'] as num).toInt(),
    staffId: (j['staff_id'] as num).toInt(),
    qty: (j['qty'] as num?)?.toInt() ?? 1,
  );

  final LineType type;
  final int id;
  final int staffId;
  final int qty;
}

/// The money block of the invoice, as the web's invoice preview prints it.
class InvoiceBreakdown {
  const InvoiceBreakdown({
    required this.serviceTotal,
    required this.serviceDiscountPercent,
    required this.productTotal,
    required this.productDiscountPercent,
    required this.tax,
    required this.tip,
    required this.total,
  });

  factory InvoiceBreakdown.fromJson(Map<String, dynamic> j) => InvoiceBreakdown(
    serviceTotal: Money.parse(j['service_total']),
    serviceDiscountPercent: _num(j['service_discount_percent']),
    productTotal: Money.parse(j['product_total']),
    productDiscountPercent: _num(j['product_discount_percent']),
    tax: Money.parse(j['tax']),
    tip: Money.parse(j['tip']),
    total: Money.parse(j['total']),
  );

  final Money serviceTotal;
  final double serviceDiscountPercent;
  final Money productTotal;
  final double productDiscountPercent;
  final Money tax;
  final Money tip;
  final Money total;

  Money get serviceDiscount => serviceTotal.percent(serviceDiscountPercent);
  Money get productDiscount => productTotal.percent(productDiscountPercent);
  Money get servicePayable => serviceTotal - serviceDiscount;
  Money get productPayable => productTotal - productDiscount;

  /// The web's "Subtotal": what is payable for services and products.
  Money get subtotal => servicePayable + productPayable;

  static double _num(Object? v) => double.tryParse('${v ?? 0}') ?? 0;
}

/// `GET /invoices/{id}`: everything on the invoice plus the cart to edit it.
class InvoiceDetail {
  const InvoiceDetail({
    required this.row,
    required this.notes,
    required this.lines,
    required this.cart,
    required this.breakdown,
  });

  factory InvoiceDetail.fromJson(Map<String, dynamic> j) => InvoiceDetail(
    row: InvoiceRow.fromJson(j),
    notes: j['notes']?.toString(),
    lines: [
      for (final l in (j['lines'] as List? ?? const []))
        InvoiceReceiptLine.fromJson(Map<String, dynamic>.from(l as Map)),
    ],
    cart: [
      for (final c in (j['cart'] as List? ?? const []))
        InvoiceCartItem.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    breakdown: InvoiceBreakdown.fromJson(
      Map<String, dynamic>.from((j['breakdown'] as Map?) ?? const {}),
    ),
  );

  final InvoiceRow row;
  final String? notes;
  final List<InvoiceReceiptLine> lines;
  final List<InvoiceCartItem> cart;
  final InvoiceBreakdown breakdown;

  List<InvoiceReceiptLine> get services => [
    for (final l in lines)
      if (l.type == LineType.service) l,
  ];

  List<InvoiceReceiptLine> get products => [
    for (final l in lines)
      if (l.type == LineType.product) l,
  ];
}
