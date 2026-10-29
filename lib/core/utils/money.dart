import 'package:flutter/foundation.dart';

/// Exact money. Stored as whole cents, so no floating-point error can ever
/// creep into a total. The API sends money as `"NN.NN"` strings and accepts
/// plain numbers; this class is the only thing that parses or prints it.
@immutable
class Money implements Comparable<Money> {
  const Money(this.cents);

  static const zero = Money(0);

  final int cents;

  /// Parses `"12.34"`, `"1,234.5"`, `12`, `12.345` (rounded half up) or null (= zero).
  factory Money.parse(Object? value) {
    if (value == null) return zero;
    if (value is Money) return value;
    if (value is int) return Money(value * 100);
    var s = value is num ? value.toString() : value.toString().trim();
    if (s.isEmpty) return zero;
    s = s.replaceAll(RegExp(r'[,$\s]'), '');
    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);
    final parts = s.split('.');
    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? 0;
    final frac = parts.length > 1 ? parts[1] : '';
    var cents = whole * 100;
    if (frac.isNotEmpty) {
      final padded = frac.padRight(3, '0');
      var c = int.tryParse(padded.substring(0, 2)) ?? 0;
      if (int.tryParse(padded[2]) != null && int.parse(padded[2]) >= 5) c += 1;
      cents += c;
    }
    return Money(negative ? -cents : cents);
  }

  /// `"12.34"` for the API.
  String toApi() {
    final abs = cents.abs();
    return '${cents < 0 ? '-' : ''}${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// `$1,234.56` (or `1,234.56` without the symbol).
  String format({bool symbol = true, bool hideZeroCents = false}) {
    final abs = cents.abs();
    final whole = (abs ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final c = abs % 100;
    final tail = hideZeroCents && c == 0
        ? ''
        : '.${c.toString().padLeft(2, '0')}';
    return '${cents < 0 ? '-' : ''}${symbol ? r'$' : ''}$whole$tail';
  }

  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
  Money operator *(int n) => Money(cents * n);
  Money operator -() => Money(-cents);

  /// `percent(10)` of $34.99 = $3.50 (rounded half up).
  Money percent(num pct) => Money((cents * pct / 100).round());

  bool get isZero => cents == 0;
  bool get isNegative => cents < 0;

  bool operator >(Money o) => cents > o.cents;
  bool operator <(Money o) => cents < o.cents;
  bool operator >=(Money o) => cents >= o.cents;
  bool operator <=(Money o) => cents <= o.cents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => format();
}
