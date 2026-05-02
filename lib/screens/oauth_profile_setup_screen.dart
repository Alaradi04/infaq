import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/ui/infaq_widgets.dart';

/// After Google (or other OAuth) sign-in, collect profile fields that match the `users` table
/// before opening the home dashboard. Shown only when there is no `users` row yet.
class OAuthProfileSetupScreen extends StatefulWidget {
  const OAuthProfileSetupScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OAuthProfileSetupScreen> createState() => _OAuthProfileSetupScreenState();
}

class _OAuthProfileSetupScreenState extends State<OAuthProfileSetupScreen> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  String? _currency = 'BHD';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    final guess = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
    if (guess.isNotEmpty) {
      _name.text = guess;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      showInfaqSnack(context, 'Session expired. Please sign in again.');
      return;
    }

    final name = _name.text.trim();
    if (name.isEmpty) {
      showInfaqSnack(context, 'Please enter your name.');
      return;
    }

    final balanceText = _balance.text.trim();
    if (balanceText.isEmpty) {
      showInfaqSnack(context, 'Enter your current balance.');
      return;
    }
    final parsedBalance = double.tryParse(balanceText.replaceAll(',', ''));
    if (parsedBalance == null || parsedBalance < 0) {
      showInfaqSnack(context, 'Balance must be a valid non‑negative number.');
      return;
    }

    final email = (user.email ?? '').trim();
    final usernameFromEmail = email.contains('@') ? email.split('@').first : email;
    final safeUsername =
        usernameFromEmail.isNotEmpty ? usernameFromEmail : 'user_${user.id.substring(0, 6)}';

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.from('users').upsert(
        <String, Object?>{
          'id': user.id,
          'name': name,
          'username': safeUsername,
          'currency': _currency ?? 'BHD',
          'Balance': parsedBalance,
        },
        onConflict: 'id',
      );

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'name': name,
            'full_name': name,
            'username': safeUsername,
            'currency': _currency ?? 'BHD',
            'balance': parsedBalance,
            'registration_synced': true,
          },
        ),
      );

      if (!mounted) return;
      widget.onComplete();
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, 'Could not save profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            InfaqHeader(
              showBack: true,
              onBack: _signOut,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create account',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start your journey to better financial health',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('name'),
                  InfaqPillField(
                    controller: _name,
                    hintText: 'full name (e.g., Ahmed Ali)',
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('currency'),
                  Container(
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
                    child: SizedBox(
                      width: double.infinity,
                      child: DropdownMenu<String>(
                        key: ValueKey<String?>(_currency),
                        initialSelection: _currency,
                        expandedInsets: EdgeInsets.zero,
                        onSelected: (v) => setState(() => _currency = v),
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(value: 'BHD', label: 'BHD'),
                          DropdownMenuEntry(value: 'USD', label: 'USD'),
                          DropdownMenuEntry(value: 'EUR', label: 'EUR'),
                          DropdownMenuEntry(value: 'GBP', label: 'GBP'),
                          DropdownMenuEntry(value: 'SAR', label: 'SAR'),
                        ],
                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: const Color(0xFFF7F8F7),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Current balance'),
                  InfaqPillField(
                    controller: _balance,
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  InfaqPrimaryButton(
                    label: 'Continue',
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : _signOut,
                      child: Text(
                        'Use a different account',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
