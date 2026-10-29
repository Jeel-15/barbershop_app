import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/roles/data/roles_repository.dart';
import 'package:barbershop_app/features/roles/domain/role_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's Roles page ("Manage user roles and permissions").
class RolesPage extends ConsumerStatefulWidget {
  const RolesPage({super.key});

  @override
  ConsumerState<RolesPage> createState() => _RolesPageState();
}

class _RolesPageState extends ConsumerState<RolesPage> {
  String _q = '';

  Future<void> _form([RoleItem? r]) async {
    final msg = await context.push<String>(
      r == null ? '/app/roles/new' : '/app/roles/edit/${r.id}',
    );
    if (msg != null && mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(rolesProvider);
    }
  }

  Future<void> _delete(RoleItem r) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Role?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final msg = await ref.read(rolesRepositoryProvider).delete(r.id);
      if (!mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(rolesProvider);
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final async = ref.watch(rolesProvider);
    final data = async.value;
    final needle = _q.trim().toLowerCase();
    final roles = [
      for (final r in data?.roles ?? const <RoleItem>[])
        if (needle.isEmpty || r.name.toLowerCase().contains(needle)) r,
    ];

    Widget body;
    if (data == null) {
      body = async.hasError
          ? ScrollableCenter(
              child: ErrorState(
                message: async.error is Failure
                    ? (async.error! as Failure).userMessage
                    : 'Could not load the roles.',
                supportCode: async.error is Failure
                    ? (async.error! as Failure).requestId
                    : null,
                onRetry: () => ref.invalidate(rolesProvider),
              ),
            )
          : const Padding(
              padding: EdgeInsets.only(top: AppSpace.md),
              child: SkeletonRows(count: 5),
            );
    } else if (roles.isEmpty) {
      body = ScrollableCenter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: QuietState(
            title: 'No roles found',
            message: needle.isEmpty
                ? 'Add the first role.'
                : 'Try another name.',
          ),
        ),
      );
    } else {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.page,
          AppSpace.md,
          AppSpace.page,
          AppSpace.xxl,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              '${needle.isEmpty ? 'ALL ROLES' : 'FOUND'} · ${roles.length}',
              style: AppType.overline.copyWith(color: t.textMuted),
            ),
          ),
          for (final r in roles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
              child: AdminTile(
                title: r.name,
                icon: Icons.admin_panel_settings_rounded,
                badge: r.locked
                    ? StatusPill(label: 'System', color: t.info, compact: true)
                    : null,
                lines: [
                  '${r.permissionIds.length} of ${data.allPermissionIds.length} permissions',
                  '${r.usersCount} ${r.usersCount == 1 ? 'user' : 'users'}',
                ],
                menu: [
                  if (user.can('Role-Edit')) ('edit', 'Edit', false),
                  if (user.can('Role-Delete') && !r.locked)
                    ('delete', 'Delete', true),
                ],
                onMenu: (v) => v == 'edit' ? _form(r) : _delete(r),
                onTap: user.can('Role-Edit') ? () => _form(r) : null,
              ),
            ),
        ],
      );
    }

    return AdminListShell(
      title: 'Roles',
      subtitle: 'Manage user roles and permissions',
      addLabel: 'Add New Role',
      onAdd: user.can('Role-Add') ? () => _form() : null,
      searchHint: 'Search role',
      query: _q,
      onSearch: (q) => setState(() => _q = q),
      body: AppRefresh(
        onRefresh: () async => ref.invalidate(rolesProvider),
        child: body,
      ),
    );
  }
}
