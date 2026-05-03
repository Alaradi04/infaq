import 'package:flutter/material.dart';

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
  required ValueChanged<IconData> onSelected,
}) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
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
                          border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.25)),
                        ),
                        child: Icon(ic, color: Theme.of(ctx).colorScheme.primary),
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
