import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/category/category_icons.dart';
import 'package:infaq/services/ai_service.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Mint header tint (reference mock).
const Color _kAddHeaderMint = Color(0xFFECF9E5);

BoxDecoration _addTxPillDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );

class _CategoryRow {
  _CategoryRow({required this.id, required this.name, required this.type, this.iconKey});
  final String id;
  final String name;
  final String type;
  final String? iconKey;

  IconData get displayIcon => categoryIconForDisplay(
        iconKey: iconKey,
        name: name,
        type: type,
        categoryId: id,
      );
}

/// Full-screen add or edit flow. Pops with `true` if a transaction was saved,
/// an `int` 0–3 to switch home tab, or `null` on back only.
///
/// For edit, pass [existingTransaction] with at least `id`, and preferably
/// `description`, `amount`, `date` (or `created_at`), `category_id`, and
/// embedded `categories: { type }` from the list query.
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({
    super.key,
    this.currencyCode,
    this.existingTransaction,
    /// When adding (not editing), pre-select Income (`true`) or Expense (`false`).
    this.initialIncome,
  });

  final String? currencyCode;
  final Map<String, dynamic>? existingTransaction;
  final bool? initialIncome;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  bool _isIncome = false;
  DateTime _date = DateTime.now();
  String? _categoryId;
  List<_CategoryRow> _categories = [];
  bool _loadingCategories = true;
  bool _saving = false;
  String? _categoryError;
  bool _supportsCategoryIconKey = true;
  Timer? _aiDebounce;
  bool _aiCategorizing = false;
  String? _aiConfidence;
  String? _aiLeafColor;

  static const _primary = kInfaqPrimaryGreen;

  String? get _existingId => widget.existingTransaction?['id']?.toString();

  bool get _isEditing => _existingId != null;

  @override
  void initState() {
    super.initState();
    if (widget.existingTransaction == null && widget.initialIncome != null) {
      _isIncome = widget.initialIncome!;
    }
    _loadCategories();
  }

  void _applyExistingTransaction() {
    final ex = widget.existingTransaction;
    if (ex == null) return;

    var incomeFromEmbed = false;
    final cat = ex['categories'];
    if (cat is Map) {
      final t = cat['type']?.toString().toLowerCase();
      if (t == 'income' || t == 'expense') {
        _isIncome = t == 'income';
        incomeFromEmbed = true;
      }
    }

    _descCtrl.text = (ex['description'] ?? ex['title'] ?? '').toString();
    final amt = ex['amount'];
    if (amt != null) {
      final n = amt is num ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0;
      _amountCtrl.text = n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
    }

    final cid = ex['category_id']?.toString();
    if (cid != null && cid.isNotEmpty) {
      _categoryId = cid;
      if (!incomeFromEmbed) {
        try {
          final row = _categories.firstWhere((c) => c.id == cid);
          _isIncome = row.type == 'income';
        } catch (_) {}
      }
    }

    final dr = ex['date'] ?? ex['created_at'];
    if (dr != null) {
      final d = DateTime.tryParse(dr.toString());
      if (d != null) _date = DateTime(d.year, d.month, d.day);
    }
  }

  @override
  void dispose() {
    _aiDebounce?.cancel();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingCategories = false);
      return;
    }

    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });

    try {
      dynamic res;
      try {
        res = await supabase
            .from('categories')
            .select('id,name,type,icon_key')
            .or('user_id.is.null,user_id.eq.${user.id}')
            .order('name');
        _supportsCategoryIconKey = true;
      } on PostgrestException catch (e) {
        // Backward compatibility before icon_key migration is applied.
        if (e.code != '42703') rethrow;
        res = await supabase
            .from('categories')
            .select('id,name,type')
            .or('user_id.is.null,user_id.eq.${user.id}')
            .order('name');
        _supportsCategoryIconKey = false;
      }

      final list = res as List<dynamic>;
      final rows = list
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final id = m['id']?.toString();
            final name = m['name']?.toString() ?? '';
            final type = (m['type']?.toString() ?? 'expense').toLowerCase();
            final iconKey = _supportsCategoryIconKey ? m['icon_key']?.toString() : null;
            if (id == null) return null;
            return _CategoryRow(id: id, name: name, type: type, iconKey: iconKey);
          })
          .whereType<_CategoryRow>()
          .toList();

      if (!mounted) return;
      setState(() {
        _categories = rows;
        _loadingCategories = false;
        if (widget.existingTransaction != null) {
          _applyExistingTransaction();
        }
        _clearCategoryIfInvalid();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _categoryError = e.toString();
      });
    }
  }

  List<_CategoryRow> get _filteredCategories =>
      _categories.where((c) => c.type == (_isIncome ? 'income' : 'expense')).toList();

  _CategoryRow? get _selectedCategory {
    if (_categoryId == null) return null;
    try {
      return _filteredCategories.firstWhere((c) => c.id == _categoryId);
    } catch (_) {
      return null;
    }
  }

  void _clearCategoryIfInvalid() {
    final sel = _selectedCategory;
    if (sel == null) _categoryId = null;
  }

  void _setIncome(bool income) {
    setState(() {
      _isIncome = income;
      _clearCategoryIfInvalid();
    });
  }

  Future<void> _suggestCategoryWithAi(String value) async {
    final desc = value.trim();
    if (desc.length < 3) return;
    if (_filteredCategories.isEmpty) return;

    setState(() => _aiCategorizing = true);
    try {
      final amountValue = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
      final result = await AiService().categorizeTransaction(
        transactionName: desc,
        amount: amountValue,
        transactionType: _isIncome ? 'income' : 'expense',
        description: null,
        availableCategories: _filteredCategories.map((c) => c.name).toList(),
      );

      final suggested = (result['suggested_category'] ?? '').toString().trim();
      final confidence = result['confidence']?.toString();
      final leafColor = result['leaf_color']?.toString();
      final match = _filteredCategories.where((c) => c.name.toLowerCase() == suggested.toLowerCase());
      final matchedCategory = match.isEmpty ? null : match.first;

      if (!mounted) return;
      setState(() {
        if (matchedCategory != null) {
          _categoryId = matchedCategory.id;
        }
        _aiConfidence = confidence;
        _aiLeafColor = leafColor;
      });
    } catch (_) {
      // Keep AI suggestion failures silent.
    } finally {
      if (mounted) {
        setState(() => _aiCategorizing = false);
      }
    }
  }

  String _currencyPrefix() {
    switch (widget.currencyCode?.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'SAR':
        return 'SAR ';
      case 'BHD':
        return 'BHD ';
      default:
        final c = widget.currencyCode?.trim();
        return c == null || c.isEmpty ? '' : '$c ';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCategory() async {
    if (_filteredCategories.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Category',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredCategories.length,
                    itemBuilder: (context, i) {
                      final c = _filteredCategories[i];
                      return ListTile(
                        leading: Icon(c.displayIcon, color: _primary, size: 26),
                        title: Text(c.name),
                        trailing: _categoryId == c.id
                            ? const Icon(Icons.check_circle_rounded, color: _primary)
                            : null,
                        onTap: () => Navigator.pop(ctx, c.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null) setState(() => _categoryId = chosen);
  }

  Future<void> _save() async {
    final desc = _descCtrl.text.trim();
    final amountRaw = _amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountRaw);

    if (desc.isEmpty) {
      showInfaqSnack(context, 'Add a short description (e.g. what you bought or received).');
      return;
    }
    if (amount == null || amount <= 0) {
      showInfaqSnack(context, 'Enter an amount greater than zero.');
      return;
    }
    if (_categoryId == null) {
      showInfaqSnack(context, 'Choose a category.');
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
          '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

      final client = Supabase.instance.client;
      if (_isEditing) {
        await client
            .from('transactions')
            .update({
              'amount': amount,
              'category_id': _categoryId,
              'description': desc,
              'date': dateStr,
            })
            .eq('id', _existingId!)
            .eq('user_id', user.id);
      } else {
        await client.from('transactions').insert({
          'user_id': user.id,
          'amount': amount,
          'category_id': _categoryId,
          'description': desc,
          'date': dateStr,
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInfaqSnack(context, 'Could not save: $e');
    }
  }

  void _cancel() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final prefix = _currencyPrefix();
    final saveLabel = _isEditing
        ? (_isIncome ? 'Update income' : 'Update expense')
        : (_isIncome ? 'Save income' : 'Save expense');
    final descHint = _isIncome
        ? 'e.g. salary, bonus, freelance'
        : 'e.g. meal, new phone, vegetables';

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
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _kAddHeaderMint,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A3F5F4A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: _cancel,
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary),
                        ),
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit transaction' : 'Add transaction',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _ExpenseIncomeToggle(
                        isIncome: _isIncome,
                        onExpense: () => _setIncome(false),
                        onIncome: () => _setIncome(true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LabeledField(
                    label: 'Description',
                    subtitle: 'What you spent or received — not the category',
                    child: _ShadowTextField(
                      controller: _descCtrl,
                      hintText: descHint,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        _aiDebounce?.cancel();
                        _aiDebounce = Timer(const Duration(milliseconds: 700), () {
                          _suggestCategoryWithAi(value);
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _LabeledField(
                    label: 'Amount',
                    child: _ShadowTextField(
                      controller: _amountCtrl,
                      hintText: '${prefix}0',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _LabeledField(
                    label: 'Date',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          decoration: _addTxPillDecoration(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_date.day}/${_date.month}/${_date.year}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black.withValues(alpha: 0.75),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.calendar_month_rounded, color: _primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _LabeledField(
                    label: 'Category',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _loadingCategories || _filteredCategories.isEmpty
                            ? null
                            : _pickCategory,
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          decoration: _addTxPillDecoration(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                if (_selectedCategory != null && !_loadingCategories) ...[
                                  Icon(_selectedCategory!.displayIcon, color: _primary, size: 22),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: _loadingCategories
                                      ? Text(
                                          'Loading…',
                                          style: TextStyle(
                                            color: Colors.black.withValues(alpha: 0.45),
                                          ),
                                        )
                                      : Text(
                                          _selectedCategory?.name ?? 'Choose a category',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: _selectedCategory != null
                                                ? Colors.black.withValues(alpha: 0.85)
                                                : Colors.black.withValues(alpha: 0.45),
                                          ),
                                        ),
                                ),
                                const Icon(Icons.keyboard_arrow_down_rounded, color: _primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_aiConfidence != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _aiCategorizing ? 'AI suggesting category...' : 'AI suggested this category',
                      style: TextStyle(
                        fontSize: 12,
                        color: switch (_aiLeafColor) {
                          'green' => Colors.green.shade700,
                          'orange' => Colors.orange.shade800,
                          'red' => Colors.red.shade700,
                          _ => Colors.black.withValues(alpha: 0.5),
                        },
                      ),
                    ),
                  ],
                  if (_categoryError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _categoryError!,
                      style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                    ),
                    TextButton(onPressed: _loadCategories, child: const Text('Retry')),
                  ],
                  if (!_loadingCategories &&
                      _categoryError == null &&
                      _filteredCategories.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'No ${_isIncome ? 'income' : 'expense'} categories yet. Add some in Supabase.',
                      style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.55)),
                    ),
                  ],
                  const SizedBox(height: 28),
                  InfaqPrimaryButton(
                    label: saveLabel,
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
                        foregroundColor: _primary,
                        side: const BorderSide(color: _primary, width: 1.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.45),
              height: 1.25,
            ),
          ),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ShadowTextField extends StatelessWidget {
  const _ShadowTextField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _addTxPillDecoration(),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _ExpenseIncomeToggle extends StatelessWidget {
  const _ExpenseIncomeToggle({
    required this.isIncome,
    required this.onExpense,
    required this.onIncome,
  });

  final bool isIncome;
  final VoidCallback onExpense;
  final VoidCallback onIncome;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _Seg(
              label: 'Expense',
              selected: !isIncome,
              onTap: onExpense,
            ),
          ),
          Expanded(
            child: _Seg(
              label: 'Income',
              selected: isIncome,
              onTap: onIncome,
            ),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? kInfaqPrimaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : Colors.black.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
