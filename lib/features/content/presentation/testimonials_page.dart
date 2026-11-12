import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:barbershop_app/features/content/application/content_controllers.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

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
    final canEdit = user.can(Perm.testimonialEdit);
    final canDelete = user.can(Perm.testimonialDelete);
    return AdminListShell(
      title: 'Testimonials',
      subtitle: 'Manage homepage “What Clients Say” reviews',
      addLabel: 'Add Testimonial',
      onAdd: user.can(Perm.testimonialAdd) ? () => _form(context, ref) : null,
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

  /// True once the person changed something: leaving then asks first.
  bool _dirty = false;
  final _keys = {
    for (final k in ['name', 'review', 'order']) k: GlobalKey(),
  };

  bool get _editing => widget.testimonial != null;

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _role, _review, _order]) {
      c.addListener(_touch);
    }
  }

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
        _dirty = true;
      }
      if (r.error != null) _errors['image'] = r.error!;
    });
  }

  static String? _nameError(String v) =>
      v.trim().isEmpty ? 'The client name field is required.' : null;

  static String? _reviewError(String v) {
    if (v.trim().isEmpty) return 'The review field is required.';
    return v.trim().length > 2000
        ? 'The review must not be greater than 2000 characters.'
        : null;
  }

  static String? _orderError(String v) {
    final o = v.trim();
    return o.isNotEmpty && (int.tryParse(o) == null || int.parse(o) < 0)
        ? 'The display order must be a whole number, 0 or more.'
        : null;
  }

  bool _validate() {
    final e = <String, String>{};
    final name = _nameError(_name.text);
    if (name != null) e['name'] = name;
    final review = _reviewError(_review.text);
    if (review != null) e['review'] = review;
    final order = _orderError(_order.text);
    if (order != null) e['order'] = order;
    setState(() {
      _errors
        ..removeWhere((k, _) => k == 'name' || k == 'review' || k == 'order')
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) {
      scrollToFirstError([
        for (final k in ['name', 'review', 'order'])
          if (_errors[k] != null) _keys[k],
      ]);
      return;
    }
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
    const gap = SizedBox(height: AppSpace.md);
    return FormPageFrame(
      title: _editing ? 'Update Testimonial' : 'Add Testimonial',
      dirty: _dirty,
      onClose: () =>
          context.canPop() ? context.pop() : context.go('/app/testimonials'),
      bottom: FormActionBar(label: 'Save', loading: _busy, onPressed: _save),
      child: ListView(
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
            title: 'Client',
            icon: Icons.person_rounded,
            children: [
              ImagePickField(
                compact: true,
                label: 'Client Photo',
                pickedPath: _image,
                savedUrl: widget.testimonial?.imageUrl,
                error: _errors['image'],
                onPick: _pick,
              ),
              AppTextField(
                key: _keys['name'],
                label: 'Client Name *',
                hint: 'Enter client name',
                controller: _name,
                errorText: _errors['name'],
                validator: _nameError,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                clearable: true,
              ),
              AppTextField(
                label: 'Client Title',
                hint: 'Regular Client',
                controller: _role,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                clearable: true,
              ),
            ],
          ),
          gap,
          FormSection(
            title: 'Review',
            icon: Icons.format_quote_rounded,
            children: [
              AppTextField(
                key: _keys['review'],
                label: 'Review *',
                hint: 'What the client said',
                controller: _review,
                errorText: _errors['review'],
                validator: _reviewError,
                maxLines: 5,
                maxLength: 2000,
                showCounter: true,
                textCapitalization: TextCapitalization.sentences,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Rating'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in const [5, 4, 3, 2, 1])
                        AppChoiceChip(
                          label: r == 1 ? '1 Star' : '$r Stars',
                          selected: _rating == r,
                          onTap: () => setState(() {
                            _rating = r;
                            _dirty = true;
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          gap,
          FormSection(
            title: 'On the website',
            icon: Icons.language_rounded,
            children: [
              SwitchTile(
                label: 'Show on website',
                hint: 'Off keeps it hidden from visitors.',
                value: _active,
                onChanged: (v) => setState(() {
                  _active = v;
                  _dirty = true;
                }),
              ),
              AppTextField(
                key: _keys['order'],
                label: 'Display Order',
                hint: '0',
                helperText: 'Smaller numbers come first.',
                controller: _order,
                errorText: _errors['order'],
                validator: _orderError,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
