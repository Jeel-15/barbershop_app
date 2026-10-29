import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's "Add Product" / "Update" modal as a page: Product Name, Category,
/// Price ($), Stock, Commission (%), Status, Product Image, Product Description.
class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.product, this.editId});

  /// Null = Add Product.
  final AdminProduct? product;
  final int? editId;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _commission = TextEditingController();
  final _description = TextEditingController();

  AdminProduct? _existing;
  bool _loading = true;
  Object? _loadError;
  int? _categoryId;
  bool _active = true;
  String? _image;
  bool _busy = false;
  final _errors = <String, String>{};

  bool get _editing => widget.editId != null || widget.product != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _stock, _commission, _description]) {
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
      await ref.read(categoriesProvider.future);
      var p = widget.product;
      if (p == null && widget.editId != null) {
        p = await ref.read(catalogRepositoryProvider).product(widget.editId!);
      }
      if (p != null) {
        _existing = p;
        _categoryId = p.categoryId;
        _name.text = p.name;
        _price.text = p.price.toApi();
        _stock.text = '${p.stock}';
        _commission.text = p.commission;
        _description.text = p.description ?? '';
        _active = p.active;
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

  Future<void> _pick() async {
    final r = await pickCatalogImage(ref);
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
    if (_name.text.trim().isEmpty) e['name'] = 'Please enter Product Name';
    if (_categoryId == null) e['category'] = 'Please select a Category';
    final price = double.tryParse(_price.text.trim());
    if (_price.text.trim().isEmpty) {
      e['price'] = 'Please enter Price';
    } else if (price == null || price < 0) {
      e['price'] = 'Price must be a number, 0 or more';
    }
    final stock = int.tryParse(_stock.text.trim());
    if (_stock.text.trim().isEmpty) {
      e['stock'] = 'Please enter Stock quantity';
    } else if (stock == null || stock < 0) {
      e['stock'] = 'Stock must be a whole number, 0 or more';
    }
    final c = double.tryParse(_commission.text.trim());
    if (_commission.text.trim().isEmpty) {
      e['commission'] = 'Please enter Commission';
    } else if (c == null || c < 0) {
      e['commission'] = 'Commission must be a number, 0 or more';
    }
    if (!_editing && _image == null) {
      e['image'] = 'Please upload a valid image file (jpg, jpeg, png, gif)';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final input = ProductInput(
      categoryId: _categoryId!,
      name: _name.text,
      price: _price.text,
      stock: _stock.text,
      commission: _commission.text,
      active: _active,
      description: _description.text,
      imagePath: _image,
    );
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final id = _existing?.id ?? widget.editId;
      final msg = id == null
          ? await repo.createProduct(input)
          : await repo.updateProduct(id, input);
      if (mounted) context.pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final e in {
          'category_id': 'category',
          'name': 'name',
          'price': 'price',
          'stock': 'stock',
          'commission': 'commission',
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
    final cats = ref.watch(categoriesProvider).value;
    final ready = !_loading && _loadError == null && cats != null;
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
                        : context.go('/app/products'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      _editing ? 'Update Product' : 'Add Product',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loadError != null
                  ? ErrorState(
                      message: _loadError is Failure
                          ? (_loadError! as Failure).userMessage
                          : 'Could not open the form.',
                      onRetry: _load,
                    )
                  : !ready
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpace.page),
                      child: SkeletonLoader(
                        child: Column(
                          children: [
                            SkeletonBox(height: 80, radius: 16),
                            SizedBox(height: AppSpace.md),
                            SkeletonBox(height: 80, radius: 16),
                            SizedBox(height: AppSpace.md),
                            SkeletonBox(height: 150, radius: 16),
                          ],
                        ),
                      ),
                    )
                  : _body(context, cats),
            ),
            if (ready)
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
                child: AppButton(
                  label: _editing ? 'Update' : 'Save',
                  loading: _busy,
                  onPressed: _save,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<AdminCategory> cats) {
    final t = context.tokens;
    const decimal = TextInputType.numberWithOptions(decimal: true);
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
          label: 'Product Name *',
          hint: 'Enter Product Name',
          controller: _name,
          errorText: _errors['name'],
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          'Category *',
          style: AppType.label.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        CategoryChips(
          names: {for (final c in cats) c.id: c.name},
          selected: _categoryId,
          error: _errors['category'],
          onSelected: (id) => setState(() {
            _categoryId = id;
            _errors.remove('category');
          }),
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Price (\$) *',
          hint: 'Enter Price',
          controller: _price,
          errorText: _errors['price'],
          keyboardType: decimal,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Stock *',
          hint: 'Enter Stock Quantity',
          controller: _stock,
          errorText: _errors['stock'],
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Commission (%) *',
          hint: 'Enter Commission',
          controller: _commission,
          errorText: _errors['commission'],
          keyboardType: decimal,
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Status *', style: AppType.label.copyWith(color: t.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            AppChoiceChip(
              label: 'Active',
              selected: _active,
              onTap: () => setState(() => _active = true),
            ),
            AppChoiceChip(
              label: 'Deactive',
              selected: !_active,
              onTap: () => setState(() => _active = false),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        ImagePickField(
          label: _editing ? 'Product Image' : 'Product Image *',
          pickedPath: _image,
          savedUrl: _existing?.imageUrl,
          error: _errors['image'],
          onPick: _pick,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Product Description',
          hint: 'Describe the product',
          controller: _description,
          maxLines: 4,
        ),
      ],
    );
  }
}
