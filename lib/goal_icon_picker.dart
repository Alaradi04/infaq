import 'package:flutter/material.dart';
import 'package:infaq/category/category_icons.dart';

/// Icons offered when creating or editing a goal.
const List<IconData> kGoalPaletteIcons = [
  Icons.menu_book_rounded,
  Icons.phone_iphone_rounded,
  Icons.directions_car_filled_rounded,
  Icons.flight_takeoff_rounded,
  Icons.home_rounded,
  Icons.savings_outlined,
  Icons.school_rounded,
  Icons.favorite_rounded,
  Icons.laptop_mac_rounded,
];

const List<Color> kGoalIconColors = kCategoryColorPalette;

void showGoalIconPickerSheet(
  BuildContext context, {
  required IconData selectedIcon,
  required Color selectedColor,
  required void Function(IconData, Color) onSelected,
}) {
  final cs = Theme.of(context).colorScheme;
  var localColor = selectedColor;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final outline = Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.28);
      return StatefulBuilder(
        builder: (context, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                'Goal icon',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                'Icon',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final ic in kGoalPaletteIcons)
                    InkWell(
                      onTap: () {
                        onSelected(ic, localColor);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: ic == selectedIcon ? localColor.withValues(alpha: 0.16) : Colors.transparent,
                          border: Border.all(
                            color: ic == selectedIcon ? localColor.withValues(alpha: 0.5) : outline,
                            width: ic == selectedIcon ? 2 : 1,
                          ),
                        ),
                        child: Icon(ic, color: localColor, size: 26),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text(
                'Color',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in kGoalIconColors)
                    InkWell(
                      onTap: () {
                        setLocal(() => localColor = c);
                        onSelected(selectedIcon, c);
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == localColor ? cs.onSurface : c.withValues(alpha: 0.4),
                            width: c == localColor ? 2.2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      );
    },
  );
}
