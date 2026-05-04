String currencyPrefixForCode(String? code) {
  switch (code?.toUpperCase()) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'SAR':
      return 'SAR ';
    case 'BHD':
      return 'BHD ';
    default:
      final c = code?.trim();
      return (c == null || c.isEmpty) ? '' : '$c ';
  }
}

String formatInsightsMoney(String? currencyCode, double v) {
  final p = currencyPrefixForCode(currencyCode);
  final n = v.abs();
  final s = n >= 1000 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  return '$p$s';
}

String formatInsightsPercent(double? v) {
  if (v == null) return '—';
  final sign = v > 0 ? '+' : '';
  return '$sign${v.toStringAsFixed(1)}%';
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
