import 'dart:math' as math;

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  // WCAG AA: 4.5:1 for normal text. The tokens are the accessibility contract
  // of the whole app, so a bad colour edit fails here, not in the shop.
  for (final (name, t) in [
    ('dark', AppTokens.dark),
    ('light', AppTokens.light),
  ]) {
    group('$name tokens meet WCAG AA', () {
      test('primary and secondary text on page and card', () {
        for (final bg in [t.bg, t.surface, t.surfaceRaised]) {
          expect(
            _contrast(t.text, bg),
            greaterThanOrEqualTo(7),
            reason: 'text on $bg',
          );
          expect(
            _contrast(t.textSecondary, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'secondary on $bg',
          );
          expect(
            _contrast(t.textMuted, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'muted on $bg',
          );
        }
      });

      test('gold text', () {
        for (final bg in [t.bg, t.surface, t.surfaceRaised]) {
          expect(
            _contrast(t.accentText, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'accentText on $bg',
          );
        }
      });

      test('status colours as text on cards', () {
        for (final c in [t.success, t.warning, t.info, t.violet, t.danger]) {
          expect(
            _contrast(c, t.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$c on surface',
          );
        }
      });

      test('text on a gold button', () {
        expect(_contrast(t.onAccent, t.accent), greaterThanOrEqualTo(7));
      });

      test('every appointment status has its own colour', () {
        final colors = AppointmentStatus.values.map(t.statusColor).toSet();
        expect(colors.length, AppointmentStatus.values.length);
      });
    });
  }

  test(
    'status codes match the web (0 pending, 1 completed, 2 cancelled, 3 confirmed, 4 rescheduled)',
    () {
      expect(AppointmentStatus.fromCode(0), AppointmentStatus.pending);
      expect(AppointmentStatus.fromCode(1), AppointmentStatus.completed);
      expect(AppointmentStatus.fromCode(2), AppointmentStatus.cancelled);
      expect(AppointmentStatus.fromCode(3), AppointmentStatus.confirmed);
      expect(AppointmentStatus.fromCode(4), AppointmentStatus.rescheduled);
      expect(AppointmentStatus.fromCode(99), AppointmentStatus.pending);
    },
  );

  test('both themes carry the token extension', () {
    expect(AppTheme.dark.extension<AppTokens>()!.isDark, isTrue);
    expect(AppTheme.light.extension<AppTokens>()!.isDark, isFalse);
  });
}
