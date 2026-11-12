import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/shop/data/shop_repository.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

class _ClosureQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final closureQueryProvider = NotifierProvider<_ClosureQuery, String>(
  _ClosureQuery.new,
);

final closuresProvider =
    AsyncNotifierProvider<ClosuresController, PagedState<ShopClosureItem>>(
      ClosuresController.new,
      retry: (_, _) => null,
    );

/// The closures, newest first; reloads on search.
class ClosuresController extends PagedNotifier<ShopClosureItem> {
  @override
  Future<PagedResult<ShopClosureItem>> fetch(int page) => ref
      .read(shopRepositoryProvider)
      .closures(q: ref.read(closureQueryProvider), page: page);

  @override
  Future<PagedState<ShopClosureItem>> build() {
    ref.watch(currentUserProvider);
    ref.watch(closureQueryProvider);
    return super.build();
  }
}

/// The web's Shop Closures ("Schedule full-day or partial shop closures").
class ClosuresPage extends ConsumerWidget {
  const ClosuresPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    ShopClosureItem? c,
  ]) async {
    final msg = await showAppSheet<String>(
      context,
      title: c == null ? 'Add Closures' : 'Update Closures',
      builder: (_) => _ClosureForm(closure: c),
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(closuresProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ShopClosureItem c,
  ) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Shop Closures?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final msg = await ref.read(shopRepositoryProvider).deleteClosure(c.id);
      if (!context.mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(closuresProvider);
    } on Failure catch (f) {
      if (context.mounted) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final query = ref.watch(closureQueryProvider);
    final canEdit = user.can(Perm.shopClosuresEdit);
    final canDelete = user.can(Perm.shopClosuresDelete);
    return AdminListShell(
      title: 'Shop Closures',
      subtitle: 'Schedule full-day or partial shop closures',
      addLabel: 'Add Closures',
      onAdd: user.can(Perm.shopClosuresAdd) ? () => _edit(context, ref) : null,
      searchHint: 'Search reason',
      query: query,
      onSearch: (q) => ref.read(closureQueryProvider.notifier).set(q),
      body: PagedBody<ShopClosureItem>(
        async: ref.watch(closuresProvider),
        countLabel: query.trim().isEmpty ? 'ALL CLOSURES' : 'FOUND',
        emptyTitle: query.trim().isEmpty
            ? 'No closures planned'
            : 'No closures found',
        emptyMessage: query.trim().isEmpty
            ? 'Holidays and short closures you add are listed here.'
            : 'Try another word of the reason.',
        onRefresh: () => ref.read(closuresProvider.notifier).refresh(),
        onRetry: () => ref.invalidate(closuresProvider),
        onMore: () => ref.read(closuresProvider.notifier).loadMore(),
        itemBuilder: (context, c) => AdminTile(
          title: ShopTime.fullDate(ShopTime.parseDate(c.date)),
          icon: Icons.event_busy_rounded,
          badge: StatusPill(
            label: c.fullDay ? 'Full Day' : 'Partial Day',
            color: c.fullDay ? t.danger : t.warning,
            compact: true,
          ),
          lines: [c.label, if ((c.reason ?? '').trim().isNotEmpty) c.reason!],
          menu: [
            if (canEdit) ('edit', 'Edit', false),
            if (canDelete) ('delete', 'Delete', true),
          ],
          onMenu: (v) =>
              v == 'edit' ? _edit(context, ref, c) : _delete(context, ref, c),
          onTap: canEdit ? () => _edit(context, ref, c) : null,
        ),
      ),
    );
  }
}

/// "Add Closures": Date *, Full Day Closure, Start Time *, End Time *, Reason *.
class _ClosureForm extends ConsumerStatefulWidget {
  const _ClosureForm({this.closure});

  final ShopClosureItem? closure;

  @override
  ConsumerState<_ClosureForm> createState() => _ClosureFormState();
}

class _ClosureFormState extends ConsumerState<_ClosureForm> {
  late String? _date = widget.closure?.date;
  late bool _full = widget.closure?.fullDay ?? true;
  late String? _start = widget.closure?.start;
  late String? _end = widget.closure?.end;
  late final _reason = TextEditingController(text: widget.closure?.reason);
  final _errors = <String, String>{};
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = ShopTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date == null ? now : ShopTime.parseDate(_date!),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() {
        _date = ShopTime.ymd(picked);
        _errors.remove('date');
      });
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final cur = (start ? _start : _end)?.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: cur == null
          ? TimeOfDay(hour: start ? 9 : 17, minute: 0)
          : TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = _hhmm(picked);
        _errors.remove('start');
      } else {
        _end = _hhmm(picked);
        _errors.remove('end');
      }
    });
  }

  bool _validate() {
    final e = <String, String>{};
    if (_date == null) e['date'] = 'Please select the closure date';
    if (!_full) {
      if (_start == null) {
        e['start'] = 'Start time is required if not a full day closure';
      }
      if (_end == null) {
        e['end'] = 'End time is required if not a full day closure';
      }
    }
    if (_reason.text.trim().isEmpty) {
      e['reason'] = 'Please enter the reason for closure';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final input = ClosureInput(
      date: _date!,
      fullDay: _full,
      start: _start,
      end: _end,
      reason: _reason.text,
    );
    try {
      final repo = ref.read(shopRepositoryProvider);
      final c = widget.closure;
      final msg = c == null
          ? await repo.createClosure(input)
          : await repo.updateClosure(c.id, input);
      if (mounted) Navigator.of(context).pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final e in {
          'date': 'date',
          'start_time': 'start',
          'end_time': 'end',
          'reason': 'reason',
        }.entries) {
          final m = f.errorFor(e.key);
          if (m != null) _errors[e.value] = m;
        }
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget field(
      String label,
      String? value,
      String? error,
      VoidCallback onTap, {
      required String empty,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onTap: onTap,
            minSize: 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: error == null ? t.border : t.danger),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? empty,
                    style: AppType.bodyStrong.copyWith(
                      color: value == null ? t.textMuted : t.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: AppType.caption.copyWith(color: t.danger),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field(
          'Date *',
          _date == null ? null : ShopTime.fullDate(ShopTime.parseDate(_date!)),
          _errors['date'],
          _pickDate,
          empty: 'Select date',
        ),
        SwitchRow(
          label: 'Full Day Closure',
          value: _full,
          onChanged: (v) => setState(() => _full = v),
        ),
        const SizedBox(height: AppSpace.lg),
        if (!_full) ...[
          field(
            'Start Time *',
            _start == null ? null : ShopTime.timeLabel(_start!),
            _errors['start'],
            () => _pickTime(start: true),
            empty: 'Select time',
          ),
          field(
            'End Time *',
            _end == null ? null : ShopTime.timeLabel(_end!),
            _errors['end'],
            () => _pickTime(start: false),
            empty: 'Select time',
          ),
        ],
        AppTextField(
          label: 'Reason *',
          hint: 'Why is the shop closed?',
          controller: _reason,
          errorText: _errors['reason'],
          maxLines: 3,
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'Save', loading: _busy, onPressed: _save),
      ],
    );
  }
}
