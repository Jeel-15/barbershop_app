/// A homepage review (web: Testimonials, "What Clients Say").
class Testimonial {
  const Testimonial({
    required this.id,
    required this.name,
    required this.role,
    required this.review,
    required this.rating,
    required this.sortOrder,
    required this.active,
    required this.imageUrl,
  });

  factory Testimonial.fromJson(Map<String, dynamic> j) => Testimonial(
    id: (j['id'] as num).toInt(),
    name: (j['client_name'] ?? '').toString(),
    role: (j['client_role'] ?? '').toString(),
    review: (j['review'] ?? '').toString(),
    rating: ((j['rating'] as num?)?.toInt() ?? 5).clamp(1, 5),
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    active: j['active'] == true,
    imageUrl: j['image_url']?.toString(),
  );

  final int id;
  final String name;

  /// The web's "Client Title" (default "Regular Client").
  final String role;
  final String review;

  /// 1..5.
  final int rating;
  final int sortOrder;

  /// "Show on website" (Active) or Hidden.
  final bool active;
  final String? imageUrl;

  /// The web's stars: `★★★★☆`.
  String get stars => '${'★' * rating}${'☆' * (5 - rating)}';
}

/// What the Add / Update Testimonial form sends.
class TestimonialInput {
  const TestimonialInput({
    required this.name,
    required this.role,
    required this.review,
    required this.rating,
    required this.sortOrder,
    required this.active,
    this.imagePath,
  });

  final String name;
  final String role;
  final String review;
  final int rating;
  final String sortOrder;
  final bool active;
  final String? imagePath;
}

/// One picture of the website gallery.
class GalleryPicture {
  const GalleryPicture(this.id, this.imageUrl);

  factory GalleryPicture.fromJson(Map<String, dynamic> j) => GalleryPicture(
    (j['id'] as num).toInt(),
    (j['image_url'] ?? '').toString(),
  );

  final int id;
  final String imageUrl;
}
