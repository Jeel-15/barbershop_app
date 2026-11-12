import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/staff/application/staff_controller.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:barbershop_app/features/staff/presentation/widgets/assign_services_sheet.dart';
import 'package:barbershop_app/features/staff/presentation/widgets/change_password_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

/// The web's Staff page ("Manage team members, roles, and commissions"): the
/// team with search, Add, and per row View / Edit / Delete / Change Password
/// (by permission) plus Assign Services for barbers.
class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});

  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(staffListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final msg = await context.push<String>('/app/staff/new');
    _saved(msg);
  }

  Future<void> _edit(StaffMember m) async {
    final msg = await context.push<String>('/app/staff/edit/${m.id}', extra: m);
    _saved(msg);
  }

  /// The form closed with the server's message: show it and reload.
  void _saved(String? message) {
    if (message == null || !mounted) return;
    showToast(context, message, kind: ToastKind.success);
    ref.invalidate(staffListProvider);
  }

  Future<void> _delete(StaffMember m) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Staff?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final msg = await ref.read(staffRepositoryProvider).delete(m.id);
      if (!mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(staffListProvider);
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final list = ref.watch(staffListProvider);
    final query = ref.watch(staffQueryProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.sm,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  RoundBackButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/app/more'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      'Staff',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                  if (user.can(Perm.staffAdd))
                    HeaderIconButton(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Add',
                      onTap: _add,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                0,
                AppSpace.page,
                AppSpace.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Manage team members, roles, and commissions',
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.page,
                vertical: AppSpace.sm,
              ),
              child: AppSearchField(
                hint: 'Search name, email, phone or service',
                initial: query,
                onChanged: (q) => ref.read(staffQueryProvider.notifier).set(q),
              ),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: AppRefresh(
                onRefresh: () => ref.read(staffListProvider.notifier).refresh(),
                child: switch (list) {
                  AsyncData(:final value) => _List(
                    state: value,
                    controller: _scroll,
                    searching: query.trim().isNotEmpty,
                    canEdit: user.can(Perm.staffEdit),
                    canDelete: user.can(Perm.staffDelete),
                    onOpen: (m) => context.push('/app/staff/${m.id}'),
                    onEdit: _edit,
                    onDelete: _delete,
                    onPassword: (m) => showChangePasswordSheet(context, m),
                    onAssign: (m) => showAssignServicesSheet(context, m),
                    onRetryMore: () =>
                        ref.read(staffListProvider.notifier).loadMore(),
                  ),
                  AsyncError(:final error) => _Scrollable(
                    child: ErrorState(
                      message: error is Failure
                          ? error.userMessage
                          : 'Could not load the team.',
                      supportCode: error is Failure ? error.requestId : null,
                      onRetry: () => ref.invalidate(staffListProvider),
                    ),
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.only(top: AppSpace.md),
                    child: SkeletonRows(count: 6),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [SizedBox(height: 480, child: child)],
  );
}

class _List extends StatelessWidget {
  const _List({
    required this.state,
    required this.controller,
    required this.searching,
    required this.canEdit,
    required this.canDelete,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onPassword,
    required this.onAssign,
    required this.onRetryMore,
  });

  final PagedState<StaffMember> state;
  final ScrollController controller;
  final bool searching;
  final bool canEdit;
  final bool canDelete;
  final ValueChanged<StaffMember> onOpen;
  final ValueChanged<StaffMember> onEdit;
  final ValueChanged<StaffMember> onDelete;
  final ValueChanged<StaffMember> onPassword;
  final ValueChanged<StaffMember> onAssign;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (state.items.isEmpty) {
      return _Scrollable(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: QuietState(
            title: searching ? 'No staff found' : 'No staff yet',
            message: searching
                ? 'Try another name, email, phone or service.'
                : 'Add your first team member.',
          ),
        ),
      );
    }
    return ListView.builder(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.md,
        AppSpace.page,
        AppSpace.xxl,
      ),
      itemCount: state.items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              '${searching ? 'FOUND' : 'TEAM'} · ${state.total}',
              style: AppType.overline.copyWith(color: t.textMuted),
            ),
          );
        }
        if (i == state.items.length + 1) {
          if (state.loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            );
          }
          if (state.loadMoreFailed) {
            return TextButton(
              onPressed: onRetryMore,
              child: const Text('Could not load more. Tap to retry'),
            );
          }
          return const SizedBox.shrink();
        }
        final m = state.items[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
          child: _StaffTile(
            member: m,
            onTap: () => onOpen(m),
            onEdit: canEdit ? () => onEdit(m) : null,
            onDelete: canDelete ? () => onDelete(m) : null,
            onPassword: canEdit ? () => onPassword(m) : null,
            onAssign: canEdit && m.isBarber ? () => onAssign(m) : null,
          ),
        );
      },
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.member,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onPassword,
    this.onAssign,
  });

  final StaffMember member;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPassword;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = member;
    final hasMenu =
        onEdit != null ||
        onDelete != null ||
        onPassword != null ||
        onAssign != null;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      minSize: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          hasMenu ? AppSpace.xs : AppSpace.md,
          AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            AppAvatar(name: m.name, imageUrl: m.photoUrl, size: 48),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.bodyStrong.copyWith(color: t.text),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(
                        label: m.active ? 'Active' : 'Deactive',
                        color: m.active ? t.success : t.danger,
                        compact: true,
                      ),
                    ],
                  ),
                  Text(
                    m.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  Text(
                    [
                      m.roleLabel,
                      if (m.isBarber && m.commission.cents > 0)
                        '${m.commission.format(symbol: false)}% commission',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.textMuted),
                  ),
                  if (m.serviceNames.isNotEmpty)
                    Text(
                      m.serviceNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: t.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
            if (hasMenu)
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: t.textSecondary,
                ),
                color: t.surfaceRaised,
                onSelected: (v) => switch (v) {
                  'edit' => onEdit?.call(),
                  'password' => onPassword?.call(),
                  'assign' => onAssign?.call(),
                  _ => onDelete?.call(),
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (onAssign != null)
                    const PopupMenuItem(
                      value: 'assign',
                      child: Text('Assign Services'),
                    ),
                  if (onPassword != null)
                    const PopupMenuItem(
                      value: 'password',
                      child: Text('Change Password'),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: t.danger)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
