import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:infaq/ui/infaq_widgets.dart';

const Color _kPrimary = Color(0xFF3F5F4A);
const Color _kMintHeader = Color(0xFFF0F8F0);

/// Contact targets — adjust to your real handles and numbers.
const String _kInstagramHandle = 'INFAQ.BH';
const String _kInstagramUrl = 'https://www.instagram.com/infaq.bh/';
const String _kWhatsappDisplay = '67676767';
const String _kWhatsappUrl = 'https://wa.me/97367676767';
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _kMintHeader,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
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
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF2C2C2C)),
                        ),
                        const Text(
                          'Help and support',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF2C2C2C),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(left: 8, right: 8),
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
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
                              size: 26,
                            ),
                          ),
                          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.black.withValues(alpha: 0.06)),
                          _ContactInkRow(
                            label: 'Whatsapp',
                            detail: _kWhatsappDisplay,
                            onTap: () => _launch(_kWhatsappUrl),
                            trailing: FaIcon(
                              FontAwesomeIcons.whatsapp,
                              color: const Color(0xFF25D366),
                              size: 26,
                            ),
                          ),
                          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.black.withValues(alpha: 0.06)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Email',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                    color: Colors.black.withValues(alpha: 0.75),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _launch(_kEmailLaunch),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _kEmailDisplay,
                                            style: const TextStyle(
                                              decoration: TextDecoration.underline,
                                              decorationColor: Color(0xFF5C6BC0),
                                              color: Color(0xFF3F5F4A),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        Icon(Icons.mail_outline_rounded, color: _kPrimary.withValues(alpha: 0.85), size: 26),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                onTap: () => _launch(_kWhatsappUrl),
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'chat with us',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black.withValues(alpha: 0.45),
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
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
                          'v0.1.0',
                          style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.35)),
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
                            color: _kPrimary,
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
    );
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
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: Colors.black.withValues(alpha: 0.75),
                ),
              ),
            ),
            Expanded(
              child: Text(
                detail,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black.withValues(alpha: 0.42),
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
