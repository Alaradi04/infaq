import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/category/category_icons.dart';
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
        res = await supabase
            .from('categories')
            .select('id,name,type,user_id,icon_key')
            .or('user_id.is.null,user_id.eq.${user.id}')
            .order('name');
        _supportsCategoryIconKey = true;
      } on PostgrestException catch (e) {
        // Older DB schema: categories.icon_key column does not exist yet.
        if (e.code != '42703') rethrow;
        res = await supabase
            .from('categories')
            .select('id,name,type,user_id')
            .or('user_id.is.null,user_id.eq.${user.id}')
            .order('name');
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
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _isDefault(Map<String, dynamic> row) {
    final uid = row['user_id'];
    return uid == null;
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

    final name = nameCtrl.text.trim();
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
      if (mounted) showInfaqSnack(context, 'Could not add: $e');
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

    final name = nameCtrl.text.trim();
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
      if (mounted) showInfaqSnack(context, 'Could not update: $e');
    }
  }

  Future<void> _deleteCustom(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;

    final name = row['name']?.toString() ?? 'Category';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Remove “$name”? Transactions using it may be blocked by the database.',
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
      await Supabase.instance.client
          .from('categories')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);
      if (mounted) {
        showInfaqSnack(context, 'Category deleted');
        await _load();
      }
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA),
        foregroundColor: cs.primary,
        elevation: 0,
        title: const Text(
          'Categories',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton(
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
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  final def = _isDefault(row);
                  final type = (row['type']?.toString() ?? '').toUpperCase();
                  final name = row['name']?.toString() ?? '';
                  final iconData = categoryIconForDisplay(
                    iconKey: row['icon_key']?.toString(),
                    name: name,
                    type: row['type']?.toString() ?? 'expense',
                    categoryId: row['id']?.toString(),
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.34 : 0.14)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isDark ? cs.surfaceContainerHighest : const Color(0xFFE8F2EA),
                        foregroundColor: _primary,
                        child: Icon(iconData, size: 22),
                      ),
                      title: Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                      subtitle: Text(
                        '$type · ${def ? 'Default' : 'Yours'}',
                        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.58)),
                      ),
                      trailing: def
                          ? Text('Built-in', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45)))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: () => _editCustom(row),
                                  icon: const Icon(Icons.edit_outlined, color: _primary, size: 22),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteCustom(row),
                                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 22),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
