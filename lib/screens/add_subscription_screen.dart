import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Pale cream header (reference mock).
const Color _kSubHeaderCream = Color(0xFFFFF6E8);

class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key, this.currencyCode});

  final String? currencyCode;

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _cycle = 'monthly';
  DateTime _nextDate = DateTime.now();
  bool _saving = false;

  static const _cycles = [
    ('monthly', 'Monthly'),
    ('yearly', 'Yearly'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String? _currencySuffix() {
    switch (widget.currencyCode?.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return null;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: kServiceFormGreen)),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _nextDate = picked);
  }

  void _cancel() => Navigator.pop(context);

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').replaceAll(r'$', ''));
    if (name.isEmpty) {
      showInfaqSnack(context, 'Enter a name for this subscription.');
      return;
    }
    if (amount == null || amount <= 0) {
      showInfaqSnack(context, 'Enter an amount greater than zero.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      showInfaqSnack(context, 'You are not signed in.');
      return;
    }

    setState(() => _saving = true);
    try {
      final dateStr =
          '${_nextDate.year.toString().padLeft(4, '0')}-${_nextDate.month.toString().padLeft(2, '0')}-${_nextDate.day.toString().padLeft(2, '0')}';

      await Supabase.instance.client.from('subscriptions').insert({
        'user_id': user.id,
        'name': name,
        'amount': amount,
        'billing_cycle': _cycle,
        'next_payment': dateStr,
        'is_active': true,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      if (msg.contains('row-level security') || msg.contains('42501')) {
        showInfaqSnack(
          context,
          'Database blocked the save: turn on RLS policies for subscriptions (see supabase/migrations in the project).',
        );
      } else {
        showInfaqSnack(context, 'Could not save subscription: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffix = _currencySuffix();

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      bottomNavigationBar: InfaqBottomNavBar(
        tabIndex: -1,
        onHome: _cancel,
        onCurrency: () => Navigator.pop(context, 1),
        onAdd: () {},
        onAnalytics: () => Navigator.pop(context, 2),
        onProfile: () => Navigator.pop(context, 3),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfaqServiceFormHeader(
            backgroundColor: _kSubHeaderCream,
            title: 'Add Subscription',
            onBack: _cancel,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InfaqLabeledPillField(
                    label: 'Name',
                    child: InfaqPillTextField(
                      controller: _nameCtrl,
                      hintText: 'Netflix, gym, iCloud…',
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: 18),
                  InfaqLabeledPillField(
                    label: 'Billing cycle',
                    child: InfaqPillDropdown<String>(
                      value: _cycle,
                      hint: null,
                      items: [
                        for (final (v, l) in _cycles)
                          DropdownMenuItem<String>(value: v, child: Text(l)),
                      ],
                      onChanged: (v) => setState(() => _cycle = v ?? 'monthly'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  InfaqLabeledPillField(
                    label: 'Amount',
                    child: InfaqPillAmountStepper(
                      controller: _amountCtrl,
                      currencySuffix: suffix,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 18),
                  InfaqLabeledPillField(
                    label: 'Date',
                    child: InfaqPillDateRow(
                      labelText: formatGoalDateLong(_nextDate),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(height: 28),
                  InfaqPrimaryButton(
                    label: 'Save change',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kServiceFormGreen,
                        side: BorderSide(color: kServiceFormGreen.withValues(alpha: 0.45), width: 1.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        backgroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
