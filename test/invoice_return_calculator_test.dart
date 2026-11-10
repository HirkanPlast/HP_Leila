import 'package:flutter_test/flutter_test.dart';
import 'package:hps/utils/invoice_return_calculator.dart';

void main() {
  group('InvoiceReturnCalculator', () {
    test('full return leaves zero remaining', () {
      expect(
        InvoiceReturnCalculator.remaining(sold: 10, returned: 10),
        0,
      );
    });

    test('multiple partial returns accumulate against sold quantity', () {
      final afterFirst = InvoiceReturnCalculator.remaining(sold: 10, returned: 3);
      final afterSecond = InvoiceReturnCalculator.remaining(sold: 10, returned: 3 + 2.5);
      expect(afterFirst, 7);
      expect(afterSecond, 4.5);
    });

    test('request cannot exceed remaining quantity', () {
      expect(
        () => InvoiceReturnCalculator.validateRequest(
          sold: 10,
          returned: 7,
          requested: 3.1,
        ),
        throwsStateError,
      );
    });

    test('valid partial and final returns are accepted', () {
      expect(
        InvoiceReturnCalculator.validateRequest(
          sold: 10,
          returned: 2,
          requested: 4,
        ),
        4,
      );
      expect(
        InvoiceReturnCalculator.validateRequest(
          sold: 10,
          returned: 6,
          requested: 4,
        ),
        4,
      );
    });
  });
}
