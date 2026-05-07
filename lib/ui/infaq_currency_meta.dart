import 'package:flutter/material.dart';

/// Emoji flags, labels, and symbols for currency pickers (no image assets).
class InfaqCurrencyMeta {
  InfaqCurrencyMeta._();

  /// Default order in profile and registration pickers.
  static const List<String> orderedCodes = [
    'BHD',
    'USD',
    'EUR',
    'GBP',
    'SAR',
    'AED',
    'KWD',
    'QAR',
    'OMR',
    'JOD',
    'EGP',
    'INR',
    'PKR',
    'PHP',
    'JPY',
    'CNY',
    'TRY',
    'CAD',
    'AUD',
    'CHF',
  ];

  /// Full picker list, appending [current] if it is a non-empty code not in [orderedCodes].
  static List<String> orderedCodesForUser(String? current) {
    final c = current?.trim().toUpperCase();
    if (c == null || c.isEmpty) return List<String>.from(orderedCodes);
    if (orderedCodes.contains(c)) return List<String>.from(orderedCodes);
    return [...orderedCodes, c];
  }

  static String flagEmoji(String code) {
    switch (code.toUpperCase()) {
      case 'BHD':
        return '🇧🇭';
      case 'USD':
        return '🇺🇸';
      case 'EUR':
        return '🇪🇺';
      case 'GBP':
        return '🇬🇧';
      case 'SAR':
        return '🇸🇦';
      case 'AED':
        return '🇦🇪';
      case 'KWD':
        return '🇰🇼';
      case 'QAR':
        return '🇶🇦';
      case 'OMR':
        return '🇴🇲';
      case 'JOD':
        return '🇯🇴';
      case 'EGP':
        return '🇪🇬';
      case 'INR':
        return '🇮🇳';
      case 'PKR':
        return '🇵🇰';
      case 'PHP':
        return '🇵🇭';
      case 'JPY':
        return '🇯🇵';
      case 'CNY':
        return '🇨🇳';
      case 'TRY':
        return '🇹🇷';
      case 'CAD':
        return '🇨🇦';
      case 'AUD':
        return '🇦🇺';
      case 'CHF':
        return '🇨🇭';
      default:
        return '';
    }
  }

  /// When no country flag exists, show a neutral glyph in pickers.
  static Widget flagOrFallback(
    BuildContext context,
    String code, {
    double size = 20,
  }) {
    final e = flagEmoji(code);
    if (e.isNotEmpty) {
      return Text(e, style: TextStyle(fontSize: size, height: 1));
    }
    final cs = Theme.of(context).colorScheme;
    return Icon(
      Icons.currency_exchange_rounded,
      size: size * 0.95,
      color: cs.onSurface.withValues(alpha: 0.45),
    );
  }

  static String currencyName(String code) {
    switch (code.toUpperCase()) {
      case 'BHD':
        return 'Bahraini Dinar';
      case 'USD':
        return 'US Dollar';
      case 'EUR':
        return 'Euro';
      case 'GBP':
        return 'British Pound';
      case 'SAR':
        return 'Saudi Riyal';
      case 'AED':
        return 'UAE Dirham';
      case 'KWD':
        return 'Kuwaiti Dinar';
      case 'QAR':
        return 'Qatari Riyal';
      case 'OMR':
        return 'Omani Rial';
      case 'JOD':
        return 'Jordanian Dinar';
      case 'EGP':
        return 'Egyptian Pound';
      case 'INR':
        return 'Indian Rupee';
      case 'PKR':
        return 'Pakistani Rupee';
      case 'PHP':
        return 'Philippine Peso';
      case 'JPY':
        return 'Japanese Yen';
      case 'CNY':
        return 'Chinese Yuan';
      case 'TRY':
        return 'Turkish Lira';
      case 'CAD':
        return 'Canadian Dollar';
      case 'AUD':
        return 'Australian Dollar';
      case 'CHF':
        return 'Swiss Franc';
      default:
        return code.toUpperCase();
    }
  }

  /// Narrow symbol for suffix / hints (optional).
  static String? narrowSymbol(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
      case 'CNY':
        return '¥';
      case 'INR':
        return '₹';
      case 'PHP':
        return '₱';
      case 'TRY':
        return '₺';
      case 'CAD':
        return r'CA$';
      case 'AUD':
        return r'A$';
      case 'CHF':
        return 'Fr';
      default:
        return null;
    }
  }

  /// Picker line: "BHD - Bahraini Dinar" (flag shown separately).
  static String menuLabel(String code) {
    final u = code.toUpperCase();
    final sym = narrowSymbol(u);
    final name = currencyName(code);
    if (sym != null) {
      return '$u - $name ($sym)';
    }
    return '$u - $name';
  }
}
