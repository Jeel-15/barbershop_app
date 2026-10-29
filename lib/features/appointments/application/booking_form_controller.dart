import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/features/appointments/application/appointments_controller.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/domain/booking.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which booking the form is for: a new one (optionally prefilled from the
/// empty calendar slot that was tapped) or an existing one to edit.
@immutable
class BookingTarget {
  const BookingTarget({this.editId, this.staffId, this.date, this.time});

  final int? editId;
  final int? staffId;

  /// `yyyy-MM-dd`.
  final String? date;

  /// `HH:mm`.
  final String? time;

  @override
  bool operator ==(Object other) =>
      other is BookingTarget &&
      other.editId == editId &&
      other.staffId == staffId &&
      other.date == date &&
      other.time == time;

  @override
  int get hashCode => Object.hash(editId, staffId, date, time);
}

class BookingFormState {
  const BookingFormState({
    this.loading = true,
    this.loadError,
    this.categories = const [],
    this.draft = const BookingDraft(),
    this.barbers = const [],
    this.allBarbers = const [],
    this.barbersLoading = false,
    this.slots,
    this.slotsLoading = false,
    this.submitting = false,
    this.current,
  });

  final bool loading;
  final Object? loadError;
  final List<BookingCategory> categories;
  final BookingDraft draft;

  /// Barbers who offer every chosen service.
  final List<BarberOption> barbers;

  /// Every barber of this calendar: shown before any service is chosen.
  final List<BarberOption> allBarbers;
  final bool barbersLoading;

  /// Free times for the chosen barber, services and day (null = not asked yet).
  final SlotsResult? slots;
  final bool slotsLoading;
  final bool submitting;

  /// When editing: the booking's own current time, which the slot finder does
  /// not offer (it is "taken" by this very booking).
  final TimeSlot? current;

  BookingFormState copyWith({
    bool? loading,
    Object? loadError,
    List<BookingCategory>? categories,
    BookingDraft? draft,
    List<BarberOption>? barbers,
    List<BarberOption>? allBarbers,
    bool? barbersLoading,
    Object? slots = _keep,
    bool? slotsLoading,
    bool? submitting,
    TimeSlot? current,
  }) => BookingFormState(
    loading: loading ?? this.loading,
    loadError: loadError,
    categories: categories ?? this.categories,
    draft: draft ?? this.draft,
    barbers: barbers ?? this.barbers,
    allBarbers: allBarbers ?? this.allBarbers,
    barbersLoading: barbersLoading ?? this.barbersLoading,
    slots: identical(slots, _keep) ? this.slots : slots as SlotsResult?,
    slotsLoading: slotsLoading ?? this.slotsLoading,
    submitting: submitting ?? this.submitting,
    current: current ?? this.current,
  );

  static const _keep = Object();
}

final bookingFormProvider = NotifierProvider.autoDispose
    .family<BookingFormController, BookingFormState, BookingTarget>(
      BookingFormController.new,
    );

/// "Add Appointment" / "Update Appointment". The barbers and the free times
/// always come from the server, so the form can only offer what can be booked.
class BookingFormController extends Notifier<BookingFormState> {
  BookingFormController(this.target);

  final BookingTarget target;

  Timer? _debounce;
  int _seq = 0;

  AppointmentsRepository get _repo => ref.read(appointmentsRepositoryProvider);

  @override
  BookingFormState build() {
    ref.onDispose(() => _debounce?.cancel());
    unawaited(Future<void>.microtask(_load));
    return const BookingFormState();
  }

  Future<void> _load() async {
    try {
      final categories = await _repo.bookingOptions();
      // The web fills "Select Staff" with every barber until services are chosen.
      var everyone = <BarberOption>[];
      try {
        final window = await ref.read(calendarProvider.future);
        everyone = [
          for (final l in window.lanes)
            BarberOption(id: l.id, name: l.name, isFirstAvailable: false),
        ];
      } catch (_) {}
      var draft = BookingDraft(
        date: target.date ?? ShopTime.ymd(ShopTime.today()),
      );
      TimeSlot? current;
      if (target.editId != null) {
        final d = await _repo.detail(target.editId!);
        final byId = {
          for (final c in categories)
            for (final s in c.services) s.id: s,
        };
        draft = BookingDraft(
          name: d.row.customerName,
          phone: d.row.customerPhone ?? '',
          email: d.customerEmail ?? '',
          notes: d.notes ?? '',
          lines: [
            for (final s in d.services)
              BookingLine(
                byId[s.serviceId] ??
                    BookingService(
                      id: s.serviceId,
                      name: s.name,
                      price: s.unitPrice,
                      durationMinutes:
                          s.durationMinutes ~/ (s.qty == 0 ? 1 : s.qty),
                    ),
                s.qty,
              ),
          ],
          staffId:
              target.staffId ??
              (d.staffIds.isNotEmpty ? d.staffIds.first : null),
          date: d.row.date,
        );
        current = TimeSlot(
          start: d.row.start,
          end: d.row.end,
          startLabel: d.row.startLabel,
          endLabel: d.row.endLabel,
        );
        draft = draft.copyWith(slot: current);
      } else {
        if (target.staffId != null) {
          draft = draft.copyWith(staffId: target.staffId);
        }
        // The empty calendar slot that was tapped.
        final tapped = target.time?.split(':');
        if (tapped != null && tapped.length == 2) {
          draft = draft.copyWith(
            slot: TimeSlot.at(int.parse(tapped[0]), int.parse(tapped[1])),
          );
        }
      }
      state = state.copyWith(
        loading: false,
        categories: categories,
        allBarbers: everyone,
        draft: draft,
        current: current,
      );
      if (draft.lines.isNotEmpty) {
        await _loadBarbers(keepStaff: true);
        await _loadSlots(wanted: target.time);
      }
    } catch (e) {
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  // --------------------------------------------------------------- edits

  void setCustomer({
    String? name,
    String? phone,
    String? email,
    String? notes,
  }) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        name: name,
        phone: phone,
        email: email,
        notes: notes,
      ),
    );
  }

  void addService(BookingService s) {
    final lines = [...state.draft.lines];
    final i = lines.indexWhere((l) => l.service.id == s.id);
    if (i >= 0) {
      lines[i] = lines[i].withQty((lines[i].qty + 1).clamp(1, 20));
    } else {
      lines.add(BookingLine(s, 1));
    }
    _servicesChanged(lines);
  }

  void setQty(int serviceId, int qty) {
    final lines = [
      for (final l in state.draft.lines)
        if (l.service.id != serviceId)
          l
        else if (qty >= 1)
          l.withQty(qty.clamp(1, 20)),
    ];
    _servicesChanged(lines);
  }

  void _servicesChanged(List<BookingLine> lines) {
    state = state.copyWith(
      draft: state.draft.copyWith(lines: lines, slot: _keepCustom()),
      slots: null,
    );
    _debounce?.cancel();
    if (lines.isEmpty) {
      state = state.copyWith(barbers: const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      await _loadBarbers(keepStaff: true);
      await _loadSlots();
    });
  }

  /// A time typed in by hand survives changes elsewhere; an offered slot does not
  /// (the offer depends on barber, services and day).
  TimeSlot? _keepCustom() =>
      state.draft.slot?.custom == true ? state.draft.slot : null;

  Future<void> setStaff(int id) async {
    state = state.copyWith(
      draft: state.draft.copyWith(staffId: id, slot: _keepCustom()),
      slots: null,
    );
    await _loadSlots();
  }

  /// "Choose time": any time of day, like the web's date-time field.
  void setCustomTime(int hour, int minute) => state = state.copyWith(
    draft: state.draft.copyWith(slot: TimeSlot.at(hour, minute)),
  );

  Future<void> setDate(DateTime day) async {
    state = state.copyWith(
      draft: state.draft.copyWith(date: ShopTime.ymd(day), slot: _keepCustom()),
      slots: null,
    );
    await _loadSlots();
  }

  void setSlot(TimeSlot s) =>
      state = state.copyWith(draft: state.draft.copyWith(slot: s));

  // ------------------------------------------------------------- loading

  Future<void> _loadBarbers({bool keepStaff = false}) async {
    final ids = state.draft.lines.map((l) => l.service.id).toList();
    if (ids.isEmpty) return;
    state = state.copyWith(barbersLoading: true);
    try {
      final all = await _repo.staffByService(ids);
      // One barber does the whole booking, so offer those who do every service
      // (if nobody does them all, offer everyone the server listed).
      final wanted = ids.toSet();
      final doAll = [
        for (final b in all)
          if (b.offersServiceIds.isEmpty ||
              wanted.every(b.offersServiceIds.contains))
            b,
      ];
      final barbers = doAll.isEmpty ? all : doAll;
      var staff = state.draft.staffId;
      if (staff != null && barbers.every((b) => b.id != staff)) staff = null;
      // One possible barber is the obvious choice.
      if (staff == null && barbers.length == 1) staff = barbers.first.id;
      state = state.copyWith(
        barbers: barbers,
        barbersLoading: false,
        draft: state.draft.copyWith(staffId: staff),
      );
    } on Failure {
      state = state.copyWith(barbers: const [], barbersLoading: false);
    }
  }

  /// Asks for the free times. [wanted] (`HH:mm`) selects that time when the
  /// server offers it (the empty slot that was tapped on the calendar).
  Future<void> _loadSlots({String? wanted}) async {
    final d = state.draft;
    if (d.staffId == null || d.lines.isEmpty || d.date == null) {
      state = state.copyWith(slots: null, slotsLoading: false);
      return;
    }
    final seq = ++_seq;
    state = state.copyWith(slotsLoading: true);
    try {
      final res = await _repo.slots(
        date: d.date!,
        staffIds: [d.staffId!],
        serviceIds: d.serviceIds,
      );
      if (seq != _seq) return;
      final draft = state.draft;
      TimeSlot? pick = draft.slot;
      if (wanted != null) {
        pick = res.slots.where((s) => s.start == wanted).firstOrNull ?? pick;
      }
      // Keep a chosen time only while it is still offered (or is this booking's own).
      final cur = state.current;
      final stillOk =
          pick != null &&
          (pick.custom ||
              res.slots.any((s) => s.start == pick!.start) ||
              (cur != null &&
                  cur.start == pick.start &&
                  d.date == (target.date ?? d.date)));
      state = state.copyWith(
        slots: res,
        slotsLoading: false,
        draft: draft.copyWith(slot: stillOk ? pick : null),
      );
    } on Failure {
      if (seq != _seq) return;
      state = state.copyWith(slots: null, slotsLoading: false);
    }
  }

  // -------------------------------------------------------------- submit

  /// Saves the booking. Returns null on success, otherwise the message to show.
  Future<String?> submit() async {
    final d = state.draft;
    if (d.name.trim().isEmpty) return 'Full Name is required.';
    if (d.phone.trim().isEmpty) return 'Phone is required.';
    if (d.lines.isEmpty) return 'Please select at least one service.';
    if (d.staffId == null) return 'Select Staff';
    if (d.slot == null) return 'Please Select Slot!!';
    state = state.copyWith(submitting: true);
    try {
      if (target.editId != null) {
        await _repo.updateBooking(target.editId!, d);
        ref.invalidate(appointmentDetailProvider(target.editId!));
      } else {
        await _repo.createBooking(d);
      }
      ref.invalidate(calendarProvider);
      ref.invalidate(homeProvider);
      ref.invalidate(appointmentListProvider);
      ref.invalidate(appointmentCountsProvider);
      state = state.copyWith(submitting: false);
      return null;
    } on ValidationFailure catch (f) {
      state = state.copyWith(submitting: false);
      return f.fieldErrors.values.expand((e) => e).firstOrNull ?? f.userMessage;
    } on Failure catch (f) {
      state = state.copyWith(submitting: false);
      // 409: the time was taken meanwhile. Refresh what is free.
      if (f is ConflictFailure) unawaited(_loadSlots());
      return f.userMessage;
    }
  }
}
