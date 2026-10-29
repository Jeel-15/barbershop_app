import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/image_pick.dart';
import 'package:barbershop_app/features/content/application/content_controllers.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The web's Gallery ("Manage website gallery images"): the pictures in a
/// grid, Add Image (Upload Gallery Image) and Delete.
class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(galleryProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final msg = await showAppSheet<String>(
      context,
      title: 'Upload Gallery Image',
      builder: (_) => const _UploadForm(),
    );
    if (msg != null && mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(galleryProvider);
    }
  }

  Future<void> _open(GalleryPicture p) async {
    final user = ref.read(currentUserProvider);
    final canDelete = user.can('Gallery-Delete');
    final remove = await showAppSheet<bool>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              p.imageUrl,
              fit: BoxFit.cover,
              height: 320,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 200,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          if (canDelete) ...[
            const SizedBox(height: AppSpace.lg),
            AppButton(
              label: 'Delete',
              icon: Icons.delete_outline_rounded,
              variant: AppButtonVariant.dangerOutline,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ],
      ),
    );
    if (remove == true && mounted) await _delete(p);
  }

  Future<void> _delete(GalleryPicture p) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Delete this image?',
      confirmLabel: 'Yes, delete it',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final msg = await ref.read(contentRepositoryProvider).deletePicture(p.id);
      if (!mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(galleryProvider);
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final async = ref.watch(galleryProvider);
    final s = async.value;

    Widget body;
    if (s == null) {
      body = async.hasError
          ? ScrollableCenter(
              child: ErrorState(
                message: async.error is Failure
                    ? (async.error! as Failure).userMessage
                    : 'Could not load the gallery.',
                onRetry: () => ref.invalidate(galleryProvider),
              ),
            )
          : const Padding(
              padding: EdgeInsets.all(AppSpace.page),
              child: SkeletonRows(count: 4),
            );
    } else if (s.items.isEmpty) {
      body = const ScrollableCenter(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.page),
          child: QuietState(
            title: 'No images yet',
            message: 'Upload the first picture of the website gallery.',
          ),
        ),
      );
    } else {
      body = CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.md,
              AppSpace.page,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                'ALL IMAGES · ${s.total}',
                style: AppType.overline.copyWith(color: t.textMuted),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpace.page),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpace.sm,
                crossAxisSpacing: AppSpace.sm,
              ),
              itemCount: s.items.length,
              itemBuilder: (context, i) {
                final p = s.items[i];
                return Pressable(
                  onTap: () => _open(p),
                  scale: 0.97,
                  minSize: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: t.surface,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: t.textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: _Footer(state: s)),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
        ],
      );
    }

    return AdminListShell(
      title: 'Gallery',
      subtitle: 'Manage website gallery images',
      addLabel: 'Add Image',
      onAdd: user.can('Gallery-Add') ? _add : null,
      body: AppRefresh(
        onRefresh: () => ref.read(galleryProvider.notifier).refresh(),
        child: body,
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final PagedState<GalleryPicture> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (state.loadMoreFailed) {
      return TextButton(
        onPressed: () => ref.read(galleryProvider.notifier).loadMore(),
        child: const Text('Could not load more. Tap to retry'),
      );
    }
    return const SizedBox.shrink();
  }
}

/// "Upload Gallery Image": Select Image, Upload.
class _UploadForm extends ConsumerStatefulWidget {
  const _UploadForm();

  @override
  ConsumerState<_UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends ConsumerState<_UploadForm> {
  String? _image;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final r = await pickCatalogImage(ref);
    if (!mounted) return;
    setState(() {
      if (r.path != null) {
        _image = r.path;
        _error = null;
      }
      if (r.error != null) _error = r.error;
    });
  }

  Future<void> _upload() async {
    if (_image == null) {
      setState(() => _error = 'Select Image');
      return;
    }
    setState(() => _busy = true);
    try {
      final msg = await ref.read(contentRepositoryProvider).addPicture(_image!);
      if (mounted) Navigator.of(context).pop(msg);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.errorFor('image') ?? f.userMessage;
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
        ImagePickField(
          label: 'Select Image',
          pickedPath: _image,
          error: _error,
          onPick: _pick,
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(
          label: 'Upload',
          icon: Icons.cloud_upload_rounded,
          loading: _busy,
          onPressed: _upload,
        ),
      ],
    );
  }
}
