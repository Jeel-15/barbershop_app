import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/application/catalog_controllers.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

/// The web's Services page ("Manage service offerings, pricing, and duration").
class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  Future<void> _form(
    BuildContext context,
    WidgetRef ref, [
    AdminService? s,
  ]) async {
    final msg = await context.push<String>(
      s == null ? '/app/services/new' : '/app/services/edit/${s.id}',
      extra: s,
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(servicesListProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AdminService s,
  ) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Service?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final msg = await ref.read(catalogRepositoryProvider).deleteService(s.id);
      if (!context.mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(servicesListProvider);
    } on Failure catch (f) {
      if (context.mounted) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    }
  }

  Future<void> _section(
    BuildContext context,
    WidgetRef ref,
    AdminService s,
  ) async {
    final msg = await showAppSheet<String>(
      context,
      title: 'Website Section',
      builder: (_) => _SectionForm(service: s),
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(servicesListProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final query = ref.watch(serviceQueryProvider);
    final canEdit = user.can(Perm.serviceEdit);
    final canDelete = user.can(Perm.serviceDelete);
    return AdminListShell(
      title: 'Services',
      subtitle: 'Manage service offerings, pricing, and duration',
      addLabel: 'Add Service',
      onAdd: user.can(Perm.serviceAdd) ? () => _form(context, ref) : null,
      searchHint: 'Search service, category, duration or price',
      query: query,
      onSearch: (q) => ref.read(serviceQueryProvider.notifier).set(q),
      body: PagedBody<AdminService>(
        async: ref.watch(servicesListProvider),
        countLabel: query.trim().isEmpty ? 'ALL SERVICES' : 'FOUND',
        emptyTitle: query.trim().isEmpty
            ? 'No services yet'
            : 'No services found',
        emptyMessage: query.trim().isEmpty
            ? 'Add the first service of the shop.'
            : 'Try another name, category, duration or price.',
        onRefresh: () => ref.read(servicesListProvider.notifier).refresh(),
        onRetry: () => ref.invalidate(servicesListProvider),
        onMore: () => ref.read(servicesListProvider.notifier).loadMore(),
        itemBuilder: (context, s) => AdminTile(
          title: s.name,
          imageUrl: s.imageUrl,
          icon: Icons.content_cut_rounded,
          badge: s.active
              ? null
              : StatusPill(
                  label: 'Inactive',
                  color: context.tokens.danger,
                  compact: true,
                ),
          lines: ['${s.categoryName} · ${s.duration} min'],
          trailing: Padding(
            padding: const EdgeInsets.only(left: AppSpace.sm),
            child: Text(
              s.price.format(),
              style: AppType.bodyStrong.copyWith(color: context.tokens.text),
            ),
          ),
          menu: [
            if (canEdit) ('edit', 'Edit', false),
            ('section', 'Website Section', false),
            if (canDelete) ('delete', 'Delete', true),
          ],
          onMenu: (v) => switch (v) {
            'edit' => _form(context, ref, s),
            'section' => _section(context, ref, s),
            _ => _delete(context, ref, s),
          },
          onTap: canEdit ? () => _form(context, ref, s) : null,
        ),
      ),
    );
  }
}

/// The web's "Website Section" modal: Select Section (none / Signature Grooming Menu).
class _SectionForm extends ConsumerStatefulWidget {
  const _SectionForm({required this.service});

  final AdminService service;

  @override
  ConsumerState<_SectionForm> createState() => _SectionFormState();
}

class _SectionFormState extends ConsumerState<_SectionForm> {
  late String? _section = widget.service.homeSection;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(catalogRepositoryProvider)
          .setHomeSection(widget.service.id, _section);
      if (mounted) Navigator.of(context).pop(msg);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.service.name,
          style: AppType.bodyStrong.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Select Section',
          style: AppType.label.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppChoiceChip(
              label: '-- Select --',
              selected: _section == null,
              onTap: () => setState(() => _section = null),
            ),
            AppChoiceChip(
              label: 'Signature Grooming Menu',
              selected: _section == 'signature_grooming',
              onTap: () => setState(() => _section = 'signature_grooming'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'Update', loading: _busy, onPressed: _save),
      ],
    );
  }
}
