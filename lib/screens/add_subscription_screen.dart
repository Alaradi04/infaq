import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/security/input_sanitizer.dart';
import 'package:infaq/subscription/subscription_icon_picker_sheet.dart';
import 'package:infaq/subscription/subscription_preset_icons.dart';
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

  /// Preset from catalog → saved as `icon_key`.
  String? _selectedIconKey;

  /// Storage path inside `subscription-icons` (saved to `icon_url`).
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
      case 'JPY':
        return '¥';
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
      final x = await _imagePicker.pickImage(
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

  Future<void> _onIconFieldTap() async {
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

  ImageProvider<Object>? _iconAvatarProvider() {
    if (_iconPreviewBytes != null) return MemoryImage(_iconPreviewBytes!);
    final presetKey = validatedSubscriptionIconKey(_selectedIconKey);
    if (presetKey != null) {
      final u = InfaqSubscriptionIconStorage.presetPublicUrl(
        Supabase.instance.client,
        presetKey,
      );
      if (u != null && u.isNotEmpty) return NetworkImage(u);
    }
    final path = _iconStoragePath?.trim();
    if (path != null && path.isNotEmpty) {
      final u = InfaqSubscriptionIconStorage.resolveDisplayUrl(
        Supabase.instance.client,
        path,
      );
      if (u != null && u.isNotEmpty) return NetworkImage(u);
    }
    return null;
  }

  bool _hasIconSelection() => _iconAvatarProvider() != null;

  void _cancel() => Navigator.pop(context);

  Future<void> _save() async {
    final name = InputSanitizer.cleanText(_nameCtrl.text, maxLength: 80);
    final amount = InputSanitizer.parsePositiveAmount(_amountCtrl.text);
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
      final preset = validatedSubscriptionIconKey(_selectedIconKey);
      final path = _iconStoragePath?.trim();
      if (preset != null) {
        row['icon_key'] = preset;
        row['icon_url'] = null;
      } else if (path != null && path.isNotEmpty) {
        row['icon_url'] = path;
        row['icon_key'] = null;
      } else {
        row['icon_key'] = null;
        row['icon_url'] = null;
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
        showInfaqSnack(
          context,
          'Could not save subscription right now. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffix = _currencySuffix();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);

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
                                    backgroundImage: _iconAvatarProvider(),
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
                      onPressed: (_uploadingIcon || _saving)
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
