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
                _p('Last updated: May 2026', muted),
                _gap(),
                _p(
                  'Welcome to INFAQ.\n\n'
                  'Your privacy matters to us. INFAQ is designed to help users manage their finances in a secure and transparent way. '
                  'This Privacy Policy explains what information we collect, how it is used, and how we protect it.',
                  bodyColor,
                ),
                _gap(),
                _h('Information We Collect', cs),
                _bullet(
                  const [
                    'Profile information such as name, email address, preferred currency, and profile photo',
                    'Financial records created inside the app, including transactions, subscriptions, goals, and categories',
                    'Notification content only when the user grants notification access permission',
                    'App preferences such as theme settings and notification settings',
                  ],
                  bodyColor,
                ),
                _gap(),
                _h('Notification Access', cs),
                _p(
                  'INFAQ may request notification access to automatically detect and record financial transactions from supported banking notifications.\n\n'
                  'The app only attempts to process financial notifications from supported banking and payment services. '
                  'Non-financial notifications are ignored whenever possible.',
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _bullet(
                  const [
                    'transaction detection',
                    'transaction categorization',
                    'balance updates',
                    'financial insights',
                  ],
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _p(
                  'INFAQ does not read personal chats, messages, or unrelated notifications for advertising or tracking purposes.',
                  bodyColor,
                ),
                _gap(),
                _h('AI Features', cs),
                _p('INFAQ uses AI-powered features to provide:', bodyColor),
                const SizedBox(height: 8),
                _bullet(
                  const [
                    'spending insights',
                    'smart categorization',
                    'sustainability analysis',
                    'financial recommendations',
                  ],
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _p(
                  'Some transaction or analytics data may be securely processed through AI services to generate these insights.\n\n'
                  'AI-generated content is informational only and should not be considered professional financial advice.',
                  bodyColor,
                ),
                _gap(),
                _h('Data Storage and Security', cs),
                _p(
                  'Your data is securely stored using Supabase cloud infrastructure and protected through authentication and database security rules.\n\n'
                  'We take reasonable measures to:',
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _bullet(
                  const [
                    'protect user information',
                    'prevent unauthorized access',
                    'secure stored financial data',
                  ],
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _p('However, no online system can guarantee absolute security.', bodyColor),
                _gap(),
                _h('Data Sharing', cs),
                _p(
                  'INFAQ does not sell your personal data.\n\n'
                  'We do not share your financial information with third parties except when required for:',
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _bullet(
                  const [
                    'app functionality',
                    'secure cloud storage',
                    'authentication',
                    'AI processing needed for app features',
                  ],
                  bodyColor,
                ),
                _gap(),
                _h('User Control', cs),
                _p('You may:', bodyColor),
                const SizedBox(height: 8),
                _bullet(
                  const [
                    'edit or delete your transactions',
                    'disable notification access',
                    'delete your account',
                    'request removal of your stored data',
                  ],
                  bodyColor,
                ),
                _gap(),
                _h('Third-Party Services', cs),
                _p('INFAQ may use trusted third-party services such as:', bodyColor),
                const SizedBox(height: 8),
                _bullet(
                  const [
                    'Supabase',
                    'Google Sign-In',
                    'AI providers used for insights and categorization',
                  ],
                  bodyColor,
                ),
                const SizedBox(height: 8),
                _p(
                  'These services may process limited data necessary for app functionality.',
                  bodyColor,
                ),
                _gap(),
                _h("Children's Privacy", cs),
                _p('INFAQ is not intended for children under 13 years old.', bodyColor),
                _gap(),
                _h('Changes to This Policy', cs),
                _p(
                  'This Privacy Policy may be updated over time. Continued use of the app after updates means you accept the revised policy.',
                  bodyColor,
                ),
                _gap(),
                _h('Contact Us', cs),
                _p(
                  'If you have questions or concerns about privacy or data usage, contact us at:',
                  bodyColor,
                ),
                const SizedBox(height: 8),
                Text(
                  kInfaqContactEmail,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Version $kInfaqAppVersionLabel',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _p(String s, Color c) => Text(s, style: TextStyle(fontSize: 15, height: 1.45, color: c));

  Widget _h(String s, ColorScheme cs) {
    return Text(
      s,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: cs.onSurface,
      ),
    );
  }

  Widget _bullet(List<String> lines, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '• $line',
              style: TextStyle(fontSize: 15, height: 1.4, color: c),
            ),
          ),
      ],
    );
  }

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
          'When enabled, INFAQ reads supported bank transaction notifications and extracts only relevant financial fields (amount, type, timestamp, merchant) for recording.',
    ),
    (
      q: 'Why do I need notification permission?',
      a: 'Notification access is required for automatic transaction recording. You can disable it anytime in Notification Settings.',
    ),
    (
      q: 'Is my transaction data private?',
      a: 'Yes. Your transaction data is tied to your account, protected by authentication, and is not sold by INFAQ.',
    ),
    (
      q: 'Does INFAQ sell user data?',
      a: 'No. INFAQ does not sell personal or financial data.',
    ),
    (
      q: 'How do subscriptions work?',
      a: 'You can add recurring subscriptions, track upcoming payments, and edit or remove subscriptions at any time.',
    ),
    (
      q: 'How do goals work?',
      a: 'Goals let you set targets, track progress, and monitor saved amounts against your deadline.',
    ),
    (
      q: 'Can I edit or recategorize transactions?',
      a: 'Yes. Transactions can be edited, recategorized, or deleted from the app.',
    ),
    (
      q: 'Why do some transactions not show environmental impact?',
      a: 'Transfers, income, or unsupported purchase descriptions may not have enough data for environmental classification.',
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
