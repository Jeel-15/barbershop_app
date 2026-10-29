import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/pos/application/invoice_form_controller.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:barbershop_app/features/pos/presentation/widgets/item_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's invoice wizard on one scrolling page: Customer Information,
/// Services & Products with Select Staff Members, and Order Summary.
/// "Complete" opens it for a booked appointment (prefilled); the gold button
/// of the nav bar opens it blank as "Create Invoice".
class InvoiceFormPage extends ConsumerStatefulWidget {
  const InvoiceFormPage({super.key, this.appointmentId, this.invoiceId});

  /// Set = completing this appointment.
  final int? appointmentId;

  /// Set = editing this invoice. Both null = a new invoice.
  final int? invoiceId;

  @override
  ConsumerState<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends ConsumerState<InvoiceFormPage> {
  final _serviceDiscount = TextEditingController();
  final _productDiscount = TextEditingController();
  final _tip = TextEditingController();
  final _notes = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    for (final c in [
      _serviceDiscount,
      _productDiscount,
      _tip,
      _notes,
      _name,
      _phone,
      _email,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  /// Copies the prefilled draft into the text fields once, after the load.
  void _fill(InvoiceDraft d) {
    if (_filled) return;
    _filled = true;
    _name.text = d.customerName;
    _phone.text = d.customerPhone;
    _email.text = d.customerEmail;
    _tip.text = d.tip.isZero ? '' : d.tip.toApi();
  }

  InvoiceTarget get _target => InvoiceTarget(
    appointmentId: widget.appointmentId,
    invoiceId: widget.invoiceId,
  );

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final ctl = ref.read(invoiceFormProvider(_target).notifier);
    final err = await ctl.submit();
    if (!mounted) return;
    if (err != null) {
      showToast(context, err, kind: ToastKind.error);
      return;
    }
    final done = widget.invoiceId != null
        ? 'Successfully Updated Invoice'
        : widget.appointmentId != null
        ? 'Appointment completed and invoiced.'
        : 'Successfully Created Invoice';
    showSuccessBurst(context);
    showToast(context, done, kind: ToastKind.success);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final provider = invoiceFormProvider(_target);
    final s = ref.watch(provider);
    final ctl = ref.read(provider.notifier);
    final completing = widget.appointmentId != null;
    final editing = widget.invoiceId != null;
    if (!s.loading && s.catalog != null) _fill(s.draft);

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
                        : context.go('/app/home'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editing
                              ? 'Edit Invoice'
                              : completing
                              ? 'Complete'
                              : 'Create Invoice',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        if (editing && s.invoice != null)
                          Text(
                            'Invoice No ${s.invoice!.row.number}',
                            style: AppType.caption.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                        if (completing && s.appointment != null)
                          Text(
                            '${s.appointment!.row.customerName} · ${ShopTime.dayLabel(ShopTime.parseDate(s.appointment!.row.date))}',
                            style: AppType.caption.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: s.loading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpace.page),
                      child: SkeletonLoader(
                        child: Column(
                          children: [
                            SkeletonBox(height: 90, radius: 16),
                            SizedBox(height: AppSpace.md),
                            SkeletonBox(height: 140, radius: 16),
                            SizedBox(height: AppSpace.md),
                            SkeletonBox(height: 200, radius: 16),
                          ],
                        ),
                      ),
                    )
                  : s.loadError != null
                  ? ErrorState(
                      message: s.loadError is Failure
                          ? (s.loadError! as Failure).userMessage
                          : 'Could not open the invoice.',
                      onRetry: () => ref.invalidate(provider),
                    )
                  : _Form(
                      s: s,
                      ctl: ctl,
                      target: _target,
                      completing: completing,
                      serviceDiscount: _serviceDiscount,
                      productDiscount: _productDiscount,
                      tip: _tip,
                      notes: _notes,
                      name: _name,
                      phone: _phone,
                      email: _email,
                      parse: _num,
                    ),
            ),
            if (!s.loading && s.loadError == null)
              _TotalBar(
                s: s,
                label: editing
                    ? 'Update'
                    : completing
                    ? 'Complete'
                    : 'Create Invoice',
                onPressed: s.submitting ? null : _submit,
              ),
          ],
        ),
      ),
    );
  }
}

/// The web's customer cards under "Search Customer": name, Total Visit,
/// Last Service and (not for staff) Total Spend. Tapping one fills the fields.
class _LookupCards extends ConsumerWidget {
  const _LookupCards({required this.phone, required this.onPick});

  final String phone;
  final ValueChanged<CustomerLookup> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final found = ref.watch(customerLookupProvider(phone)).value ?? const [];
    if (found.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final c in found)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: Pressable(
              onTap: () => onPick(c),
              scale: 0.99,
              minSize: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.accent.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer : ${c.name.isEmpty ? '-' : c.name}',
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                    Text(
                      'Total Visit : ${c.visits}',
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                    Text(
                      'Last Service : ${c.lastService}',
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                    if (c.lastSpend != null)
                      Text(
                        'Total Spend : ${c.lastSpend}',
                        style: AppType.caption.copyWith(color: t.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.s,
    required this.ctl,
    required this.target,
    required this.completing,
    required this.serviceDiscount,
    required this.productDiscount,
    required this.tip,
    required this.notes,
    required this.name,
    required this.phone,
    required this.email,
    required this.parse,
  });

  final InvoiceFormState s;
  final InvoiceFormController ctl;
  final InvoiceTarget target;
  final bool completing;
  final TextEditingController serviceDiscount;
  final TextEditingController productDiscount;
  final TextEditingController tip;
  final TextEditingController notes;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final double Function(String) parse;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = s.draft;
    final catalog = s.catalog!;
    final totals = s.totals;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
      child: Text(text, style: AppType.subheading.copyWith(color: t.text)),
    );

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.sm,
        AppSpace.page,
        AppSpace.xl,
      ),
      children: [
        title('Customer Information'),
        if (completing)
          _CustomerCard(d: d)
        else
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: t.border),
            ),
            child: Column(
              children: [
                AppTextField(
                  label: 'Phone Number',
                  hint: 'Enter phone number',
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (v) => ctl.setCustomer(phone: v),
                ),
                // Like the web: from 10 digits the number is looked up.
                if (d.customerPhone.trim().length >= 10)
                  _LookupCards(
                    phone: d.customerPhone.trim(),
                    onPick: (c) {
                      name.text = c.name;
                      email.text = c.email;
                      ctl.setCustomer(name: c.name, email: c.email);
                    },
                  ),
                const SizedBox(height: AppSpace.md),
                AppTextField(
                  label: 'Full Name',
                  hint: 'Enter customer name',
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (v) => ctl.setCustomer(name: v),
                ),
                const SizedBox(height: AppSpace.md),
                AppTextField(
                  label: 'Email (Optional)',
                  hint: 'Enter email address',
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => ctl.setCustomer(email: v),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Leave empty to continue as Guest.',
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpace.xl),
        title('Services & Products'),
        if (d.lines.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.xl),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: t.border),
            ),
            child: Text(
              'Click on a service to select it. You can also add products below.',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: t.textSecondary),
            ),
          )
        else
          for (final l in d.lines) ...[
            _LineCard(
              line: l,
              staff: catalog.staff,
              onQty: (q) => ctl.setQty(l.key, q),
              onRemove: () => ctl.removeLine(l.key),
              onStaff: (id) => ctl.setStaff(l.key, id),
            ),
            const SizedBox(height: AppSpace.sm + 2),
          ],
        const SizedBox(height: AppSpace.xs),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Add Services',
                icon: Icons.content_cut_rounded,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => showItemPicker(
                  context,
                  target: target,
                  catalog: catalog,
                  type: LineType.service,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm + 2),
            Expanded(
              child: AppButton(
                label: 'Add Products',
                icon: Icons.inventory_2_rounded,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => showItemPicker(
                  context,
                  target: target,
                  catalog: catalog,
                  type: LineType.product,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        title('Order Summary'),
        if (d.hasServices)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: AppTextField(
              label: 'Service Discount (%)',
              hint: '0',
              controller: serviceDiscount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: decimal,
              onChanged: (v) => ctl.setServiceDiscount(parse(v)),
            ),
          ),
        if (d.hasProducts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: AppTextField(
              label: 'Product Discount (%)',
              hint: '0',
              controller: productDiscount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: decimal,
              onChanged: (v) => ctl.setProductDiscount(parse(v)),
            ),
          ),
        AppTextField(
          label: 'Tip',
          hint: '0.00',
          prefixText: r'$ ',
          controller: tip,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimal,
          onChanged: (v) => ctl.setTip(Money.parse(v)),
        ),
        const SizedBox(height: AppSpace.sm + 2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final pct in const [0, 10, 15, 20])
              AppChoiceChip(
                label: pct == 0 ? 'No tip' : '$pct%',
                selected: _tipMatches(d.tip, totals, pct),
                onTap: totals == null && pct != 0
                    ? () {}
                    : () {
                        final v = pct == 0
                            ? Money.zero
                            : (totals!.subtotal).percent(pct);
                        tip.text = v.isZero ? '' : v.toApi();
                        ctl.setTip(v);
                      },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          'Payment Method',
          style: AppType.label.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in catalog.paymentMethods)
              AppChoiceChip(
                label: m,
                selected: d.paymentMethod == m,
                onTap: () => ctl.setPayment(m),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Notes (Optional)',
          controller: notes,
          maxLines: 2,
          onChanged: ctl.setNotes,
        ),
        const SizedBox(height: AppSpace.xl),
        _TotalsCard(s: s, taxLabel: catalog.taxLabel),
      ],
    );
  }

  bool _tipMatches(Money tip, InvoiceTotals? totals, int pct) {
    if (pct == 0) return tip.isZero;
    if (totals == null) return false;
    return !tip.isZero && tip == totals.subtotal.percent(pct);
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.d});

  final InvoiceDraft d;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          AppAvatar(name: d.customerName, size: 46),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.customerName,
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
                if (d.customerPhone.isNotEmpty)
                  Text(
                    d.customerPhone,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                if (d.customerEmail.isNotEmpty)
                  Text(
                    d.customerEmail,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.staff,
    required this.onQty,
    required this.onRemove,
    required this.onStaff,
  });

  final InvoiceLine line;
  final List<StaffOption> staff;
  final ValueChanged<int> onQty;
  final VoidCallback onRemove;
  final ValueChanged<int> onStaff;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isService = line.type == LineType.service;
    final missing = line.staffId == null;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: missing ? t.danger.withValues(alpha: 0.6) : t.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isService
                      ? Icons.content_cut_rounded
                      : Icons.inventory_2_rounded,
                  size: 19,
                  color: t.accentText,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                    Text(
                      '${line.price.format()} each',
                      style: AppType.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              QuantityStepper(qty: line.qty, onChanged: onQty),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 20, color: t.textMuted),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            missing ? 'Select Staff Members' : 'Staff',
            style: AppType.caption.copyWith(
              color: missing ? t.danger : t.textMuted,
              fontWeight: missing ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: staff.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => AppChoiceChip(
                label: staff[i].name,
                selected: line.staffId == staff[i].id,
                onTap: () => onStaff(staff[i].id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The server's arithmetic, in the web's rows.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.s, required this.taxLabel});

  final InvoiceFormState s;
  final String taxLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final totals = s.totals;
    final d = s.draft;

    Widget row(
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

    Widget body;
    if (d.lines.isEmpty) {
      body = Text(
        'Add a service or product to see the total.',
        style: AppType.body.copyWith(color: t.textSecondary),
      );
    } else if (!d.allHaveStaff) {
      body = Text(
        'Select Staff Members to see the total.',
        style: AppType.body.copyWith(color: t.danger),
      );
    } else if (totals == null) {
      body = const SkeletonLoader(child: SkeletonBox(height: 110, radius: 12));
    } else {
      body = AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: s.previewing ? 0.55 : 1,
        child: Column(
          children: [
            if (d.hasServices) ...[
              row('Total Services Amount', totals.serviceTotal.format()),
              if (!totals.serviceDiscountAmount.isZero)
                row(
                  'Service Discount (${_pct(totals.serviceDiscountPercent)}%)',
                  '-${totals.serviceDiscountAmount.format()}',
                  color: t.success,
                ),
            ],
            if (d.hasProducts) ...[
              row('Total Product Amount', totals.productTotal.format()),
              if (!totals.productDiscountAmount.isZero)
                row(
                  'Product Discount (${_pct(totals.productDiscountPercent)}%)',
                  '-${totals.productDiscountAmount.format()}',
                  color: t.success,
                ),
            ],
            Divider(height: AppSpace.lg, color: t.border),
            row('Subtotal', totals.subtotal.format()),
            if (taxLabel.isNotEmpty) row(taxLabel, totals.tax.format()),
            row('Tip', totals.tip.format()),
            Divider(height: AppSpace.lg, color: t.border),
            Row(
              children: [
                Text(
                  'Total Amount',
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
                const Spacer(),
                MoneyText(
                  totals.finalTotal,
                  style: AppText.display(26, color: t.text),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.accent.withValues(alpha: 0.4)),
      ),
      child: body,
    );
  }

  static String _pct(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// Pinned under the form: the total and the one button that saves.
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.s,
    required this.label,
    required this.onPressed,
  });

  final InvoiceFormState s;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = s.totals?.finalTotal;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.md,
        AppSpace.page,
        AppSpace.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: t.sheet,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Amount',
                style: AppType.caption.copyWith(color: t.textMuted),
              ),
              total == null
                  ? Text('—', style: AppText.display(24, color: t.textMuted))
                  : MoneyText(total, style: AppText.display(24, color: t.text)),
            ],
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: AppButton(
              label: label,
              icon: Icons.check_rounded,
              loading: s.submitting,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}
