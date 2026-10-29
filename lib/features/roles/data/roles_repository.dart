import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/features/roles/domain/role_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ROLE-1..4: roles and the permissions they grant. Needs Role-Add / Edit / Delete.
class RolesRepository {
  const RolesRepository(this._api);

  final ApiClient _api;

  Future<RolesData> load() async =>
      RolesData.fromJson((await _api.get('/roles')).data);

  Future<String> create(String name, Iterable<int> permissionIds) async =>
      (await _api.post(
        '/roles',
        body: {
          'name': name.trim(),
          'permission_ids': permissionIds.toList()..sort(),
        },
      )).message;

  Future<String> update(
    int id,
    String name,
    Iterable<int> permissionIds,
  ) async => (await _api.put(
    '/roles/$id',
    body: {
      'name': name.trim(),
      'permission_ids': permissionIds.toList()..sort(),
    },
  )).message;

  Future<String> delete(int id) async =>
      (await _api.delete('/roles/$id')).message;
}

final rolesRepositoryProvider = Provider<RolesRepository>(
  (ref) => RolesRepository(ref.watch(apiClientProvider)),
);

final rolesProvider = FutureProvider.autoDispose<RolesData>(
  (ref) => ref.read(rolesRepositoryProvider).load(),
);
