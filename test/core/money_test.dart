import 'package:barbershop_app/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('API strings', () {
      expect(Money.parse('34.99').cents, 3499);
      expect(Money.parse('0.00').cents, 0);
      expect(Money.parse('15').cents, 1500);
      expect(Money.parse('15.5').cents, 1550);
      expect(Money.parse('1,234.56').cents, 123456);
      expect(Money.parse(r'$9.99').cents, 999);
      expect(Money.parse('-3.25').cents, -325);
    });

    test('numbers, null and junk', () {
      expect(Money.parse(null), Money.zero);
      expect(Money.parse(''), Money.zero);
      expect(Money.parse(12).cents, 1200);
      expect(Money.parse(12.5).cents, 1250);
      expect(Money.parse('abc'), Money.zero);
    });

    test('a third decimal rounds half up', () {
      expect(Money.parse('1.005').cents, 101);
      expect(Money.parse('1.004').cents, 100);
      expect(Money.parse('2.675').cents, 268);
    });
  });

  group('formatting', () {
    test('toApi is always two decimals', () {
      expect(const Money(3499).toApi(), '34.99');
      expect(const Money(5).toApi(), '0.05');
      expect(const Money(-5).toApi(), '-0.05');
      expect(Money.zero.toApi(), '0.00');
    });

    test('format groups thousands', () {
      expect(const Money(123456).format(), r'$1,234.56');
      expect(const Money(100000000).format(), r'$1,000,000.00');
      expect(const Money(999).format(symbol: false), '9.99');
      expect(const Money(1200).format(hideZeroCents: true), r'$12');
      expect(const Money(-250).format(), r'-$2.50');
    });
  });

  group('arithmetic (no floating point drift)', () {
    test('ten times 0.10 is exactly 1.00', () {
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total += Money.parse('0.10');
      }
      expect(total, Money.parse('1.00'));
    });

    test('the cart from the welcome screen: 2 x 34.99 + 15.00 + tip 8.00', () {
      final total =
          Money.parse('34.99') * 2 + Money.parse('15.00') + Money.parse('8.00');
      expect(total.format(), r'$92.98');
    });

    test('percent rounds half up', () {
      expect(Money.parse('34.99').percent(10).cents, 350); // 349.9
      expect(Money.parse('10.00').percent(12.5).cents, 125);
      expect(Money.parse('0.05').percent(10).cents, 1); // 0.5 -> 1
    });

    test('comparison and equality', () {
      expect(Money.parse('1.00') < Money.parse('1.01'), isTrue);
      expect(Money.parse('2.00') >= Money.parse('2.00'), isTrue);
      expect(Money.parse('3') == Money.parse('3.00'), isTrue);
      expect({Money.parse('3'), Money.parse('3.00')}.length, 1);
    });
  });
}
