import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/booking_form_controller.dart';
import 'package:barbershop_app/features/appointments/domain/booking.dart';
import 'package:barbershop_app/features/appointments/presentation/widgets/slot_groups.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web calendar's "Add Appointment" form (Full Name, Phone, Email, Service,
/// Staff, Date + time) as one scrolling page. The same page edits a booking.
class BookingFormPage extends ConsumerStatefulWidget {
  const BookingFormPage({super.key, required this.target});

  final BookingTarget target;

  @override
  ConsumerState<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends ConsumerState<BookingFormPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  bool _filled = false;

  /// What the suggestion list searches for (set while typing name or phone).
  String _query = '';

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(BookingDraft d) {
    if (_filled) return;
    _filled = true;
    _name.text = d.name;
    _phone.text = d.phone;
    _email.text = d.email;
    _notes.text = d.notes;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final ctl = ref.read(bookingFormProvider(widget.target).notifier);
    final err = await ctl.submit();
    if (!mounted) return;
    if (err != null) {
      showToast(context, err, kind: ToastKind.error);
      return;
    }
    final saved = widget.target.editId != null
        ? 'Appointment updated.'
        : 'Appointment saved.';
    // The burst lives in the root overlay, so it keeps playing as the form closes.
    showSuccessBurst(context);
    showToast(context, saved, kind: ToastKind.success);
    context.pop();
  }

  /// "Check before you save": who, what, with whom and when, with anything
  /// unusual called out. Edit goes back to the form untouched; Done saves.
  Future<void> _review() async {
    FocusScope.of(context).unfocus();
    // The state as it is now, not as it was when the button was last built.
    final s = ref.read(bookingFormProvider(widget.target));
    final d = s.draft;
    final String? problem = d.name.trim().isEmpty
        ? 'Full Name is required.'
        : d.phone.trim().isEmpty
        ? 'Phone is required.'
        : d.lines.isEmpty
        ? 'Please select at least one service.'
        : d.staffId == null
        ? 'Select Staff'
        : d.slot == null
        ? 'Please Select Slot!!'
        : null;
    if (problem != null) {
      showToast(context, problem, kind: ToastKind.error);
      return;
    }
    final slot = d.slot!;
    final barber = [
      ...s.barbers,
      ...s.allBarbers,
    ].where((b) => b.id == d.staffId).firstOrNull;
    final date = d.date == null
        ? ShopTime.today()
        : ShopTime.parseDate(d.date!);
    final time = slot.custom || slot.startLabel == slot.endLabel
        ? slot.startLabel
        : '${slot.startLabel} – ${slot.endLabel}';

    final warnings = <String>[];
    final today = ShopTime.today();
    final now = ShopTime.now();
    if (date.isBefore(today)) {
      warnings.add('This date is in the past.');
    } else if (ShopTime.isSameDay(date, today) &&
        ShopTime.minutes(slot.start) < now.hour * 60 + now.minute) {
      warnings.add('This time has already passed today.');
    }
    final email = d.email.trim();
    final ok = await showReviewSheet(
      context,
      title: 'Check the booking',
      intro: widget.target.editId != null
          ? 'You are changing this appointment.'
          : 'Make sure everything is right. Done saves it.',
      warnings: warnings,
      sections: [
        ReviewSection('Customer', [
          ReviewRow(d.name.trim(), ''),
          ReviewRow('Phone', d.phone.trim()),
          if (email.isNotEmpty) ReviewRow('Email', email),
        ], icon: Icons.person_rounded),
        ReviewSection('Services', [
          for (final l in d.lines)
            ReviewRow(
              l.qty > 1 ? '${l.service.name} x ${l.qty}' : l.service.name,
              Money(l.service.price.cents * l.qty).format(),
              note: '${l.service.durationMinutes * l.qty} min',
            ),
        ], icon: Icons.content_cut_rounded),
        ReviewSection('When and with whom', [
          ReviewRow('Barber', barber?.name ?? 'Selected barber'),
          ReviewRow(
            'Date',
            '${ShopTime.weekdayLong(date)}, ${ShopTime.fullDate(date)}',
          ),
          ReviewRow('Time', time),
          ReviewRow('Duration', '${d.totalMinutes} min'),
          if (d.notes.trim().isNotEmpty) ReviewRow('Notes', d.notes.trim()),
        ], icon: Icons.event_rounded),
      ],
      total: ReviewRow('Total', d.total.format()),
    );
    // Closing the sheet hands focus back to the last field and opens the
    // keyboard; the form should look as it did.
    if (mounted) FocusScope.of(context).unfocus();
    if (ok && mounted) await _save();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final provider = bookingFormProvider(widget.target);
    final s = ref.watch(provider);
    final ctl = ref.read(provider.notifier);
    final editing = widget.target.editId != null;
    if (!s.loading && s.loadError == null) _fill(s.draft);

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
                        : context.go('/app/calendar'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      editing ? 'Update Appointment' : 'Add Appointment',
                      style: AppType.heading.copyWith(color: t.text),
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
                            SkeletonBox(height: 190, radius: 16),
                            SizedBox(height: AppSpace.md),
                            SkeletonBox(height: 120, radius: 16),
                          ],
                        ),
                      ),
                    )
                  : s.loadError != null
                  ? ErrorState(
                      message: s.loadError is Failure
                          ? (s.loadError! as Failure).userMessage
                          : 'Could not open the form.',
                      onRetry: () => ref.invalidate(provider),
                    )
                  : _Body(
                      s: s,
                      ctl: ctl,
                      target: widget.target,
                      name: _name,
                      phone: _phone,
                      email: _email,
                      notes: _notes,
                      query: _query,
                      onQuery: (q) => setState(() => _query = q),
                    ),
            ),
            if (!s.loading && s.loadError == null)
              _SaveBar(
                s: s,
                label: editing ? 'Review changes' : 'Review appointment',
                onPressed: s.submitting ? null : _review,
              ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.s,
    required this.ctl,
    required this.target,
    required this.name,
    required this.phone,
    required this.email,
    required this.notes,
    required this.query,
    required this.onQuery,
  });

  final BookingFormState s;
  final BookingFormController ctl;
  final BookingTarget target;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController notes;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final d = s.draft;
    final user = ref.watch(currentUserProvider);
    final date = d.date == null
        ? ShopTime.today()
        : ShopTime.parseDate(d.date!);
    final staffList = d.lines.isEmpty ? s.allBarbers : s.barbers;
    final showSuggestions =
        user.modules.customers &&
        target.editId == null &&
        query.trim().length >= 3;

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
                label: 'Phone',
                hint: 'Enter phone number',
                prefixIcon: Icons.phone_outlined,
                clearable: true,
                controller: phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  ctl.setCustomer(phone: v);
                  onQuery(v);
                },
              ),
              if (showSuggestions)
                _Suggestions(
                  query: query.trim(),
                  onPick: (c) {
                    name.text = c.name;
                    phone.text = c.phone ?? '';
                    email.text = c.email ?? '';
                    ctl.setCustomer(
                      name: c.name,
                      phone: c.phone ?? '',
                      email: c.email ?? '',
                    );
                    onQuery('');
                  },
                ),
              const SizedBox(height: AppSpace.md),
              AppTextField(
                label: 'Full Name',
                hint: 'Enter customer name',
                prefixIcon: Icons.person_outline_rounded,
                clearable: true,
                controller: name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  ctl.setCustomer(name: v);
                  if (phone.text.trim().length < 3) onQuery(v);
                },
              ),
              const SizedBox(height: AppSpace.md),
              AppTextField(
                label: 'Email',
                hint: 'Optional',
                prefixIcon: Icons.mail_outline_rounded,
                clearable: true,
                controller: email,
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => ctl.setCustomer(email: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        title('Service'),
        for (final l in d.lines) ...[
          _ServiceCard(line: l, onQty: (q) => ctl.setQty(l.service.id, q)),
          const SizedBox(height: AppSpace.sm + 2),
        ],
        AppButton(
          label: d.lines.isEmpty ? 'Select Service' : 'Add another service',
          icon: Icons.content_cut_rounded,
          variant: AppButtonVariant.secondary,
          compact: true,
          onPressed: () => showBookingServicePicker(context, target: target),
        ),
        // Staff, Date and Time are always on the form (like the web). Until a
        // service is chosen "Staff" lists every barber; times need a service.
        const SizedBox(height: AppSpace.xl),
        title('Staff'),
        if (s.barbersLoading && staffList.isEmpty)
          const SkeletonLoader(child: SkeletonBox(height: 38, radius: 19))
        else if (staffList.isEmpty)
          Text(
            d.lines.isEmpty
                ? 'No barbers found.'
                : 'No barber offers all of these services.',
            style: AppType.body.copyWith(color: t.danger),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in staffList)
                AppChoiceChip(
                  label: b.name,
                  selected: d.staffId == b.id,
                  onTap: () => ctl.setStaff(b.id),
                ),
            ],
          ),
        const SizedBox(height: AppSpace.xl),
        title('Date'),
        Text(
          '${ShopTime.weekdayLong(date)}, ${ShopTime.fullDate(date)}',
          style: AppType.body.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),
        DateStrip(
          selected: date,
          pastDays: 0,
          futureDays: 90,
          onSelected: ctl.setDate,
        ),
        const SizedBox(height: AppSpace.xl),
        title('Select Time'),
        if (d.lines.isEmpty || d.staffId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
            child: Text(
              d.lines.isEmpty
                  ? 'Select a service and a barber to see the free times, or choose a time yourself.'
                  : 'Select a barber to see the free times, or choose a time yourself.',
              style: AppType.caption.copyWith(color: t.textMuted),
            ),
          )
        else if (s.slotsLoading && s.slots == null)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.sm + 2),
            child: SkeletonLoader(child: SkeletonBox(height: 90, radius: 16)),
          )
        else if (s.slots != null && s.slots!.slots.isEmpty && s.current == null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
            child: Text(
              s.slots!.message ??
                  'No free times on this day. Try another day or choose a time yourself.',
              style: AppType.body.copyWith(color: t.textSecondary),
            ),
          )
        else if (s.slots != null)
          AnimatedOpacity(
            duration: AppMotion.fast,
            opacity: s.slotsLoading ? 0.5 : 1,
            child: SlotGroups(
              slots: s.slots!.slots,
              selected: d.slot,
              current:
                  d.date == (s.current == null ? null : target.date ?? d.date)
                  ? s.current
                  : null,
              onSelected: ctl.setSlot,
            ),
          ),
        // Any time of day, like the web's date-time field.
        AppChoiceChip(
          label: d.slot?.custom == true
              ? 'Time: ${d.slot!.startLabel}'
              : 'Choose time',
          icon: Icons.schedule_rounded,
          selected: d.slot?.custom == true,
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: d.slot == null
                  ? const TimeOfDay(hour: 10, minute: 0)
                  : TimeOfDay(
                      hour: int.parse(d.slot!.start.split(':')[0]),
                      minute: int.parse(d.slot!.start.split(':')[1]),
                    ),
            );
            if (picked != null) ctl.setCustomTime(picked.hour, picked.minute);
          },
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Notes (Optional)',
          controller: notes,
          maxLines: 2,
          onChanged: (v) => ctl.setCustomer(notes: v),
        ),
        // The web's update modal also has "Make Payment" (the invoice page).
        if (target.editId != null && user.canCompleteBooking) ...[
          const SizedBox(height: AppSpace.lg),
          AppButton(
            label: 'Make Payment',
            icon: Icons.task_alt_rounded,
            variant: AppButtonVariant.success,
            compact: true,
            onPressed: () =>
                context.push('/app/invoice/complete/${target.editId}'),
          ),
        ],
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.line, required this.onQty});

  final BookingLine line;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.content_cut_rounded,
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
                  line.service.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
                Text(
                  '${line.service.price.format()} · ${line.service.durationMinutes} min',
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
            onPressed: () => onQty(0),
          ),
        ],
      ),
    );
  }
}

/// Existing customers that match what is being typed; tap to fill the form.
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.query, required this.onPick});

  final String query;
  final ValueChanged<CustomerSummary> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final res = ref.watch(customerSearchProvider(query));
    final list = res.value ?? const <CustomerSummary>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in list)
            Pressable(
              onTap: () => onPick(c),
              minSize: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: t.accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_rounded, size: 15, color: t.accentText),
                    const SizedBox(width: 6),
                    Text(
                      '${c.name} · ${c.phone ?? ''}',
                      style: AppType.label.copyWith(
                        color: t.text,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.s,
    required this.label,
    required this.onPressed,
  });

  final BookingFormState s;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = s.draft;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.lines.isEmpty
                      ? 'No service yet'
                      : [
                          '${d.serviceCount} ${d.serviceCount == 1 ? 'service' : 'services'}',
                          '${d.totalMinutes} min',
                          if (d.slot != null) d.slot!.startLabel,
                        ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
                Text(
                  d.total.format(),
                  style: AppText.display(22, color: t.text),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: AppButton(
              label: label,
              icon: Icons.fact_check_rounded,
              loading: s.submitting,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Select Service": the shop's services, grouped by category; tap to add,
/// tap again for one more.
Future<void> showBookingServicePicker(
  BuildContext context, {
  required BookingTarget target,
}) {
  return showAppSheet<void>(
    context,
    title: 'Select Service',
    builder: (_) => _ServicePicker(target: target),
    footer: (ctx) => AppButton(
      label: 'Done',
      compact: true,
      onPressed: () => Navigator.of(ctx).pop(),
    ),
  );
}

class _ServicePicker extends ConsumerStatefulWidget {
  const _ServicePicker({required this.target});

  final BookingTarget target;

  @override
  ConsumerState<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends ConsumerState<_ServicePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final provider = bookingFormProvider(widget.target);
    final s = ref.watch(provider);
    final ctl = ref.read(provider.notifier);
    final q = _q.trim().toLowerCase();
    int count(int id) => s.draft.lines
        .where((l) => l.service.id == id)
        .fold(0, (a, l) => a + l.qty);

    final children = <Widget>[
      AppSearchField(hint: 'Search', onChanged: (v) => setState(() => _q = v)),
      const SizedBox(height: AppSpace.md),
    ];
    for (final c in s.categories) {
      final services = [
        for (final sv in c.services)
          if (q.isEmpty || sv.name.toLowerCase().contains(q)) sv,
      ];
      if (services.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.sm),
          child: Text(
            c.name.toUpperCase(),
            style: AppType.overline.copyWith(color: t.textSecondary),
          ),
        ),
      );
      for (final sv in services) {
        children.add(
          PickRow(
            name: sv.name,
            detail: '${sv.price.format()} · ${sv.durationMinutes} min',
            imageUrl: sv.imageUrl,
            count: count(sv.id),
            onTap: () => ctl.addService(sv),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
