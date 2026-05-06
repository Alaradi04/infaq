import 'package:flutter/material.dart';

import 'package:infaq/ui/infaq_service_form_widgets.dart';

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

void showGoalIconPickerSheet(
  BuildContext context, {
  required IconData selectedIcon,
  required ValueChanged<IconData> onSelected,
}) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final outline = Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.28);
      return SafeArea(
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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final ic in kGoalPaletteIcons)
                    InkWell(
                      onTap: () {
                        onSelected(ic);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: ic == selectedIcon
                              ? kServiceFormGreen.withValues(alpha: 0.16)
                              : Colors.transparent,
                          border: Border.all(
                            color: ic == selectedIcon
                                ? kServiceFormGreen.withValues(alpha: 0.5)
                                : outline,
                            width: ic == selectedIcon ? 2 : 1,
                          ),
                        ),
                        child: Icon(ic, color: kServiceFormGreen, size: 26),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
