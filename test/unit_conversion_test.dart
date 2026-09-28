import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/services/unit_conversion.dart';

void main() {
  test('millilitres are scaled down into litres', () {
    expect(convertQuantity(1000, 'ml', 'l'), closeTo(1, 0.0001));
    expect(convertQuantity(2.5, 'L', 'ml'), closeTo(2500, 0.0001));
  });

  test('grams and kilograms convert both ways', () {
    expect(convertQuantity(500, 'g', 'kg'), closeTo(0.5, 0.0001));
    expect(convertQuantity(1.2, 'Kgs', 'gm'), closeTo(1200, 0.0001));
  });

  test('the same unit passes through untouched, whatever it is', () {
    expect(convertQuantity(7, 'crate', 'crate'), 7);
    expect(convertQuantity(3, ' pcs ', 'pcs'), 3);
  });

  test('mass cannot be received into volume', () {
    expect(convertQuantity(1, 'kg', 'l'), isNull);
    expect(unitsAreCompatible('kg', 'l'), isFalse);
  });

  test('an unknown unit is refused rather than guessed', () {
    expect(convertQuantity(1, 'crate', 'kg'), isNull);
    expect(convertQuantity(1, 'kg', ''), isNull);
  });
}
