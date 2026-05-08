class InputSanitizer {
  const InputSanitizer._();

  static String cleanText(
    String raw, {
    required int maxLength,
    bool allowNewLines = false,
  }) {
    final collapsed = allowNewLines
        ? raw.replaceAll('\r', '').replaceAll(RegExp(r'[^\S\n]+'), ' ')
        : raw.replaceAll(RegExp(r'\s+'), ' ');
    var value = collapsed.trim();
    value = value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');
    if (value.length > maxLength) {
      value = value.substring(0, maxLength);
    }
    return value;
  }

  static double? parsePositiveAmount(
    String raw, {
    double min = 0.01,
    double max = 1000000000,
  }) {
    final cleaned = raw.replaceAll(',', '').replaceAll(r'$', '').trim();
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;
    if (parsed < min || parsed > max) return null;
    return parsed;
  }
}
