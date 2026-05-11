import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/services/subscription_reminder_local_notifications.dart';
import 'package:infaq/security/input_sanitizer.dart';
import 'package:infaq/subscription/subscription_analytics.dart';
import 'package:infaq/subscription/subscription_icon_picker_sheet.dart';
import 'package:infaq/subscription/subscription_preset_icons.dart';
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
  String? _selectedIconKey;
  Uint8List? _iconPreviewBytes;
  final ImagePicker _picker = ImagePicker();
  bool _uploadingIcon = false;
  bool _saving = false;

  static const _cycles = [('monthly', 'Monthly'), ('yearly', 'Yearly')];

  String? _currencySuffix() {
    switch (widget.currencyCode?.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
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
    _selectedIconKey = validatedSubscriptionIconKey(s['icon_key']?.toString());
    final p = s['icon_url']?.toString().trim();
    if (_selectedIconKey != null) {
      _iconStoragePath = null;
    } else {
      _iconStoragePath = p != null && p.isNotEmpty ? p : null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  (String ext, String mime) _imageExtAndMime(String lowerName) {
    if (lowerName.endsWith('.webp')) return ('webp', 'image/webp');
    if (lowerName.endsWith('.png')) return ('png', 'image/png');
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return ('jpg', 'image/jpeg');
    }
    return ('jpg', 'image/jpeg');
  }

  Future<void> _pickIconFromGallery() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _uploadingIcon = true);
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
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
      final (ext, mime) = _imageExtAndMime(lower);
      final fileName = 'sub_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = InfaqSubscriptionIconStorage.customUploadPath(
        user.id,
        fileName,
      );
      await Supabase.instance.client.storage
          .from(InfaqSubscriptionIconStorage.userUploadBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime),
          );
      if (!mounted) return;
      setState(() {
        _iconPreviewBytes = bytes;
        _iconStoragePath = path;
        _selectedIconKey = null;
        _uploadingIcon = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingIcon = false);
        showInfaqSnack(
          context,
          'Could not upload icon right now. Please try again.',
        );
      }
    }
  }

  Future<void> _onEditIcon() async {
    await showSubscriptionIconPickerSheet(
      context: context,
      onPresetChosen: (key) {
        setState(() {
          _selectedIconKey = validatedSubscriptionIconKey(key);
          _iconStoragePath = null;
          _iconPreviewBytes = null;
        });
      },
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
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: kServiceFormGreen),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _nextDate = picked);
  }

  Future<void> _save() async {
    final name = InputSanitizer.cleanText(_nameCtrl.text, maxLength: 80);
    final amount = InputSanitizer.parsePositiveAmount(_amountCtrl.text);
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
      final preset = validatedSubscriptionIconKey(_selectedIconKey);
      final path = _iconStoragePath?.trim();
      if (preset != null) {
        patch['icon_key'] = preset;
        patch['icon_url'] = null;
      } else if (path != null && path.isNotEmpty) {
        patch['icon_url'] = path;
        patch['icon_key'] = null;
      } else {
        patch['icon_key'] = null;
        patch['icon_url'] = null;
      }

      await Supabase.instance.client
          .from('subscriptions')
          .update(patch)
          .eq('id', id)
          .eq('user_id', user.id);

      if (!mounted) return;
      final updatedSub = Map<String, dynamic>.from(widget.subscription);
      updatedSub.addAll(patch);
      updatedSub['id'] = id;
      unawaited(
        SubscriptionReminderLocalNotifications.replaceRemindersForSubscription(
          updatedSub,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showInfaqSnack(
          context,
          'Could not save subscription right now. Please try again.',
        );
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
        content: Text(
          'Remove "${_nameCtrl.text}"?',
          style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
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

    try {
      await SubscriptionReminderLocalNotifications.cancelRemindersForSubscriptionId(
        id,
      );
      final path = _iconStoragePath?.trim();
      if (path != null &&
          path.isNotEmpty &&
          !path.startsWith('http://') &&
          !path.startsWith('https://')) {
        try {
          final bucket = path.startsWith('custom/')
              ? InfaqSubscriptionIconStorage.userUploadBucket
              : InfaqSubscriptionIconStorage.legacyUserIconBucket;
          await Supabase.instance.client.storage.from(bucket).remove([path]);
        } catch (_) {}
      }
      await Supabase.instance.client
          .from('subscriptions')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not delete subscription right now. Please try again.',
        );
      }
    }
  }

  ImageProvider<Object>? _iconProvider() {
    if (_iconPreviewBytes != null) return MemoryImage(_iconPreviewBytes!);
    final presetKey = validatedSubscriptionIconKey(_selectedIconKey);
    if (presetKey != null) {
      final u = InfaqSubscriptionIconStorage.presetPublicUrl(
        Supabase.instance.client,
        presetKey,
      );
      if (u != null && u.isNotEmpty) return NetworkImage(u);
    }
    final resolved = InfaqSubscriptionIconStorage.resolveDisplayUrl(
      Supabase.instance.client,
      _iconStoragePath,
    );
    if (resolved != null && resolved.isNotEmpty) return NetworkImage(resolved);
    return null;
  }

  bool _hasIconSelection() => _iconProvider() != null;

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
              icon: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade600,
                size: 24,
              ),
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
                            color: isDark
                                ? cs.surfaceContainerHigh
                                : const Color(0xFFF7F8F7),
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
                                    backgroundColor: isDark
                                        ? cs.surfaceContainerHighest
                                        : Colors.white,
                                    backgroundImage: _iconProvider(),
                                    child: _hasIconSelection()
                                        ? null
                                        : Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.5,
                                            ),
                                            size: 28,
                                          ),
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
                                  _hasIconSelection()
                                      ? 'Tap to change preset'
                                      : 'Tap to choose a preset icon',
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _uploadingIcon || _saving
                          ? null
                          : _pickIconFromGallery,
                      icon: const Icon(Icons.photo_library_outlined, size: 22),
                      label: const Text(
                        'Upload from gallery',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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
                  const SizedBox(height: 18),
                  Semantics(
                    label: 'Subscription active',
                    toggled: _isActive,
                    child: Container(
                      decoration: infaqServicePillDecoration(context),
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 4,
                        bottom: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                            activeTrackColor: kServiceFormGreen,
                            inactiveTrackColor: cs.onSurface.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ],
                      ),
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
