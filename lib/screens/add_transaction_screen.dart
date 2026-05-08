import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/category/category_icons.dart';
import 'package:infaq/security/input_sanitizer.dart';
import 'package:infaq/services/ai_service.dart'
    show AiCategorizeCallKind, AiService;
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_widgets.dart';

BoxDecoration _addTxPillDecoration(BuildContext context) => BoxDecoration(
  color: Theme.of(context).colorScheme.surfaceContainerLowest,
  borderRadius: BorderRadius.circular(999),
  boxShadow: const [],
);

class _CategoryRow {
  _CategoryRow({
    required this.id,
    required this.name,
    required this.type,
    this.iconKey,
  });
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
  bool _recategorizing = false;
  DateTime? _lastRecategorizeTap;
  String? _aiConfidence;
  String? _aiLeafColor;
  bool _categoryLockedByUser = false;
  bool _didRemoteUpdate = false;

  /// Prevents [_loadCategories] from re-running [_applyExistingTransaction] and wiping user changes.
  bool _hasSeededEditFormFromExisting = false;

  /// Copy of the row being edited; updated after Recategorize so logs/UI stay consistent.
  Map<String, dynamic>? _transactionEditSnapshot;

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

    _transactionEditSnapshot = Map<String, dynamic>.from(ex);

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
      final n = amt is num
          ? amt.toDouble()
          : double.tryParse(amt.toString()) ?? 0;
      _amountCtrl.text = n % 1 == 0
          ? n.toStringAsFixed(0)
          : n.toStringAsFixed(2);
    }

    final cid = ex['category_id']?.toString();
    if (cid != null && cid.isNotEmpty) {
      _categoryId = cid;
      _categoryLockedByUser = true;
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
        final global = await supabase
            .from('categories')
            .select('id,name,type,icon_key')
            .isFilter('user_id', null)
            .order('name');
        final mine = await supabase
            .from('categories')
            .select('id,name,type,icon_key')
            .eq('user_id', user.id)
            .order('name');
        res = [...(global as List<dynamic>), ...(mine as List<dynamic>)];
        _supportsCategoryIconKey = true;
      } on PostgrestException catch (e) {
        // Backward compatibility before icon_key migration is applied.
        if (e.code != '42703') rethrow;
        final global = await supabase
            .from('categories')
            .select('id,name,type')
            .isFilter('user_id', null)
            .order('name');
        final mine = await supabase
            .from('categories')
            .select('id,name,type')
            .eq('user_id', user.id)
            .order('name');
        res = [...(global as List<dynamic>), ...(mine as List<dynamic>)];
        _supportsCategoryIconKey = false;
      }

      final list = res as List<dynamic>;
      final rows = list
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final id = m['id']?.toString();
            final name = m['name']?.toString() ?? '';
            final type = (m['type']?.toString() ?? 'expense').toLowerCase();
            final iconKey = _supportsCategoryIconKey
                ? m['icon_key']?.toString()
                : null;
            if (id == null) return null;
            return _CategoryRow(
              id: id,
              name: name,
              type: type,
              iconKey: iconKey,
            );
          })
          .whereType<_CategoryRow>()
          .toList();

      if (!mounted) return;
      setState(() {
        _categories = rows;
        _loadingCategories = false;
        // Only seed once. Re-applying on every category reload overwrites Recategorize / manual picks.
        if (widget.existingTransaction != null &&
            !_hasSeededEditFormFromExisting) {
          _applyExistingTransaction();
          _hasSeededEditFormFromExisting = true;
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

  List<_CategoryRow> get _filteredCategories => _categories
      .where((c) => c.type == (_isIncome ? 'income' : 'expense'))
      .toList();

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

  String _normalizeCategoryKey(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  _CategoryRow? _findCategoryByNormalizedName(String name) {
    final target = _normalizeCategoryKey(name);
    if (target.isEmpty) return null;
    for (final c in _filteredCategories) {
      if (_normalizeCategoryKey(c.name) == target) return c;
    }
    return null;
  }

  /// Maps AI (or partial) category text to a row — exact match, substring, then token overlap.
  _CategoryRow? _matchAiSuggestionToCategory(String suggested) {
    final raw = suggested.trim();
    if (raw.isEmpty) return null;
    final byExact = _findCategoryByNormalizedName(raw);
    if (byExact != null) return byExact;

    final s = raw.toLowerCase();
    final list = _filteredCategories;
    _CategoryRow? best;
    var bestScore = 0;
    for (final c in list) {
      final cn = c.name.toLowerCase();
      if (cn == s) return c;
      if (cn.contains(s) || s.contains(cn)) {
        final sc = cn.contains(s) ? 1000 + cn.length : 500 + cn.length;
        if (sc > bestScore) {
          bestScore = sc;
          best = c;
        }
      }
    }
    if (best != null) return best;

    final sTokens = s
        .split(RegExp(r'[\s/&,\-]+'))
        .where((t) => t.length > 1)
        .toSet();
    best = null;
    bestScore = 0;
    for (final c in list) {
      final cn = c.name.toLowerCase();
      final cTokens = cn
          .split(RegExp(r'[\s/&,\-]+'))
          .where((t) => t.length > 1)
          .toSet();
      final overlap = sTokens.intersection(cTokens).length;
      if (overlap > bestScore) {
        bestScore = overlap;
        best = c;
      }
    }
    if (best != null && bestScore > 0) return best;
    return null;
  }

  _CategoryRow? _localCategoryFromDescription(String desc) {
    final d = desc.toLowerCase().trim();
    if (d.isEmpty) return null;
    final list = _filteredCategories;
    if (_isIncome) {
      if (d.contains('salary')) {
        for (final c in list) {
          if (c.name.toLowerCase().contains('salary')) return c;
        }
      }
      if (d.contains('fawri') ||
          d.contains('benefit') ||
          d.contains('transfer')) {
        for (final c in list) {
          final n = c.name.toLowerCase();
          if (n == 'other income' ||
              (n.contains('other') && n.contains('income'))) {
            return c;
          }
        }
      }
      return null;
    }
    if (d.contains('talabat') ||
        d.contains('jahez') ||
        d.contains('restaurant') ||
        d.contains('cafe') ||
        d.contains('food')) {
      for (final c in list) {
        if (c.name.toLowerCase().contains('food')) return c;
      }
    }
    if (d.contains('uber') || d.contains('careem') || d.contains('taxi')) {
      for (final c in list) {
        if (c.name.toLowerCase().contains('transport')) return c;
      }
    }
    if (d.contains('netflix') || d.contains('spotify')) {
      for (final c in list) {
        if (c.name.toLowerCase().contains('entertainment')) return c;
      }
    }
    if (d.contains('fawri') ||
        d.contains('benefit') ||
        d.contains('transfer')) {
      for (final c in list) {
        final n = c.name.toLowerCase();
        if (n == 'other expense' ||
            (n.contains('other') && n.contains('expense'))) {
          return c;
        }
      }
    }
    return null;
  }

  _CategoryRow? _fallbackOtherCategory() {
    for (final c in _filteredCategories) {
      final n = c.name.toLowerCase();
      if (_isIncome) {
        if (n == 'other income' ||
            (n.contains('other') && n.contains('income'))) {
          return c;
        }
      } else {
        if (n == 'other expense' ||
            (n.contains('other') && n.contains('expense'))) {
          return c;
        }
      }
    }
    for (final c in _filteredCategories) {
      if (c.name.toLowerCase().contains('other')) return c;
    }
    return null;
  }

  Future<void> _suggestCategoryWithAi(String value) async {
    final desc = value.trim();
    if (desc.length < 3) return;
    if (_filteredCategories.isEmpty) return;
    if (_categoryLockedByUser) return;

    setState(() => _aiCategorizing = true);
    try {
      final amountValue =
          double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
      final result = await AiService().categorizeTransaction(
        transactionName: desc,
        amount: amountValue,
        transactionType: _isIncome ? 'income' : 'expense',
        description: null,
        availableCategories: _filteredCategories.map((c) => c.name).toList(),
        callKind: AiCategorizeCallKind.debouncedSuggestion,
        reason: 'add_tx_description_suggest',
      );

      final suggested = (result['suggested_category'] ?? '').toString().trim();
      final confidence = result['confidence']?.toString();
      final leafColor = result['leaf_color']?.toString();
      final match = _filteredCategories.where(
        (c) => c.name.toLowerCase() == suggested.toLowerCase(),
      );
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
      case 'JPY':
        return '¥';
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
          data: Theme.of(
            context,
          ).copyWith(colorScheme: const ColorScheme.light(primary: _primary)),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
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
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: _primary,
                              )
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
    if (chosen != null) {
      setState(() {
        _categoryId = chosen;
        _categoryLockedByUser = true;
      });
    }
  }

  Future<void> _save() async {
    final desc = InputSanitizer.cleanText(_descCtrl.text, maxLength: 120);
    final amountRaw = _amountCtrl.text.trim().replaceAll(',', '');
    final amount = InputSanitizer.parsePositiveAmount(
      amountRaw,
      min: 0.01,
      max: 1000000000,
    );

    if (desc.isEmpty) {
      showInfaqSnack(
        context,
        'Add a short description (e.g. what you bought or received).',
      );
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
      Map<String, dynamic>? leafData;
      final categoryName = _selectedCategory?.name.trim() ?? '';
      final shouldClassifyLeaf = AiService.shouldClassifyLeafImpact(
        transactionName: desc,
        category: categoryName,
        transactionType: _isIncome ? 'income' : 'expense',
      );
      if (shouldClassifyLeaf && categoryName.isNotEmpty) {
        try {
          leafData = await AiService().classifyLeafImpact(
            transactionName: desc,
            category: categoryName,
            transactionType: 'expense',
            reason: 'add_tx_save',
          );
          debugPrint(
            'leaf classified from edge function: color=${leafData['leaf_color']}',
          );
        } catch (e, st) {
          debugPrint('leaf classify failed during save: $e\n$st');
        }
      }

      final txPayload = <String, dynamic>{
        'amount': amount,
        'category_id': _categoryId,
        'description': desc,
        'date': dateStr,
        'leaf_color': shouldClassifyLeaf && leafData != null
            ? leafData['leaf_color']
            : null,
        'leaf_title': shouldClassifyLeaf && leafData != null
            ? leafData['title']
            : null,
        'leaf_message': shouldClassifyLeaf && leafData != null
            ? leafData['message']
            : null,
      };

      final client = Supabase.instance.client;
      if (_isEditing) {
        await client
            .from('transactions')
            .update(txPayload)
            .eq('id', _existingId!)
            .eq('user_id', user.id);
      } else {
        await client.from('transactions').insert({
          'user_id': user.id,
          ...txPayload,
        });
      }

      if (!mounted) return;
      _didRemoteUpdate = true;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInfaqSnack(
        context,
        'Could not save transaction right now. Please try again.',
      );
    }
  }

  Future<void> _recategorizeCurrentTransaction() async {
    if (!_isEditing) return;
    if (_recategorizing || _saving) return;
    final nowTap = DateTime.now();
    if (_lastRecategorizeTap != null &&
        nowTap.difference(_lastRecategorizeTap!) < const Duration(seconds: 2)) {
      return;
    }
    _lastRecategorizeTap = nowTap;
    if (_filteredCategories.isEmpty) {
      showInfaqSnack(context, 'Categories are still loading.');
      return;
    }
    final id = _existingId!;
    final desc = InputSanitizer.cleanText(_descCtrl.text, maxLength: 120);
    if (desc.length < 3) {
      showInfaqSnack(context, 'Add a short description before recategorizing.');
      return;
    }
    final amountValue =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final snap = _transactionEditSnapshot;
    final oldCategoryId = _categoryId ?? snap?['category_id']?.toString();
    final oldCategoryName =
        _selectedCategory?.name ??
        (snap?['categories'] is Map
            ? (snap!['categories']['name'] ?? '').toString()
            : '');
    final oldLeafColor = snap?['leaf_color'];
    final oldLeafTitle = snap?['leaf_title'];
    final oldLeafMessage = snap?['leaf_message'];

    debugPrint('[Recategorize] clicked');
    debugPrint('[Recategorize] transaction id=$id');
    debugPrint('[Recategorize] transaction description="$desc"');
    debugPrint(
      '[Recategorize] old category id=$oldCategoryId name="$oldCategoryName"',
    );
    debugPrint(
      '[Recategorize] old leaf={color:$oldLeafColor,title:$oldLeafTitle,message:$oldLeafMessage}',
    );

    setState(() => _recategorizing = true);
    try {
      String categorySource = 'local';
      _CategoryRow? picked = _localCategoryFromDescription(desc);
      var aiSuggested = '';

      if (picked == null) {
        categorySource = 'ai';
        final result = await AiService().categorizeTransaction(
          transactionName: desc,
          amount: amountValue,
          transactionType: _isIncome ? 'income' : 'expense',
          description: null,
          availableCategories: _filteredCategories.map((c) => c.name).toList(),
          callKind: AiCategorizeCallKind.manualRecategorize,
          reason: 'add_tx_recategorize',
        );
        aiSuggested = (result['suggested_category'] ?? '').toString().trim();
        debugPrint('[Recategorize] category result (ai)="$aiSuggested"');
        picked = _matchAiSuggestionToCategory(aiSuggested);
        if (picked == null) {
          picked = _fallbackOtherCategory();
          if (picked != null) {
            categorySource = 'ai+fallback';
            debugPrint(
              '[Recategorize] could not map "$aiSuggested" to a category; using "${picked.name}"',
            );
          }
        }
      } else {
        debugPrint('[Recategorize] category result (local)="${picked.name}"');
      }

      if (picked == null) {
        throw Exception(
          'Could not resolve a category. AI suggested: "$aiSuggested".',
        );
      }
      var resolvedCategory = picked;
      final expectedType = _isIncome ? 'income' : 'expense';
      if (resolvedCategory.type != expectedType) {
        debugPrint(
          '[Recategorize] type mismatch resolved=${resolvedCategory.type} '
          'expected=$expectedType; using fallback',
        );
        final fb = _fallbackOtherCategory();
        if (fb == null) {
          throw Exception('No valid $expectedType category available.');
        }
        resolvedCategory = fb;
        categorySource = '$categorySource+type_fix';
      }

      final newCategoryId = resolvedCategory.id.trim();
      debugPrint(
        '[Recategorize] category source=$categorySource '
        'resolved name="${resolvedCategory.name}" category_id=$newCategoryId',
      );

      Map<String, dynamic>? leafData;
      final shouldClassifyLeaf = AiService.shouldClassifyLeafImpact(
        transactionName: desc,
        category: resolvedCategory.name,
        transactionType: _isIncome ? 'income' : 'expense',
      );
      if (shouldClassifyLeaf && resolvedCategory.name.trim().isNotEmpty) {
        leafData = await AiService().classifyLeafImpact(
          transactionName: desc,
          category: resolvedCategory.name,
          transactionType: 'expense',
          reason: 'add_tx_recategorize',
        );
      }
      debugPrint('[Recategorize] classify leaf result=$leafData');

      final payload = <String, dynamic>{
        'category_id': newCategoryId,
        'leaf_color': shouldClassifyLeaf && leafData != null
            ? leafData['leaf_color']
            : null,
        'leaf_title': shouldClassifyLeaf && leafData != null
            ? leafData['title']
            : null,
        'leaf_message': shouldClassifyLeaf && leafData != null
            ? leafData['message']
            : null,
      };
      debugPrint(
        '[Recategorize] old category_id=$oldCategoryId new category_id=$newCategoryId',
      );
      debugPrint('[Recategorize] supabase update payload=$payload');

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not signed in.');

      final updateRes = await Supabase.instance.client
          .from('transactions')
          .update(payload)
          .eq('id', id)
          .eq('user_id', user.id)
          .select('id, category_id, leaf_color, leaf_title, leaf_message');

      debugPrint('[Recategorize] supabase update response=$updateRes');

      final updateRows = updateRes as List<dynamic>;
      if (updateRows.isEmpty) {
        throw Exception(
          'Recategorize failed: update affected 0 rows (check transaction id, '
          'RLS policies, or user_id). id=$id',
        );
      }

      dynamic verified;
      try {
        verified = await Supabase.instance.client
            .from('transactions')
            .select(
              'id, category_id, leaf_color, leaf_title, leaf_message, '
              'categories(id, name, type, icon_key, color)',
            )
            .eq('id', id)
            .eq('user_id', user.id)
            .maybeSingle();
      } catch (_) {
        verified = await Supabase.instance.client
            .from('transactions')
            .select(
              'id, category_id, leaf_color, leaf_title, leaf_message, '
              'categories(id, name, type, icon_key)',
            )
            .eq('id', id)
            .eq('user_id', user.id)
            .maybeSingle();
      }

      if (verified == null) {
        throw Exception(
          'Recategorize verification failed: could not re-read transaction $id',
        );
      }

      final vMap = Map<String, dynamic>.from(verified as Map);
      final savedCatId = vMap['category_id']?.toString().trim();
      debugPrint(
        '[Recategorize] verification read category_id=$savedCatId '
        'leaf_color=${vMap['leaf_color']} leaf_title=${vMap['leaf_title']} '
        'leaf_message=${vMap['leaf_message']}',
      );

      if (savedCatId != newCategoryId) {
        throw Exception(
          'Recategorize verification failed: expected category_id=$newCategoryId '
          'but database has $savedCatId',
        );
      }

      if (!mounted) return;
      setState(() {
        _categoryId = savedCatId;
        _categoryLockedByUser = true;
        _transactionEditSnapshot = Map<String, dynamic>.from(vMap);
        final catMap = vMap['categories'];
        if (catMap is Map) {
          final t = catMap['type']?.toString().toLowerCase();
          if (t == 'income' || t == 'expense') {
            _isIncome = t == 'income';
          }
        }
      });
      _didRemoteUpdate = true;
      debugPrint('[Recategorize] success; UI state category_id=$_categoryId');
      showInfaqSnack(context, 'Category updated');
    } catch (e, st) {
      debugPrint('[Recategorize] error: $e\n$st');
      if (!mounted) return;
      showInfaqSnack(context, 'Recategorize failed. Please try again.');
    } finally {
      if (mounted) setState(() => _recategorizing = false);
    }
  }

  void _cancel() => Navigator.pop(context, _didRemoteUpdate);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefix = _currencyPrefix();
    final saveLabel = _isEditing
        ? (_isIncome ? 'Update income' : 'Update expense')
        : (_isIncome ? 'Save income' : 'Save expense');
    final descHint = _isIncome
        ? 'e.g. salary, bonus, freelance'
        : 'e.g. meal, new phone, vegetables';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (!context.mounted) return;
        Navigator.of(context).pop(_didRemoteUpdate);
      },
      child: Scaffold(
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
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A2520)
                    : const Color(0xFFE8F2EA),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
                boxShadow: const [],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: _cancel,
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: cs.primary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _isEditing
                                  ? 'Edit transaction'
                                  : 'Add transaction',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: _ExpenseIncomeToggle(
                            isIncome: _isIncome,
                            onExpense: () => _setIncome(false),
                            onIncome: () => _setIncome(true),
                          ),
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
                          _aiDebounce = Timer(
                            const Duration(milliseconds: 700),
                            () {
                              _suggestCategoryWithAi(value);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LabeledField(
                      label: 'Amount',
                      child: _ShadowTextField(
                        controller: _amountCtrl,
                        hintText: '${prefix}0',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                            decoration: _addTxPillDecoration(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_date.day}/${_date.month}/${_date.year}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.75,
                                        ),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.calendar_month_rounded,
                                    color: _primary,
                                  ),
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
                          onTap:
                              _loadingCategories || _filteredCategories.isEmpty
                              ? null
                              : _pickCategory,
                          borderRadius: BorderRadius.circular(999),
                          child: Ink(
                            decoration: _addTxPillDecoration(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  if (_selectedCategory != null &&
                                      !_loadingCategories) ...[
                                    Icon(
                                      _selectedCategory!.displayIcon,
                                      color: _primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: _loadingCategories
                                        ? Text(
                                            'Loading…',
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            _selectedCategory?.name ??
                                                'Choose a category',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: _selectedCategory != null
                                                  ? cs.onSurface.withValues(
                                                      alpha: 0.85,
                                                    )
                                                  : cs.onSurface.withValues(
                                                      alpha: 0.45,
                                                    ),
                                            ),
                                          ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: _primary,
                                  ),
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
                        _aiCategorizing
                            ? 'AI suggesting category...'
                            : 'AI suggested this category',
                        style: TextStyle(
                          fontSize: 12,
                          color: switch (_aiLeafColor) {
                            'green' => Colors.green.shade700,
                            'orange' => Colors.orange.shade800,
                            'red' => Colors.red.shade700,
                            _ => cs.onSurface.withValues(alpha: 0.5),
                          },
                        ),
                      ),
                    ],
                    if (_isEditing) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _recategorizing || _saving
                            ? null
                            : _recategorizeCurrentTransaction,
                        child: _recategorizing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Recategorize'),
                      ),
                    ],
                    if (_categoryError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _categoryError!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                        ),
                      ),
                      TextButton(
                        onPressed: _loadCategories,
                        child: const Text('Retry'),
                      ),
                    ],
                    if (!_loadingCategories &&
                        _categoryError == null &&
                        _filteredCategories.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No ${_isIncome ? 'income' : 'expense'} categories yet. Add some in Supabase.',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
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
                          backgroundColor: cs.surface,
                          elevation: 0,
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: _addTxPillDecoration(context),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: cs.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
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
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [],
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
            child: _Seg(label: 'Income', selected: isIncome, onTap: onIncome),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
                color: selected
                    ? Colors.white
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
