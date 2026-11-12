import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

/// A short list (no paging) with pull-to-refresh and the usual states.
class _ShortList<T> extends StatelessWidget {
  const _ShortList({
    required this.async,
    required this.onRefresh,
    required this.itemBuilder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.countLabel = 'ALL',
  });

  final AsyncValue<List<T>> async;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyTitle;
  final String emptyMessage;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = async.value;
    Widget content;
    if (items == null) {
      content = async.hasError
          ? ScrollableCenter(
              child: ErrorState(
                message: async.error is Failure
                    ? (async.error! as Failure).userMessage
                    : 'Could not load this list.',
                supportCode: async.error is Failure
                    ? (async.error! as Failure).requestId
                    : null,
                onRetry: onRefresh,
              ),
            )
          : const Padding(
              padding: EdgeInsets.only(top: AppSpace.md),
              child: SkeletonRows(count: 5),
            );
    } else if (items.isEmpty) {
      content = ScrollableCenter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: QuietState(title: emptyTitle, message: emptyMessage),
        ),
      );
    } else {
      content = ListView(
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
              '$countLabel · ${items.length}',
              style: AppType.overline.copyWith(color: t.textMuted),
            ),
          ),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
              child: itemBuilder(context, i),
            ),
        ],
      );
    }
    return AppRefresh(onRefresh: onRefresh, child: content);
  }
}

Future<bool> _confirmDelete(BuildContext context, String what) => showConfirm(
  context,
  title: 'Are you sure?',
  message: 'Are you sure to delete $what?',
  confirmLabel: 'Yes, confirm!',
  destructive: true,
);

// ============================================================ categories

/// The web's Service Categories page ("Organize services into categories").
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  String _q = '';

  Future<void> _edit([AdminCategory? c]) async {
    final msg = await showAppSheet<String>(
      context,
      title: c == null ? 'Add Service Category' : 'Update Service Category',
      builder: (_) => _CategoryForm(category: c),
    );
    if (msg != null && mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(categoriesProvider);
    }
  }

  Future<void> _delete(AdminCategory c) async {
    if (!await _confirmDelete(context, 'Service category') || !mounted) return;
    try {
      final msg = await ref
          .read(catalogRepositoryProvider)
          .deleteCategory(c.id);
      if (!mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(categoriesProvider);
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canEdit = user.can(Perm.serviceCategoryEdit);
    final canDelete = user.can(Perm.serviceCategoryDelete);
    final async = ref.watch(categoriesProvider);
    final needle = _q.trim().toLowerCase();
    final filtered = async.whenData(
      (l) => [
        for (final c in l)
          if (needle.isEmpty || c.name.toLowerCase().contains(needle)) c,
      ],
    );
    return AdminListShell(
      title: 'Service Categories',
      subtitle: 'Organize services into categories',
      addLabel: 'Add Service Category',
      onAdd: user.can(Perm.serviceCategoryAdd) ? () => _edit() : null,
      searchHint: 'Search category',
      query: _q,
      onSearch: (q) => setState(() => _q = q),
      body: _ShortList<AdminCategory>(
        async: filtered,
        countLabel: needle.isEmpty ? 'ALL CATEGORIES' : 'FOUND',
        emptyTitle: needle.isEmpty
            ? 'No categories yet'
            : 'No categories found',
        emptyMessage: needle.isEmpty
            ? 'Add a category to organize services and products.'
            : 'Try another name.',
        onRefresh: () async => ref.invalidate(categoriesProvider),
        itemBuilder: (context, c) => AdminTile(
          title: c.name,
          imageUrl: c.imageUrl,
          icon: Icons.category_rounded,
          lines: [if ((c.description ?? '').trim().isNotEmpty) c.description!],
          menu: [
            if (canEdit) ('edit', 'Edit', false),
            if (canDelete) ('delete', 'Delete', true),
          ],
          onMenu: (v) => v == 'edit' ? _edit(c) : _delete(c),
          onTap: canEdit ? () => _edit(c) : null,
        ),
      ),
    );
  }
}

/// "Add Service Category": Category Name *, Category Image, Category Description.
class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.category});

  final AdminCategory? category;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final _name = TextEditingController(text: widget.category?.name);
  late final _desc = TextEditingController(text: widget.category?.description);
  String? _image;
  String? _nameError;
  String? _imageError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await pickCatalogImage(ref);
    if (!mounted) return;
    setState(() {
      if (r.path != null) {
        _image = r.path;
        _imageError = null;
      }
      if (r.error != null) _imageError = r.error;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Please Enter Category Name');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _nameError = null;
      _busy = true;
    });
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final c = widget.category;
      final msg = c == null
          ? await repo.createCategory(
              name: _name.text,
              description: _desc.text,
              imagePath: _image,
            )
          : await repo.updateCategory(
              c.id,
              name: _name.text,
              description: _desc.text,
              imagePath: _image,
            );
      if (mounted) Navigator.of(context).pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = f.errorFor('name');
        _imageError = f.errorFor('image');
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Category Name *',
          hint: 'Enter Category Name',
          clearable: true,
          controller: _name,
          errorText: _nameError,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofocus: widget.category == null,
        ),
        const SizedBox(height: AppSpace.lg),
        ImagePickField(
          label: 'Category Image',
          pickedPath: _image,
          savedUrl: widget.category?.imageUrl,
          error: _imageError,
          onPick: _pick,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Category Description',
          hint: 'Describe the category',
          controller: _desc,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'Save', loading: _busy, onPressed: _save),
      ],
    );
  }
}

// ================================================================== GST

/// The web's GST Settings page ("Configure tax rates for services and products").
class GstPage extends ConsumerWidget {
  const GstPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [GstItem? g]) async {
    final msg = await showAppSheet<String>(
      context,
      title: g == null ? 'Add GST' : 'Update GST',
      builder: (_) => _GstForm(gst: g),
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(gstListProvider);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, GstItem g) async {
    if (!await _confirmDelete(context, 'Gst') || !context.mounted) return;
    try {
      final msg = await ref.read(catalogRepositoryProvider).deleteGst(g.id);
      if (!context.mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(gstListProvider);
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
    final canEdit = user.can(Perm.gstEdit);
    final canDelete = user.can(Perm.gstDelete);
    return AdminListShell(
      title: 'GST Settings',
      subtitle: 'Configure tax rates for services and products',
      addLabel: 'Add GST',
      onAdd: user.can(Perm.gstAdd) ? () => _edit(context, ref) : null,
      body: _ShortList<GstItem>(
        async: ref.watch(gstListProvider),
        countLabel: 'TAX RATES',
        emptyTitle: 'No GST yet',
        emptyMessage: 'Without a default GST new invoices have no tax.',
        onRefresh: () async => ref.invalidate(gstListProvider),
        itemBuilder: (context, g) => AdminTile(
          title: g.name,
          icon: Icons.percent_rounded,
          badge: g.isDefault
              ? StatusPill(label: 'Default', color: t.success, compact: true)
              : null,
          lines: ['${g.rate}% · ${g.typeLabel}'],
          menu: [
            if (canEdit) ('edit', 'Edit', false),
            if (canDelete) ('delete', 'Delete', true),
          ],
          onMenu: (v) =>
              v == 'edit' ? _edit(context, ref, g) : _delete(context, ref, g),
          onTap: canEdit ? () => _edit(context, ref, g) : null,
        ),
      ),
    );
  }
}

/// "Add GST": GST Name, Total Rate, Type (Include / Exclude), Defualt.
class _GstForm extends ConsumerStatefulWidget {
  const _GstForm({this.gst});

  final GstItem? gst;

  @override
  ConsumerState<_GstForm> createState() => _GstFormState();
}

class _GstFormState extends ConsumerState<_GstForm> {
  late final _name = TextEditingController(text: widget.gst?.name);
  late final _rate = TextEditingController(text: widget.gst?.rate);
  late bool _exclude = widget.gst?.exclude ?? false;
  late bool _default = widget.gst?.isDefault ?? false;
  String? _nameError;
  String? _rateError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_rate.text.trim());
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Please enter GST Name' : null;
      _rateError = _rate.text.trim().isEmpty
          ? 'Please enter GST Rate'
          : (rate == null || rate < 0 || rate > 100)
          ? 'Rate must be between 0 and 100'
          : null;
    });
    if (_nameError != null || _rateError != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final g = widget.gst;
      final msg = g == null
          ? await repo.createGst(
              _name.text,
              _rate.text,
              exclude: _exclude,
              isDefault: _default,
            )
          : await repo.updateGst(
              g.id,
              _name.text,
              _rate.text,
              exclude: _exclude,
              isDefault: _default,
            );
      if (mounted) Navigator.of(context).pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = f.errorFor('name');
        _rateError = f.errorFor('rate');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'GST Name',
          hint: 'Enter GST Name',
          controller: _name,
          errorText: _nameError,
          textInputAction: TextInputAction.next,
          autofocus: widget.gst == null,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Total Rate',
          hint: 'Enter GST Rate',
          suffixText: '%',
          controller: _rate,
          errorText: _rateError,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Type', style: AppType.label.copyWith(color: t.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            AppChoiceChip(
              label: 'Include',
              selected: !_exclude,
              onTap: () => setState(() => _exclude = false),
            ),
            AppChoiceChip(
              label: 'Exclude',
              selected: _exclude,
              onTap: () => setState(() => _exclude = true),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        SwitchRow(
          label: 'Defualt',
          value: _default,
          onChanged: (v) => setState(() => _default = v),
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'Save', loading: _busy, onPressed: _save),
      ],
    );
  }
}

// ======================================================== payment methods

/// The web's Settings → Payment Options ("Custom Payment Methods").
class PaymentMethodsPage extends ConsumerWidget {
  const PaymentMethodsPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PaymentMethodItem? m,
  ]) async {
    final msg = await showAppSheet<String>(
      context,
      title: m == null ? 'Add Payment Method' : 'Update Payment Method',
      builder: (_) => _PaymentForm(method: m),
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(paymentMethodsProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PaymentMethodItem m,
  ) async {
    if (!await _confirmDelete(context, 'Payment Method') || !context.mounted) {
      return;
    }
    try {
      final msg = await ref.read(catalogRepositoryProvider).deletePayment(m.id);
      if (!context.mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(paymentMethodsProvider);
    } on Failure catch (f) {
      if (context.mounted) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminListShell(
      title: 'Payment Options',
      subtitle: 'Custom Payment Methods',
      addLabel: 'Add Payment Method',
      onAdd: () => _edit(context, ref),
      body: _ShortList<PaymentMethodItem>(
        async: ref.watch(paymentMethodsProvider),
        countLabel: 'PAYMENT METHODS',
        emptyTitle: 'No payment methods',
        emptyMessage: 'Add the ways customers can pay.',
        onRefresh: () async => ref.invalidate(paymentMethodsProvider),
        itemBuilder: (context, m) => AdminTile(
          title: m.name,
          icon: Icons.credit_card_rounded,
          lines: const [],
          menu: const [('edit', 'Edit', false), ('delete', 'Delete', true)],
          onMenu: (v) =>
              v == 'edit' ? _edit(context, ref, m) : _delete(context, ref, m),
          onTap: () => _edit(context, ref, m),
        ),
      ),
    );
  }
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({this.method});

  final PaymentMethodItem? method;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  late final _name = TextEditingController(text: widget.method?.name);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Please Enter Payment Method');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final m = widget.method;
      final msg = m == null
          ? await repo.createPayment(_name.text)
          : await repo.updatePayment(m.id, _name.text);
      if (mounted) Navigator.of(context).pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.errorFor('name') ?? f.userMessage;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Payment Method',
          hint: 'Enter Payment Method',
          controller: _name,
          errorText: _error,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(label: 'Save', loading: _busy, onPressed: _save),
      ],
    );
  }
}
