import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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

  /// True once the person changed something: leaving then asks first.
  bool _dirty = false;
  bool _listening = false;

  /// One key per field that can show an error, to scroll to the first one.
  final _keys = {
    for (final k in [
      'image',
      'name',
      'category',
      'price',
      'stock',
      'commission',
    ])
      k: GlobalKey(),
  };

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

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
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
      if (!_listening) {
        _listening = true;
        for (final c in [_name, _price, _stock, _commission, _description]) {
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

  Future<void> _pick() async {
    final r = await pickCatalogImage(ref);
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
      v.trim().isEmpty ? 'Please enter Product Name' : null;

  static String? _priceError(String v) {
    if (v.trim().isEmpty) return 'Please enter Price';
    final n = double.tryParse(v.trim());
    return n == null || n < 0 ? 'Price must be a number, 0 or more' : null;
  }

  static String? _stockError(String v) {
    if (v.trim().isEmpty) return 'Please enter Stock quantity';
    final n = int.tryParse(v.trim());
    return n == null || n < 0
        ? 'Stock must be a whole number, 0 or more'
        : null;
  }

  static String? _commissionError(String v) {
    if (v.trim().isEmpty) return 'Please enter Commission';
    final n = double.tryParse(v.trim());
    return n == null || n < 0 ? 'Commission must be a number, 0 or more' : null;
  }

  bool _validate() {
    final e = <String, String>{};
    final name = _nameError(_name.text);
    if (name != null) e['name'] = name;
    if (_categoryId == null) e['category'] = 'Please select a Category';
    final price = _priceError(_price.text);
    if (price != null) e['price'] = price;
    final stock = _stockError(_stock.text);
    if (stock != null) e['stock'] = stock;
    final com = _commissionError(_commission.text);
    if (com != null) e['commission'] = com;
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

  /// Brings the first field with an error into view, top to bottom.
  void _showFirstError() => scrollToFirstError([
    for (final k in [
      'image',
      'name',
      'category',
      'price',
      'stock',
      'commission',
    ])
      if (_errors[k] != null) _keys[k],
  ]);

  Future<void> _save() async {
    if (!_validate()) {
      _showFirstError();
      return;
    }
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
    final cats = ref.watch(categoriesProvider).value;
    final ready = !_loading && _loadError == null && cats != null;
    return FormPageFrame(
      title: _editing ? 'Update Product' : 'Add Product',
      dirty: _dirty,
      onClose: () =>
          context.canPop() ? context.pop() : context.go('/app/products'),
      bottom: ready
          ? FormActionBar(
              label: _editing ? 'Update' : 'Save',
              loading: _busy,
              onPressed: _save,
            )
          : null,
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
                    SkeletonBox(height: 150, radius: 16),
                    SizedBox(height: AppSpace.md),
                    SkeletonBox(height: 220, radius: 16),
                    SizedBox(height: AppSpace.md),
                    SkeletonBox(height: 150, radius: 16),
                  ],
                ),
              ),
            )
          : _body(context, cats),
    );
  }

  Widget _body(BuildContext context, List<AdminCategory> cats) {
    const decimal = TextInputType.numberWithOptions(decimal: true);
    const gap = SizedBox(height: AppSpace.md);
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
          title: 'Photo',
          icon: Icons.photo_camera_rounded,
          children: [
            ImagePickField(
              key: _keys['image'],
              compact: true,
              label: _editing ? 'Product Image' : 'Product Image *',
              pickedPath: _image,
              savedUrl: _existing?.imageUrl,
              error: _errors['image'],
              onPick: _pick,
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Basics',
          icon: Icons.inventory_2_rounded,
          children: [
            AppTextField(
              key: _keys['name'],
              label: 'Product Name *',
              hint: 'Enter Product Name',
              controller: _name,
              errorText: _errors['name'],
              validator: _nameError,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              clearable: true,
            ),
            Column(
              key: _keys['category'],
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Category *'),
                const SizedBox(height: 8),
                CategoryChips(
                  names: {for (final c in cats) c.id: c.name},
                  selected: _categoryId,
                  error: _errors['category'],
                  onSelected: (id) => setState(() {
                    _categoryId = id;
                    _errors.remove('category');
                    _dirty = true;
                  }),
                ),
              ],
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Price and stock',
          icon: Icons.payments_rounded,
          children: [
            FormRow(
              children: [
                AppTextField(
                  key: _keys['price'],
                  label: 'Price (\$) *',
                  hint: '0.00',
                  prefixText: '\$ ',
                  controller: _price,
                  errorText: _errors['price'],
                  validator: _priceError,
                  keyboardType: decimal,
                  textInputAction: TextInputAction.next,
                ),
                AppTextField(
                  key: _keys['stock'],
                  label: 'Stock *',
                  hint: '0',
                  suffixText: 'pcs',
                  controller: _stock,
                  errorText: _errors['stock'],
                  validator: _stockError,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ],
            ),
            AppTextField(
              key: _keys['commission'],
              label: 'Commission (%) *',
              hint: 'Enter Commission',
              suffixText: '%',
              helperText: 'The share the barber earns on each sale.',
              controller: _commission,
              errorText: _errors['commission'],
              validator: _commissionError,
              keyboardType: decimal,
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
        gap,
        FormSection(
          title: 'Description',
          icon: Icons.notes_rounded,
          children: [
            AppTextField(
              label: 'Product Description',
              hint: 'Describe the product',
              controller: _description,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ],
    );
  }
}
