import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The filters of the Staff Report (web: Start Date, End Date, Status).
class ReportFilter {
  const ReportFilter({this.start, this.end, this.status});

  /// `yyyy-MM-dd`.
  final String? start;
  final String? end;

  /// Appointment status code (0 pending, 1 completed, 2 cancelled, 3 confirmed, 4 rescheduled).
  final int? status;

  bool get isClear => start == null && end == null && status == null;

  int get activeCount =>
      (start != null || end != null ? 1 : 0) + (status != null ? 1 : 0);

  ReportFilter copyWith({
    Object? start = _keep,
    Object? end = _keep,
    Object? status = _keep,
  }) => ReportFilter(
    start: identical(start, _keep) ? this.start : start as String?,
    end: identical(end, _keep) ? this.end : end as String?,
    status: identical(status, _keep) ? this.status : status as int?,
  );

  static const _keep = Object();

  Map<String, dynamic> toQuery() => {
    'start_date': ?start,
    'end_date': ?end,
    'status': ?status,
  };

  @override
  bool operator ==(Object other) =>
      other is ReportFilter &&
      other.start == start &&
      other.end == end &&
      other.status == status;

  @override
  int get hashCode => Object.hash(start, end, status);
}

/// ME-1..11: my profile, my earnings report and my working hours.
class MeRepository {
  const MeRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------- profile

  Future<MyProfile> profile() async {
    final res = await _api.get('/me/profile');
    return MyProfile.fromJson(res.data);
  }

  /// Saves the profile; [photoPath] is a picked image file (JPG, PNG, GIF; 2 MB).
  Future<MyProfile> updateProfile({
    required String name,
    required String email,
    required String phone,
    String? photoPath,
  }) async {
    final res = await _api.post(
      '/me/profile',
      body: FormData.fromMap({
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        if (photoPath != null)
          'profile_image': await MultipartFile.fromFile(photoPath),
      }),
    );
    return MyProfile.fromJson(res.data);
  }

  // -------------------------------------------------------------- report

  Future<ReportSummary> reportSummary(ReportFilter f) async {
    final res = await _api.get('/me/report/summary', query: f.toQuery());
    return ReportSummary.fromJson(
      Map<String, dynamic>.from(res.data['summary'] as Map),
    );
  }

  Future<PagedResult<ReportAppointment>> reportAppointments(
    ReportFilter f, {
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/me/report/appointments',
      query: {...f.toQuery(), 'page': page, 'per_page': perPage},
    );
    return _page(res, ReportAppointment.fromJson);
  }

  Future<PagedResult<ServiceEarning>> reportServices({
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/me/report/services',
      query: {'page': page, 'per_page': perPage},
    );
    return _page(res, ServiceEarning.fromJson);
  }

  Future<PagedResult<DailyEarning>> reportDays({
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/me/report/earnings',
      query: {'page': page, 'per_page': perPage},
    );
    return _page(res, DailyEarning.fromJson);
  }

  PagedResult<T> _page<T>(
    ApiResponse res,
    T Function(Map<String, dynamic>) parse,
  ) => PagedResult(
    items: [
      for (final e in (res.data['items'] as List? ?? const []))
        parse(Map<String, dynamic>.from(e as Map)),
    ],
    hasMore: res.meta['has_more'] == true,
    total: (res.meta['total'] as num?)?.toInt() ?? 0,
  );

  // ------------------------------------------------------- working hours

  Future<List<WorkDay>> workingHours() async {
    final res = await _api.get('/me/working-hours');
    return [
      for (final d in (res.data['days'] as List? ?? const []))
        WorkDay.fromJson(Map<String, dynamic>.from(d as Map)),
    ];
  }

  /// "Working Hours Added Successfully." (409 when it overlaps another range).
  Future<String> addHours(int slotId, String start, String end) async {
    final res = await _api.post(
      '/me/working-hours',
      body: {'day_id': slotId, 'start_time': start, 'end_time': end},
    );
    return res.message;
  }

  Future<String> updateHours(int blockId, String start, String end) async {
    final res = await _api.put(
      '/me/working-hours/$blockId',
      body: {'start_time': start, 'end_time': end},
    );
    return res.message;
  }

  Future<String> deleteHours(int blockId) async {
    final res = await _api.delete('/me/working-hours/$blockId');
    return res.message;
  }

  Future<void> setDayOff(int slotId, {required bool off}) async {
    await _api.put(
      '/me/working-hours/days/$slotId/day-off',
      body: {'off': off},
    );
  }
}

final meRepositoryProvider = Provider<MeRepository>(
  (ref) => MeRepository(ref.watch(apiClientProvider)),
);

final myProfileProvider = FutureProvider.autoDispose<MyProfile>(
  (ref) => ref.read(meRepositoryProvider).profile(),
);

final workingHoursProvider = FutureProvider.autoDispose<List<WorkDay>>(
  (ref) => ref.read(meRepositoryProvider).workingHours(),
);
