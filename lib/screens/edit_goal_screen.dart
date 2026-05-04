import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/goal_accent.dart';
import 'package:infaq/goal_icon_picker.dart';
import 'package:infaq/goal_local_storage.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

class EditGoalScreen extends StatefulWidget {
  const EditGoalScreen({super.key, required this.goal, this.currencyCode});

  final Map<String, dynamic> goal;
  final String? currencyCode;

  @override
  State<EditGoalScreen> createState() => _EditGoalScreenState();
}

class _EditGoalScreenState extends State<EditGoalScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _reachedCtrl;
  late final TextEditingController _monthlyCtrl;

  late DateTime _deadline;
  IconData _goalIcon = Icons.menu_book_rounded;
  bool _saving = false;
  bool _extrasLoaded = false;

  String? get _goalId => widget.goal['id']?.toString();

  static double _readAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.goal['title']?.toString() ?? '';
    _titleCtrl = TextEditingController(text: t);
    _targetCtrl = TextEditingController(text: _readAmount(widget.goal['target_amount']).toStringAsFixed(0));
    _reachedCtrl = TextEditingController(text: _readAmount(widget.goal['current_amount']).toStringAsFixed(0));
    _monthlyCtrl = TextEditingController();

    final rawD = widget.goal['deadline'];
    final parsed = rawD != null ? DateTime.tryParse(rawD.toString()) : null;
    _deadline = parsed ?? DateTime.now().add(const Duration(days: 365));

    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final id = _goalId;
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _extrasLoaded = true);
      return;
    }
    final raw = await readGoalLocalExtrasJson(id);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final monthly = (m['monthly'] as num?)?.toDouble();
        if (monthly != null && monthly > 0) {
          _monthlyCtrl.text = monthly % 1 == 0 ? monthly.toStringAsFixed(0) : monthly.toStringAsFixed(2);
        }
        final iconCp = (m['icon'] as num?)?.toInt();
        if (mounted) {
          setState(() {
            if (iconCp != null) {
              _goalIcon = IconData(iconCp, fontFamily: 'MaterialIcons');
            }
            _extrasLoaded = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _extrasLoaded = true);
      }
    } else {
      if (mounted) setState(() => _extrasLoaded = true);
    }
  }

  Future<void> _persistExtras() async {
    final id = _goalId;
    if (id == null || id.isEmpty) return;
    final monthly = double.tryParse(_monthlyCtrl.text.replaceAll(',', ''));
    await persistGoalLocalExtras(
      goalId: id,
      iconCodePoint: _goalIcon.codePoint,
      monthly: monthly,
    );
  }

  Future<void> _clearExtras() async {
    final id = _goalId;
    if (id == null || id.isEmpty) return;
    await clearGoalLocalExtras(id);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _reachedCtrl.dispose();
    _monthlyCtrl.dispose();
    super.dispose();
  }

  void _cancel() => Navigator.pop(context);

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
    final saved = double.tryParse(_reachedCtrl.text.replaceAll(',', '')) ?? 0;
    final monthly = double.tryParse(_monthlyCtrl.text.replaceAll(',', '')) ?? 0;
    if (target == null || target <= 0 || monthly <= 0) {
      return 'Add target and monthly amount to see how long it could take.';
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
      initialDate: _deadline.isBefore(today) ? today : _deadline,
      firstDate: today,
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _confirmDelete() async {
    final id = _goalId;
    if (id == null || id.isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this goal?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.from('goals').delete().eq('id', id).eq('created_by', user.id);
      await _clearExtras();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text.replaceAll(',', ''));
    final reached = double.tryParse(_reachedCtrl.text.replaceAll(',', '')) ?? 0;

    if (title.isEmpty) {
      showInfaqSnack(context, 'Enter a name for this goal.');
      return;
    }
    if (target == null || target <= 0) {
      showInfaqSnack(context, 'Enter a target amount greater than zero.');
      return;
    }
    if (reached < 0 || reached > target) {
      showInfaqSnack(context, 'Saved amount must be between 0 and the target.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    final id = _goalId;
    if (user == null || id == null || id.isEmpty) {
      showInfaqSnack(context, 'You are not signed in.');
      return;
    }

    setState(() => _saving = true);
    try {
      final d = _deadline;
      final deadline =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      await Supabase.instance.client.from('goals').update({
        'title': title,
        'target_amount': target,
        'current_amount': reached,
        'deadline': deadline,
      }).eq('id', id).eq('created_by', user.id);

      await _persistExtras();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      if (msg.contains('row-level security') || msg.contains('42501')) {
        showInfaqSnack(context, 'Could not save: check database access for goals.');
      } else {
        showInfaqSnack(context, 'Could not save: $e');
      }
    }
  }

  void _showIconPicker() {
    showGoalIconPickerSheet(
      context,
      onSelected: (ic) => setState(() => _goalIcon = ic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg =
        isDark ? Color.lerp(cs.primaryContainer, cs.surface, 0.35)! : kInfaqMgmtHeaderMint;
    final suffix = _currencySuffix();
    final target = double.tryParse(_targetCtrl.text.replaceAll(',', ''));
    final reached = double.tryParse(_reachedCtrl.text.replaceAll(',', '')) ?? 0;
    final t = target != null && target > 0 ? target : 0.0;
    final progress = t > 0 ? (reached / t).clamp(0.0, 1.0) : 0.0;
    final accent = accentColorForGoalTitle(
      _titleCtrl.text.trim().isEmpty ? 'x' : _titleCtrl.text.trim(),
    );

    if (!_extrasLoaded) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
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
            backgroundColor: headerBg,
            title: 'Goals',
            onBack: _cancel,
            trailing: IconButton(
              onPressed: _confirmDelete,
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 24),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.shadow.withValues(alpha: isDark ? 0.35 : 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(_goalIcon, color: Colors.white, size: 40),
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Material(
                              color: cs.surface,
                              elevation: 2,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: _showIconPicker,
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(Icons.edit_rounded, size: 16, color: accent),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _titleCtrl,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.only(top: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total goal reached',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _fmtMoney(reached),
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Budget',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t > 0 ? _fmtMoney(t) : '—',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withValues(alpha: 0.42),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withValues(alpha: isDark ? 0.25 : 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfaqLabeledPillField(
                          label: 'Saved so far',
                          child: InfaqPillAmountStepper(
                            controller: _reachedCtrl,
                            currencySuffix: suffix,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfaqLabeledPillField(
                          label: 'Target amount',
                          child: InfaqPillAmountStepper(
                            controller: _targetCtrl,
                            currencySuffix: suffix,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfaqLabeledPillField(
                          label: 'Date',
                          child: InfaqPillDateRow(
                            labelText: formatGoalDateLong(_deadline),
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfaqLabeledPillField(
                          label: 'Monthly amount',
                          child: InfaqPillAmountStepper(
                            controller: _monthlyCtrl,
                            currencySuffix: suffix,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _timeToGoalLine(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  InfaqPrimaryButton(
                    label: 'Save changes',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(color: cs.primary.withValues(alpha: 0.45), width: 1.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        backgroundColor: cs.surface,
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

  String _fmtMoney(double v) {
    final abs = v.abs();
    final body = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
    switch (widget.currencyCode?.toUpperCase()) {
      case 'USD':
        return '\$$body';
      case 'EUR':
        return '€$body';
      case 'GBP':
        return '£$body';
      case 'SAR':
        return 'SAR $body';
      case 'BHD':
        return 'BHD $body';
      default:
        final c = widget.currencyCode?.trim();
        final prefix = c == null || c.isEmpty ? '' : '$c ';
        return '$prefix$body';
    }
  }
}
