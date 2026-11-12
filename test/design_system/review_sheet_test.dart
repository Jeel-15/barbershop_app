import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/load_fonts.dart';

/// Opens the sheet from a button and records what it answered.
Future<List<bool>> _open(
  WidgetTester tester, {
  List<String> warnings = const [],
}) async {
  final answers = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => answers.add(
                await showReviewSheet(
                  context,
                  title: 'Check the invoice',
                  intro: 'Make sure everything is right.',
                  warnings: warnings,
                  sections: const [
                    ReviewSection('Customer', [
                      ReviewRow('Ravi Shah', ''),
                      ReviewRow('Phone', '7805559999'),
                    ]),
                    ReviewSection('Services', [
                      ReviewRow("Men's cut x 2", '\$70.00', note: 'with Mutaz'),
                    ]),
                  ],
                  total: const ReviewRow('Total Amount', '\$70.00'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return answers;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows every section, the notes, the warnings and the total', (
    tester,
  ) async {
    await _open(tester, warnings: const ['The total is \$0.00.']);
    expect(find.text('Check the invoice'), findsOneWidget);
    expect(find.text('Make sure everything is right.'), findsOneWidget);
    expect(find.text('The total is \$0.00.'), findsOneWidget);
    expect(find.text('CUSTOMER'), findsOneWidget);
    expect(find.text('Ravi Shah'), findsOneWidget);
    expect(find.text('7805559999'), findsOneWidget);
    expect(find.text("Men's cut x 2"), findsOneWidget);
    expect(find.text('with Mutaz'), findsOneWidget);
    expect(find.text('Total Amount'), findsOneWidget);
  });

  testWidgets('no warning box when nothing is unusual', (tester) async {
    await _open(tester);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('Done answers true', (tester) async {
    final answers = await _open(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    await _settle(tester);
    expect(answers, [true]);
  });

  testWidgets('Edit answers false and so does the phone Back', (tester) async {
    final answers = await _open(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Edit'));
    await _settle(tester);
    expect(answers, [false]);

    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(answers, [false, false]);
  });
}
