import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/subscription/subscription_analytics.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const Color _kCream = Color(0xFFFFF6E8);

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

  double get _totalAllTime =>
      subscriptionAttributedExpenseAllTime(widget.subscription, widget.allTransactions);

  double get _perPeriod => subReadAmount(_amountCtrl.text.replaceAll(',', ''));

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
            fileOptions: FileOptions(contentType: mime, upsert: true),
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
          ],
        ),
      ),
    );
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

  Future<void> _openServiceSite() async {
    final name = _nameCtrl.text.trim();
    final q = Uri.encodeComponent('$name official site');
    final uri = Uri.parse('https://www.google.com/search?q=$q');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final suffix = _currencySuffix();
    final subName = (widget.subscription['name'] ?? 'Subscription').toString();
    final now = DateTime.now();
    final foodThisMonth = foodLikeExpenseInMonth(widget.allTransactions, now);
    final subSpendThisMonth = subscriptionAttributedExpenseInMonth(widget.subscription, widget.allTransactions, now);
    final showOverspendBanner =
        _isActive && foodThisMonth > 0 && subSpendThisMonth > foodThisMonth;

    return Scaffold(
      backgroundColor: Colors.white,
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
          Container(
            decoration: const BoxDecoration(
              color: _kCream,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A)),
                    ),
                    const Expanded(
                      child: Text(
                        'Edit Subscription',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
                      ),
                    ),
                    IconButton(
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 26),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: 72,
                              height: 72,
                              color: const Color(0xFFE8E8E8),
                              child: _iconProvider() != null
                                  ? Image(image: _iconProvider()!, fit: BoxFit.cover)
                                  : Icon(Icons.subscriptions_outlined, size: 36, color: Colors.grey.shade600),
                            ),
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              elevation: 2,
                              child: InkWell(
                                onTap: _uploadingIcon ? null : _onEditIcon,
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: _uploadingIcon
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: kServiceFormGreen),
                                        )
                                      : const Icon(Icons.edit_outlined, size: 18, color: kServiceFormGreen),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: ListenableBuilder(
                            listenable: _nameCtrl,
                            builder: (context, _) {
                              final n = _nameCtrl.text.trim();
                              return Text(
                                n.isNotEmpty ? n : subName,
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InfaqLabeledPillField(
                    label: 'Name',
                    child: InfaqPillTextField(
                      controller: _nameCtrl,
                      hintText: 'Service name',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: infaqServicePillDecoration(context),
                    child: Column(
                      children: [
                        _detailRow(
                          'Billing cycle',
                          InkWell(
                            onTap: () {
                              showModalBottomSheet<void>(
                                context: context,
                                builder: (ctx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final (v, l) in _cycles)
                                        ListTile(
                                          title: Text(l),
                                          trailing: _cycle == v ? const Icon(Icons.check, color: kServiceFormGreen) : null,
                                          onTap: () {
                                            setState(() => _cycle = v);
                                            Navigator.pop(ctx);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _cycles.firstWhere((c) => c.$1 == _cycle, orElse: () => _cycles.first).$2,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                                const Icon(Icons.keyboard_arrow_down_rounded, color: kServiceFormGreen),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                        _detailRow(
                          'amount',
                          InfaqPillAmountStepper(
                            controller: _amountCtrl,
                            currencySuffix: suffix,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        const Divider(height: 24),
                        _detailRow(
                          'Date',
                          InfaqPillDateRow(
                            labelText: formatGoalDateLong(_nextDate),
                            onTap: _pickDate,
                          ),
                        ),
                        const Divider(height: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total amount',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black.withValues(alpha: 0.45),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'All time (from your transactions)',
                                        style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.35)),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${suffix ?? ''}${_totalAllTime.toStringAsFixed(_totalAllTime % 1 == 0 ? 0 : 2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF1A1A1A)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        InfaqPillSwitchRow(
                          title: 'Active subscription',
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          leading: Icon(Icons.power_settings_new_rounded, color: kServiceFormGreen.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  if (showOverspendBanner) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EEE9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFC5D4C8)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                            child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Overspending alert',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.red.shade900),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Your tracked spending on $subName this month is higher than your food and grocery expenses this month.',
                                  style: TextStyle(fontSize: 13, height: 1.35, color: Colors.black.withValues(alpha: 0.55)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openServiceSite,
                      icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                      label: Text('Open ${_nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'service'} online'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5C5C5C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  InfaqPrimaryButton(
                    label: 'Save changes',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, Widget right, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black.withValues(alpha: 0.45)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.35))),
        ],
        const SizedBox(height: 10),
        right,
      ],
    );
  }
}
