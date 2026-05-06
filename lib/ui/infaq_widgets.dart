import 'package:flutter/material.dart';

/// Bundled wallet brand mark (`assets/`).
const String kInfaqBrandIconAsset = 'assets/infaq_icon.jpeg';

class InfaqHeader extends StatelessWidget {
  const InfaqHeader({super.key, this.showBack = false, this.onBack});

  final bool showBack;
  /// When set, replaces the default [Navigator.maybePop] behavior (e.g. multi-step flows).
  final VoidCallback? onBack;

  static const Color _kBrandGreen = Color(0xFF4D6658);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final Widget leading;
    var hasBackControl = false;
    if (!showBack) {
      leading = const SizedBox.shrink();
    } else if (onBack != null) {
      hasBackControl = true;
      leading = IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _kBrandGreen),
      );
    } else if (canPop) {
      hasBackControl = true;
      leading = IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _kBrandGreen),
      );
    } else {
      leading = const SizedBox.shrink();
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            if (hasBackControl) const SizedBox(width: 8),
            Image.asset(
              kInfaqBrandIconAsset,
              height: 38,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 10),
            const Text(
              'INFAQ',
              style: TextStyle(
                fontSize: 22,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: _kBrandGreen,
                fontFamily: 'Georgia',
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class InfaqPillField extends StatelessWidget {
  const InfaqPillField({
    super.key,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x223F5F4A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofillHints: autofillHints,
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: const Color(0xFFF7F8F7),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class InfaqPrimaryButton extends StatelessWidget {
  const InfaqPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF4D6658);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class InfaqTextButton extends StatelessWidget {
  const InfaqTextButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4D6658),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

void showInfaqSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

