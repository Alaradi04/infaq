import 'package:flutter/material.dart';

class DataPrivacyScreen extends StatelessWidget {
  const DataPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Data and privacy'),
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: const [
            _PolicyTitle('Privacy Policy'),
            SizedBox(height: 6),
            _PolicyBody('Last Updated: 6/5/2026'),
            SizedBox(height: 16),
            _PolicyBody(
              'Welcome to Infaq.\n'
              'Your privacy is important to us. This Privacy Policy explains how we collect, use, '
              'and protect your information when you use our application.',
            ),
            SizedBox(height: 18),
            _PolicySection(
              title: 'Information We Collect',
              body:
                  'We may collect the following types of information:\n\n'
                  'Personal Information\n'
                  'Name\n'
                  'Email address\n'
                  'Profile picture\n'
                  'Phone number, if provided by you\n'
                  'Usage Information\n'
                  'App activity\n'
                  'Features you use\n'
                  'Time spent in the app\n'
                  'Device type and operating system\n'
                  'IP address or general location\n'
                  'User-Provided Content\n'
                  'Any text, images, files, or other content you upload, create, or store inside the app',
            ),
            _PolicySection(
              title: 'How We Use Your Information',
              body:
                  'We use your information to:\n\n'
                  'Provide and maintain the app\n'
                  'Improve app performance and user experience\n'
                  'Personalize features and content\n'
                  'Respond to support requests\n'
                  'Send important updates related to the app\n'
                  'Protect the security of the app and its users',
            ),
            _PolicySection(
              title: 'Data Sharing',
              body:
                  'We do not sell your personal information.\n'
                  'We may share your information only in the following cases:\n\n'
                  'With service providers that help us operate the app\n'
                  'When required by law or legal process\n'
                  'To protect our rights, users, or app security',
            ),
            _PolicySection(
              title: 'Data Storage and Security',
              body:
                  'We take reasonable measures to protect your information from unauthorized access, '
                  'loss, misuse, or disclosure.\n'
                  'However, no method of transmission or storage is completely secure, so we cannot '
                  'guarantee absolute security.',
            ),
            _PolicySection(
              title: 'User Accounts',
              body:
                  'If you create an account in Infaq, you are responsible for keeping your login '
                  'credentials secure.\n'
                  'Please do not share your password with others.',
            ),
            _PolicySection(
              title: 'Third-Party Services',
              body:
                  'Infaq may use third-party services such as:\n\n'
                  'Authentication providers\n'
                  'Analytics tools\n'
                  'Cloud storage services\n'
                  'Payment-related services, if applicable\n\n'
                  'These third parties may collect and process information according to their own '
                  'privacy policies.',
            ),
            _PolicySection(
              title: 'Cookies and Similar Technologies',
              body:
                  'If applicable, we may use cookies or similar technologies to improve app '
                  'functionality, remember preferences, and analyze usage.',
            ),
            _PolicySection(
              title: 'Your Rights',
              body:
                  'Depending on your location, you may have the right to:\n\n'
                  'Access your personal data\n'
                  'Correct inaccurate information\n'
                  'Request deletion of your data\n'
                  'Withdraw consent where applicable\n\n'
                  'To request any of these, please contact us at: infaq.bh@gmail.com',
            ),
            _PolicySection(
              title: 'Data Retention',
              body:
                  'We keep your information only for as long as necessary to provide the app and '
                  'meet legal or operational requirements.',
            ),
            _PolicySection(
              title: 'Children\'s Privacy',
              body:
                  'Infaq is not intended for children without parental or guardian consent.\n'
                  'We do not knowingly collect personal information from children where prohibited by law.',
            ),
            _PolicySection(
              title: 'Changes to This Privacy Policy',
              body:
                  'We may update this Privacy Policy from time to time.\n'
                  'Any changes will be posted in the app with the updated effective date.',
            ),
            _PolicySection(
              title: 'Contact Us',
              body:
                  'If you have any questions about this Privacy Policy, please contact us at:\n\n'
                  'App Name: Infaq\n'
                  'Email: infaq.bh@gmail.com',
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyTitle extends StatelessWidget {
  const _PolicyTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _PolicyBody(body),
        ],
      ),
    );
  }
}

class _PolicyBody extends StatelessWidget {
  const _PolicyBody(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: onSurface.withValues(alpha: 0.85),
      ),
    );
  }
}
