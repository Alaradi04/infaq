import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/category/category_icons.dart';
import 'package:infaq/security/input_sanitizer.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const _primary = kInfaqPrimaryGreen;

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _supportsCategoryIconKey = true;
  bool _catSelectMode = false;
  final Set<String> _selectedCatIds = <String>{};
  final Set<String> _removingCatIds = <String>{};
  bool _bulkDeletingCats = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      dynamic res;
      try {
        try {
          final global = await supabase
              .from('categories')
              .select('id,name,type,user_id,icon_key,color')
              .isFilter('user_id', null)
              .order('name');
          final mine = await supabase
              .from('categories')
              .select('id,name,type,user_id,icon_key,color')
              .eq('user_id', user.id)
              .order('name');
          res = [...(global as List<dynamic>), ...(mine as List<dynamic>)];
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
          final global = await supabase
              .from('categories')
              .select('id,name,type,user_id,icon_key')
              .isFilter('user_id', null)
              .order('name');
          final mine = await supabase
              .from('categories')
              .select('id,name,type,user_id,icon_key')
              .eq('user_id', user.id)
              .order('name');
          res = [...(global as List<dynamic>), ...(mine as List<dynamic>)];
        }
        _supportsCategoryIconKey = true;
      } on PostgrestException catch (e) {
        // Older DB schema: categories.icon_key column does not exist yet.
        if (e.code != '42703') rethrow;
        final global = await supabase
            .from('categories')
            .select('id,name,type,user_id')
            .isFilter('user_id', null)
            .order('name');
        final mine = await supabase
            .from('categories')
            .select('id,name,type,user_id')
            .eq('user_id', user.id)
            .order('name');
        res = [...(global as List<dynamic>), ...(mine as List<dynamic>)];
        _supportsCategoryIconKey = false;
      }

      final list = (res as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Manage categories load failed: $e');
      setState(() {
        _error = 'Could not load categories. Please try again.';
        _loading = false;
      });
    }
  }

  bool _isDefault(Map<String, dynamic> row) {
    final uid = row['user_id'];
    return uid == null;
  }

  List<Map<String, dynamic>> get _customRows => _rows.where((r) => !_isDefault(r)).toList();

  List<Map<String, dynamic>> get _builtInRows => _rows.where(_isDefault).toList();

  void _exitCatSelection() {
    setState(() {
      _catSelectMode = false;
      _selectedCatIds.clear();
    });
  }

  void _toggleCatSelection(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedCatIds.contains(id)) {
        _selectedCatIds.remove(id);
        if (_selectedCatIds.isEmpty) _catSelectMode = false;
      } else {
        _selectedCatIds.add(id);
      }
    });
  }

  void _onCustomCategoryLongPress(String id) {
    if (id.isEmpty) return;
    setState(() {
      _catSelectMode = true;
      _selectedCatIds.add(id);
    });
  }

  void _selectAllCustomCategories() {
    setState(() {
      _catSelectMode = true;
      for (final r in _customRows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) _selectedCatIds.add(id);
      }
    });
  }

  void _clearCategorySelection() {
    setState(() {
      _selectedCatIds.clear();
      _catSelectMode = false;
    });
  }

  Widget _wrapListCardExit({required bool exiting, required Widget child}) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInCubic,
      offset: exiting ? const Offset(0, -0.05) : Offset.zero,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInCubic,
        opacity: exiting ? 0.0 : 1.0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInCubic,
          scale: exiting ? 0.92 : 1.0,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  /// Built-in "Other" row for reassigning transactions before deleting custom categories.
  String? _fallbackCategoryId(String typeLower) {
    Map<String, dynamic>? pickByNames(List<String> names) {
      for (final r in _rows) {
        if (!_isDefault(r)) continue;
        if ((r['type']?.toString().toLowerCase() ?? '') != typeLower) {
          continue;
        }
        final n = r['name']?.toString().toLowerCase().trim() ?? '';
        for (final want in names) {
          if (n == want || n.contains(want)) {
            return r;
          }
        }
      }
      return null;
    }

    final income = typeLower == 'income';
    final picked = income
        ? pickByNames(const ['other income', 'other'])
        : pickByNames(const ['other expense', 'other', 'misc', 'miscellaneous']);
    if (picked != null) {
      return picked['id']?.toString();
    }
    for (final r in _rows) {
      if (!_isDefault(r)) continue;
      if ((r['type']?.toString().toLowerCase() ?? '') != typeLower) continue;
      final n = r['name']?.toString().toLowerCase() ?? '';
      if (n.contains('other')) {
        return r['id']?.toString();
      }
    }
    return null;
  }

  Future<Map<String, int>> _transactionCountsByCategory(
    List<String> categoryIds,
  ) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null || categoryIds.isEmpty) return {};
    try {
      final res = await supabase
          .from('transactions')
          .select('category_id')
          .eq('user_id', user.id)
          .inFilter('category_id', categoryIds);
      final map = {for (final id in categoryIds) id: 0};
      for (final e in res as List<dynamic>) {
        final row = e as Map<String, dynamic>;
        final c = row['category_id']?.toString();
        if (c != null) {
          map[c] = (map[c] ?? 0) + 1;
        }
      }
      return map;
    } catch (e, st) {
      debugPrint('transactionCountsByCategory: $e\n$st');
      return {for (final id in categoryIds) id: 0};
    }
  }

  Future<Set<String>> _deleteCategoryIdsBatched(List<String> ids) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null || ids.isEmpty) return ids.toSet();
    try {
      await supabase
          .from('categories')
          .delete()
          .inFilter('id', ids)
          .eq('user_id', user.id);
      return <String>{};
    } catch (e, st) {
      debugPrint('Batch delete categories failed: $e\n$st');
      final failed = <String>{};
      for (final id in ids) {
        try {
          await supabase
              .from('categories')
              .delete()
              .eq('id', id)
              .eq('user_id', user.id);
        } catch (e2, st2) {
          debugPrint('Delete category $id failed: $e2\n$st2');
          failed.add(id);
        }
      }
      return failed;
    }
  }

  Future<void> _onBulkDeleteCategories() async {
    final ids = _selectedCatIds.toList();
    if (ids.isEmpty) return;
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    for (final id in ids) {
      Map<String, dynamic>? row;
      for (final r in _rows) {
        if (r['id']?.toString() == id) {
          row = r;
          break;
        }
      }
      if (row == null || _isDefault(row)) {
        if (mounted) {
          showInfaqSnack(context, 'Built-in categories cannot be deleted.');
        }
        return;
      }
    }

    final counts = await _transactionCountsByCategory(ids);
    if (!mounted) return;
    final totalTx = counts.values.fold<int>(0, (a, b) => a + b);
    final n = ids.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n ${n == 1 ? 'category' : 'categories'}?'),
        content: Text(
          totalTx > 0
              ? '$totalTx ${totalTx == 1 ? 'transaction uses' : 'transactions use'} these categories. '
                    'They will be moved to Other Expense or Other Income before removal.\n\n'
                    'This action cannot be undone.'
              : 'This action cannot be undone.',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkDeletingCats = true);
    try {
      for (final id in ids) {
        final txN = counts[id] ?? 0;
        if (txN <= 0) continue;
        Map<String, dynamic>? row;
        for (final r in _rows) {
          if (r['id']?.toString() == id) {
            row = r;
            break;
          }
        }
        if (row == null) {
          if (mounted) {
            showInfaqSnack(context, 'Category not found.');
          }
          return;
        }
        final type = row['type']?.toString().toLowerCase() ?? 'expense';
        final fb = _fallbackCategoryId(type);
        if (fb == null) {
          if (mounted) {
            showInfaqSnack(
              context,
              'No built-in “Other ${type == 'income' ? 'Income' : 'Expense'}” category found. Cannot reassign transactions.',
            );
          }
          return;
        }
        try {
          await supabase
              .from('transactions')
              .update({'category_id': fb})
              .eq('category_id', id)
              .eq('user_id', user.id);
        } catch (e, st) {
          debugPrint('Reassign transactions from $id failed: $e\n$st');
          if (mounted) {
            showInfaqSnack(
              context,
              'Could not reassign transactions right now. Please try again.',
            );
          }
          return;
        }
      }

      final failed = await _deleteCategoryIdsBatched(ids);
      final success = ids.where((id) => !failed.contains(id)).toList();
      if (success.isEmpty) {
        if (failed.isNotEmpty && mounted) {
          showInfaqSnack(
            context,
            'Could not delete categories. They stay selected.',
          );
        }
        return;
      }

      if (mounted) {
        setState(() => _removingCatIds.addAll(success));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _rows.removeWhere((r) => success.contains(r['id']?.toString()));
        _removingCatIds.removeAll(success);
        _selectedCatIds.removeAll(success);
        if (_selectedCatIds.isEmpty) {
          _catSelectMode = false;
        }
      });

      if (failed.isNotEmpty) {
        showInfaqSnack(
          context,
          'Deleted ${success.length} of $n. ${failed.length} could not be removed — still selected.',
        );
      } else {
        showInfaqSnack(
          context,
          'Deleted ${success.length} ${success.length == 1 ? 'category' : 'categories'}.',
        );
      }
    } finally {
      if (mounted) setState(() => _bulkDeletingCats = false);
    }
  }

  Future<void> _addCategory() async {
    final nameCtrl = TextEditingController();
    String type = 'expense';
    String iconKey = kDefaultCategoryIconKey;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('New category'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('Expense'),
                      ),
                      DropdownMenuItem(value: 'income', child: Text('Income')),
                    ],
                    onChanged: (v) => setLocal(() => type = v ?? 'expense'),
                  ),
                  const SizedBox(height: 16),
                  CategoryIconPickerGrid(
                    selectedKey: iconKey,
                    accentColor: _primary,
                    onSelected: (k) => setLocal(() => iconKey = k),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !mounted) return;

    final name = InputSanitizer.cleanText(nameCtrl.text, maxLength: 60);
    if (name.isEmpty) {
      showInfaqSnack(context, 'Enter a category name.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final payload = <String, dynamic>{
        'user_id': user.id,
        'name': name,
        'type': type,
      };
      if (_supportsCategoryIconKey) {
        payload['icon_key'] = validatedCategoryIconKey(iconKey);
      }
      await Supabase.instance.client.from('categories').insert(payload);
      if (mounted) {
        showInfaqSnack(context, 'Category added');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not add category right now. Please try again.',
        );
      }
    }
  }

  Future<void> _editCustom(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;

    final nameCtrl = TextEditingController(text: row['name']?.toString() ?? '');
    var iconKey = validatedCategoryIconKey(row['icon_key']?.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Edit category'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 16),
                  CategoryIconPickerGrid(
                    selectedKey: iconKey,
                    accentColor: _primary,
                    onSelected: (k) => setLocal(() => iconKey = k),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !mounted) return;

    final name = InputSanitizer.cleanText(nameCtrl.text, maxLength: 60);
    if (name.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final payload = <String, dynamic>{'name': name};
      if (_supportsCategoryIconKey) {
        payload['icon_key'] = validatedCategoryIconKey(iconKey);
      }
      await Supabase.instance.client
          .from('categories')
          .update(payload)
          .eq('id', id)
          .eq('user_id', user.id);
      if (mounted) {
        showInfaqSnack(context, 'Updated');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not update category right now. Please try again.',
        );
      }
    }
  }

  Future<void> _deleteCustom(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;

    final name = row['name']?.toString() ?? 'Category';
    final counts = await _transactionCountsByCategory([id]);
    if (!mounted) return;
    final txN = counts[id] ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          txN > 0
              ? 'Remove “$name”? $txN ${txN == 1 ? 'transaction' : 'transactions'} '
                    'will move to Other Expense or Other Income.\n\nThis cannot be undone.'
              : 'Remove “$name”? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      if (txN > 0) {
        final type = row['type']?.toString().toLowerCase() ?? 'expense';
        final fb = _fallbackCategoryId(type);
        if (fb == null) {
          if (mounted) {
            showInfaqSnack(
              context,
              'No built-in “Other ${type == 'income' ? 'Income' : 'Expense'}” category found.',
            );
          }
          return;
        }
        await Supabase.instance.client
            .from('transactions')
            .update({'category_id': fb})
            .eq('category_id', id)
            .eq('user_id', user.id);
      }
      await Supabase.instance.client
          .from('categories')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);
      if (mounted) {
        setState(() {
          _rows.removeWhere((r) => r['id']?.toString() == id);
          _selectedCatIds.remove(id);
          if (_selectedCatIds.isEmpty) {
            _catSelectMode = false;
          }
        });
        showInfaqSnack(context, 'Category deleted');
      }
    } catch (e) {
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not delete category right now. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);
    final appBarBg = _catSelectMode
        ? Color.lerp(headerBg, cs.primary, isDark ? 0.2 : 0.12) ?? headerBg
        : headerBg;

    return PopScope(
      canPop: !_catSelectMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (!mounted) return;
        _exitCatSelection();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: appBarBg,
          foregroundColor: cs.primary,
          elevation: 0,
          leading: _catSelectMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Exit selection',
                  onPressed: _exitCatSelection,
                )
              : null,
          automaticallyImplyLeading: !_catSelectMode,
          title: Text(
            _catSelectMode ? '${_selectedCatIds.length} selected' : 'Categories',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_catSelectMode) ...[
              TextButton(
                onPressed: _selectAllCustomCategories,
                child: Text(
                  'All',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearCategorySelection,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_bulkDeletingCats)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selectedCatIds.isEmpty
                      ? null
                      : _onBulkDeleteCategories,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ],
        ),
        floatingActionButton: _catSelectMode
            ? null
            : FloatingActionButton(
                onPressed: _addCategory,
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add),
              ),
        body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              color: _primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                children: [
                  _sectionTitle(context, 'Your Categories'),
                  const SizedBox(height: 8),
                  if (_customRows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
                      child: Text(
                        'No custom categories yet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ..._customRows.map((row) {
                      final cid = row['id']?.toString() ?? '';
                      return _wrapListCardExit(
                        exiting: _removingCatIds.contains(cid),
                        child: _categoryCard(
                          context,
                          row,
                          isBuiltIn: false,
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  _sectionTitle(context, 'Built-in Categories'),
                  const SizedBox(height: 8),
                  ..._builtInRows.map((row) => _categoryCard(context, row, isBuiltIn: true)),
                ],
              ),
            ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onSurface),
    );
  }

  Widget _categoryCard(BuildContext context, Map<String, dynamic> row, {required bool isBuiltIn}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = (row['type']?.toString() ?? '').toUpperCase();
    final name = row['name']?.toString() ?? '';
    final id = row['id']?.toString() ?? '';
    final selected = !isBuiltIn && _selectedCatIds.contains(id);
    final iconData = categoryIconForDisplay(
      iconKey: row['icon_key']?.toString(),
      name: name,
      type: row['type']?.toString() ?? 'expense',
      categoryId: row['id']?.toString(),
    );
    final categoryColor = categoryDisplayColorFor(
      name,
      categoryId: row['id']?.toString(),
      savedColor: row['color'] ?? row['color_value'] ?? row['hex_color'],
    );

    final outline = cs.outline.withValues(alpha: isDark ? 0.34 : 0.14);
    final showSelected = !isBuiltIn && _catSelectMode && selected;
    final selectedTint = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    final cardColor = showSelected
        ? Color.alphaBlend(selectedTint, cs.surfaceContainerLow)
        : cs.surfaceContainerLow;
    final borderColor =
        showSelected ? cs.primary : outline;
    final borderW = showSelected ? 2.0 : 1.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: borderW),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: isBuiltIn || id.isEmpty ? null : () => _onCustomCategoryLongPress(id),
          onTap: !isBuiltIn && _catSelectMode && id.isNotEmpty
              ? () => _toggleCatSelection(id)
              : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: categoryDisplayTintFor(
                name,
                categoryId: row['id']?.toString(),
                savedColor: row['color'] ?? row['color_value'] ?? row['hex_color'],
                strength: isDark ? 0.78 : 0.84,
              ),
              foregroundColor: categoryColor,
              child: Icon(iconData, size: 22),
            ),
            title: Text(
              name,
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            subtitle: Text(
              '$type · ${isBuiltIn ? 'Default' : 'Yours'}',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.58)),
            ),
            trailing: isBuiltIn
                ? Text(
                    'Built-in',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  )
                : _catSelectMode
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => _editCustom(row),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: _primary,
                          size: 22,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteCustom(row),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red.shade700,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
