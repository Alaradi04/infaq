import 'package:flutter/material.dart';

const String kInfaqAppVersionLabel = '6.7.2';
const String kInfaqWebsiteLabel = 'www.infaqbh.com';
const String kInfaqContactEmail = 'contact@infaqbh.com';
const String kInfaqSupportMailto =
    'mailto:contact@infaqbh.com?subject=INFAQ%20support';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);
    final bodyColor = cs.onSurface.withValues(alpha: 0.88);
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface),
                    ),
                    Expanded(
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
              children: [
                _p(
                  'INFAQ values your privacy and is committed to protecting your personal and financial information.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'We only collect the information necessary to provide features such as expense tracking, budgeting insights, goals, subscriptions, and automatic transaction recording.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'Your financial data is stored securely using Supabase and is never sold to third parties.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'If automatic transaction recording is enabled, INFAQ may process bank notification content locally on your device to detect transactions. Only relevant transaction data is used for financial management features.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'AI-powered insights may analyze spending behavior to generate personalized recommendations and financial summaries.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'INFAQ does not access unnecessary personal content such as private chats, photos, or unrelated notifications.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'Users can edit or delete their data at any time from within the application.',
                  bodyColor,
                ),
                _gap(),
                _p(
                  'By using INFAQ, you agree to this privacy policy.',
                  bodyColor,
                ),
                const SizedBox(height: 28),
                Text('Contact', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(kInfaqContactEmail, style: TextStyle(fontSize: 15, color: muted)),
                const SizedBox(height: 16),
                Text('Website', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(kInfaqWebsiteLabel, style: TextStyle(fontSize: 15, color: muted)),
                const SizedBox(height: 16),
                Text('Version', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(kInfaqAppVersionLabel, style: TextStyle(fontSize: 15, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _p(String s, Color c) => Text(s, style: TextStyle(fontSize: 15, height: 1.45, color: c));

  Widget _gap() => const SizedBox(height: 14);
}

class AboutInfaqScreen extends StatelessWidget {
  const AboutInfaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);
    final bodyColor = cs.onSurface.withValues(alpha: 0.88);
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface),
                    ),
                    Expanded(
                      child: Text(
                        'About INFAQ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
              children: [
                Text(
                  'INFAQ is an AI-powered personal financial management application designed to help users track expenses, manage subscriptions, monitor goals, and better understand their spending habits.',
                  style: TextStyle(fontSize: 15, height: 1.45, color: bodyColor),
                ),
                const SizedBox(height: 14),
                Text(
                  'The app combines automation, smart insights, and sustainability awareness to make financial management simpler and more personalized.',
                  style: TextStyle(fontSize: 15, height: 1.45, color: bodyColor),
                ),
                const SizedBox(height: 20),
                Text(
                  'Features include:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                ),
                const SizedBox(height: 10),
                _bullet('Automatic transaction recording', bodyColor),
                _bullet('Expense categorization', bodyColor),
                _bullet('Smart financial insights', bodyColor),
                _bullet('Subscription tracking', bodyColor),
                _bullet('Goal management', bodyColor),
                _bullet('Environmental impact awareness', bodyColor),
                const SizedBox(height: 20),
                Text(
                  'Developed using:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                ),
                const SizedBox(height: 10),
                _bullet('Flutter', bodyColor),
                _bullet('Supabase', bodyColor),
                _bullet('AI-powered services', bodyColor),
                const SizedBox(height: 28),
                Text('Contact', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(kInfaqContactEmail, style: TextStyle(fontSize: 15, color: muted)),
                const SizedBox(height: 16),
                Text('Website', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(kInfaqWebsiteLabel, style: TextStyle(fontSize: 15, color: muted)),
                const SizedBox(height: 16),
                Text('Version', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(kInfaqAppVersionLabel, style: TextStyle(fontSize: 15, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(fontSize: 15, height: 1.4, color: c)),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, height: 1.4, color: c))),
        ],
      ),
    );
  }
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _items = <({String q, String a})>[
    (
      q: 'How does automatic transaction recording work?',
      a:
          'INFAQ can detect supported bank transaction notifications and automatically record expenses and income securely on your device.',
    ),
    (
      q: 'Does INFAQ access my private messages?',
      a: 'No. INFAQ only processes supported financial notifications needed for transaction recording.',
    ),
    (
      q: 'Why are some transactions categorized automatically?',
      a:
          'INFAQ uses local rules and AI-powered categorization to organize transactions into useful categories.',
    ),
    (
      q: 'Can I edit or recategorize transactions?',
      a: 'Yes. Transactions can be edited, deleted, and recategorized anytime.',
    ),
    (
      q: 'Why do some transactions not show environmental impact?',
      a:
          'Transfers, income, and unsupported purchases may not have enough information for environmental impact classification.',
    ),
    (
      q: 'Is my data secure?',
      a:
          'Yes. User data is securely stored and protected using Supabase authentication and database security.',
    ),
    (
      q: 'How can I contact INFAQ?',
      a: 'Email us at $kInfaqContactEmail for account help, feedback, or support.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface),
                    ),
                    Expanded(
                      child: Text(
                        'FAQ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  Material(
                    color: Colors.transparent,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: cs.outline.withValues(alpha: 0.2),
                        splashColor: cs.primary.withValues(alpha: 0.08),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          _items[i].q,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.3,
                            color: cs.onSurface,
                          ),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _items[i].a,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: cs.onSurface.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (i < _items.length - 1)
                    Divider(height: 1, indent: 12, endIndent: 12, color: cs.outline.withValues(alpha: 0.15)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
