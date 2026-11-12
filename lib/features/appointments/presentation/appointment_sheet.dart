import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/appointments_controller.dart';
import 'package:barbershop_app/features/appointments/application/slots_controller.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/presentation/widgets/slot_groups.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/shared/contact_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens an appointment as a shutter that rises from the bottom: drag it up
/// for everything about the customer and the booking, with every action the
/// web has (Confirm, Cancel, Reschedule...). One sheet for Home, the list and
/// the Calendar, so a booking always looks and behaves the same. It opens on
/// the root navigator, so it covers the floating nav bar.
Future<void> showAppointmentSheet(
  BuildContext context, {
  required AppointmentRow row,

  /// The barber column the booking was opened from (the Calendar), so Edit
  /// changes that barber's part of a multi-barber booking.
  int? laneStaffId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 520),
      reverseDuration: Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) => AppointmentSheet(row: row, laneStaffId: laneStaffId),
  );
}

enum _View { details, reschedule }

class AppointmentSheet extends ConsumerStatefulWidget {
  const AppointmentSheet({super.key, required this.row, this.laneStaffId});

  final AppointmentRow row;
  final int? laneStaffId;

  @override
  ConsumerState<AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends ConsumerState<AppointmentSheet> {
  _View _view = _View.details;
  String? _busy;

  void _reloadEverywhere() {
    ref.invalidate(appointmentDetailProvider(widget.row.id));
    ref.invalidate(appointmentListProvider);
    ref.invalidate(appointmentCountsProvider);
    ref.invalidate(homeProvider);
    ref.invalidate(calendarProvider);
  }

  Future<bool> _run(
    String key,
    Future<void> Function() action,
    String done,
  ) async {
    setState(() => _busy = key);
    try {
      await action();
      _reloadEverywhere();
      if (mounted) showToast(context, done, kind: ToastKind.success);
      return true;
    } on Failure catch (f) {
      if (!mounted) return false;
      showToast(context, f.userMessage, kind: ToastKind.error);
      if (f is ConflictFailure) _reloadEverywhere();
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final detail = ref.watch(appointmentDetailProvider(widget.row.id));
    // The list row is shown at once; the detail replaces it when it arrives.
    final row = detail.value?.row ?? widget.row;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.72, 0.95],
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: t.sheet,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: AppMotion.normal,
            switchInCurve: AppMotion.curve,
            child: _view == _View.details
                ? _Details(
                    key: const ValueKey('details'),
                    scroll: scroll,
                    row: row,
                    detail: detail,
                    busy: _busy,
                    onClose: () => Navigator.of(context).pop(),
                    onEdit: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      final lane = widget.laneStaffId;
                      router.push(
                        '/app/appointment/edit/${row.id}${lane == null ? '' : '?staff=$lane'}',
                      );
                    },
                    onComplete: () {
                      // The web's Complete opens the invoice page for this appointment.
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.push('/app/invoice/complete/${row.id}');
                    },
                    onReschedule: () =>
                        setState(() => _view = _View.reschedule),
                    onConfirm: () => _run(
                      'confirm',
                      () => ref
                          .read(appointmentsRepositoryProvider)
                          .confirm(row.id),
                      'Appointment confirmed.',
                    ),
                    onCancel: () async {
                      final ok = await showConfirm(
                        context,
                        title: 'Are you sure?',
                        message: 'Are you sure to cancel order?',
                        confirmLabel: 'Yes, confirm!',
                        cancelLabel: 'Cancel',
                        destructive: true,
                      );
                      if (ok) {
                        await _run(
                          'cancel',
                          () => ref
                              .read(appointmentsRepositoryProvider)
                              .cancel(row.id),
                          'Appointment cancelled.',
                        );
                      }
                    },
                  )
                : _Reschedule(
                    key: const ValueKey('reschedule'),
                    scroll: scroll,
                    row: row,
                    detail: detail.value,
                    busy: _busy == 'reschedule',
                    onBack: () => setState(() => _view = _View.details),
                    onSubmit: (date, slot) async {
                      final ok = await _run(
                        'reschedule',
                        () => ref
                            .read(appointmentsRepositoryProvider)
                            .reschedule(
                              row.id,
                              date: date,
                              slotStart: slot.start,
                              slotEnd: slot.end,
                            ),
                        'Appointment rescheduled.',
                      );
                      if (ok && mounted) {
                        setState(() => _view = _View.details);
                      }
                    },
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- details

class _Details extends ConsumerWidget {
  const _Details({
    super.key,
    required this.scroll,
    required this.row,
    required this.detail,
    required this.busy,
    required this.onClose,
    required this.onEdit,
    required this.onReschedule,
    required this.onConfirm,
    required this.onComplete,
    required this.onCancel,
  });

  final ScrollController scroll;
  final AppointmentRow row;
  final AsyncValue<AppointmentDetail> detail;
  final String? busy;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onReschedule;
  final VoidCallback onConfirm;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final d = detail.value;
    final color = t.statusColor(row.status);
    final date = ShopTime.parseDate(row.date);
    final phone = (row.customerPhone ?? '').trim();
    final email = (d?.customerEmail ?? '').trim();
    final user = ref.watch(currentUserProvider);
    // "Complete" creates an invoice, so it needs the permission to add one.
    final actions = [
      for (final a in row.actions)
        if (a != 'view' && (a != 'complete' || user.canCompleteBooking)) a,
    ];
    final customerId = d?.customerId;
    final summary = (customerId != null && user.modules.customers)
        ? ref.watch(customerSummaryProvider(customerId))
        : null;
    final staff = (d?.barbers ?? row.staffNames);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              // A soft wash of the status colour behind the header.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 170,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: t.isDark ? 0.18 : 0.14),
                        color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  10,
                  AppSpace.page,
                  AppSpace.xl,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.textMuted.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Reveal(
                    child: Row(
                      children: [
                        AppointmentStatusPill(row.status),
                        const Spacer(),
                        // Edit (the calendar's update form): open bookings only.
                        if (user.modules.calendar &&
                            row.actions.contains('cancel')) ...[
                          Semantics(
                            button: true,
                            label: 'Edit',
                            child: Pressable(
                              onTap: onEdit,
                              minSize: 0,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.surface,
                                  border: Border.all(color: t.border),
                                ),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 17,
                                  color: t.text,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                        ],
                        Semantics(
                          button: true,
                          label: 'Close',
                          child: Pressable(
                            onTap: onClose,
                            minSize: 0,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.surface,
                                border: Border.all(color: t.border),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 19,
                                color: t.text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Reveal(
                    delay: const Duration(milliseconds: 50),
                    child: Text(
                      row.customerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.display(30, color: t.text, height: 1.1),
                    ),
                  ),
                  if (phone.isNotEmpty || email.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Reveal(
                      delay: const Duration(milliseconds: 80),
                      child: Text(
                        [
                          if (phone.isNotEmpty) phone,
                          if (email.isNotEmpty) email,
                        ].join('  ·  '),
                        style: AppType.body.copyWith(color: t.textSecondary),
                      ),
                    ),
                  ],
                  if (row.bookingCode != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      row.bookingCode!,
                      style: AppType.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.lg),
                    Reveal(
                      delay: const Duration(milliseconds: 110),
                      child: Row(
                        children: [
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.call_rounded,
                              label: 'Call',
                              onTap: () => callCustomer(context, phone),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm + 2),
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.sms_rounded,
                              label: 'Message',
                              onTap: () => messageCustomer(context, phone),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm + 2),
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.copy_rounded,
                              label: 'Copy',
                              onTap: () => copyPhone(context, phone),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (summary != null) ...[
                    const SizedBox(height: AppSpace.md),
                    Reveal(
                      delay: const Duration(milliseconds: 140),
                      child: summary.when(
                        data: (c) => _CustomerFacts(c: c),
                        loading: () => const SkeletonLoader(
                          child: SkeletonBox(height: 66, radius: 16),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  const Reveal(
                    delay: Duration(milliseconds: 170),
                    child: _Heading('Appointment Details'),
                  ),
                  Reveal(
                    delay: const Duration(milliseconds: 190),
                    child: _Panel(
                      children: [
                        _InfoRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Date',
                          value:
                              '${ShopTime.weekdayLong(date)}, ${ShopTime.fullDate(date)}',
                        ),
                        _InfoRow(
                          icon: Icons.schedule_rounded,
                          label: 'Time',
                          value: '${row.startLabel} - ${row.endLabel}',
                          note: d != null && d.totalMinutes > 0
                              ? '${d.totalMinutes} min'
                              : null,
                        ),
                        _InfoRow(
                          icon: Icons.person_rounded,
                          label: 'Staff',
                          value: staff.isEmpty ? '-' : staff.join(', '),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  const Reveal(
                    delay: Duration(milliseconds: 220),
                    child: _Heading('Services'),
                  ),
                  Reveal(
                    delay: const Duration(milliseconds: 240),
                    child: d == null
                        ? (detail.hasError
                              ? ErrorState(
                                  title: 'Could not load the details',
                                  message: detail.error is Failure
                                      ? (detail.error! as Failure).userMessage
                                      : 'Please try again.',
                                  onRetry: () => ref.invalidate(
                                    appointmentDetailProvider(row.id),
                                  ),
                                )
                              : const SkeletonLoader(
                                  child: SkeletonBox(height: 120, radius: 16),
                                ))
                        : _Services(d: d),
                  ),
                  if ((d?.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xl),
                    const _Heading('Notes'),
                    _Panel(
                      children: [
                        Text(
                          d!.notes!,
                          style: AppType.body.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ),
                  ],
                  if (d?.isInvoiced == true) ...[
                    const SizedBox(height: AppSpace.xl),
                    _Panel(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.receipt_long_rounded, color: t.success),
                            const SizedBox(width: AppSpace.md),
                            Text(
                              'Invoiced${d!.invoiceNumber != null ? ' · ${d.invoiceNumber}' : ''}',
                              style: AppType.bodyStrong.copyWith(color: t.text),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty)
          _ActionBar(
            actions: actions,
            busy: busy,
            onConfirm: onConfirm,
            onComplete: onComplete,
            onCancel: onCancel,
            onReschedule: onReschedule,
          ),
      ],
    );
  }
}

/// The sheet's buttons, exactly the web's set for this status and in its
/// order (Confirm, Complete, Cancel, Reschedule), two to a row.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.actions,
    required this.busy,
    required this.onConfirm,
    required this.onComplete,
    required this.onCancel,
    required this.onReschedule,
  });

  /// Action names from the server ("confirm", "complete", "cancel"...).
  final List<String> actions;
  final String? busy;
  final VoidCallback onConfirm;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final idle = busy == null;

    Widget? button(String a) => switch (a) {
      'confirm' => AppButton(
        label: 'Confirm',
        icon: Icons.check_rounded,
        compact: true,
        loading: busy == 'confirm',
        onPressed: idle ? onConfirm : null,
      ),
      'complete' => AppButton(
        label: 'Complete',
        icon: Icons.task_alt_rounded,
        variant: AppButtonVariant.success,
        compact: true,
        onPressed: idle ? onComplete : null,
      ),
      'cancel' => AppButton(
        label: 'Cancel',
        icon: Icons.close_rounded,
        variant: AppButtonVariant.dangerOutline,
        compact: true,
        loading: busy == 'cancel',
        onPressed: idle ? onCancel : null,
      ),
      'reschedule' => AppButton(
        label: 'Reschedule',
        icon: Icons.event_repeat_rounded,
        variant: AppButtonVariant.secondary,
        compact: true,
        onPressed: idle ? onReschedule : null,
      ),
      _ => null,
    };

    final buttons = [for (final a in actions) ?button(a)];
    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: buttons[i]),
            if (i + 1 < buttons.length) ...[
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(child: buttons[i + 1]),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.md,
        AppSpace.page,
        AppSpace.md + bottom,
      ),
      decoration: BoxDecoration(
        color: t.sheet,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm + 2),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _Services extends StatelessWidget {
  const _Services({required this.d});

  final AppointmentDetail d;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Panel(
      children: [
        for (var i = 0; i < d.services.length; i++) ...[
          if (i > 0) _Rule(),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.services[i].qty > 1
                          ? '${d.services[i].name} × ${d.services[i].qty}'
                          : d.services[i].name,
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.services[i].unitPrice.format()} · ${d.services[i].durationMinutes} min',
                      style: AppType.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                d.services[i].lineTotal.format(),
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
            ],
          ),
        ],
        _Rule(),
        Row(
          children: [
            Text('Total', style: AppType.bodyStrong.copyWith(color: t.text)),
            const Spacer(),
            MoneyText(d.total, style: AppText.display(22, color: t.text)),
          ],
        ),
      ],
    );
  }
}

class _CustomerFacts extends StatelessWidget {
  const _CustomerFacts({required this.c});

  final CustomerSummary c;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget cell(String value, String label) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppType.heading.copyWith(color: t.text, fontSize: 17),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
    Widget divider() => Container(width: 1, height: 30, color: t.border);
    final since = c.memberSince == null
        ? '-'
        : ShopTime.fullDate(ShopTime.parseDate(c.memberSince!));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          cell('${c.totalVisits}', 'Visits'),
          divider(),
          cell('${c.appointmentsTotal}', 'Appointments'),
          divider(),
          cell(since, 'Customer since'),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onTap,
      minSize: 0,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: t.isDark ? 0.12 : 0.16),
          borderRadius: AppRadius.card,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: t.accentText),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppType.label.copyWith(color: t.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
    child: Text(
      text,
      style: AppType.subheading.copyWith(color: context.tokens.text),
    ),
  );
}

/// A rounded white (or dark) card holding rows; rows are separated by rules.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && children[i - 1] is! _Rule && children[i] is! _Rule) {
        rows.add(_Rule());
      }
      rows.add(children[i]);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(children: rows),
    );
  }
}

class _Rule extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
    child: Divider(height: 1, color: context.tokens.border),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: t.accentText),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppType.caption.copyWith(color: t.textMuted)),
              const SizedBox(height: 1),
              Text(
                value,
                style: AppType.body.copyWith(color: t.text, fontSize: 15),
              ),
            ],
          ),
        ),
        if (note != null)
          Text(note!, style: AppType.caption.copyWith(color: t.textMuted)),
      ],
    );
  }
}

// ------------------------------------------------------------- reschedule

/// "Reschedule Appointment": pick a day, then a free time ("Select Time").
class _Reschedule extends ConsumerStatefulWidget {
  const _Reschedule({
    super.key,
    required this.scroll,
    required this.row,
    required this.detail,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
  });

  final ScrollController scroll;
  final AppointmentRow row;
  final AppointmentDetail? detail;
  final bool busy;
  final VoidCallback onBack;
  final Future<void> Function(String date, TimeSlot slot) onSubmit;

  @override
  ConsumerState<_Reschedule> createState() => _RescheduleState();
}

class _RescheduleState extends ConsumerState<_Reschedule> {
  late DateTime _date = _firstDay();
  TimeSlot? _slot;
  bool _missing = false;

  DateTime _firstDay() {
    final d = ShopTime.parseDate(widget.row.date);
    return d.isBefore(ShopTime.today()) ? ShopTime.today() : d;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = widget.detail;
    final ready = d != null && d.staffIds.isNotEmpty && d.serviceIds.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              10,
              AppSpace.page,
              AppSpace.xl,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.textMuted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  RoundBackButton(onPressed: widget.onBack),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reschedule Appointment',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          widget.row.customerName,
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                '${ShopTime.weekdayLong(_date)}, ${ShopTime.fullDate(_date)}',
                style: AppType.subheading.copyWith(color: t.text),
              ),
              const SizedBox(height: AppSpace.sm),
              DateStrip(
                selected: _date,
                pastDays: 0,
                futureDays: 90,
                onSelected: (day) => setState(() {
                  _date = day;
                  _slot = null;
                  _missing = false;
                }),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                'Select Time',
                style: AppType.subheading.copyWith(color: t.text),
              ),
              const SizedBox(height: AppSpace.md),
              if (!ready)
                const SkeletonLoader(
                  child: SkeletonBox(height: 120, radius: 16),
                )
              else
                _Slots(
                  query: SlotQuery(
                    date: ShopTime.ymd(_date),
                    staffIds: d.staffIds,
                    serviceIds: d.serviceIds,
                  ),
                  selected: _slot,
                  onSelected: (s) => setState(() {
                    _slot = s;
                    _missing = false;
                  }),
                ),
            ],
          ),
        ),
        Container(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text(
                    'Please Select Slot!!',
                    style: AppType.label.copyWith(color: t.danger),
                  ),
                ),
              AppButton(
                label: 'Reschedule',
                compact: true,
                loading: widget.busy,
                onPressed: () {
                  if (_slot == null) {
                    setState(() => _missing = true);
                    return;
                  }
                  widget.onSubmit(ShopTime.ymd(_date), _slot!);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Slots extends ConsumerWidget {
  const _Slots({
    required this.query,
    required this.selected,
    required this.onSelected,
  });

  final SlotQuery query;
  final TimeSlot? selected;
  final ValueChanged<TimeSlot> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final res = ref.watch(slotsProvider(query));
    return res.when(
      loading: () =>
          const SkeletonLoader(child: SkeletonBox(height: 120, radius: 16)),
      error: (e, _) => ErrorState(
        title: 'Could not load times',
        message: e is Failure ? e.userMessage : 'Please try again.',
        onRetry: () => ref.invalidate(slotsProvider(query)),
      ),
      data: (r) {
        if (r.slots.isEmpty) {
          return _Panel(
            children: [
              Text(
                r.message ?? 'No free times on this day. Try another day.',
                style: AppType.body.copyWith(color: t.textSecondary),
              ),
            ],
          );
        }
        return SlotGroups(
          slots: r.slots,
          selected: selected,
          onSelected: onSelected,
        );
      },
    );
  }
}
