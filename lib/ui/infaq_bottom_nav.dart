import 'package:flutter/material.dart';

/// App primary green (labels, selected tab).
const Color kInfaqPrimaryGreen = Color(0xFF4D6658);

/// Center CTA on the bottom bar.
const Color kInfaqNavCenterGreen = Color(0xFF4A6356);

/// Bottom navigation: white rounded bar + raised center add button.
class InfaqBottomNavBar extends StatelessWidget {
  const InfaqBottomNavBar({
    super.key,
    required this.tabIndex,
    required this.onHome,
    required this.onCurrency,
    required this.onAdd,
    required this.onAnalytics,
    required this.onProfile,
  });

  final int tabIndex;
  final VoidCallback onHome;
  final VoidCallback onCurrency;
  final VoidCallback onAdd;
  final VoidCallback onAnalytics;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    Color iconColor(bool selected) => selected ? primary : muted;

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.45 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: SizedBox(
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: InfaqNavIconButton(
                          tooltip: 'Home',
                          selected: tabIndex == 0,
                          onPressed: onHome,
                          child: Icon(
                            Icons.home_outlined,
                            size: 24,
                            color: iconColor(tabIndex >= 0 && tabIndex == 0),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InfaqNavIconButton(
                          tooltip: 'Currency',
                          selected: tabIndex == 1,
                          onPressed: onCurrency,
                          child: Text(
                            r'$',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: iconColor(tabIndex >= 0 && tabIndex == 1),
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 56),
                      Expanded(
                        child: InfaqNavIconButton(
                          tooltip: 'Analytics',
                          selected: tabIndex == 2,
                          onPressed: onAnalytics,
                          child: Icon(
                            Icons.show_chart_rounded,
                            size: 24,
                            color: iconColor(tabIndex >= 0 && tabIndex == 2),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InfaqNavIconButton(
                          tooltip: 'Profile',
                          selected: tabIndex == 3,
                          onPressed: onProfile,
                          child: Icon(
                            Icons.person_outline_rounded,
                            size: 24,
                            color: iconColor(tabIndex >= 0 && tabIndex == 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -10),
                child: Material(
                  color: primary,
                  borderRadius: BorderRadius.circular(18),
                  elevation: 5,
                  shadowColor: Colors.black38,
                  child: InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(18),
                    child: const SizedBox(
                      width: 50,
                      height: 50,
                      child: Icon(Icons.add, color: Colors.white, size: 25),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InfaqNavIconButton extends StatelessWidget {
  const InfaqNavIconButton({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        child: SizedBox(
          height: 40,
          child: Center(child: child),
        ),
      ),
    );
  }
}
