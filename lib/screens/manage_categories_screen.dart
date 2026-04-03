import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const Color _kMint = Color(0xFFECF9E5);
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
      final res = await supabase
          .from('categories')
          .select('id,name,type,user_id')
          .or('user_id.is.null,user_id.eq.${user.id}')
          .order('name');

      final list = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('New category'),
            content: Column(
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
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? 'expense'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
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
      await Supabase.instance.client.from('categories').insert({
        'user_id': user.id,
        'name': name,
        'type': type,
      });
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('categories').update({'name': name}).eq('id', id).eq('user_id', user.id);
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
        content: Text('Remove “$name”? Transactions using it may be blocked by the database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
      await Supabase.instance.client.from('categories').delete().eq('id', id).eq('user_id', user.id);
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kMint,
        foregroundColor: _primary,
        elevation: 0,
        title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCategory,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
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
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final row = _rows[i];
                      final def = _isDefault(row);
                      final type = (row['type']?.toString() ?? '').toUpperCase();
                      final name = row['name']?.toString() ?? '';

                      return ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('$type · ${def ? 'Default' : 'Yours'}'),
                        trailing: def
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  'Built-in',
                                  style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
                                ),
                              )
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
                      );
                    },
                  ),
                ),
    );
  }
}
