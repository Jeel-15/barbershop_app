import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// CONT-1/2: the website's testimonials and gallery.
class ContentRepository {
  const ContentRepository(this._api);

  final ApiClient _api;

  PagedResult<T> _page<T>(
    ApiResponse res,
    T Function(Map<String, dynamic>) parse,
  ) => PagedResult(
    items: [
      for (final e in (res.data['items'] as List? ?? const []))
        parse(Map<String, dynamic>.from(e as Map)),
    ],
    hasMore: res.meta['has_more'] == true,
    total: (res.meta['total'] as num?)?.toInt() ?? 0,
  );

  // -------------------------------------------------------- testimonials

  Future<PagedResult<Testimonial>> testimonials({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async => _page(
    await _api.get(
      '/testimonials',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'per_page': perPage,
      },
    ),
    Testimonial.fromJson,
  );

  @visibleForTesting
  static Future<FormData> testimonialForm(TestimonialInput i) async {
    final form = FormData()
      ..fields.addAll([
        MapEntry('client_name', i.name.trim()),
        if (i.role.trim().isNotEmpty) MapEntry('client_role', i.role.trim()),
        MapEntry('review', i.review.trim()),
        MapEntry('rating', '${i.rating}'),
        if (i.sortOrder.trim().isNotEmpty)
          MapEntry('sort_order', i.sortOrder.trim()),
        MapEntry('active_status', i.active ? '1' : '0'),
      ]);
    if (i.imagePath != null) {
      form.files.add(
        MapEntry('image', await MultipartFile.fromFile(i.imagePath!)),
      );
    }
    return form;
  }

  Future<String> createTestimonial(TestimonialInput i) async =>
      (await _api.post(
        '/testimonials',
        body: await testimonialForm(i),
      )).message;

  Future<String> updateTestimonial(int id, TestimonialInput i) async =>
      (await _api.post(
        '/testimonials/$id',
        body: await testimonialForm(i),
      )).message;

  Future<String> deleteTestimonial(int id) async =>
      (await _api.delete('/testimonials/$id')).message;

  // ------------------------------------------------------------- gallery

  Future<PagedResult<GalleryPicture>> gallery({
    int page = 1,
    int perPage = 30,
  }) async => _page(
    await _api.get('/gallery', query: {'page': page, 'per_page': perPage}),
    GalleryPicture.fromJson,
  );

  Future<String> addPicture(String imagePath) async => (await _api.post(
    '/gallery',
    body: FormData()
      ..files.add(MapEntry('image', await MultipartFile.fromFile(imagePath))),
  )).message;

  Future<String> deletePicture(int id) async =>
      (await _api.delete('/gallery/$id')).message;
}

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(ref.watch(apiClientProvider)),
);
