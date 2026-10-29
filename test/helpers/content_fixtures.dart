import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> testimonialJson(
  int id,
  String name, {
  int rating = 5,
  bool active = true,
}) => {
  'id': id,
  'client_name': name,
  'client_role': 'Regular Client',
  'review': 'Best fade in Edmonton.',
  'rating': rating,
  'sort_order': 1,
  'active': active,
  'image_url': null,
};

class FakeContent extends ContentRepository {
  FakeContent() : super(_NoApi());

  final calls = <String>[];
  final inputs = <TestimonialInput>[];
  Failure? uploadFails;

  @override
  Future<PagedResult<Testimonial>> testimonials({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('testimonials:$q');
    final all = [
      testimonialJson(1, 'Sam Patel'),
      testimonialJson(2, 'Daniel Okafor', rating: 3, active: false),
    ];
    final hit = [
      for (final t in all)
        if (q.isEmpty ||
            t['client_name'].toString().toLowerCase().contains(q.toLowerCase()))
          Testimonial.fromJson(t),
    ];
    return PagedResult(items: hit, hasMore: false, total: hit.length);
  }

  @override
  Future<String> createTestimonial(TestimonialInput i) async {
    calls.add('create');
    inputs.add(i);
    return 'Testimonial added successfully.';
  }

  @override
  Future<String> updateTestimonial(int id, TestimonialInput i) async {
    calls.add('update:$id');
    inputs.add(i);
    return 'Testimonial updated successfully.';
  }

  @override
  Future<String> deleteTestimonial(int id) async {
    calls.add('deleteTestimonial:$id');
    return 'Testimonial deleted successfully.';
  }

  @override
  Future<PagedResult<GalleryPicture>> gallery({
    int page = 1,
    int perPage = 30,
  }) async => const PagedResult(
    items: [
      GalleryPicture(1, 'http://x/1.jpg'),
      GalleryPicture(2, 'http://x/2.jpg'),
    ],
    hasMore: false,
    total: 2,
  );

  @override
  Future<String> addPicture(String imagePath) async {
    calls.add('add:$imagePath');
    if (uploadFails != null) throw uploadFails!;
    return 'Image added successfully';
  }

  @override
  Future<String> deletePicture(int id) async {
    calls.add('deletePicture:$id');
    return 'Image deleted successfully';
  }
}
