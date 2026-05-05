import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

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

  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _iconPreviewBytes;

  /// Storage path inside the configured storage bucket (saved to `icon_url`).
  String? _iconStoragePath;
  bool _uploadingIcon = false;

  static const _cycles = [('monthly', 'Monthly'), ('yearly', 'Yearly')];

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
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: kServiceFormGreen),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _nextDate = picked);
  }

  Future<void> _pickIcon(ImageSource source) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _uploadingIcon = true);
    try {
      final x = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 88,
      );
      if (x == null || !mounted) {
        setState(() => _uploadingIcon = false);
        return;
      }

      final bytes = await x.readAsBytes();
      final lower = x.name.toLowerCase();
      final ext = lower.endsWith('.png') ? 'png' : 'jpg';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final path =
          '${user.id}/sub_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from(InfaqSubscriptionIconStorage.bucket)
          .uploadBinary(
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

  Future<void> _onIconFieldTap() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

  void _cancel() => Navigator.pop(context);

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(
      _amountCtrl.text.replaceAll(',', '').replaceAll(r'$', ''),
    );
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

      final row = <String, Object?>{
        'user_id': user.id,
        'name': name,
        'amount': amount,
        'billing_cycle': _cycle,
        'next_payment': dateStr,
        'is_active': true,
      };
      if (_iconStoragePath != null && _iconStoragePath!.trim().isNotEmpty) {
        row['icon_url'] = _iconStoragePath!.trim();
      }

      await Supabase.instance.client.from('subscriptions').insert(row);

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

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark
        ? Color.lerp(cs.primaryContainer, cs.surface, 0.35)!
        : kInfaqMgmtHeaderMint;

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
            backgroundColor: headerBg,
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
                    label: 'Icon',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _uploadingIcon ? null : _onIconFieldTap,
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8F7),
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
                                    backgroundColor: Colors.white,
                                    backgroundImage: _iconPreviewBytes != null
                                        ? MemoryImage(_iconPreviewBytes!)
                                        : (_iconStoragePath != null &&
                                                  _iconStoragePath!.isNotEmpty
                                              ? NetworkImage(
                                                  InfaqSubscriptionIconStorage.resolveDisplayUrl(
                                                    Supabase.instance.client,
                                                    _iconStoragePath!,
                                                  )!,
                                                )
                                              : null),
                                    child:
                                        _iconPreviewBytes == null &&
                                            (_iconStoragePath == null ||
                                                _iconStoragePath!.isEmpty)
                                        ? Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: Colors.grey.shade500,
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
                                    color: Colors.black.withValues(alpha: 0.55),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.black.withValues(alpha: 0.25),
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
                        side: BorderSide(
                          color: kServiceFormGreen.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        backgroundColor: Colors.white,
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
