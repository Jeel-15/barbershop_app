import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/load_fonts.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUpAll(loadAppFonts);

  group('AppTextField', () {
    testWidgets('a label ending in * keeps its words and shows a red star', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const AppTextField(label: 'Service Name *')),
      );
      // The web's wording is unchanged for finders and screen readers.
      expect(find.text('Service Name *'), findsOneWidget);
      final rich = tester.widget<Text>(find.text('Service Name *'));
      final star = (rich.textSpan! as TextSpan).children!.single as TextSpan;
      expect(star.text, ' *');
      expect(star.style!.color, isNot(equals(null)));
    });

    testWidgets('judges the value when the person leaves the field, and '
        'forgives at once when it is fixed', (tester) async {
      final ctl = TextEditingController();
      final next = FocusNode();
      addTearDown(next.dispose);
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              AppTextField(
                label: 'Price',
                controller: ctl,
                validator: (v) =>
                    double.tryParse(v) == null ? 'Not a number' : null,
              ),
              TextField(focusNode: next),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.pump();
      // Still typing: no scolding yet.
      expect(find.text('Not a number'), findsNothing);
      // Leaving the field: now it is judged.
      next.requestFocus();
      await tester.pump();
      expect(find.text('Not a number'), findsOneWidget);
      // Fixing it clears the message while typing.
      await tester.enterText(find.byType(TextField).first, '12');
      await tester.pump();
      expect(find.text('Not a number'), findsNothing);
    });

    testWidgets('an error from the server wins over the field own check', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          AppTextField(
            label: 'Name',
            errorText: 'Already taken',
            validator: (_) => 'Own message',
          ),
        ),
      );
      expect(find.text('Already taken'), findsOneWidget);
      expect(find.text('Own message'), findsNothing);
    });

    testWidgets('counter, unit and clear button', (tester) async {
      final ctl = TextEditingController(text: 'hello');
      await tester.pumpWidget(
        _app(
          AppTextField(
            controller: ctl,
            maxLength: 20,
            showCounter: true,
            clearable: true,
            suffixText: 'min',
            prefixText: '\$ ',
          ),
        ),
      );
      expect(find.text('5/20'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      // The x only shows while the field has focus and text.
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.cancel_rounded));
      await tester.pump();
      expect(ctl.text, isEmpty);
      expect(find.text('0/20'), findsOneWidget);
    });
  });

  group('FormPageFrame', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool dirty,
      required VoidCallback onClose,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: FormPageFrame(
          title: 'Add Service',
          dirty: dirty,
          onClose: onClose,
          bottom: const FormActionBar(label: 'Save', onPressed: null),
          child: const SizedBox(),
        ),
      ),
    );

    testWidgets('a clean form closes at once', (tester) async {
      var closed = 0;
      await pump(tester, dirty: false, onClose: () => closed++);
      await tester.tap(
        find.bySemanticsLabel('Back').first,
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.tap(find.byType(RoundBackButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(closed, greaterThan(0));
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('a changed form asks first; Keep editing stays', (
      tester,
    ) async {
      var closed = 0;
      await pump(tester, dirty: true, onClose: () => closed++);
      await tester.tap(find.byType(RoundBackButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(closed, 0);
    });

    testWidgets('Discard leaves the form', (tester) async {
      var closed = 0;
      await pump(tester, dirty: true, onClose: () => closed++);
      await tester.tap(find.byType(RoundBackButton));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Discard'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(closed, 1);
    });

    testWidgets('the phone Back asks too when something changed', (
      tester,
    ) async {
      var closed = 0;
      await pump(tester, dirty: true, onClose: () => closed++);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(closed, 0);
    });
  });

  testWidgets('FormSection groups its children under a title', (tester) async {
    await tester.pumpWidget(
      _app(
        const FormSection(
          title: 'Price and time',
          subtitle: 'What it costs',
          icon: Icons.payments_rounded,
          children: [Text('one'), Text('two')],
        ),
      ),
    );
    expect(find.text('Price and time'), findsOneWidget);
    expect(find.text('What it costs'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('scrollToFirstError brings the field into view', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            // As in the forms: every section is built, so its key has a context.
            scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
            children: [
              for (var i = 0; i < 30; i++) const SizedBox(height: 120),
              SizedBox(key: key, height: 60, child: const Text('bottom field')),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );
    scrollToFirstError([null, key]);
    // One frame starts the scroll, the next ones play it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('bottom field'), findsOneWidget);
  });
}
