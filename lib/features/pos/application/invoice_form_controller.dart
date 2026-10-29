import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/features/appointments/application/appointments_controller.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/pos/application/invoices_controller.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InvoiceFormState {
  const InvoiceFormState({
    this.loading = true,
    this.loadError,
    this.catalog,
    this.draft = const InvoiceDraft(),
    this.totals,
    this.previewing = false,
    this.submitting = false,
    this.appointment,
    this.invoice,
  });

  final bool loading;
  final Object? loadError;
  final PosCatalog? catalog;
  final InvoiceDraft draft;

  /// The server's arithmetic for [draft] (null until the first answer).
  final InvoiceTotals? totals;
  final bool previewing;
  final bool submitting;

  /// The appointment being completed (null when creating a new invoice).
  final AppointmentDetail? appointment;

  /// The invoice being edited (null when creating or completing).
  final InvoiceDetail? invoice;

  InvoiceFormState copyWith({
    bool? loading,
    Object? loadError,
    PosCatalog? catalog,
    InvoiceDraft? draft,
    Object? totals = _keep,
    bool? previewing,
    bool? submitting,
    AppointmentDetail? appointment,
    InvoiceDetail? invoice,
  }) => InvoiceFormState(
    loading: loading ?? this.loading,
    loadError: loadError,
    catalog: catalog ?? this.catalog,
    draft: draft ?? this.draft,
    totals: identical(totals, _keep) ? this.totals : totals as InvoiceTotals?,
    previewing: previewing ?? this.previewing,
    submitting: submitting ?? this.submitting,
    appointment: appointment ?? this.appointment,
    invoice: invoice ?? this.invoice,
  );

  static const _keep = Object();
}

/// What the invoice form works on: nothing (a new invoice), an appointment to
/// complete, or an existing invoice to edit.
class InvoiceTarget {
  const InvoiceTarget({this.appointmentId, this.invoiceId});

  final int? appointmentId;
  final int? invoiceId;

  @override
  bool operator ==(Object other) =>
      other is InvoiceTarget &&
      other.appointmentId == appointmentId &&
      other.invoiceId == invoiceId;

  @override
  int get hashCode => Object.hash(appointmentId, invoiceId);
}

/// The invoice form behind "Complete" (an appointment, prefilled), "Create
/// Invoice" (blank) and "Edit Invoice" (an existing invoice). Every figure comes from the server's preview, so
/// the screen can never disagree with what gets saved.
final invoiceFormProvider = NotifierProvider.autoDispose
    .family<InvoiceFormController, InvoiceFormState, InvoiceTarget>(
      InvoiceFormController.new,
    );

class InvoiceFormController extends Notifier<InvoiceFormState> {
  InvoiceFormController(this.target);

  final InvoiceTarget target;

  /// Set = completing this appointment.
  int? get appointmentId => target.appointmentId;

  /// Set = editing that invoice.
  int? get invoiceId => target.invoiceId;

  Timer? _debounce;
  int _previewSeq = 0;

  /// One key per form, reused on retry so a double tap can never make two invoices.
  late final String _idempotencyKey =
      'app-${DateTime.now().microsecondsSinceEpoch}';

  @override
  InvoiceFormState build() {
    ref.onDispose(() => _debounce?.cancel());
    unawaited(Future<void>.microtask(_load));
    return const InvoiceFormState();
  }

  Future<void> _load() async {
    try {
      final catalog = await ref.read(posRepositoryProvider).catalog();
      var draft = InvoiceDraft(paymentMethod: catalog.defaultPayment);
      AppointmentDetail? appt;
      InvoiceDetail? invoice;
      if (invoiceId != null) {
        invoice = await ref.read(invoicesRepositoryProvider).detail(invoiceId!);
        draft = _fromInvoice(invoice, catalog, draft);
      } else if (appointmentId != null) {
        appt = await ref
            .read(appointmentsRepositoryProvider)
            .detail(appointmentId!);
        draft = _prefill(appt, catalog, draft);
      }
      state = state.copyWith(
        loading: false,
        catalog: catalog,
        draft: draft,
        appointment: appt,
        invoice: invoice,
      );
      _schedulePreview(immediately: true);
    } catch (e) {
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// The saved invoice as a draft: its cart, discounts, tip, payment and customer.
  InvoiceDraft _fromInvoice(
    InvoiceDetail inv,
    PosCatalog catalog,
    InvoiceDraft base,
  ) {
    final services = {
      for (final c in catalog.categories)
        for (final s in c.services) s.id: s,
    };
    final products = {for (final p in catalog.products) p.id: p};
    final perKey = <String, int>{};
    for (final c in inv.cart) {
      final k = '${c.type.name}:${c.id}';
      perKey[k] = (perKey[k] ?? 0) + 1;
    }
    final lines = <InvoiceLine>[];
    for (final c in inv.cart) {
      final k = '${c.type.name}:${c.id}';
      final isService = c.type == LineType.service;
      final svc = isService ? services[c.id] : null;
      final prod = isService ? null : products[c.id];
      // An item the catalog no longer lists is shown as it was sold.
      final sold = inv.lines
          .where((l) => l.type == c.type && l.name.isNotEmpty)
          .firstOrNull;
      lines.add(
        InvoiceLine(
          type: c.type,
          id: c.id,
          name: svc?.name ?? prod?.name ?? sold?.name ?? 'Item ${c.id}',
          price: svc?.price ?? prod?.price ?? sold?.price ?? Money.zero,
          qty: c.qty,
          staffId: c.staffId,
          // Two barbers on the same item must stay two rows.
          uid: (perKey[k] ?? 0) > 1 ? '$k:${c.staffId}' : null,
        ),
      );
    }
    final b = inv.breakdown;
    return base.copyWith(
      customerName: inv.row.isGuest ? '' : inv.row.customerName,
      customerPhone: inv.row.isGuest ? '' : (inv.row.customerPhone ?? ''),
      customerEmail: inv.row.hasRealEmail ? inv.row.customerEmail : '',
      lines: lines,
      serviceDiscount: b.serviceDiscountPercent,
      productDiscount: b.productDiscountPercent,
      tip: b.tip,
      paymentMethod: inv.row.paymentMethod?.isNotEmpty == true
          ? inv.row.paymentMethod
          : base.paymentMethod,
      notes: inv.notes ?? '',
    );
  }

  InvoiceDraft _prefill(
    AppointmentDetail a,
    PosCatalog catalog,
    InvoiceDraft base,
  ) {
    final known = {for (final s in catalog.staff) s.id};
    return base.copyWith(
      customerName: a.row.customerName,
      customerPhone: a.row.customerPhone ?? '',
      customerEmail: a.customerEmail ?? '',
      lines: [
        for (final s in a.services)
          InvoiceLine(
            type: LineType.service,
            id: s.serviceId,
            name: s.name,
            price: s.unitPrice,
            qty: s.qty,
            staffId: s.staffIds.where(known.contains).firstOrNull,
          ),
      ],
    );
  }

  // --------------------------------------------------------------- edits

  void _set(InvoiceDraft d) {
    state = state.copyWith(draft: d);
    _schedulePreview();
  }

  void addService(CatalogService s) => _addLine(
    InvoiceLine(
      type: LineType.service,
      id: s.id,
      name: s.name,
      price: s.price,
      qty: 1,
    ),
  );

  void addProduct(CatalogProduct p) => _addLine(
    InvoiceLine(
      type: LineType.product,
      id: p.id,
      name: p.name,
      price: p.price,
      qty: 1,
    ),
  );

  /// Adding the same item again raises its quantity.
  void _addLine(InvoiceLine line) {
    final lines = [...state.draft.lines];
    final i = lines.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      lines[i] = lines[i].copyWith(qty: (lines[i].qty + 1).clamp(1, 20));
    } else {
      // A single barber on the bill is the obvious choice for the new line.
      final staff = state.catalog?.staff ?? const [];
      final lastStaff = lines.isNotEmpty ? lines.last.staffId : null;
      lines.add(
        line.copyWith(
          staffId: lastStaff ?? (staff.length == 1 ? staff.first.id : null),
        ),
      );
    }
    _set(state.draft.copyWith(lines: lines));
  }

  void setQty(String key, int qty) {
    if (qty < 1) return removeLine(key);
    _set(
      state.draft.copyWith(
        lines: [
          for (final l in state.draft.lines)
            l.key == key ? l.copyWith(qty: qty.clamp(1, 20)) : l,
        ],
      ),
    );
  }

  void removeLine(String key) => _set(
    state.draft.copyWith(
      lines: [
        for (final l in state.draft.lines)
          if (l.key != key) l,
      ],
    ),
  );

  void setStaff(String key, int staffId) => _set(
    state.draft.copyWith(
      lines: [
        for (final l in state.draft.lines)
          l.key == key ? l.copyWith(staffId: staffId) : l,
      ],
    ),
  );

  void setServiceDiscount(double v) =>
      _set(state.draft.copyWith(serviceDiscount: v.clamp(0, 100)));

  void setProductDiscount(double v) =>
      _set(state.draft.copyWith(productDiscount: v.clamp(0, 100)));

  void setTip(Money tip) => _set(state.draft.copyWith(tip: tip));

  void setPayment(String method) =>
      _set(state.draft.copyWith(paymentMethod: method));

  void setNotes(String v) =>
      state = state.copyWith(draft: state.draft.copyWith(notes: v));

  void setCustomer({String? name, String? phone, String? email}) =>
      state = state.copyWith(
        draft: state.draft.copyWith(
          customerName: name,
          customerPhone: phone,
          customerEmail: email,
        ),
      );

  // ------------------------------------------------------------- preview

  void _schedulePreview({bool immediately = false}) {
    _debounce?.cancel();
    final d = state.draft;
    // The server needs a barber on every line; wait until they are chosen.
    if (d.lines.isEmpty || !d.allHaveStaff) {
      state = state.copyWith(totals: null, previewing: false);
      return;
    }
    state = state.copyWith(previewing: true);
    _debounce = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 320),
      _runPreview,
    );
  }

  Future<void> _runPreview() async {
    final seq = ++_previewSeq;
    final draft = state.draft;
    try {
      final totals = await ref.read(posRepositoryProvider).preview(draft);
      if (seq != _previewSeq) return; // a newer edit is already on its way
      state = state.copyWith(totals: totals, previewing: false);
    } on Failure {
      if (seq != _previewSeq) return;
      state = state.copyWith(totals: null, previewing: false);
    }
  }

  // -------------------------------------------------------------- submit

  /// Saves the invoice. Returns null on success, otherwise the message to show
  /// (the web's own words where it has them).
  Future<String?> submit() async {
    final d = state.draft;
    if (d.lines.isEmpty) {
      return 'Please select at least one service or product.';
    }
    if (!d.allHaveStaff) return 'Select Staff Members';
    state = state.copyWith(submitting: true);
    try {
      final repo = ref.read(posRepositoryProvider);
      if (invoiceId != null) {
        await repo.updateInvoice(invoiceId!, d);
      } else if (appointmentId != null) {
        await repo.completeAppointment(appointmentId!, d);
      } else {
        await repo.createInvoice(d, idempotencyKey: _idempotencyKey);
      }
      // Every screen that shows bookings or money reloads.
      ref.invalidate(homeProvider);
      ref.invalidate(calendarProvider);
      ref.invalidate(appointmentListProvider);
      ref.invalidate(appointmentCountsProvider);
      ref.invalidate(invoiceListProvider);
      if (invoiceId != null) ref.invalidate(invoiceDetailProvider(invoiceId!));
      if (appointmentId != null) {
        ref.invalidate(appointmentDetailProvider(appointmentId!));
      }
      state = state.copyWith(submitting: false);
      return null;
    } on ValidationFailure catch (f) {
      state = state.copyWith(submitting: false);
      return f.fieldErrors.values.expand((e) => e).firstOrNull ?? f.userMessage;
    } on Failure catch (f) {
      state = state.copyWith(submitting: false);
      return f.userMessage;
    }
  }
}
