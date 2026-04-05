import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:infaq/ui/infaq_bottom_nav.dart';

/// Dark green for primary actions (mock ~#3D5C45 / app seed).
const Color kServiceFormGreen = kInfaqPrimaryGreen;

BoxDecoration infaqServicePillDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(24),
    border: isDark ? Border.all(color: cs.outline.withValues(alpha: 0.22)) : null,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.09),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

class InfaqServiceFormHeader extends StatelessWidget {
  const InfaqServiceFormHeader({
    super.key,
    required this.backgroundColor,
    required this.title,
    required this.onBack,
  });

  final Color backgroundColor;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 18),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: primary),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class InfaqLabeledPillField extends StatelessWidget {
  const InfaqLabeledPillField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class InfaqPillTextField extends StatelessWidget {
  const InfaqPillTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: infaqServicePillDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        onChanged: onChanged,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

class InfaqPillAmountStepper extends StatelessWidget {
  const InfaqPillAmountStepper({
    super.key,
    required this.controller,
    required this.onChanged,
    this.currencySuffix,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? currencySuffix;

  void _nudge(double delta) {
    final raw = controller.text.replaceAll(',', '').replaceAll(r'$', '').trim();
    var v = double.tryParse(raw) ?? 0;
    v = (v + delta).clamp(0, 1e15);
    if (v % 1 == 0) {
      controller.text = v.toStringAsFixed(0);
    } else {
      controller.text = v.toStringAsFixed(2);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: infaqServicePillDecoration(context),
      padding: const EdgeInsets.only(left: 18, right: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
              decoration: InputDecoration(
                border: InputBorder.none,
                suffixText: currencySuffix,
                suffixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
                onPressed: () => _nudge(1),
                icon: Icon(Icons.keyboard_arrow_up_rounded, color: onSurface.withValues(alpha: 0.55)),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
                onPressed: () => _nudge(-1),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class InfaqPillDropdown<T> extends StatelessWidget {
  const InfaqPillDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: infaqServicePillDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: hint != null ? Text(hint!, style: TextStyle(color: onSurface.withValues(alpha: 0.4))) : null,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: primary),
          borderRadius: BorderRadius.circular(16),
          items: items,
          onChanged: onChanged,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
        ),
      ),
    );
  }
}

class InfaqPillDateRow extends StatelessWidget {
  const InfaqPillDateRow({
    super.key,
    required this.labelText,
    required this.onTap,
  });

  final String labelText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: infaqServicePillDecoration(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labelText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.calendar_month_rounded, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InfaqPillSwitchRow extends StatelessWidget {
  const InfaqPillSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.leading,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: infaqServicePillDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: kServiceFormGreen,
            inactiveTrackColor: onSurface.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}

String formatGoalDateLong(DateTime d) {
  const months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  return '${months[d.month - 1]} ${d.day} ${d.year}';
}
