import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/pos/application/invoice_form_controller.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Select Services" / "Select Products": tap an item to add it (tap again for
/// one more). The sheet stays open so several items can be added in one go.
Future<void> showItemPicker(
  BuildContext context, {
  required InvoiceTarget target,
  required PosCatalog catalog,
  required LineType type,
}) {
  return showAppSheet<void>(
    context,
    title: type == LineType.service ? 'Select Services' : 'Select Products',
    builder: (_) => _Picker(target: target, catalog: catalog, type: type),
    footer: (ctx) => AppButton(
      label: 'Done',
      compact: true,
      onPressed: () => Navigator.of(ctx).pop(),
    ),
  );
}

class _Picker extends ConsumerStatefulWidget {
  const _Picker({
    required this.target,
    required this.catalog,
    required this.type,
  });

  final InvoiceTarget target;
  final PosCatalog catalog;
  final LineType type;

  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Watch the draft so the "added" counts update as items are tapped.
    final provider = invoiceFormProvider(widget.target);
    final ctl = ref.read(provider.notifier);
    final lines = ref.watch(provider).draft.lines;
    int added(LineType type, int id) => lines
        .where((l) => l.type == type && l.id == id)
        .fold(0, (a, l) => a + l.qty);
    final q = _q.trim().toLowerCase();

    Widget item({
      required String name,
      required String sub,
      required int count,
      required VoidCallback onTap,
      String? imageUrl,
      IconData placeholder = Icons.content_cut_rounded,
    }) => PickRow(
      name: name,
      detail: sub,
      count: count,
      onTap: onTap,
      imageUrl: imageUrl,
      placeholder: placeholder,
    );

    final children = <Widget>[
      AppSearchField(hint: 'Search', onChanged: (v) => setState(() => _q = v)),
      const SizedBox(height: AppSpace.md),
    ];

    if (widget.type == LineType.service) {
      for (final c in widget.catalog.categories) {
        final services = [
          for (final s in c.services)
            if (q.isEmpty || s.name.toLowerCase().contains(q)) s,
        ];
        if (services.isEmpty) continue;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.sm,
              bottom: AppSpace.sm,
            ),
            child: Text(
              c.name.toUpperCase(),
              style: AppType.overline.copyWith(color: t.textSecondary),
            ),
          ),
        );
        for (final s in services) {
          children.add(
            item(
              name: s.name,
              sub: '${s.price.format()} · ${s.durationMinutes} min',
              count: added(LineType.service, s.id),
              imageUrl: s.imageUrl,
              onTap: () => ctl.addService(s),
            ),
          );
        }
      }
    } else {
      for (final p in widget.catalog.products) {
        if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) continue;
        children.add(
          item(
            name: p.name,
            sub: p.stock == null
                ? p.price.format()
                : '${p.price.format()} · ${p.stock} in stock',
            count: added(LineType.product, p.id),
            imageUrl: p.imageUrl,
            placeholder: Icons.shopping_bag_outlined,
            onTap: () => ctl.addProduct(p),
          ),
        );
      }
    }
    if (children.length == 2) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Center(
            child: Text(
              'Nothing found.',
              style: AppType.body.copyWith(color: t.textSecondary),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
