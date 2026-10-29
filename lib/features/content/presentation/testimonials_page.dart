import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:barbershop_app/features/content/application/content_controllers.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's Testimonials page ("Manage homepage "What Clients Say" reviews").
class TestimonialsPage extends ConsumerWidget {
  const TestimonialsPage({super.key});

  Future<void> _form(
    BuildContext context,
    WidgetRef ref, [
    Testimonial? t,
  ]) async {
    final msg = await context.push<String>(
      t == null ? '/app/testimonials/new' : '/app/testimonials/edit/${t.id}',
      extra: t,
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(testimonialsProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Testimonial t,
  ) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Delete this testimonial?',
      confirmLabel: 'Yes, delete it',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final msg = await ref
          .read(contentRepositoryProvider)
          .deleteTestimonial(t.id);
      if (!context.mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(testimonialsProvider);
    } on Failure catch (f) {
      if (context.mounted) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final query = ref.watch(testimonialQueryProvider);
    final canEdit = user.can('Testimonial-Edit');
    final canDelete = user.can('Testimonial-Delete');
    return AdminListShell(
      title: 'Testimonials',
      subtitle: 'Manage homepage “What Clients Say” reviews',
      addLabel: 'Add Testimonial',
      onAdd: user.can('Testimonial-Add') ? () => _form(context, ref) : null,
      searchHint: 'Search name, title or review',
      query: query,
      onSearch: (q) => ref.read(testimonialQueryProvider.notifier).set(q),
      body: PagedBody<Testimonial>(
        async: ref.watch(testimonialsProvider),
        countLabel: query.trim().isEmpty ? 'ALL TESTIMONIALS' : 'FOUND',
        emptyTitle: query.trim().isEmpty
            ? 'No testimonials yet'
            : 'No testimonials found',
        emptyMessage: query.trim().isEmpty
            ? 'Add the first review for the homepage.'
            : 'Try another name, title or word of the review.',
        onRefresh: () => ref.read(testimonialsProvider.notifier).refresh(),
        onRetry: () => ref.invalidate(testimonialsProvider),
        onMore: () => ref.read(testimonialsProvider.notifier).loadMore(),
        itemBuilder: (context, x) => AdminTile(
          title: x.name,
          imageUrl: x.imageUrl,
          icon: Icons.format_quote_rounded,
          badge: StatusPill(
            label: x.active ? 'Active' : 'Hidden',
            color: x.active ? t.success : t.textMuted,
            compact: true,
          ),
          lines: [
            '${x.stars} · ${x.role}',
            x.review.length > 90 ? '${x.review.substring(0, 90)}…' : x.review,
          ],
          menu: [
            if (canEdit) ('edit', 'Edit', false),
            if (canDelete) ('delete', 'Delete', true),
          ],
          onMenu: (v) =>
              v == 'edit' ? _form(context, ref, x) : _delete(context, ref, x),
          onTap: canEdit ? () => _form(context, ref, x) : null,
        ),
      ),
    );
  }
}

/// The web's "Add Testimonial" / update modal as a page: Client Name, Client
/// Title, Review, Rating, Display Order, Show on website, Client Photo.
class TestimonialFormPage extends ConsumerStatefulWidget {
  const TestimonialFormPage({super.key, this.testimonial});

  /// Null = Add Testimonial.
  final Testimonial? testimonial;

  @override
  ConsumerState<TestimonialFormPage> createState() =>
      _TestimonialFormPageState();
}

class _TestimonialFormPageState extends ConsumerState<TestimonialFormPage> {
  late final _name = TextEditingController(text: widget.testimonial?.name);
  late final _role = TextEditingController(text: widget.testimonial?.role);
  late final _review = TextEditingController(text: widget.testimonial?.review);
  late final _order = TextEditingController(
    text: '${widget.testimonial?.sortOrder ?? 0}',
  );
  late int _rating = widget.testimonial?.rating ?? 5;
  late bool _active = widget.testimonial?.active ?? true;
  String? _image;
  bool _busy = false;
  final _errors = <String, String>{};

  bool get _editing => widget.testimonial != null;

  @override
  void dispose() {
    for (final c in [_name, _role, _review, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await pickCatalogImage(
      ref,
      allowWebp: true,
      invalidMessage: 'Please upload a valid image (jpg, png, gif, webp)',
    );
    if (!mounted) return;
    setState(() {
      if (r.path != null) {
        _image = r.path;
        _errors.remove('image');
      }
      if (r.error != null) _errors['image'] = r.error!;
    });
  }

  bool _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) {
      e['name'] = 'The client name field is required.';
    }
    if (_review.text.trim().isEmpty) {
      e['review'] = 'The review field is required.';
    } else if (_review.text.trim().length > 2000) {
      e['review'] = 'The review must not be greater than 2000 characters.';
    }
    final o = _order.text.trim();
    if (o.isNotEmpty && (int.tryParse(o) == null || int.parse(o) < 0)) {
      e['order'] = 'The display order must be a whole number, 0 or more.';
    }
    setState(() {
      _errors
        ..removeWhere((k, _) => k == 'name' || k == 'review' || k == 'order')
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final input = TestimonialInput(
      name: _name.text,
      role: _role.text,
      review: _review.text,
      rating: _rating,
      sortOrder: _order.text,
      active: _active,
      imagePath: _image,
    );
    try {
      final repo = ref.read(contentRepositoryProvider);
      final msg = _editing
          ? await repo.updateTestimonial(widget.testimonial!.id, input)
          : await repo.createTestimonial(input);
      if (mounted) context.pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final e in {
          'client_name': 'name',
          'review': 'review',
          'sort_order': 'order',
          'image': 'image',
        }.entries) {
          final m = f.errorFor(e.key);
          if (m != null) _errors[e.value] = m;
        }
      });
      if (f.fieldErrors.isEmpty) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
                        : context.go('/app/testimonials'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      _editing ? 'Update Testimonial' : 'Add Testimonial',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.sm,
                  AppSpace.page,
                  AppSpace.xl,
                ),
                children: [
                  AppTextField(
                    label: 'Client Name *',
                    hint: 'Enter client name',
                    controller: _name,
                    errorText: _errors['name'],
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppTextField(
                    label: 'Client Title',
                    hint: 'Regular Client',
                    controller: _role,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppTextField(
                    label: 'Review *',
                    hint: 'What the client said',
                    controller: _review,
                    errorText: _errors['review'],
                    maxLines: 5,
                    maxLength: 2000,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    'Rating',
                    style: AppType.label.copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in const [5, 4, 3, 2, 1])
                        AppChoiceChip(
                          label: r == 1 ? '1 Star' : '$r Stars',
                          selected: _rating == r,
                          onTap: () => setState(() => _rating = r),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppTextField(
                    label: 'Display Order',
                    controller: _order,
                    errorText: _errors['order'],
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  SwitchRow(
                    label: 'Show on website',
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  ImagePickField(
                    label: 'Client Photo',
                    pickedPath: _image,
                    savedUrl: widget.testimonial?.imageUrl,
                    error: _errors['image'],
                    onPick: _pick,
                  ),
                ],
              ),
            ),
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
              child: AppButton(label: 'Save', loading: _busy, onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}
