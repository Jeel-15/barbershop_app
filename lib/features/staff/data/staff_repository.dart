import 'package:flutter/foundation.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// STAFF-1..12: the team list, the form, the profile numbers, password and
/// assigned services. Writes need Staff-Add / Staff-Edit / Staff-Delete.
class StaffRepository {
  const StaffRepository(this._api);

  final ApiClient _api;

  Future<PagedResult<StaffMember>> list({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/staff',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'per_page': perPage,
      },
    );
    return PagedResult(
      items: [
        for (final r in (res.data['items'] as List? ?? const []))
          StaffMember.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
      hasMore: res.meta['has_more'] == true,
      total: (res.meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<StaffFormOptions> formOptions() async {
    final res = await _api.get('/staff/form-options');
    return StaffFormOptions.fromJson(res.data);
  }

  /// The profile: the person and their numbers (optionally within a date range).
  Future<StaffProfile> profile(int id) async {
    final res = await _api.get('/staff/$id');
    return StaffProfile.fromJson(res.data);
  }

  Future<PagedResult<StaffAppointment>> appointments(
    int id, {
    String? start,
    String? end,
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/staff/$id/appointments',
      query: {
        'start_date': ?start,
        'end_date': ?end,
        'page': page,
        'per_page': perPage,
      },
    );
    return _page(res, StaffAppointment.fromJson);
  }

  Future<PagedResult<ServiceEarning>> services(
    int id, {
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/staff/$id/services',
      query: {'page': page, 'per_page': perPage},
    );
    return _page(res, ServiceEarning.fromJson);
  }

  Future<PagedResult<DailyEarning>> earnings(
    int id, {
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/staff/$id/earnings',
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

  /// The multipart body. The services go as `service_ids[]` (one field each):
  /// PHP only reads a list from that key, a bare `service_ids` is a string.
  @visibleForTesting
  static Future<FormData> buildForm(StaffInput i) async {
    final form = FormData()
      ..fields.addAll([
        MapEntry('name', i.name.trim()),
        MapEntry('email', i.email.trim()),
        MapEntry('phone', i.phone.trim()),
        if (i.password.isNotEmpty) MapEntry('password', i.password),
        MapEntry('is_barber', i.isBarber ? '1' : '0'),
        if (i.isBarber)
          for (final s in i.serviceIds) MapEntry('service_ids[]', '$s'),
        if (i.isBarber && i.commission.trim().isNotEmpty)
          MapEntry('commission', i.commission.trim()),
        MapEntry('active_status', i.active ? '1' : '0'),
        MapEntry('role_id', '${i.roleId}'),
      ]);
    if (i.photoPath != null) {
      form.files.add(
        MapEntry('profile_image', await MultipartFile.fromFile(i.photoPath!)),
      );
    }
    return form;
  }

  Future<String> create(StaffInput input) async =>
      (await _api.post('/staff', body: await buildForm(input))).message;

  /// Update goes by POST: a picture needs a multipart request.
  Future<String> update(int id, StaffInput input) async =>
      (await _api.post('/staff/$id', body: await buildForm(input))).message;

  Future<String> delete(int id) async =>
      (await _api.delete('/staff/$id')).message;

  Future<String> changePassword(
    int id,
    String password,
    String confirm,
  ) async => (await _api.put(
    '/staff/$id/password',
    body: {'new_password': password, 'confirm_password': confirm},
  )).message;

  Future<List<int>> assignedServices(int id) async {
    final res = await _api.get('/staff/$id/assigned-services');
    return [
      for (final s in (res.data['service_ids'] as List? ?? const []))
        (s as num).toInt(),
    ];
  }

  Future<String> assignServices(int id, List<int> serviceIds) async =>
      (await _api.put(
        '/staff/$id/assigned-services',
        body: {'service_ids': serviceIds},
      )).message;
}

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(apiClientProvider)),
);

final staffFormOptionsProvider = FutureProvider.autoDispose<StaffFormOptions>(
  (ref) => ref.read(staffRepositoryProvider).formOptions(),
);

final staffProfileProvider = FutureProvider.autoDispose
    .family<StaffProfile, int>(
      (ref, id) => ref.read(staffRepositoryProvider).profile(id),
    );
