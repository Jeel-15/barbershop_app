import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The search text of the Staff list (name, email, phone or service).
class StaffQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final staffQueryProvider = NotifierProvider<StaffQueryNotifier, String>(
  StaffQueryNotifier.new,
);

final staffListProvider =
    AsyncNotifierProvider<StaffListController, PagedState<StaffMember>>(
      StaffListController.new,
      retry: (_, _) => null,
    );

class StaffListController extends PagedNotifier<StaffMember> {
  @override
  Future<PagedResult<StaffMember>> fetch(int page) => ref
      .read(staffRepositoryProvider)
      .list(q: ref.read(staffQueryProvider), page: page);

  @override
  Future<PagedState<StaffMember>> build() {
    ref.watch(currentUserProvider);
    ref.watch(staffQueryProvider);
    return super.build();
  }
}

/// The date range of the profile's Appointments tab (Start Date / End Date / Apply).
class StaffRange {
  const StaffRange({this.start, this.end});

  /// `yyyy-MM-dd`.
  final String? start;
  final String? end;

  bool get isClear => start == null && end == null;

  @override
  bool operator ==(Object other) =>
      other is StaffRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final staffAppointmentsProvider = AsyncNotifierProvider.autoDispose
    .family<
      StaffAppointmentsController,
      PagedState<StaffAppointment>,
      (int, StaffRange)
    >(StaffAppointmentsController.new, retry: (_, _) => null);

class StaffAppointmentsController extends PagedNotifier<StaffAppointment> {
  StaffAppointmentsController(this.args);

  final (int, StaffRange) args;

  @override
  Future<PagedResult<StaffAppointment>> fetch(int page) => ref
      .read(staffRepositoryProvider)
      .appointments(
        args.$1,
        start: args.$2.start,
        end: args.$2.end,
        page: page,
      );
}

final staffServicesProvider = AsyncNotifierProvider.autoDispose
    .family<StaffServicesController, PagedState<ServiceEarning>, int>(
      StaffServicesController.new,
      retry: (_, _) => null,
    );

class StaffServicesController extends PagedNotifier<ServiceEarning> {
  StaffServicesController(this.id);

  final int id;

  @override
  Future<PagedResult<ServiceEarning>> fetch(int page) =>
      ref.read(staffRepositoryProvider).services(id, page: page);
}

final staffEarningsProvider = AsyncNotifierProvider.autoDispose
    .family<StaffEarningsController, PagedState<DailyEarning>, int>(
      StaffEarningsController.new,
      retry: (_, _) => null,
    );

class StaffEarningsController extends PagedNotifier<DailyEarning> {
  StaffEarningsController(this.id);

  final int id;

  @override
  Future<PagedResult<DailyEarning>> fetch(int page) =>
      ref.read(staffRepositoryProvider).earnings(id, page: page);
}
