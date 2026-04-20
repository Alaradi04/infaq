import 'package:flutter/material.dart';

/// Default when [validatedCategoryIconKey] receives null/unknown.
const String kDefaultCategoryIconKey = 'category';

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

/// Icon for list UI: uses DB [iconKey] when set, otherwise guesses from [name] / [type].
IconData categoryIconForDisplay({
  String? iconKey,
  required String name,
  required String type,
}) {
  final fromDb = _iconFromStoredKey(iconKey);
  if (fromDb != null) return fromDb;
  return _categoryIconFallback(name, type);
}

IconData _categoryIconFallback(String name, String type) {
  final n = name.toLowerCase();
  final t = type.toLowerCase();
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
  if (n.contains('transport') || n.contains('car') || n.contains('fuel') || n.contains('parking')) {
    return Icons.directions_car_outlined;
  }
  if (n.contains('shop') || n.contains('clothes') || n.contains('retail')) {
    return Icons.shopping_cart_outlined;
  }
  if (n.contains('entertain') || n.contains('game') || n.contains('stream')) {
    return Icons.movie_outlined;
  }
  if (n.contains('bill') || n.contains('util') || n.contains('electric') || n.contains('water')) {
    return Icons.receipt_long_outlined;
  }
  if (n.contains('health') || n.contains('medical') || n.contains('pharm')) {
    return Icons.favorite_border_rounded;
  }
  if (n.contains('home') || n.contains('rent') || n.contains('mortgage')) {
    return Icons.home_outlined;
  }
  if (n.contains('education') || n.contains('school') || n.contains('tuition')) {
    return Icons.school_outlined;
  }
  return Icons.folder_outlined;
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
