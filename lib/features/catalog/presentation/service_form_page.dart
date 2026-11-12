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

/// The web's "Add Service" / "Update" modal as a page: Category, Service Name,
/// Price ($), Duration (Minutes), Commission (%), Active, Eligible for Tip,
/// Service Image, Service Description. Pops with the server's message.
class ServiceFormPage extends ConsumerStatefulWidget {
  const ServiceFormPage({super.key, this.service, this.editId});

  /// Null = Add Service.
  final AdminService? service;
  final int? editId;

  @override
  ConsumerState<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends ConsumerState<ServiceFormPage> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController(text: '30');
  final _commission = TextEditingController();
  final _description = TextEditingController();

  AdminService? _existing;
  bool _loading = true;
  Object? _loadError;
  int? _categoryId;
  bool _active = true;
  bool _tip = false;
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
      'category',
      'name',
      'price',
      'duration',
      'commission',
    ])
      k: GlobalKey(),
  };

  bool get _editing => widget.editId != null || widget.service != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _duration, _commission, _description]) {
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
      var s = widget.service;
      if (s == null && widget.editId != null) {
        s = await ref.read(catalogRepositoryProvider).service(widget.editId!);
      }
      if (s != null) {
        _existing = s;
        _categoryId = s.categoryId;
        _name.text = s.name;
        _price.text = s.price.toApi();
        _duration.text = '${s.duration}';
        _commission.text = s.commission ?? '';
        _description.text = s.description ?? '';
        _active = s.active;
        _tip = s.eligibleForTip;
      }
      if (!_listening) {
        _listening = true;
        for (final c in [_name, _price, _duration, _commission, _description]) {
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
    final r = await pickCatalogImage(
      ref,
      invalidMessage: 'Please upload a valid image (jpg, jpeg, png, gif)',
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
      v.trim().isEmpty ? 'Please enter service name' : null;

  static String? _priceError(String v) {
    if (v.trim().isEmpty) return 'Please enter price';
    final n = double.tryParse(v.trim());
    return n == null || n < 0 ? 'Price must be a number, 0 or more' : null;
  }

  static String? _durationError(String v) {
    if (v.trim().isEmpty) return 'Please enter duration';
    final n = int.tryParse(v.trim());
    return n == null || n < 1
        ? 'Duration must be a whole number, 1 or more'
        : null;
  }

  static String? _commissionError(String v) {
    if (v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    return n == null || n < 0 || n > 100
        ? 'Commission must be between 0 and 100'
        : null;
  }

  bool _validate() {
    final e = <String, String>{};
    if (_categoryId == null) e['category'] = 'Please select a category';
    final name = _nameError(_name.text);
    if (name != null) e['name'] = name;
    final price = _priceError(_price.text);
    if (price != null) e['price'] = price;
    final dur = _durationError(_duration.text);
    if (dur != null) e['duration'] = dur;
    final com = _commissionError(_commission.text);
    if (com != null) e['commission'] = com;
    if (!_editing && _image == null) {
      e['image'] = 'Please upload a service image';
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
      'category',
      'name',
      'price',
      'duration',
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
    final input = ServiceInput(
      categoryId: _categoryId!,
      name: _name.text,
      price: _price.text,
      duration: _duration.text,
      commission: _commission.text,
      active: _active,
      eligibleForTip: _tip,
      description: _description.text,
      imagePath: _image,
    );
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final id = _existing?.id ?? widget.editId;
      final msg = id == null
          ? await repo.createService(input)
          : await repo.updateService(id, input);
      if (mounted) context.pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final e in {
          'category_id': 'category',
          'name': 'name',
          'price': 'price',
          'duration': 'duration',
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
      title: _editing ? 'Update Service' : 'Add Service',
      dirty: _dirty,
      onClose: () =>
          context.canPop() ? context.pop() : context.go('/app/services'),
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
    final t = context.tokens;
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
              label: _editing ? 'Service Image' : 'Service Image *',
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
          icon: Icons.content_cut_rounded,
          children: [
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
            AppTextField(
              key: _keys['name'],
              label: 'Service Name *',
              hint: 'Enter Service Name',
              controller: _name,
              errorText: _errors['name'],
              validator: _nameError,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              clearable: true,
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Price and time',
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
                  key: _keys['duration'],
                  label: 'Duration (Minutes) *',
                  hint: '30',
                  suffixText: 'min',
                  controller: _duration,
                  errorText: _errors['duration'],
                  validator: _durationError,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ],
            ),
            AppTextField(
              key: _keys['commission'],
              label: 'Commission (%)',
              hint: 'Enter Commission',
              suffixText: '%',
              helperText: 'The share the barber earns on this service.',
              controller: _commission,
              errorText: _errors['commission'],
              validator: _commissionError,
              keyboardType: decimal,
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Options',
          icon: Icons.tune_rounded,
          children: [
            SwitchTile(
              label: 'Active',
              hint: 'Shown when booking and in the POS.',
              value: _active,
              onChanged: (v) => setState(() {
                _active = v;
                _dirty = true;
              }),
            ),
            Divider(height: 1, color: t.border),
            SwitchTile(
              label: 'Eligible for Tip',
              hint: 'Customers can leave a tip on this service.',
              value: _tip,
              onChanged: (v) => setState(() {
                _tip = v;
                _dirty = true;
              }),
            ),
          ],
        ),
        gap,
        FormSection(
          title: 'Description',
          icon: Icons.notes_rounded,
          children: [
            AppTextField(
              label: 'Service Description',
              hint: 'Describe the service',
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
