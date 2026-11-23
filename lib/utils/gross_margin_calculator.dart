/// Shared gross-margin calculation for dashboard and reports.
class GrossMarginCalculator {
  /// Returns gross margin percentage. A non-positive net sales value has no
  /// meaningful percentage and is represented as null.
  static double? percentage({required num netSales, required num costOfGoodsSold}) {
    final sales = netSales.toDouble();
    if (sales <= 0) return null;
    return ((sales - costOfGoodsSold.toDouble()) / sales) * 100;
  }
}
