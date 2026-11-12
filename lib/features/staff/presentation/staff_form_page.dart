import 'dart:io';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's "Add Staff" / "Update Staff" modal as a page: Staff Name, Email,
/// Phone, Password, Barber, Service, Product Commission (%), Status, Role and
/// Staff Profile Image. Pops with the server's message when saved.
class StaffFormPage extends ConsumerStatefulWidget {
  const StaffFormPage({super.key, this.editId, this.member});

  /// Null = Add Staff.
  final int? editId;

  /// The row the list already has (saves a request when editing).
  final StaffMember? member;

  @override
  ConsumerState<StaffFormPage> createState() => _StaffFormPageState();
}

class _StaffFormPageState extends ConsumerState<StaffFormPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _commission = TextEditingController();

  bool _loading = true;
  Object? _loadError;
  StaffMember? _existing;

  bool _isBarber = true;
  bool _active = true;
  int? _roleId;
  Set<int> _services = {};
  String? _photo;
  bool _busy = false;
  bool _showPassword = false;

  final _errors = <String, String>{};

  /// True once the person changed something: leaving then asks first.
  bool _dirty = false;
  bool _listening = false;

  /// One key per field that can show an error, to scroll to the first one.
  static const _order = [
    'photo',
    'name',
    'email',
    'phone',
    'password',
    'role',
    'services',
    'commission',
  ];
  final _keys = {for (final k in _order) k: GlobalKey()};

  bool get _editing => widget.editId != null;

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  static String? _nameError(String v) =>
      v.trim().isEmpty ? 'Please enter Staff Name' : null;

  static String? _emailError(String v) {
    final email = v.trim();
    if (email.isEmpty) return 'Please enter Staff Email';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
        ? null
        : 'Enter valid email';
  }

  static String? _passwordError(String v) => v.isNotEmpty && v.length < 6
      ? 'Password must be at least 6 characters long'
      : null;

  void _showFirstError() => scrollToFirstError([
    for (final k in _order)
      if (_errors[k] != null) _keys[k],
  ]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(staffRepositoryProvider);
      await ref.read(staffFormOptionsProvider.future);
      if (_editing) {
        final m = widget.member ?? (await repo.profile(widget.editId!)).staff;
        var ids = m.serviceIds;
        if (m.isBarber && m.panelRole == 'Staff' && ids.isEmpty) {
          ids = await repo.assignedServices(m.id);
        }
        _existing = m;
        _name.text = m.name;
        _email.text = m.email;
        _phone.text = m.phone ?? '';
        _commission.text = m.commission.isZero ? '' : m.commission.toApi();
        _isBarber = m.isBarber;
        _active = m.active;
        _roleId = m.roleIds.isEmpty ? null : m.roleIds.first;
        _services = ids.toSet();
      }
      if (!_listening) {
        _listening = true;
        for (final c in [_name, _email, _phone, _password, _commission]) {
          c.addListener(_touch);
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e;
        });
      }
    }
  }

  RoleOption? _role(StaffFormOptions o) =>
      o.roles.where((r) => r.id == _roleId).firstOrNull;

  Future<void> _pickPhoto() async {
    final path = await ref.read(photoPickerProvider)();
    if (path == null || !mounted) return;
    final ext = path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
      setState(
        () => _errors['photo'] =
            'Please upload a valid image file (jpg, jpeg, png, gif)',
      );
      return;
    }
    if (await File(path).length() > 2 * 1024 * 1024) {
      if (mounted) setState(() => _errors['photo'] = 'Max 2MB.');
      return;
    }
    setState(() {
      _photo = path;
      _errors.remove('photo');
      _dirty = true;
    });
  }

  Future<void> _pickServices(StaffFormOptions o) async {
    final res = await showAppSheet<Set<int>>(
      context,
      title: 'Service',
      builder: (_) => _ServicePicker(options: o.services, selected: _services),
    );
    if (res != null) {
      setState(() {
        _services = res;
        _errors.remove('services');
        _dirty = true;
      });
    }
  }

  /// The web's own checks, in the web's words. Returns false if anything is wrong.
  bool _validate(StaffFormOptions o) {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'Please enter Staff Name';
    final email = _email.text.trim();
    if (email.isEmpty) {
      e['email'] = 'Please enter Staff Email';
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      e['email'] = 'Enter valid email';
    }
    if (!_editing && _password.text.isEmpty) {
      e['password'] = 'Please enter Password';
    } else if (_password.text.isNotEmpty && _password.text.length < 6) {
      e['password'] = 'Password must be at least 6 characters long';
    }
    if (_roleId == null) e['role'] = 'Please select Role';
    final barber = _isBarber && !(_role(o)?.isAccountant ?? false);
    if (barber && _services.isEmpty) {
      e['services'] = 'Please select at least one Service';
    }
    if (barber && _commission.text.trim().isNotEmpty) {
      final c = double.tryParse(_commission.text.trim());
      if (c == null) {
        e['commission'] = 'Commission must be a number';
      } else if (c < 0) {
        e['commission'] = 'Commission cannot be negative';
      }
    }
    setState(() {
      _errors
        ..removeWhere((k, _) => k != 'photo')
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save(StaffFormOptions o) async {
    if (!_validate(o)) {
      _showFirstError();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final barber = _isBarber && !(_role(o)?.isAccountant ?? false);
    final input = StaffInput(
      name: _name.text,
      email: _email.text,
      phone: _phone.text,
      password: _password.text,
      isBarber: barber,
      serviceIds: _services.toList()..sort(),
      commission: _commission.text,
      active: _active,
      roleId: _roleId!,
      photoPath: _photo,
    );
    try {
      final repo = ref.read(staffRepositoryProvider);
      final msg = _editing
          ? await repo.update(widget.editId!, input)
          : await repo.create(input);
      ref.invalidate(staffProfileProvider);
      if (mounted) context.pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final e in {
          'name': 'name',
          'email': 'email',
          'password': 'password',
          'phone': 'phone',
          'commission': 'commission',
          'role_id': 'role',
          'service_ids': 'services',
          'profile_image': 'photo',
        }.entries) {
          final m = f.errorFor(e.key);
          if (m != null) _errors[e.value] = m;
        }
      });
      if (f.fieldErrors.isEmpty) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      } else {
        _showFirstError();
      }
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(staffFormOptionsProvider).value;
    final loading = _loading || (options == null && _loadError == null);
    final ready = !loading && _loadError == null && options != null;

    return FormPageFrame(
      title: _editing ? 'Update Staff' : 'Add Staff',
      dirty: _dirty,
      onClose: () =>
          context.canPop() ? context.pop() : context.go('/app/staff'),
      bottom: ready
          ? FormActionBar(
              label: _editing ? 'Update Staff' : 'Add Staff',
              loading: _busy,
              onPressed: () => _save(options),
            )
          : null,
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(AppSpace.page),
              child: SkeletonLoader(
                child: Column(
                  children: [
                    SkeletonBox(height: 200, radius: 16),
                    SizedBox(height: AppSpace.md),
                    SkeletonBox(height: 120, radius: 16),
                    SizedBox(height: AppSpace.md),
                    SkeletonBox(height: 160, radius: 16),
                  ],
                ),
              ),
            )
          : _loadError != null || options == null
          ? ErrorState(
              message: _loadError is Failure
                  ? (_loadError! as Failure).userMessage
                  : 'Could not open the form.',
              onRetry: _load,
            )
          : _body(context, options),
    );
  }

  Widget _body(BuildContext context, StaffFormOptions o) {
    final t = context.tokens;
    final accountant = _role(o)?.isAccountant ?? false;
    final barber = _isBarber && !accountant;
    final chosen = [
      for (final s in o.services)
        if (_services.contains(s.id)) s,
    ];
    const gap = SizedBox(height: AppSpace.md);

    Widget error(String key) => _errors[key] == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_rounded, size: 15, color: t.danger),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _errors[key]!,
                    style: AppType.caption.copyWith(color: t.danger),
                  ),
                ),
              ],
            ),
          );

    return ListView(
      // Every section is built, so a field with an error can be scrolled to.
      scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.sm,
        AppSpace.page,
        AppSpace.xl,
      ),
      children: [
        FormSection(
          title: 'Profile',
          icon: Icons.person_rounded,
          children: [
            Column(
              key: _keys['photo'],
              children: [
                Center(
                  child: Pressable(
                    onTap: _pickPhoto,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (_photo != null)
                          CircleAvatar(
                            radius: 44,
                            backgroundImage: FileImage(File(_photo!)),
                          )
                        else
                          AppAvatar(
                            name: _name.text.isEmpty ? 'Staff' : _name.text,
                            imageUrl: _existing?.photoUrl,
                            size: 88,
                            ring: true,
                          ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: t.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.surface, width: 2),
                            ),
                            child: Icon(
                              Icons.photo_camera_rounded,
                              size: 15,
                              color: t.onAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _errors['photo'] ?? 'Staff Profile Image',
                  style: AppType.caption.copyWith(
                    color: _errors['photo'] == null ? t.textMuted : t.danger,
                  ),
                ),
              ],
            ),
            AppTextField(
              key: _keys['name'],
              label: 'Staff Name *',
              hint: 'Enter Staff Name',
              controller: _name,
              errorText: _errors['name'],
              validator: _nameError,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              clearable: true,
              onChanged: (_) => setState(() {}),
            ),
            AppTextField(
              key: _keys['email'],
              label: 'Email *',
              hint: 'Enter Staff Email',
              prefixIcon: Icons.mail_outline_rounded,
              controller: _email,
              errorText: _errors['email'],
              validator: _emailError,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              clearable: true,
            ),
            AppTextField(
              key: _keys['phone'],
              label: 'Phone',
              hint: 'Enter Staff Phone',
              prefixIcon: Icons.phone_outlined,
              controller: _phone,
              errorText: _errors['phone'],
              keyboardType: TextInputType.phone,
              maxLength: 20,
              clearable: true,
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Sign-in',
          icon: Icons.lock_outline_rounded,
          subtitle: _editing ? 'Leave the password empty to keep it.' : null,
          children: [
            AppTextField(
              key: _keys['password'],
              label: _editing ? 'Password' : 'Password *',
              hint: _editing
                  ? 'Leave empty to keep the password'
                  : 'Enter Password',
              controller: _password,
              errorText: _errors['password'],
              validator: _passwordError,
              obscure: !_showPassword,
              suffix: IconButton(
                tooltip: _showPassword ? 'Hide' : 'Show',
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: t.textMuted,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Role and work',
          icon: Icons.badge_rounded,
          children: [
            Column(
              key: _keys['role'],
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Role *'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in o.roles)
                      AppChoiceChip(
                        label: r.name,
                        selected: _roleId == r.id,
                        onTap: () => setState(() {
                          _roleId = r.id;
                          _errors.remove('role');
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                error('role'),
              ],
            ),
            if (!accountant)
              SwitchTile(
                label: 'Barber',
                hint:
                    'Turn off if this staff is not a barber. Service and commission will be hidden.',
                value: _isBarber,
                onChanged: (v) => setState(() {
                  _isBarber = v;
                  _dirty = true;
                }),
              ),
            if (barber)
              Column(
                key: _keys['services'],
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Service'),
                  const SizedBox(height: 8),
                  Pressable(
                    onTap: () => _pickServices(o),
                    minSize: 0,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _errors['services'] == null
                              ? t.border
                              : t.danger,
                        ),
                      ),
                      child: chosen.isEmpty
                          ? Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Select Service',
                                    style: AppType.body.copyWith(
                                      color: t.textMuted,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: t.textMuted,
                                ),
                              ],
                            )
                          : Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final s in chosen)
                                  StatusPill(
                                    label: s.name,
                                    color: t.accentText,
                                    compact: true,
                                  ),
                              ],
                            ),
                    ),
                  ),
                  error('services'),
                ],
              ),
            if (barber)
              AppTextField(
                key: _keys['commission'],
                label: 'Product Commission (%)',
                hint: 'Enter Product Commission',
                suffixText: '%',
                controller: _commission,
                errorText: _errors['commission'],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
          ],
        ),
        gap,
        FormSection(
          title: 'Status',
          icon: Icons.toggle_on_rounded,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Status *'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    AppChoiceChip(
                      label: 'Active',
                      selected: _active,
                      onTap: () => setState(() {
                        _active = true;
                        _dirty = true;
                      }),
                    ),
                    AppChoiceChip(
                      label: 'Deactive',
                      selected: !_active,
                      onTap: () => setState(() {
                        _active = false;
                        _dirty = true;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Multi-select of the shop's services (the web's Service dropdown).
class _ServicePicker extends StatefulWidget {
  const _ServicePicker({required this.options, required this.selected});

  final List<ServiceOption> options;
  final Set<int> selected;

  @override
  State<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends State<_ServicePicker> {
  late final Set<int> _picked = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in widget.options)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _picked.contains(s.id),
            title: Text(s.name, style: AppType.body.copyWith(color: t.text)),
            onChanged: (v) => setState(() {
              if (v == true) {
                _picked.add(s.id);
              } else {
                _picked.remove(s.id);
              }
            }),
          ),
        const SizedBox(height: AppSpace.lg),
        AppButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }
}
