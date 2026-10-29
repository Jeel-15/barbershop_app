import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/features/roles/data/roles_repository.dart';
import 'package:barbershop_app/features/roles/domain/role_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> rolesJson() => {
  'roles': [
    {
      'id': 2,
      'name': 'Staff',
      'permission_ids': [1, 2],
      'users_count': 4,
      'locked': true,
    },
    {
      'id': 6,
      'name': 'Reception',
      'permission_ids': [1],
      'users_count': 0,
      'locked': false,
    },
  ],
  'permission_groups': [
    {
      'group': 'Staff',
      'permissions': [
        {'id': 1, 'name': 'Staff-Add'},
        {'id': 2, 'name': 'Staff-Edit'},
      ],
    },
    {
      'group': 'Pos_invoice',
      'permissions': [
        {'id': 3, 'name': 'Pos_invoice-Show_All'},
      ],
    },
  ],
};

class FakeRoles extends RolesRepository {
  FakeRoles() : super(_NoApi());

  final calls = <String>[];
  Failure? deleteFails;
  Failure? saveFails;

  @override
  Future<RolesData> load() async => RolesData.fromJson(rolesJson());

  @override
  Future<String> create(String name, Iterable<int> ids) async {
    calls.add('create:$name:${(ids.toList()..sort()).join(',')}');
    if (saveFails != null) throw saveFails!;
    return 'Role created successfully.';
  }

  @override
  Future<String> update(int id, String name, Iterable<int> ids) async {
    calls.add('update:$id:$name:${(ids.toList()..sort()).join(',')}');
    return 'Role updated successfully.';
  }

  @override
  Future<String> delete(int id) async {
    calls.add('delete:$id');
    if (deleteFails != null) throw deleteFails!;
    return 'Role deleted successfully.';
  }
}
