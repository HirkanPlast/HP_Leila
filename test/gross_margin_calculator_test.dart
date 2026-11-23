import 'package:flutter_test/flutter_test.dart';
import 'package:hps/utils/gross_margin_calculator.dart';

void main() {
  group('GrossMarginCalculator', () {
    test('calculates gross margin against net sales', () {
      expect(
        GrossMarginCalculator.percentage(netSales: 1000, costOfGoodsSold: 650),
        35,
      );
    });

    test('supports a gross loss', () {
      expect(
        GrossMarginCalculator.percentage(netSales: 1000, costOfGoodsSold: 1200),
        -20,
      );
    });

    test('returns null for zero or negative net sales', () {
      expect(GrossMarginCalculator.percentage(netSales: 0, costOfGoodsSold: 0), isNull);
      expect(GrossMarginCalculator.percentage(netSales: -100, costOfGoodsSold: 50), isNull);
    });
  });
}
