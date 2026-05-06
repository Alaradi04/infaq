import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:infaq/ui/infaq_widgets.dart';

/// Contact targets — adjust to your real handles and numbers.
const String _kInstagramHandle = 'INFAQ.BH';
const String _kInstagramUrl = 'https://www.instagram.com/infaq.bh/';
const String _kWebsiteDisplay = 'www.infaqbh.com';
const String _kWebsiteUrl = 'https://www.infaqbh.com';
const String _kEmailDisplay = 'INFAQ.BH@Gmail.com';
const String _kEmailLaunch = 'mailto:Infaq.bh@gmail.com?subject=INFAQ%20support';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {}
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);
    final statusStyle = SystemUiOverlayStyle(
      statusBarColor: headerBg,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: cs.surface,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: statusStyle,
      child: Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.primary),
                        ),
                        Text(
                          'Help and support',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(left: 8, right: 8),
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: isDark ? 0.25 : 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _ContactInkRow(
                            label: 'Instagram',
                            detail: _kInstagramHandle,
                            onTap: () => _launch(_kInstagramUrl),
                            trailing: FaIcon(
                              FontAwesomeIcons.instagram,
                              color: const Color(0xFFE4405F),
                              size: 22,
                            ),
                          ),
                          Divider(height: 1, indent: 16, endIndent: 16, color: cs.outline.withValues(alpha: 0.2)),
                          _ContactInkRow(
                            label: 'Website',
                            detail: _kWebsiteDisplay,
                            onTap: () => _launch(_kWebsiteUrl),
                            trailing: Icon(
                              Icons.language_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          Divider(height: 1, indent: 16, endIndent: 16, color: cs.outline.withValues(alpha: 0.2)),
                          _ContactInkRow(
                            label: 'Email',
                            detail: _kEmailDisplay,
                            onTap: () => _launch(_kEmailLaunch),
                            trailing: Icon(
                              Icons.mail_outline_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'v6.7.2',
                          style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.45)),
                        ),
                        const SizedBox(height: 20),
                        Image.asset(
                          kInfaqBrandIconAsset,
                          height: 88,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'INFAQ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                            fontFamily: 'Georgia',
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ));
  }
}

class _ContactInkRow extends StatelessWidget {
  const _ContactInkRow({
    required this.label,
    required this.detail,
    required this.onTap,
    required this.trailing,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
            Expanded(
              child: Text(
                detail,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
