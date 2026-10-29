import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/roles/data/roles_repository.dart';
import 'package:barbershop_app/features/roles/domain/role_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's "Add New Role" / edit form: Role Name, then Role Permissions
/// grouped by module with "Administrator Access - Select All". Pops with the
/// server's message when saved.
class RoleFormPage extends ConsumerStatefulWidget {
  const RoleFormPage({super.key, this.roleId});

  /// Null = Add New Role.
  final int? roleId;

  @override
  ConsumerState<RoleFormPage> createState() => _RoleFormPageState();
}

class _RoleFormPageState extends ConsumerState<RoleFormPage> {
  final _name = TextEditingController();
  Set<int> _picked = {};
  RoleItem? _role;
  bool _filled = false;
  bool _busy = false;
  String? _nameError;

  bool get _editing => widget.roleId != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _fill(RolesData data) {
    if (_filled) return;
    _filled = true;
    if (_editing) {
      final r = data.roles.where((r) => r.id == widget.roleId).firstOrNull;
      _role = r;
      if (r != null) {
        _name.text = r.name;
        _picked = {...r.permissionIds};
      }
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Please Enter Role Name');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _nameError = null;
      _busy = true;
    });
    try {
      final repo = ref.read(rolesRepositoryProvider);
      final msg = _editing
          ? await repo.update(widget.roleId!, _name.text, _picked)
          : await repo.create(_name.text, _picked);
      if (mounted) context.pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = f.errorFor('name') ?? f.userMessage;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(rolesProvider);
    final data = async.value;
    if (data != null) _fill(data);

    return Scaffold(
      body: SafeArea(
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
                        : context.go('/app/roles'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      _editing ? 'Edit Role' : 'Add New Role',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: data == null
                  ? (async.hasError
                        ? ErrorState(
                            message: async.error is Failure
                                ? (async.error! as Failure).userMessage
                                : 'Could not open the form.',
                            onRetry: () => ref.invalidate(rolesProvider),
                          )
                        : const Padding(
                            padding: EdgeInsets.all(AppSpace.page),
                            child: SkeletonRows(count: 5),
                          ))
                  : _editing && _role == null
                  ? const QuietState(
                      title: 'Role not found',
                      message: 'It may have been deleted.',
                    )
                  : _body(context, data),
            ),
            if (data != null && !(_editing && _role == null))
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.page,
                  AppSpace.md,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => context.pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm + 2),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: 'Submit',
                        loading: _busy,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, RolesData data) {
    final t = context.tokens;
    final all = data.allPermissionIds;
    final allOn = all.isNotEmpty && all.every(_picked.contains);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.sm,
        AppSpace.page,
        AppSpace.xl,
      ),
      children: [
        AppTextField(
          label: 'Role Name',
          hint: 'Enter a role name',
          controller: _name,
          errorText: _nameError,
          textCapitalization: TextCapitalization.words,
          autofocus: !_editing,
        ),
        if (_role?.locked ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'A system role: its name cannot be changed.',
              style: AppType.caption.copyWith(color: t.textMuted),
            ),
          ),
        const SizedBox(height: AppSpace.xl),
        Text(
          'Role Permissions',
          style: AppType.subheading.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.sm + 2),
        SwitchRow(
          label: 'Administrator Access',
          hint: 'Allows a full access to the system. Select All',
          value: allOn,
          onChanged: (v) => setState(() {
            _picked = v ? {...all} : <int>{};
          }),
        ),
        for (final g in data.groups) ...[
          const SizedBox(height: AppSpace.lg),
          Text(g.name, style: AppType.bodyStrong.copyWith(color: t.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in g.permissions)
                AppChoiceChip(
                  label: p.label,
                  selected: _picked.contains(p.id),
                  onTap: () => setState(() {
                    if (!_picked.add(p.id)) _picked.remove(p.id);
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
