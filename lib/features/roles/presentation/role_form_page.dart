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

  /// True once the person changed something: leaving then asks first.
  bool _dirty = false;

  bool get _editing => widget.roleId != null;

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

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
    _name.addListener(_touch);
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
    final async = ref.watch(rolesProvider);
    final data = async.value;
    if (data != null) _fill(data);
    final ready = data != null && !(_editing && _role == null);

    return FormPageFrame(
      title: _editing ? 'Edit Role' : 'Add New Role',
      dirty: _dirty,
      onClose: () =>
          context.canPop() ? context.pop() : context.go('/app/roles'),
      bottom: ready
          ? FormActionBar(
              label: 'Submit',
              loading: _busy,
              onPressed: _save,
              secondaryLabel: 'Cancel',
              onSecondary: () =>
                  context.canPop() ? context.pop() : context.go('/app/roles'),
            )
          : null,
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
    );
  }

  Widget _body(BuildContext context, RolesData data) {
    final t = context.tokens;
    final all = data.allPermissionIds;
    final allOn = all.isNotEmpty && all.every(_picked.contains);
    const gap = SizedBox(height: AppSpace.md);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.sm,
        AppSpace.page,
        AppSpace.xl,
      ),
      children: [
        FormSection(
          title: 'Role',
          icon: Icons.admin_panel_settings_rounded,
          children: [
            AppTextField(
              label: 'Role Name',
              hint: 'Enter a role name',
              controller: _name,
              errorText: _nameError,
              textCapitalization: TextCapitalization.words,
              autofocus: !_editing,
              helperText: (_role?.locked ?? false)
                  ? 'A system role: its name cannot be changed.'
                  : null,
            ),
          ],
        ),
        gap,
        SwitchRow(
          label: 'Administrator Access',
          hint: 'Allows a full access to the system. Select All',
          value: allOn,
          onChanged: (v) => setState(() {
            _picked = v ? {...all} : <int>{};
            _dirty = true;
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, AppSpace.lg, 0, AppSpace.sm),
          child: Text(
            'Role Permissions',
            style: AppType.subheading.copyWith(color: t.text),
          ),
        ),
        for (final g in data.groups) ...[
          FormSection(
            title: g.name,
            subtitle:
                '${g.permissions.where((p) => _picked.contains(p.id)).length} of ${g.permissions.length} allowed',
            children: [
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
                        _dirty = true;
                      }),
                    ),
                ],
              ),
            ],
          ),
          gap,
        ],
      ],
    );
  }
}
