/// A role with the permissions it grants (web: Roles).
class RoleItem {
  const RoleItem({
    required this.id,
    required this.name,
    required this.permissionIds,
    required this.usersCount,
    required this.locked,
  });

  factory RoleItem.fromJson(Map<String, dynamic> j) => RoleItem(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    permissionIds: {
      for (final p in (j['permission_ids'] as List? ?? const []))
        (p as num).toInt(),
    },
    usersCount: (j['users_count'] as num?)?.toInt() ?? 0,
    locked: j['locked'] == true,
  );

  final int id;
  final String name;
  final Set<int> permissionIds;

  /// How many people have this role.
  final int usersCount;

  /// A system role: it cannot be deleted (or renamed).
  final bool locked;
}

class PermissionItem {
  const PermissionItem(this.id, this.name);

  final int id;

  /// `Staff-Add`, `Pos_invoice-Show_All`.
  final String name;

  /// The web's checkbox label: the part after the first dash, `_` as a space,
  /// each word capitalised (`Show_All` -> `Show All`).
  String get label {
    final i = name.indexOf('-');
    final tail = i < 0 ? name : name.substring(i + 1);
    return tail
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

/// One row of the web's permission table (e.g. `Staff`: Add, Edit, Delete).
class PermissionGroup {
  const PermissionGroup(this.name, this.permissions);

  final String name;
  final List<PermissionItem> permissions;
}

class RolesData {
  const RolesData({required this.roles, required this.groups});

  factory RolesData.fromJson(Map<String, dynamic> j) => RolesData(
    roles: [
      for (final r in (j['roles'] as List? ?? const []))
        RoleItem.fromJson(Map<String, dynamic>.from(r as Map)),
    ],
    groups: [
      for (final g in (j['permission_groups'] as List? ?? const []))
        PermissionGroup((g['group'] ?? '').toString(), [
          for (final p in (g['permissions'] as List? ?? const []))
            PermissionItem((p['id'] as num).toInt(), p['name'].toString()),
        ]),
    ],
  );

  final List<RoleItem> roles;
  final List<PermissionGroup> groups;

  List<int> get allPermissionIds => [
    for (final g in groups)
      for (final p in g.permissions) p.id,
  ];
}
