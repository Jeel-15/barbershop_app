// Live booking -> confirm -> reschedule -> complete -> invoice flow, and the
// staff-only areas, against the LOCAL web API with the app's real repositories.
// Not part of tool/check.sh. Run:
//   flutter test tool/live/live_flow_test.dart
// Test rows carry the note "ZZ-AUDIT" / phone 7805559993 (clean-up SQL in
// docs/COMMANDS.md style at the end of the run output).
import 'dart:io';

import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/tokens/colors.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/domain/booking.dart';
import 'package:barbershop_app/features/auth/data/auth_repository.dart';
import 'package:barbershop_app/features/calendar/data/calendar_repository.dart';
import 'package:barbershop_app/features/home/data/dashboard_repository.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:barbershop_app/features/reports/data/reports_repository.dart';
import 'package:barbershop_app/features/reports/domain/report_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'http://localhost/rosen_barber/public/api/v1';

Future<ApiClient> _client(String email) async {
  final anon = ApiClient(
    baseUrl: _base,
    readToken: () async => null,
    log: false,
  );
  final r = await AuthRepository(
    anon,
  ).login(email: email, password: 'Rosen@12345', deviceName: 'live-test');
  return ApiClient(baseUrl: _base, readToken: () async => r.token, log: false);
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  late ApiClient admin;
  late ApiClient staff;

  setUpAll(() async {
    HttpOverrides.global = null;
    ShopTime.init();
    admin = await _client('apitest.admin@rosen.test');
    staff = await _client('apitest.staff@rosen.test');
  });

  test('admin: book, confirm, reschedule, update, cancel', () async {
    final appts = AppointmentsRepository(admin);
    final options = await appts.bookingOptions();
    final svc = options.expand((c) => c.services).first;
    final barbers = await appts.staffByService([svc.id]);
    expect(barbers, isNotEmpty);
    final barber = barbers.firstWhere(
      (b) => !b.isFirstAvailable,
      orElse: () => barbers.first,
    );

    // The first of the next 14 days that has free time.
    String? date;
    SlotsResult? slots;
    for (var i = 1; i < 15 && date == null; i++) {
      final d = _ymd(DateTime.now().add(Duration(days: i)));
      final r = await appts.slots(
        date: d,
        staffIds: [barber.id],
        serviceIds: [svc.id],
      );
      if (r.slots.length >= 2) {
        date = d;
        slots = r;
      }
    }
    expect(date, isNotNull, reason: 'no day with two free slots in 14 days');
    final first = slots!.slots.first;
    final second = slots.slots.last;

    BookingDraft draft(TimeSlot s, String notes) => BookingDraft(
      name: 'ZZ Audit Flow',
      phone: '7805559993',
      email: '',
      notes: notes,
      lines: [BookingLine(svc, 1)],
      staffId: barber.id,
      date: date,
      slot: s,
    );

    await appts.createBooking(draft(first, 'ZZ-AUDIT'));
    final listed = await appts.list(
      const AppointmentFilter(query: 'ZZ Audit Flow'),
    );
    expect(listed.items, isNotEmpty);
    final fresh = listed.items.firstWhere(
      (a) => a.status == AppointmentStatus.pending,
    );
    final id = fresh.id;

    // The same slot twice must be refused, not double-booked.
    await expectLater(
      appts.createBooking(draft(first, 'ZZ-AUDIT dup')),
      throwsA(anything),
    );

    await appts.reschedule(
      id,
      date: date!,
      slotStart: second.start,
      slotEnd: second.end,
    );
    await appts.updateBooking(id, draft(second, 'ZZ-AUDIT edited'));
    await appts.confirm(id);
    expect((await appts.detail(id)).row.status, AppointmentStatus.confirmed);
    // A confirmed booking cannot be moved (the web says so too).
    await expectLater(
      appts.reschedule(
        id,
        date: date,
        slotStart: first.start,
        slotEnd: first.end,
      ),
      throwsA(anything),
    );
    await appts.cancel(id);
    expect((await appts.detail(id)).row.status, AppointmentStatus.cancelled);
    await appts.counts();
  });

  test(
    'admin: complete an appointment into an invoice, then edit it',
    () async {
      final appts = AppointmentsRepository(admin);
      final pos = PosRepository(admin);
      final svc = (await appts.bookingOptions())
          .expand((c) => c.services)
          .first;
      final barber = (await appts.staffByService([svc.id])).first;

      // A back entry for today (the web allows past times).
      await appts.createBooking(
        BookingDraft(
          name: 'ZZ Audit Flow',
          phone: '7805559993',
          notes: 'ZZ-AUDIT done',
          lines: [BookingLine(svc, 1)],
          staffId: barber.id,
          date: _ymd(ShopTime.today()),
          slot: TimeSlot.at(9, 0),
        ),
      );
      final id = (await appts.list(
        const AppointmentFilter(query: 'ZZ Audit Flow'),
      )).items.firstWhere((a) => a.status == AppointmentStatus.pending).id;

      final line = InvoiceLine(
        type: LineType.service,
        id: svc.id,
        name: svc.name,
        price: svc.price,
        qty: 1,
        staffId: barber.id,
      );
      final draft = InvoiceDraft(
        customerName: 'ZZ Audit Flow',
        customerPhone: '7805559993',
        lines: [line],
        tip: Money.parse('2.00'),
        paymentMethod: 'Cash',
        notes: 'ZZ-AUDIT',
      );
      final totals = await pos.preview(draft);
      expect(totals.finalTotal.cents, greaterThan(0));
      await pos.completeAppointment(id, draft);
      expect((await appts.detail(id)).row.status, AppointmentStatus.completed);

      final invoices = InvoicesRepository(admin);
      final rows = await invoices.list(q: 'ZZ Audit');
      expect(rows.items, isNotEmpty);
      final inv = await invoices.detail(rows.items.first.id);
      expect(inv.lines, isNotEmpty);

      // An invoice by itself; the same idempotency key creates it only once.
      const key = 'zz-audit-key-1';
      await pos.createInvoice(
        draft,
        idempotencyKey: '$key-${DateTime.now().microsecondsSinceEpoch}',
      );
      final again = DateTime.now().microsecondsSinceEpoch;
      await pos.createInvoice(draft, idempotencyKey: 'same-$again');
      final before = (await invoices.list(q: 'ZZ Audit')).items.length;
      await pos.createInvoice(draft, idempotencyKey: 'same-$again');
      expect((await invoices.list(q: 'ZZ Audit')).items.length, before);

      await pos.updateInvoice(
        rows.items.first.id,
        draft.copyWith(notes: 'ZZ-AUDIT edited', tip: Money.parse('3.00')),
      );
      final lookup = await pos.lookupCustomer('7805559993');
      expect(lookup, isNotEmpty);
      await pos.catalog();
    },
  );

  test('admin: reports, dashboard, calendar, break validation', () async {
    final rep = ReportsRepository(admin);
    final f = ReportsFilter(
      start: _ymd(DateTime.now().subtract(const Duration(days: 30))),
      end: _ymd(DateTime.now()),
    );
    await rep.overview(f);
    await rep.earning(f);
    await rep.payments(f);
    await rep.staff(f);
    await rep.invoices(f);
    await rep.productSales(f);
    await rep.topProducts(f);
    await DashboardRepository(admin).load();
    final cal = CalendarRepository(admin);
    final today = _ymd(ShopTime.today());
    final ev = await cal.events(today, today);
    expect(ev.lanes, isNotEmpty);
    await cal.availability(today);
    // The server must refuse a break of 0 minutes.
    await expectLater(
      cal.addBreak(staffId: ev.lanes.first.id),
      throwsA(anything),
    );
  });

  test('staff: own profile, report, working hours', () async {
    final me = MeRepository(staff);
    final p = await me.profile();
    final back = await me.updateProfile(
      name: p.name,
      email: p.email,
      phone: p.phone ?? '',
    );
    expect(back.name, p.name);

    const f = ReportFilter();
    await me.reportSummary(f);
    await me.reportAppointments(f);
    await me.reportServices();
    await me.reportDays();

    final days = await me.workingHours();
    if (days.isEmpty) {
      // This test account has no day rows (the web page is empty for it too).
      return;
    }
    final day = days.first;
    await me.addHours(day.slotId, '22:00', '22:30');
    var fresh = (await me.workingHours()).firstWhere(
      (d) => d.slotId == day.slotId,
    );
    final block = fresh.blocks.firstWhere((b) => b.start == '22:00');
    await me.updateHours(block.id, '22:00', '22:45');
    await me.deleteHours(block.id);
    fresh = (await me.workingHours()).firstWhere((d) => d.slotId == day.slotId);
    expect(fresh.blocks.any((b) => b.start == '22:00'), isFalse);

    final was = day.isDayOff;
    await me.setDayOff(day.slotId, off: !was);
    await me.setDayOff(day.slotId, off: was);

    // Staff must not reach admin areas.
    await expectLater(
      ReportsRepository(staff).overview(const ReportsFilter()),
      throwsA(anything),
    );
  });
}
