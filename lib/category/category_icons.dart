import 'package:flutter/material.dart';

/// Default when [validatedCategoryIconKey] receives null/unknown.
const String kDefaultCategoryIconKey = 'category';
const List<Color> kCategoryColorPalette = <Color>[
  Color(0xFFE8A87C),
  Color(0xFFE27D9A),
  Color(0xFF6B9BD1),
  Color(0xFF9B7ED9),
  Color(0xFF4D6658),
  Color(0xFF2BB3A8),
  Color(0xFFC9A227),
  Color(0xFF7EB6DF),
];

class CategoryIconChoice {
  const CategoryIconChoice({required this.key, required this.icon, required this.label});
  final String key;
  final IconData icon;
  final String label;
}

/// Preset icons shown in the category picker; keys are stored in `categories.icon_key`.
const List<CategoryIconChoice> kCategoryIconChoices = [
  CategoryIconChoice(key: 'category', icon: Icons.category_outlined, label: 'General'),
  CategoryIconChoice(key: 'shopping_cart', icon: Icons.shopping_cart_outlined, label: 'Shopping'),
  CategoryIconChoice(key: 'restaurant', icon: Icons.restaurant_outlined, label: 'Food'),
  CategoryIconChoice(key: 'local_cafe', icon: Icons.local_cafe_outlined, label: 'Cafe'),
  CategoryIconChoice(key: 'directions_car', icon: Icons.directions_car_outlined, label: 'Transport'),
  CategoryIconChoice(key: 'home', icon: Icons.home_outlined, label: 'Home'),
  CategoryIconChoice(key: 'bolt', icon: Icons.bolt_outlined, label: 'Utilities'),
  CategoryIconChoice(key: 'movie', icon: Icons.movie_outlined, label: 'Entertainment'),
  CategoryIconChoice(key: 'fitness_center', icon: Icons.fitness_center_outlined, label: 'Fitness'),
  CategoryIconChoice(key: 'school', icon: Icons.school_outlined, label: 'Education'),
  CategoryIconChoice(key: 'work', icon: Icons.work_outline_rounded, label: 'Work'),
  CategoryIconChoice(key: 'flight', icon: Icons.flight_outlined, label: 'Travel'),
  CategoryIconChoice(key: 'favorite', icon: Icons.favorite_border_rounded, label: 'Health'),
  CategoryIconChoice(key: 'pets', icon: Icons.pets_outlined, label: 'Pets'),
  CategoryIconChoice(key: 'savings', icon: Icons.savings_outlined, label: 'Savings'),
  CategoryIconChoice(key: 'card_giftcard', icon: Icons.card_giftcard_outlined, label: 'Gifts'),
  CategoryIconChoice(key: 'devices', icon: Icons.devices_outlined, label: 'Tech'),
  CategoryIconChoice(key: 'receipt_long', icon: Icons.receipt_long_outlined, label: 'Bills'),
  CategoryIconChoice(key: 'trending_up', icon: Icons.trending_up_rounded, label: 'Income'),
  CategoryIconChoice(key: 'payments', icon: Icons.payments_outlined, label: 'Payments'),
  CategoryIconChoice(key: 'more', icon: Icons.more_horiz_rounded, label: 'Other'),
  CategoryIconChoice(key: 'subscriptions', icon: Icons.subscriptions_outlined, label: 'Subscriptions'),
  CategoryIconChoice(key: 'local_grocery_store', icon: Icons.local_grocery_store_outlined, label: 'Groceries'),
  CategoryIconChoice(key: 'local_gas_station', icon: Icons.local_gas_station_outlined, label: 'Fuel'),
  CategoryIconChoice(key: 'medical_services', icon: Icons.medical_services_outlined, label: 'Medical'),
  CategoryIconChoice(key: 'phone_iphone', icon: Icons.phone_iphone_outlined, label: 'Phone'),
  CategoryIconChoice(key: 'child_care', icon: Icons.child_care_outlined, label: 'Family'),
  CategoryIconChoice(key: 'volunteer_activism', icon: Icons.volunteer_activism_outlined, label: 'Charity'),
  CategoryIconChoice(key: 'shield', icon: Icons.shield_outlined, label: 'Insurance'),
  CategoryIconChoice(key: 'account_balance', icon: Icons.account_balance_outlined, label: 'Banking'),
  CategoryIconChoice(key: 'currency_exchange', icon: Icons.currency_exchange_rounded, label: 'Transfer'),
  CategoryIconChoice(key: 'sports_esports', icon: Icons.sports_esports_outlined, label: 'Gaming'),
  CategoryIconChoice(key: 'headphones', icon: Icons.headphones_outlined, label: 'Audio'),
  CategoryIconChoice(key: 'beach_access', icon: Icons.beach_access_outlined, label: 'Leisure'),
  CategoryIconChoice(key: 'handyman', icon: Icons.handyman_outlined, label: 'Repairs'),
  CategoryIconChoice(key: 'local_pharmacy', icon: Icons.local_pharmacy_outlined, label: 'Pharmacy'),
  CategoryIconChoice(key: 'emoji_events', icon: Icons.emoji_events_outlined, label: 'Awards'),
];

final Map<String, IconData> _categoryIconByKey = {
  for (final e in kCategoryIconChoices) e.key: e.icon,
};

bool isKnownCategoryIconKey(String key) => _categoryIconByKey.containsKey(key);

String validatedCategoryIconKey(String? raw) {
  if (raw != null && raw.isNotEmpty && isKnownCategoryIconKey(raw)) return raw;
  return kDefaultCategoryIconKey;
}

IconData? _iconFromStoredKey(String? key) {
  if (key == null || key.isEmpty) return null;
  return _categoryIconByKey[key];
}

/// Icon for list UI: uses DB [iconKey] when set, otherwise guesses from [name] / [type],
/// then a stable icon from [categoryId] (or name) so each category can look distinct.
bool _nameSuggestsTravel(String name) {
  final n = name.toLowerCase();
  return n.contains('travel') ||
      n.contains('flight') ||
      n.contains('airline') ||
      n.contains('vacation') ||
      n.contains('holiday') ||
      n.contains('hotel') ||
      n.contains('passport') ||
      n.contains('luggage');
}

IconData categoryIconForDisplay({
  String? iconKey,
  required String name,
  required String type,
  String? categoryId,
}) {
  final fromDb = _iconFromStoredKey(iconKey);
  if (fromDb != null) {
    final useDefaultKey = iconKey == null || iconKey.isEmpty || iconKey == kDefaultCategoryIconKey;
    if (useDefaultKey && _nameSuggestsTravel(name)) {
      return Icons.flight_outlined;
    }
    return fromDb;
  }
  return _categoryIconFallback(name, type, categoryId);
}

IconData _categoryIconFallback(String name, String type, String? categoryId) {
  final n = name.toLowerCase();
  final t = type.toLowerCase();
  if (_nameSuggestsTravel(name)) {
    return Icons.flight_outlined;
  }
  if (t == 'income') {
    if (n.contains('salary') || n.contains('wage')) return Icons.payments_outlined;
    if (n.contains('freelance') || n.contains('business')) return Icons.work_outline_rounded;
    if (n.contains('invest') || n.contains('dividend')) return Icons.trending_up_rounded;
    if (n.contains('gift')) return Icons.card_giftcard_outlined;
    return Icons.account_balance_wallet_outlined;
  }
  if (n.contains('food') || n.contains('grocer') || n.contains('dining') || n.contains('restaurant')) {
    return Icons.restaurant_outlined;
  }
  if (n.contains('grocery') || n.contains('supermarket')) {
    return Icons.local_grocery_store_outlined;
  }
  if (n.contains('gas') || n.contains('fuel') || n.contains('petrol')) {
    return Icons.local_gas_station_outlined;
  }
  if (n.contains('subscri') || n.contains('streaming') || n.contains('netflix') || n.contains('spotify')) {
    return Icons.subscriptions_outlined;
  }
  if (n.contains('transport') || n.contains('car') || n.contains('parking') || n.contains('uber') || n.contains('taxi')) {
    return Icons.directions_car_outlined;
  }
  if (n.contains('shop') || n.contains('clothes') || n.contains('retail')) {
    return Icons.shopping_cart_outlined;
  }
  if (n.contains('entertain') || n.contains('game') || n.contains('stream') || n.contains('cinema')) {
    return Icons.movie_outlined;
  }
  if (n.contains('bill') || n.contains('util') || n.contains('electric') || n.contains('water')) {
    return Icons.receipt_long_outlined;
  }
  if (n.contains('health') || n.contains('medical')) {
    return Icons.favorite_border_rounded;
  }
  if (n.contains('pharm')) {
    return Icons.local_pharmacy_outlined;
  }
  if (n.contains('home') || n.contains('rent') || n.contains('mortgage')) {
    return Icons.home_outlined;
  }
  if (n.contains('education') || n.contains('school') || n.contains('tuition')) {
    return Icons.school_outlined;
  }
  if (n.contains('insur')) {
    return Icons.shield_outlined;
  }
  if (n.contains('charity') || n.contains('donat')) {
    return Icons.volunteer_activism_outlined;
  }
  return _iconFromStableCategorySeed(type: t, name: n, categoryId: categoryId);
}

/// Picks a deterministic icon from [kCategoryIconChoices] so different categories
/// usually get different icons even without a stored [icon_key].
IconData _iconFromStableCategorySeed({
  required String type,
  required String name,
  String? categoryId,
}) {
  final seed = (categoryId != null && categoryId.isNotEmpty) ? '$type|$categoryId' : '$type|$name';
  var h = 5381;
  for (final unit in seed.codeUnits) {
    h = ((h << 5) + h + unit) & 0x7fffffff;
  }
  final choices = kCategoryIconChoices;
  return choices[h.abs() % choices.length].icon;
}

Color categoryDisplayColor(
  String rawName, {
  String? categoryId,
  dynamic savedColor,
}) {
  return categoryDisplayColorFor(
    rawName,
    categoryId: categoryId,
    savedColor: savedColor,
  );
}

Color categoryDisplayColorFor(
  String rawName, {
  String? categoryId,
  dynamic savedColor,
}) {
  final explicit = _parseStoredColor(savedColor);
  if (explicit != null) return explicit;

  final normalized = rawName.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const Color(0xFF7A7A7A);
  }

  // Built-in/common categories keep fixed colors app-wide.
  if (normalized.contains('food') ||
      normalized.contains('restaurant') ||
      normalized.contains('grocery') ||
      normalized.contains('grocer')) {
    return const Color(0xFF2E7D32);
  }
  if (normalized.contains('shopping') || normalized.contains('shop')) {
    return const Color(0xFF7E57C2);
  }
  if (normalized.contains('transport') ||
      normalized.contains('car') ||
      normalized.contains('fuel') ||
      normalized.contains('gas') ||
      normalized.contains('taxi') ||
      normalized.contains('uber')) {
    return const Color(0xFF1E88E5);
  }
  if (normalized.contains('travel') || normalized.contains('flight') || normalized.contains('hotel')) {
    return const Color(0xFF00897B);
  }
  if (normalized.contains('subscription') || normalized.contains('streaming')) {
    return const Color(0xFFFB8C00);
  }
  if (normalized.contains('entertain') || normalized.contains('movie') || normalized.contains('game')) {
    return const Color(0xFFEC407A);
  }
  if (normalized.contains('health') || normalized.contains('medical') || normalized.contains('pharmacy')) {
    return const Color(0xFF8E24AA);
  }
  if (normalized.contains('salary')) {
    return const Color(0xFF1B5E20);
  }
  if (normalized.contains('other income') || normalized.contains('income')) {
    return const Color(0xFF66BB6A);
  }
  if (normalized.contains('other expense') || normalized == 'other' || normalized.contains('uncategorized')) {
    return const Color(0xFF757575);
  }

  // Custom categories: stable by id when available, else by name.
  final seed = (categoryId != null && categoryId.trim().isNotEmpty)
      ? categoryId.trim().toLowerCase()
      : normalized;
  var h = 5381;
  for (final unit in seed.codeUnits) {
    h = ((h << 5) + h + unit) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  return HSVColor.fromAHSV(1, hue, 0.55, 0.84).toColor();
}

Color categoryDisplayTintFor(
  String rawName, {
  String? categoryId,
  dynamic savedColor,
  double strength = 0.82,
}) {
  final base = categoryDisplayColorFor(
    rawName,
    categoryId: categoryId,
    savedColor: savedColor,
  );
  final s = strength.clamp(0.0, 1.0);
  return Color.lerp(base, Colors.white, s) ?? base.withValues(alpha: 0.2);
}

Color categoryDisplayDarkContainerFor(
  String rawName, {
  String? categoryId,
  dynamic savedColor,
  double depth = 0.82,
}) {
  final base = categoryDisplayColorFor(
    rawName,
    categoryId: categoryId,
    savedColor: savedColor,
  );
  final d = depth.clamp(0.0, 1.0);
  final mixed = Color.lerp(base, Colors.black, d) ?? base;
  return mixed.withValues(alpha: 1);
}

Color? _parseStoredColor(dynamic raw) {
  if (raw == null) return null;

  if (raw is Color) return raw;
  if (raw is int) return Color(raw);
  if (raw is num) return Color(raw.toInt());

  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  if (text.toLowerCase() == 'null') return null;

  final direct = int.tryParse(text);
  if (direct != null) return Color(direct);

  var hex = text.toLowerCase();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.startsWith('0x')) hex = hex.substring(2);
  if (hex.length == 6) hex = 'ff$hex';
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(value);
}

/// Compact grid of icon choices for dialogs.
class CategoryIconPickerGrid extends StatelessWidget {
  const CategoryIconPickerGrid({
    super.key,
    required this.selectedKey,
    required this.onSelected,
    this.accentColor,
  });

  final String selectedKey;
  final ValueChanged<String> onSelected;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Icon',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in kCategoryIconChoices)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(e.key),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selectedKey == e.key ? accent.withValues(alpha: 0.12) : surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedKey == e.key ? accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(e.icon, color: selectedKey == e.key ? accent : Colors.black87, size: 24),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
