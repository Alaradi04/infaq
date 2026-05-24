import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:infaq/screens/login_screen.dart';
import 'package:infaq/screens/profile_info_screens.dart';
import 'package:infaq/screens/register_flow_screen.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// First screen for signed-out users: marketing highlights and paths to sign up / sign in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const Color _kPrimaryLight = Color(0xFF3F5F4A);
  static const Color _kIconTileBgLight = Color(0xFFE8F4EA);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final scaffoldBg = isDark ? cs.surface : Colors.white;
    final brandColor = isDark ? cs.primary : _kPrimaryLight;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: scaffoldBg,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Image.asset(
                    kInfaqBrandIconAsset,
                    height: 88,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'INFAQ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: brandColor,
                    fontFamily: 'Georgia',
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 32),
                const _FeatureRow(
                  icon: Icons.trending_up_rounded,
                  title: 'Track Your Spending',
                  subtitle: 'Monitor expenses and stay within budget',
                ),
                const SizedBox(height: 18),
                const _FeatureRow(
                  icon: Icons.auto_awesome_rounded,
                  title: 'AI-Powered Insights',
                  subtitle: 'Get smart analysis of your spending habits',
                ),
                const SizedBox(height: 18),
                const _FeatureRow(
                  icon: Icons.eco_rounded,
                  title: 'Sustainability Tips',
                  subtitle: 'Make eco-friendly financial choices',
                ),
                const SizedBox(height: 36),
                _ShadowPill(
                  child: InfaqPrimaryButton(
                    label: 'Sign up',
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegisterFlowScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _ShadowPill(
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: brandColor,
                        backgroundColor:
                            isDark ? cs.surfaceContainerHighest : Colors.white,
                        side: BorderSide(
                          color: isDark
                              ? cs.outline.withValues(alpha: 0.45)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const _LegalFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShadowPill extends StatelessWidget {
  const _ShadowPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: isDark
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x223F5F4A),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconTileBg =
        isDark ? cs.surfaceContainerHighest : WelcomeScreen._kIconTileBgLight;
    final iconColor = isDark ? cs.primary : WelcomeScreen._kPrimaryLight;
    final titleColor = isDark ? cs.onSurface : const Color(0xFF1B1B1B);
    final subtitleColor = isDark
        ? cs.onSurface.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.52);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: iconTileBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: subtitleColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegalFooter extends StatefulWidget {
  const _LegalFooter();

  @override
  State<_LegalFooter> createState() => _LegalFooterState();
}

class _LegalFooterState extends State<_LegalFooter> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () {
        showInfaqSnack(
          context,
          'Terms of Service: contact $kInfaqContactEmail or visit $kInfaqWebsiteLabel for the full document.',
        );
      };
    _privacyTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
        );
      };
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final linkColor =
        isDark ? cs.primary : WelcomeScreen._kPrimaryLight;
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: isDark
          ? cs.onSurface.withValues(alpha: 0.55)
          : Colors.black.withValues(alpha: 0.42),
    );
    final linkStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: linkColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: linkColor.withValues(alpha: 0.6),
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms of Service',
            style: linkStyle,
            recognizer: _termsTap,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacyTap,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
