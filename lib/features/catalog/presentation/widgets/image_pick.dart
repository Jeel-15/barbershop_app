import 'dart:io';

import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the gallery and checks what the web checks: JPG, PNG or GIF (and
/// WebP where the web allows it), up to 2 MB. Returns the picked path, or an
/// [error] in words, or neither when cancelled.
Future<({String? path, String? error})> pickCatalogImage(
  WidgetRef ref, {
  String invalidMessage =
      'Please upload a valid image file (jpg, jpeg, png, gif)',
  bool allowWebp = false,
}) async {
  final path = await ref.read(photoPickerProvider)();
  if (path == null) return (path: null, error: null);
  final ext = path.split('.').last.toLowerCase();
  final allowed = ['jpg', 'jpeg', 'png', 'gif', if (allowWebp) 'webp'];
  if (!allowed.contains(ext)) {
    return (path: null, error: invalidMessage);
  }
  if (await File(path).length() > 2 * 1024 * 1024) {
    return (path: null, error: 'Max 2MB.');
  }
  return (path: path, error: null);
}
