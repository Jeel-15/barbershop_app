import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's "View Invoice" (the invoice preview): who, what, the discounts and
/// totals, with Send Invoice Mail, Print, Download PDF and Edit.
class InvoiceDetailPage extends ConsumerStatefulWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  ConsumerState<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends ConsumerState<InvoiceDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    } catch (_) {
      if (mounted) {
        showToast(context, 'Something went wrong.', kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Send Invoice Mail": to the customer's address, or to one typed in when
  /// the customer has none (a guest).
  Future<void> _mail(InvoiceDetail inv) async {
    String? to;
    if (inv.row.hasRealEmail) {
      final ok = await showConfirm(
        context,
        title: 'Send Invoice Mail',
        message: 'Send this invoice to ${inv.row.customerEmail}?',
        confirmLabel: 'Send',
      );
      if (!ok || !mounted) return;
    } else {
      to = await _askEmail();
      if (to == null || !mounted) return;
    }
    await _run(() async {
      final msg = await ref
          .read(invoicesRepositoryProvider)
          .sendEmail(inv.row.id, email: to);
      if (mounted) showToast(context, msg, kind: ToastKind.success);
    });
  }

  Future<String?> _askEmail() => showAppSheet<String>(
    context,
    title: 'Send Invoice Mail',
    builder: (_) => const _EmailForm(),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final shop = ref.watch(bootstrapProvider).shop;
    final async = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final inv = async.value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.sm,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  RoundBackButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/app/invoices'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'View Invoice',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        if (inv != null)
                          Text(
                            inv.row.number,
                            style: AppType.caption.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (inv != null) StatusPill(label: 'Paid', color: t.success),
                ],
              ),
            ),
            Expanded(
              child: switch (async) {
                AsyncError(:final error) when inv == null => ErrorState(
                  message: error is Failure
                      ? error.userMessage
                      : 'Could not load this invoice.',
                  supportCode: error is Failure ? error.requestId : null,
                  onRetry: () =>
                      ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
                ),
                _ when inv == null => const Padding(
                  padding: EdgeInsets.all(AppSpace.page),
                  child: SkeletonLoader(
                    child: Column(
                      children: [
                        SkeletonBox(height: 120, radius: 16),
                        SizedBox(height: AppSpace.md),
                        SkeletonBox(height: 220, radius: 16),
                      ],
                    ),
                  ),
                ),
                _ => ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.sm,
                    AppSpace.page,
                    AppSpace.xl,
                  ),
                  children: [_Receipt(inv: inv, shop: shop)],
                ),
              },
            ),
            if (inv != null)
              _Actions(
                busy: _busy,
                canEdit: user.can('Pos_invoice-Edit'),
                onMail: () => _mail(inv),
                onPdf: () => _run(() => shareInvoicePdf(inv, shop)),
                onPrint: () => _run(() => printInvoice(inv, shop)),
                onEdit: () => context.push('/app/invoice/edit/${inv.row.id}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.busy,
    required this.canEdit,
    required this.onMail,
    required this.onPdf,
    required this.onPrint,
    required this.onEdit,
  });

  final bool busy;
  final bool canEdit;
  final VoidCallback onMail;
  final VoidCallback onPdf;
  final VoidCallback onPrint;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.md,
        AppSpace.page,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Send Invoice Mail',
            icon: Icons.mail_outline_rounded,
            loading: busy,
            onPressed: busy ? null : onMail,
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Download PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: busy ? null : onPdf,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton(
                  label: 'Print',
                  icon: Icons.print_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: busy ? null : onPrint,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: AppButton(
                    label: 'Edit',
                    icon: Icons.edit_rounded,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    onPressed: busy ? null : onEdit,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The invoice as printed: shop, customer, services, products, totals.
class _Receipt extends StatelessWidget {
  const _Receipt({required this.inv, required this.shop});

  final InvoiceDetail inv;
  final ShopInfo shop;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final row = inv.row;
    final b = inv.breakdown;
    final day = row.day == null
        ? null
        : ShopTime.fullDate(ShopTime.parseDate(row.day!));

    Widget sum(
      String label,
      String value, {
      bool strong = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? AppType.bodyStrong : AppType.body).copyWith(
                color: color ?? (strong ? t.text : t.textSecondary),
              ),
            ),
          ),
          Text(
            value,
            style: (strong ? AppType.bodyStrong : AppType.body).copyWith(
              color: color ?? t.text,
            ),
          ),
        ],
      ),
    );

    Widget section(
      String title,
      List<InvoiceReceiptLine> lines,
      Money total,
      Money discount,
      double percent,
      Money payable,
      String name,
    ) {
      if (lines.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpace.lg),
          Text(
            title.toUpperCase(),
            style: AppType.overline.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.name,
                          style: AppType.bodyStrong.copyWith(color: t.text),
                        ),
                        if ((l.staffName ?? '').isNotEmpty)
                          Text(
                            l.staffName!,
                            style: AppType.caption.copyWith(color: t.textMuted),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    l.price.format(),
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                ],
              ),
            ),
          Divider(height: AppSpace.lg, color: t.border),
          sum('Total $name Amount', total.format()),
          if (!discount.isZero)
            sum(
              '${name == 'Services' ? 'Service' : name} Discount (${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 2)}%)',
              '-${discount.format()}',
              color: t.success,
            ),
          sum('Total $name Payable', payable.format()),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(shop.name, style: AppType.title.copyWith(color: t.text)),
          for (final l in [shop.email, shop.phone, shop.website])
            if ((l ?? '').trim().isNotEmpty)
              Text(l!, style: AppType.caption.copyWith(color: t.textSecondary)),
          Divider(height: AppSpace.xl, color: t.border),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CUSTOMER',
                      style: AppType.overline.copyWith(color: t.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.customerName.isEmpty ? '-' : row.customerName,
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                    if (!row.isGuest && (row.customerEmail ?? '').isNotEmpty)
                      Text(
                        row.customerEmail!,
                        style: AppType.caption.copyWith(color: t.textSecondary),
                      ),
                    if (!row.isGuest && (row.customerPhone ?? '').isNotEmpty)
                      Text(
                        row.customerPhone!,
                        style: AppType.caption.copyWith(color: t.textSecondary),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'INVOICE NO',
                    style: AppType.overline.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.number,
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                  if (day != null)
                    Text(
                      day,
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                  if ((row.paymentMethod ?? '').isNotEmpty)
                    Text(
                      row.paymentMethod!,
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                ],
              ),
            ],
          ),
          section(
            'Services',
            inv.services,
            b.serviceTotal,
            b.serviceDiscount,
            b.serviceDiscountPercent,
            b.servicePayable,
            'Services',
          ),
          section(
            'Products',
            inv.products,
            b.productTotal,
            b.productDiscount,
            b.productDiscountPercent,
            b.productPayable,
            'Product',
          ),
          Divider(height: AppSpace.xl, color: t.border),
          sum('Subtotal', b.subtotal.format()),
          sum('Tax', b.tax.format()),
          sum('Tip', b.tip.format()),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Amount',
                  style: AppType.heading.copyWith(color: t.text),
                ),
              ),
              Text(
                b.total.format(),
                style: AppText.display(28, color: t.accentText),
              ),
            ],
          ),
          if ((inv.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            Text('NOTES', style: AppType.overline.copyWith(color: t.textMuted)),
            const SizedBox(height: 4),
            Text(inv.notes!, style: AppType.body.copyWith(color: t.text)),
          ],
        ],
      ),
    );
  }
}

/// Asks for the address when the customer has none.
class _EmailForm extends StatefulWidget {
  const _EmailForm();

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _send() {
    final v = _c.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This customer has no email address. Where should the invoice go?',
          style: AppType.body.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Email',
          hint: 'Enter Email Address',
          controller: _c,
          errorText: _error,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(
          label: 'Send Invoice Mail',
          icon: Icons.send_rounded,
          onPressed: _send,
        ),
      ],
    );
  }
}
