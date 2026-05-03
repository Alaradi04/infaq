import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:infaq/screens/data_privacy_screen.dart';
import 'package:infaq/screens/login_screen.dart';
import 'package:infaq/screens/register_flow_screen.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// First screen for signed-out users: marketing highlights and paths to sign up / sign in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const Color _kPrimary = Color(0xFF3F5F4A);
  static const Color _kIconTileBg = Color(0xFFE8F4EA);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
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
              const Text(
                'INFAQ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: _kPrimary,
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
                      MaterialPageRoute<void>(builder: (_) => const RegisterFlowScreen()),
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
                        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kPrimary,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    child: const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _LegalFooter(),
            ],
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Color(0x223F5F4A), blurRadius: 14, offset: Offset(0, 6)),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: WelcomeScreen._kIconTileBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: WelcomeScreen._kPrimary, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B1B1B),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: Colors.black.withValues(alpha: 0.52),
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
        showInfaqSnack(context, 'Terms of Service: contact support or visit our site for the full document.');
      };
    _privacyTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const DataPrivacyScreen()),
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
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: Colors.black.withValues(alpha: 0.42),
    );
    final linkStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: WelcomeScreen._kPrimary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: WelcomeScreen._kPrimary.withValues(alpha: 0.6),
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(text: 'Terms of Service', style: linkStyle, recognizer: _termsTap),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: linkStyle, recognizer: _privacyTap),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
