import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _Query extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

/// Search text of the Testimonials list.
final testimonialQueryProvider = NotifierProvider<_Query, String>(_Query.new);

final testimonialsProvider =
    AsyncNotifierProvider<TestimonialsController, PagedState<Testimonial>>(
      TestimonialsController.new,
      retry: (_, _) => null,
    );

class TestimonialsController extends PagedNotifier<Testimonial> {
  @override
  Future<PagedResult<Testimonial>> fetch(int page) => ref
      .read(contentRepositoryProvider)
      .testimonials(q: ref.read(testimonialQueryProvider), page: page);

  @override
  Future<PagedState<Testimonial>> build() {
    ref.watch(currentUserProvider);
    ref.watch(testimonialQueryProvider);
    return super.build();
  }
}

final galleryProvider =
    AsyncNotifierProvider<GalleryController, PagedState<GalleryPicture>>(
      GalleryController.new,
      retry: (_, _) => null,
    );

class GalleryController extends PagedNotifier<GalleryPicture> {
  @override
  Future<PagedResult<GalleryPicture>> fetch(int page) =>
      ref.read(contentRepositoryProvider).gallery(page: page);

  @override
  Future<PagedState<GalleryPicture>> build() {
    ref.watch(currentUserProvider);
    return super.build();
  }
}
