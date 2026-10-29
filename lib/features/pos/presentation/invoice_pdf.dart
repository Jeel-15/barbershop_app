import 'dart:typed_data';

import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// The web's invoice preview (header, customer, Service Name / Qty / Price /
/// Total, totals, footer) as an A4 PDF: what "Print" and "Download PDF" give.
Future<Uint8List> buildInvoicePdf(InvoiceDetail inv, ShopInfo shop) async {
  const red = PdfColor.fromInt(0xFFBC1E2D);
  const grey = PdfColor.fromInt(0xFF555555);
  final b = inv.breakdown;
  final row = inv.row;
  final day = row.day == null
      ? ''
      : ShopTime.fullDate(ShopTime.parseDate(row.day!));

  pw.Widget cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    PdfColor? color,
    PdfColor? background,
  }) => pw.Container(
    color: background,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 10.5,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );

  pw.TableRow itemRow(InvoiceReceiptLine l, String kind) => pw.TableRow(
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
    ),
    children: [
      cell('$kind: ${l.name}'),
      cell('1', align: pw.TextAlign.center),
      cell(l.price.format(), align: pw.TextAlign.center),
      cell(l.price.format(), align: pw.TextAlign.right),
    ],
  );

  pw.TableRow sumRow(String label, String value) => pw.TableRow(
    children: [
      cell(label, color: red),
      cell(''),
      cell(''),
      cell(value, align: pw.TextAlign.right, color: red),
    ],
  );

  final discountService = b.serviceDiscount.isZero
      ? null
      : '(${b.serviceDiscount.format()}) ${b.serviceDiscountPercent.toStringAsFixed(2)}%';
  final discountProduct = b.productDiscount.isZero
      ? null
      : '(${b.productDiscount.format()}) ${b.productDiscountPercent.toStringAsFixed(2)}%';

  final doc = pw.Document(title: 'Invoice ${row.number}');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: red, width: 1.5)),
        ),
        child: pw.Center(
          child: pw.Text(
            '${shop.name} - For Style & Elegance\n'
            'Need help? Contact us at ${shop.email ?? ''}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 9, color: grey),
          ),
        ),
      ),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: red, width: 1.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                shop.name,
                style: const pw.TextStyle(
                  fontSize: 18,
                  color: red,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  for (final l in [shop.email, shop.phone, shop.website])
                    if ((l ?? '').trim().isNotEmpty)
                      pw.Text(l!, style: const pw.TextStyle(fontSize: 9.5)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Customer:',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(row.customerName),
                if (!row.isGuest && (row.customerEmail ?? '').isNotEmpty)
                  pw.Text(row.customerEmail!),
                if (!row.isGuest && (row.customerPhone ?? '').isNotEmpty)
                  pw.Text(row.customerPhone!),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Invoice No: ${row.number}'),
                pw.Text('Date: $day'),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              children: [
                cell(
                  'Service Name',
                  bold: true,
                  color: PdfColors.white,
                  background: red,
                ),
                cell(
                  'Qty',
                  bold: true,
                  color: PdfColors.white,
                  background: red,
                  align: pw.TextAlign.center,
                ),
                cell(
                  'Price',
                  bold: true,
                  color: PdfColors.white,
                  background: red,
                  align: pw.TextAlign.center,
                ),
                cell(
                  'Total',
                  bold: true,
                  color: PdfColors.white,
                  background: red,
                  align: pw.TextAlign.right,
                ),
              ],
            ),
            for (final l in inv.services) itemRow(l, 'Service'),
            if (!b.serviceTotal.isZero) ...[
              sumRow('Total Services Amount', b.serviceTotal.format()),
              if (discountService != null)
                sumRow('Service Discount', discountService),
              sumRow('Total Services Payable', b.servicePayable.format()),
            ],
            for (final l in inv.products) itemRow(l, 'Product'),
            if (!b.productTotal.isZero) ...[
              sumRow('Total Product Amount', b.productTotal.format()),
              if (discountProduct != null)
                sumRow('Product Discount', discountProduct),
              sumRow('Total Product Payable', b.productPayable.format()),
            ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 230,
            child: pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
              },
              children: [
                for (final e in <(String, Money, bool)>[
                  ('Subtotal:', b.subtotal, false),
                  ('Tax:', b.tax, false),
                  ('Tip:', b.tip, false),
                  ('Total Amount:', b.total, true),
                ])
                  pw.TableRow(
                    children: [
                      cell(e.$1, bold: true),
                      cell(
                        e.$2.format(),
                        align: pw.TextAlign.right,
                        bold: e.$3,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

String invoiceFileName(InvoiceDetail inv) =>
    'Invoice-${inv.row.number.isEmpty ? inv.row.id : inv.row.number}.pdf';

/// "Print": the system print dialog.
Future<void> printInvoice(InvoiceDetail inv, ShopInfo shop) async {
  final bytes = await buildInvoicePdf(inv, shop);
  await Printing.layoutPdf(
    name: invoiceFileName(inv),
    onLayout: (_) async => bytes,
  );
}

/// "Download PDF": the share sheet, where the file can be saved or sent.
Future<void> shareInvoicePdf(InvoiceDetail inv, ShopInfo shop) async {
  final bytes = await buildInvoicePdf(inv, shop);
  await Printing.sharePdf(bytes: bytes, filename: invoiceFileName(inv));
}
