import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Light cyan header (reference mock).
const Color _kGoalHeaderCyan = Color(0xFFE8F4FA);

class AddGoalScreen extends StatefulWidget {
  const AddGoalScreen({super.key, this.currencyCode});

  final String? currencyCode;

  @override
  State<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends State<AddGoalScreen> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _savedCtrl = TextEditingController(text: '0');
  final _monthlyCtrl = TextEditingController();

  DateTime _targetDate = DateTime.now().add(const Duration(days: 365));
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _savedCtrl.dispose();
    _monthlyCtrl.dispose();
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

  String _timeToGoalLine() {
    final target = double.tryParse(_targetCtrl.text.replaceAll(',', ''));
    final saved = double.tryParse(_savedCtrl.text.replaceAll(',', '')) ?? 0;
    final monthly = double.tryParse(_monthlyCtrl.text.replaceAll(',', '')) ?? 0;
    if (target == null || target <= 0 || monthly <= 0) {
      return 'Add target and monthly saving to see how long it could take.';
    }
    final left = target - saved;
    if (left <= 0) return 'You have already reached this target.';
    final monthsTotal = (left / monthly).ceil();
    final y = monthsTotal ~/ 12;
    final m = monthsTotal % 12;
    if (y > 0 && m > 0) {
      return 'You need $y ${y == 1 ? 'year' : 'years'} $m ${m == 1 ? 'month' : 'months'} to save for this.';
    }
    if (y > 0) {
      return 'You need $y ${y == 1 ? 'year' : 'years'} to save for this.';
    }
    return 'You need $m ${m == 1 ? 'month' : 'months'} to save for this.';
  }

  Future<void> _pickDate() async {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: today,
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: kServiceFormGreen)),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  void _cancel() => Navigator.pop(context);

  Future<void> _save() async {
    final title = _nameCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text.replaceAll(',', ''));
    final current = double.tryParse(_savedCtrl.text.replaceAll(',', '')) ?? 0;

    if (title.isEmpty) {
      showInfaqSnack(context, 'Enter a title for your goal.');
      return;
    }
    if (target == null || target <= 0) {
      showInfaqSnack(context, 'Enter a target amount greater than zero.');
      return;
    }
    if (current < 0 || current > target) {
      showInfaqSnack(context, 'Current saved amount must be between 0 and the target.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      showInfaqSnack(context, 'You are not signed in.');
      return;
    }

    setState(() => _saving = true);
    try {
      final d = _targetDate;
      final deadline =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      await Supabase.instance.client.from('goals').insert({
        'created_by': user.id,
        'title': title,
        'target_amount': target,
        'current_amount': current,
        'deadline': deadline,
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
          'Database blocked the save: add RLS policies for goals (see supabase/migrations).',
        );
      } else {
        showInfaqSnack(context, 'Could not save goal: $e');
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
              backgroundColor: _kGoalHeaderCyan,
              title: 'Add Goals',
              onBack: _cancel,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfaqLabeledPillField(
                      label: 'Title',
                      child: InfaqPillTextField(
                        controller: _nameCtrl,
                        hintText: 'PhD, new car, emergency fund…',
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 18),
                    InfaqLabeledPillField(
                      label: 'Target amount',
                      child: InfaqPillAmountStepper(
                        controller: _targetCtrl,
                        currencySuffix: suffix,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 18),
                    InfaqLabeledPillField(
                      label: 'Current saved amount',
                      child: InfaqPillAmountStepper(
                        controller: _savedCtrl,
                        currencySuffix: suffix,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 18),
                    InfaqLabeledPillField(
                      label: 'Date',
                      child: InfaqPillDateRow(
                        labelText: formatGoalDateLong(_targetDate),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 18),
                    InfaqLabeledPillField(
                      label: 'Monthly saving amount',
                      child: InfaqPillAmountStepper(
                        controller: _monthlyCtrl,
                        currencySuffix: suffix,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _timeToGoalLine(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.5),
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
