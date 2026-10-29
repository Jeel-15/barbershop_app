import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:flutter/material.dart';
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
      }
      if (r.error != null) _errors['image'] = r.error!;
    });
  }

  bool _validate() {
    final e = <String, String>{};
    if (_categoryId == null) e['category'] = 'Please select a category';
    if (_name.text.trim().isEmpty) e['name'] = 'Please enter service name';
    final price = double.tryParse(_price.text.trim());
    if (_price.text.trim().isEmpty) {
      e['price'] = 'Please enter price';
    } else if (price == null || price < 0) {
      e['price'] = 'Price must be a number, 0 or more';
    }
    final dur = int.tryParse(_duration.text.trim());
    if (_duration.text.trim().isEmpty) {
      e['duration'] = 'Please enter duration';
    } else if (dur == null || dur < 1) {
      e['duration'] = 'Duration must be a whole number, 1 or more';
    }
    if (_commission.text.trim().isNotEmpty) {
      final c = double.tryParse(_commission.text.trim());
      if (c == null || c < 0 || c > 100) {
        e['commission'] = 'Commission must be between 0 and 100';
      }
    }
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

  Future<void> _save() async {
    if (!_validate()) return;
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
                        : context.go('/app/services'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      _editing ? 'Update Service' : 'Add Service',
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
          label: 'Service Name *',
          hint: 'Enter Service Name',
          controller: _name,
          errorText: _errors['name'],
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
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
          label: 'Duration (Minutes) *',
          hint: 'Enter Duration (Minutes)',
          controller: _duration,
          errorText: _errors['duration'],
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Commission (%)',
          hint: 'Enter Commission',
          controller: _commission,
          errorText: _errors['commission'],
          keyboardType: decimal,
        ),
        const SizedBox(height: AppSpace.lg),
        SwitchRow(
          label: 'Active',
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        const SizedBox(height: AppSpace.sm + 2),
        SwitchRow(
          label: 'Eligible for Tip',
          value: _tip,
          onChanged: (v) => setState(() => _tip = v),
        ),
        const SizedBox(height: AppSpace.lg),
        ImagePickField(
          label: _editing ? 'Service Image' : 'Service Image *',
          pickedPath: _image,
          savedUrl: _existing?.imageUrl,
          error: _errors['image'],
          onPick: _pick,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Service Description',
          hint: 'Describe the service',
          controller: _description,
          maxLines: 4,
        ),
      ],
    );
  }
}
