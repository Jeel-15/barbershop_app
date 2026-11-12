import 'dart:io';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

/// Opens the gallery and returns the chosen image's path (null = cancelled).
/// A provider so tests can answer without a real gallery.
final photoPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    return x?.path;
  },
);

/// Reloads the signed-in user (name and photo in the headers). A provider so
/// tests can skip the network.
final refreshAccountProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(sessionControllerProvider.notifier).refreshBootstrap(),
);

/// The web's My Profile ("View and update your account details"): the person,
/// their assigned services, Edit Profile (Name, Email, Phone, Role, Profile
/// Photo) and, for staff, the numbers.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _role = TextEditingController();
  bool _filled = false;
  bool _busy = false;
  String? _photo;
  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _photoError;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _role]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(MyProfile p) {
    if (_filled) return;
    _filled = true;
    _name.text = p.name;
    _email.text = p.email;
    _phone.text = p.phone ?? '';
    _role.text = p.role;
  }

  Future<void> _pickPhoto() async {
    final path = await ref.read(photoPickerProvider)();
    if (path == null || !mounted) return;
    // The web accepts JPG, PNG or GIF up to 2 MB.
    final ext = path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
      setState(() => _photoError = 'JPG, PNG or GIF only.');
      return;
    }
    if (await File(path).length() > 2 * 1024 * 1024) {
      if (mounted) setState(() => _photoError = 'Max 2MB.');
      return;
    }
    setState(() {
      _photo = path;
      _photoError = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _nameError = _name.text.trim().isEmpty
          ? 'The name field is required.'
          : null;
      _emailError = _email.text.trim().isEmpty
          ? 'The email field is required.'
          : null;
      _phoneError = null;
    });
    if (_nameError != null || _emailError != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref
          .read(meRepositoryProvider)
          .updateProfile(
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            photoPath: _photo,
          );
      // The header of Home / More shows this name and photo.
      await ref.read(refreshAccountProvider)();
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() {
        _photo = null;
        _filled = false;
      });
      showToast(
        context,
        'Profile updated successfully.',
        kind: ToastKind.success,
      );
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _nameError = f.errorFor('name');
        _emailError = f.errorFor('email');
        _phoneError = f.errorFor('phone');
        _photoError = f.errorFor('profile_image');
      });
      if (_nameError == null &&
          _emailError == null &&
          _phoneError == null &&
          _photoError == null) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final async = ref.watch(myProfileProvider);
    final p = async.value;
    if (p != null) _fill(p);

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
                        : context.go('/app/more'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Profile',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          'View and update your account details',
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (async) {
                AsyncError(:final error) when p == null => ErrorState(
                  message: error is Failure
                      ? error.userMessage
                      : 'Could not load your profile.',
                  supportCode: error is Failure ? error.requestId : null,
                  onRetry: () => ref.invalidate(myProfileProvider),
                ),
                _ when p == null => const Padding(
                  padding: EdgeInsets.all(AppSpace.page),
                  child: SkeletonLoader(
                    child: Column(
                      children: [
                        SkeletonBox(height: 200, radius: 20),
                        SizedBox(height: AppSpace.md),
                        SkeletonBox(height: 260, radius: 16),
                      ],
                    ),
                  ),
                ),
                _ => ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.sm,
                    AppSpace.page,
                    AppSpace.xxl,
                  ),
                  children: [
                    _Hero(
                      profile: p,
                      photoPath: _photo,
                      onPhoto: _pickPhoto,
                      onFullStats: user.modules.staffReport
                          ? () => context.push('/app/report')
                          : null,
                    ),
                    if (p.stats != null) ...[
                      const SizedBox(height: AppSpace.lg),
                      _Stats(stats: p.stats!),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    FormSection(
                      title: 'Edit Profile',
                      icon: Icons.edit_rounded,
                      children: [
                        AppTextField(
                          label: 'Name *',
                          prefixIcon: Icons.person_outline_rounded,
                          controller: _name,
                          errorText: _nameError,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          clearable: true,
                        ),
                        AppTextField(
                          label: 'Email *',
                          prefixIcon: Icons.mail_outline_rounded,
                          controller: _email,
                          errorText: _emailError,
                          validator: (v) =>
                              RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(v.trim())
                              ? null
                              : 'Enter a valid email address.',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          clearable: true,
                        ),
                        AppTextField(
                          label: 'Phone',
                          prefixIcon: Icons.phone_outlined,
                          controller: _phone,
                          errorText: _phoneError,
                          keyboardType: TextInputType.phone,
                          maxLength: 20,
                          clearable: true,
                        ),
                        AppTextField(
                          label: 'Role',
                          prefixIcon: Icons.badge_outlined,
                          controller: _role,
                          enabled: false,
                          helperText: 'Set by an administrator.',
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Profile Photo'),
                            const SizedBox(height: 8),
                            AppButton(
                              label: _photo == null
                                  ? 'Choose photo'
                                  : 'Photo chosen: ${_photo!.split(RegExp(r'[\\/]')).last}',
                              icon: Icons.photo_library_rounded,
                              variant: AppButtonVariant.secondary,
                              compact: true,
                              onPressed: _pickPhoto,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _photoError ?? 'JPG, PNG or GIF. Max 2MB.',
                              style: AppType.caption.copyWith(
                                color: _photoError == null
                                    ? t.textMuted
                                    : t.danger,
                              ),
                            ),
                          ],
                        ),
                        AppButton(
                          label: 'Save Changes',
                          icon: Icons.check_rounded,
                          loading: _busy,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.profile,
    required this.photoPath,
    required this.onPhoto,
    required this.onFullStats,
  });

  final MyProfile profile;
  final String? photoPath;
  final VoidCallback onPhoto;
  final VoidCallback? onFullStats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = profile;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Pressable(
            onTap: onPhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (photoPath != null)
                  CircleAvatar(
                    radius: 46,
                    backgroundImage: FileImage(File(photoPath!)),
                  )
                else
                  AppAvatar(
                    name: p.name,
                    imageUrl: p.imageUrl,
                    size: 92,
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
          const SizedBox(height: AppSpace.md),
          Text(p.name, style: AppType.title.copyWith(color: t.text)),
          Text(p.role, style: AppType.body.copyWith(color: t.textSecondary)),
          const SizedBox(height: AppSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mail_outline_rounded, size: 16, color: t.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  p.email,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(color: t.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.call_outlined, size: 16, color: t.textMuted),
              const SizedBox(width: 6),
              Text(
                (p.phone ?? '').isEmpty ? '—' : p.phone!,
                style: AppType.body.copyWith(color: t.text),
              ),
            ],
          ),
          if (p.services.isNotEmpty) ...[
            Divider(height: AppSpace.xl, color: t.border),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Assigned Services',
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in p.services)
                    StatusPill(label: s, color: t.accentText, compact: true),
                ],
              ),
            ),
          ],
          if (onFullStats != null) ...[
            const SizedBox(height: AppSpace.lg),
            AppButton(
              label: 'View full stats',
              variant: AppButtonVariant.secondary,
              compact: true,
              onPressed: onFullStats,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats});

  final MyStats stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget tile(String label, String value) => Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.caption.copyWith(color: t.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: AppType.title.copyWith(color: t.text)),
        ],
      ),
    );
    return TileGrid(
      children: [
        tile('Completed Services', '${stats.appointments}'),
        tile('Total Visits', '${stats.visits}'),
        tile('Tips', stats.tips.format()),
        tile('Total Earning', stats.totalEarning.format()),
      ],
    );
  }
}
