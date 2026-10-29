import 'package:barbershop_app/core/utils/money.dart';

/// A service category (web: Service Categories).
class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
  });

  factory AdminCategory.fromJson(Map<String, dynamic> j) => AdminCategory(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    description: j['description']?.toString(),
    imageUrl: j['image_url']?.toString(),
  );

  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
}

/// A service as the web's Services page lists and edits it.
class AdminService {
  const AdminService({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.price,
    required this.duration,
    required this.active,
    required this.eligibleForTip,
    required this.commission,
    required this.description,
    required this.imageUrl,
    required this.homeSection,
  });

  factory AdminService.fromJson(Map<String, dynamic> j) => AdminService(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    categoryId: (j['category_id'] as num).toInt(),
    categoryName: (j['category_name'] ?? '').toString(),
    price: Money.parse(j['price']),
    duration: (j['duration'] as num?)?.toInt() ?? 0,
    active: j['active'] == true,
    eligibleForTip: j['eligible_for_tip'] == true,
    commission: j['commission_percent']?.toString(),
    description: j['description']?.toString(),
    imageUrl: j['image_url']?.toString(),
    homeSection: j['home_section']?.toString(),
  );

  final int id;
  final String name;
  final int categoryId;
  final String categoryName;
  final Money price;

  /// Minutes.
  final int duration;
  final bool active;
  final bool eligibleForTip;

  /// Percent as sent by the API (`10.00`), null when not set.
  final String? commission;
  final String? description;
  final String? imageUrl;

  /// `signature_grooming` or null (the website section).
  final String? homeSection;
}

/// A retail product (web: Products).
class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.price,
    required this.stock,
    required this.commission,
    required this.active,
    required this.description,
    required this.imageUrl,
  });

  factory AdminProduct.fromJson(Map<String, dynamic> j) => AdminProduct(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    categoryId: (j['category_id'] as num).toInt(),
    categoryName: (j['category_name'] ?? '').toString(),
    price: Money.parse(j['price']),
    stock: (j['stock'] as num?)?.toInt() ?? 0,
    commission: (j['commission_percent'] ?? '0').toString(),
    active: j['active'] == true,
    description: j['description']?.toString(),
    imageUrl: j['image_url']?.toString(),
  );

  final int id;
  final String name;
  final int categoryId;
  final String categoryName;
  final Money price;
  final int stock;

  /// Percent as sent by the API.
  final String commission;
  final bool active;
  final String? description;
  final String? imageUrl;
}

/// A GST (tax) record.
class GstItem {
  const GstItem({
    required this.id,
    required this.name,
    required this.rate,
    required this.exclude,
    required this.isDefault,
  });

  factory GstItem.fromJson(Map<String, dynamic> j) => GstItem(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    rate: (j['rate'] ?? '0').toString(),
    exclude: j['tax_type'] == 'exclude',
    isDefault: j['is_default'] == true,
  );

  final int id;
  final String name;

  /// Percent as sent by the API (`5.00`).
  final String rate;

  /// True = "Exclude" (tax added on top), false = "Include".
  final bool exclude;
  final bool isDefault;

  String get typeLabel => exclude ? 'Exclude' : 'Include';
}

/// A payment method of the shop (Payment Options).
class PaymentMethodItem {
  const PaymentMethodItem(this.id, this.name);

  factory PaymentMethodItem.fromJson(Map<String, dynamic> j) =>
      PaymentMethodItem((j['id'] as num).toInt(), (j['name'] ?? '').toString());

  final int id;
  final String name;
}

/// What the Service form sends (web names: Category, Service Name, Price,
/// Duration, Commission, Active, Eligible for Tip, Service Image, Description).
class ServiceInput {
  const ServiceInput({
    required this.categoryId,
    required this.name,
    required this.price,
    required this.duration,
    required this.commission,
    required this.active,
    required this.eligibleForTip,
    required this.description,
    this.imagePath,
  });

  final int categoryId;
  final String name;
  final String price;
  final String duration;
  final String commission;
  final bool active;
  final bool eligibleForTip;
  final String description;
  final String? imagePath;
}

/// What the Product form sends.
class ProductInput {
  const ProductInput({
    required this.categoryId,
    required this.name,
    required this.price,
    required this.stock,
    required this.commission,
    required this.active,
    required this.description,
    this.imagePath,
  });

  final int categoryId;
  final String name;
  final String price;
  final String stock;
  final String commission;
  final bool active;
  final String description;
  final String? imagePath;
}
