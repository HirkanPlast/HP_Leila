/// Quantity guards shared by invoice-return persistence and its unit tests.
class InvoiceReturnCalculator {
  static double remaining({
    required double sold,
    required double returned,
  }) {
    if (!sold.isFinite || !returned.isFinite || sold < 0 || returned < 0) {
      throw ArgumentError('مقادیر تعداد معتبر نیستند.');
    }
    return (sold - returned).clamp(0.0, sold).toDouble();
  }

  static double validateRequest({
    required double sold,
    required double returned,
    required double requested,
  }) {
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError('مقدار برگشت باید بیشتر از صفر باشد.');
    }
    final available = remaining(sold: sold, returned: returned);
    if (requested > available + 0.0000001) {
      throw StateError('مقدار برگشت از مقدار باقی‌ماندهٔ کالا بیشتر است.');
    }
    return requested;
  }
}
