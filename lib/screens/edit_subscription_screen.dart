import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/subscription/subscription_analytics.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

class EditSubscriptionScreen extends StatefulWidget {
  const EditSubscriptionScreen({
    super.key,
    required this.subscription,
    required this.allTransactions,
    this.currencyCode,
  });

  final Map<String, dynamic> subscription;
  final List<Map<String, dynamic>> allTransactions;
  final String? currencyCode;

  @override
  State<EditSubscriptionScreen> createState() => _EditSubscriptionScreenState();
}

class _EditSubscriptionScreenState extends State<EditSubscriptionScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late String _cycle;
  late DateTime _nextDate;
  late bool _isActive;
  String? _iconStoragePath;
  Uint8List? _iconPreviewBytes;
  final ImagePicker _picker = ImagePicker();
  bool _uploadingIcon = false;
  bool _saving = false;

  static const _cycles = [
    ('monthly', 'Monthly'),
    ('yearly', 'Yearly'),
  ];

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

  @override
  void initState() {
    super.initState();
    final s = widget.subscription;
    _nameCtrl = TextEditingController(text: (s['name'] ?? '').toString());
    final amt = subReadAmount(s['amount']);
    _amountCtrl = TextEditingController(
      text: amt % 1 == 0 ? amt.toStringAsFixed(0) : amt.toStringAsFixed(2),
    );
    _cycle = (s['billing_cycle'] ?? 'monthly').toString().toLowerCase();
    if (_cycle != 'monthly' && _cycle != 'yearly') _cycle = 'monthly';

    final raw = s['next_payment'] ?? s['next_payment_date'];
    final parsed = raw != null ? DateTime.tryParse(raw.toString()) : null;
    _nextDate = parsed ?? DateTime.now();

    _isActive = parseSubscriptionIsActive(s['is_active']);
    final p = s['icon_url']?.toString().trim();
    _iconStoragePath = p != null && p.isNotEmpty ? p : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon(ImageSource source) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _uploadingIcon = true);
    try {
      final x = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 88);
      if (x == null || !mounted) {
        setState(() => _uploadingIcon = false);
        return;
      }
      final bytes = await x.readAsBytes();
      final lower = x.name.toLowerCase();
      final ext = lower.endsWith('.png') ? 'png' : 'jpg';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final path = '${user.id}/sub_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage.from(InfaqSubscriptionIconStorage.bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime),
          );
      if (!mounted) return;
      setState(() {
        _iconPreviewBytes = bytes;
        _iconStoragePath = path;
        _uploadingIcon = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingIcon = false);
        showInfaqSnack(context, 'Could not upload icon: $e');
      }
    }
  }

  Future<void> _onEditIcon() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickIcon(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickIcon(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Use image URL'),
              onTap: () {
                Navigator.pop(ctx);
                _enterImageUrl();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enterImageUrl() async {
    final ctrl = TextEditingController(
      text: _iconStoragePath != null && _iconStoragePath!.startsWith('http')
          ? _iconStoragePath
          : '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image URL'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/icon.png',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Use URL'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    final uri = Uri.tryParse(value);
    final valid =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host.isNotEmpty);
    if (!valid) {
      showInfaqSnack(context, 'Please enter a valid http/https image URL.');
      return;
    }
    setState(() {
      _iconPreviewBytes = null;
      _iconStoragePath = value;
    });
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

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').replaceAll(r'$', ''));
    final id = widget.subscription['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return;
    if (name.isEmpty) {
      showInfaqSnack(context, 'Enter a name.');
      return;
    }
    if (amount == null || amount <= 0) {
      showInfaqSnack(context, 'Enter a valid amount.');
      return;
    }

    setState(() => _saving = true);
    try {
      final dateStr =
          '${_nextDate.year.toString().padLeft(4, '0')}-${_nextDate.month.toString().padLeft(2, '0')}-${_nextDate.day.toString().padLeft(2, '0')}';

      final patch = <String, Object?>{
        'name': name,
        'amount': amount,
        'billing_cycle': _cycle,
        'next_payment': dateStr,
        'is_active': _isActive,
      };
      if (_iconStoragePath != null && _iconStoragePath!.isNotEmpty) {
        patch['icon_url'] = _iconStoragePath;
      }

      await Supabase.instance.client.from('subscriptions').update(patch).eq('id', id).eq('user_id', user.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showInfaqSnack(context, 'Could not save: $e');
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.subscription['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subscription?'),
        content: Text('Remove "${_nameCtrl.text}"?', style: TextStyle(color: Colors.black.withValues(alpha: 0.7))),
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
    if (ok != true || !mounted) return;

    try {
      final path = _iconStoragePath?.trim();
      if (path != null && path.isNotEmpty) {
        try {
          await Supabase.instance.client.storage.from(InfaqSubscriptionIconStorage.bucket).remove([path]);
        } catch (_) {}
      }
      await Supabase.instance.client.from('subscriptions').delete().eq('id', id).eq('user_id', user.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
    }
  }

  ImageProvider<Object>? _iconProvider() {
    if (_iconPreviewBytes != null) return MemoryImage(_iconPreviewBytes!);
    final resolved = InfaqSubscriptionIconStorage.resolveDisplayUrl(
      Supabase.instance.client,
      _iconStoragePath,
    );
    if (resolved != null && resolved.isNotEmpty) return NetworkImage(resolved);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);
    final suffix = _currencySuffix();

    return Scaffold(
      backgroundColor: cs.surface,
      extendBody: true,
      bottomNavigationBar: InfaqBottomNavBar(
        tabIndex: -1,
        onHome: () => Navigator.pop(context),
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
            title: 'Edit Subscription',
            onBack: () => Navigator.pop(context),
            trailing: IconButton(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 24),
              tooltip: 'Delete',
            ),
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
                    label: 'Icon',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _uploadingIcon ? null : _onEditIcon,
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? cs.surfaceContainerHigh : const Color(0xFFF7F8F7),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: kServiceFormGreen.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: isDark ? cs.surfaceContainerHighest : Colors.white,
                                    backgroundImage: _iconProvider(),
                                    child:
                                        _iconProvider() == null
                                        ? Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: cs.onSurface.withValues(alpha: 0.5),
                                            size: 28,
                                          )
                                        : null,
                                  ),
                                  if (_uploadingIcon)
                                    const SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: kServiceFormGreen,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _iconStoragePath != null &&
                                          _iconStoragePath!.isNotEmpty
                                      ? 'Tap to change picture'
                                      : 'Tap to add subscription icon',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.65),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurface.withValues(alpha: 0.35),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                      showStepper: false,
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
                    label: 'Save changes',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kServiceFormGreen,
                        side: BorderSide(
                          color: kServiceFormGreen.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
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
    );
  }

}
