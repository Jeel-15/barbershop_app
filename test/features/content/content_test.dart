import 'dart:async';
import 'dart:io';

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:barbershop_app/features/content/presentation/gallery_page.dart';
import 'package:barbershop_app/features/content/presentation/testimonials_page.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/content_fixtures.dart';
import '../../helpers/load_fonts.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

const _all = [
  'Testimonial-Add',
  'Testimonial-Edit',
  'Testimonial-Delete',
  'Gallery-Add',
  'Gallery-Delete',
];

Future<FakeContent> _open(
  WidgetTester tester,
  String start, {
  List<String> perms = _all,
  String? photo,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeContent();
  final boot = adminBootstrapWith(perms);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(
        path: '/app/testimonials',
        builder: (_, _) => const TestimonialsPage(),
      ),
      GoRoute(
        path: '/app/testimonials/new',
        builder: (_, _) => const TestimonialFormPage(),
      ),
      GoRoute(
        path: '/app/testimonials/edit/:id',
        builder: (_, s) => TestimonialFormPage(
          testimonial: s.extra is Testimonial ? s.extra! as Testimonial : null,
        ),
      ),
      GoRoute(path: '/app/gallery', builder: (_, _) => const GalleryPage()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        contentRepositoryProvider.overrideWithValue(repo),
        photoPickerProvider.overrideWithValue(() async => photo),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push(start));
  await _settle(tester);
  return repo;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
  });

  test('stars follow the web: filled then empty', () {
    final t = Testimonial.fromJson(testimonialJson(1, 'A', rating: 4));
    expect(t.stars, '★★★★☆');
    expect(Testimonial.fromJson(testimonialJson(1, 'A', rating: 9)).rating, 5);
  });

  test(
    'the form sends only what is set; the picture only when picked',
    () async {
      final form = await ContentRepository.testimonialForm(
        const TestimonialInput(
          name: ' Sam ',
          role: '',
          review: 'Great',
          rating: 4,
          sortOrder: '',
          active: false,
        ),
      );
      final f = {for (final e in form.fields) e.key: e.value};
      expect(f['client_name'], 'Sam');
      expect(f.containsKey('client_role'), isFalse);
      expect(f.containsKey('sort_order'), isFalse);
      expect(f['active_status'], '0');
      expect(form.files, isEmpty);
    },
  );

  group('Testimonials', () {
    testWidgets('list: name, stars, title, review, status', (tester) async {
      await _open(tester, '/app/testimonials');
      expect(find.text('Testimonials'), findsOneWidget);
      expect(
        find.text('Manage homepage “What Clients Say” reviews'),
        findsOneWidget,
      );
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('★★★★★ · Regular Client'), findsOneWidget);
      expect(find.text('★★★☆☆ · Regular Client'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);
    });

    testWidgets('search and delete', (tester) async {
      final r = await _open(tester, '/app/testimonials');
      await tester.enterText(find.byType(TextField).first, 'dan');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(r.calls, contains('testimonials:dan'));
      await tester.tap(find.byTooltip('More'));
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Delete this testimonial?'), findsOneWidget);
      await tester.tap(find.text('Yes, delete it'));
      await _settle(tester);
      expect(r.calls, contains('deleteTestimonial:2'));
    });

    testWidgets('Add Testimonial: required fields, then a valid save', (
      tester,
    ) async {
      final r = await _open(tester, '/app/testimonials/new');
      expect(find.text('Client Name *'), findsOneWidget);
      expect(find.text('Client Title'), findsOneWidget);
      expect(find.text('Review *'), findsOneWidget);
      expect(find.text('5 Stars'), findsOneWidget);
      expect(find.text('1 Star'), findsOneWidget);
      expect(find.text('Display Order'), findsOneWidget);
      expect(find.text('Show on website'), findsOneWidget);
      expect(find.text('Client Photo'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('The client name field is required.'), findsOneWidget);
      expect(find.text('The review field is required.'), findsOneWidget);
      expect(r.calls, isNot(contains('create')));

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Client Name *'),
        'Ravi',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Review *'),
        'Clean lines.',
      );
      await tester.tap(find.widgetWithText(AppChoiceChip, '4 Stars'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      final i = r.inputs.single;
      expect(i.name, 'Ravi');
      expect(i.rating, 4);
      expect(i.active, isTrue);
    });

    testWidgets('Update opens filled', (tester) async {
      final r = await _open(tester, '/app/testimonials');
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Edit'));
      await _settle(tester);
      expect(find.text('Update Testimonial'), findsOneWidget);
      expect(find.text('Sam Patel'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(r.calls, contains('update:1'));
    });

    testWidgets('no rights: no Add, no menu', (tester) async {
      await _open(tester, '/app/testimonials', perms: const []);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('Gallery', () {
    testWidgets('a grid of the pictures and Add Image', (tester) async {
      await _open(tester, '/app/gallery');
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Manage website gallery images'), findsOneWidget);
      expect(find.text('ALL IMAGES · 2'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('Upload needs an image first, then uploads it', (tester) async {
      final pic = File('${Directory.systemTemp.path}/rosen_gallery_pic.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(pic.deleteSync);
      final r = await _open(tester, '/app/gallery', photo: pic.path);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _settle(tester);
      expect(find.text('Upload Gallery Image'), findsOneWidget);
      expect(find.text('Select Image'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Upload'));
      await _settle(tester);
      expect(find.text('Select Image'), findsWidgets);
      expect(r.calls.where((c) => c.startsWith('add')), isEmpty);

      await tester.tap(find.text('Choose photo'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Upload'));
      await _settle(tester);
      expect(r.calls, contains('add:${pic.path}'));
    });

    testWidgets('opening a picture offers Delete with the web question', (
      tester,
    ) async {
      final r = await _open(tester, '/app/gallery');
      // The pole of the refresh indicator is an asset Image too: pick the pictures.
      await tester.tap(
        find
            .byWidgetPredicate((w) => w is Image && w.image is! AssetImage)
            .first,
      );
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Delete'));
      await _settle(tester);
      expect(find.text('Delete this image?'), findsOneWidget);
      await tester.tap(find.text('Yes, delete it'));
      await _settle(tester);
      expect(r.calls, contains('deletePicture:1'));
    });
  });
}
