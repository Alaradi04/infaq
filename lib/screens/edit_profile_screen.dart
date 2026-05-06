import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/avatar_storage.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const List<String> _kCurrencyCodes = ['BHD', 'USD', 'EUR', 'SAR', 'GBP'];

/// Full-screen **Edit Profile**: avatar, name, currency, save, password, logout, delete.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialCurrency,
    required this.initialProfilePhotoPath,
    required this.initialAvatarPublicUrl,
  });

  final String? initialName;
  final String? initialCurrency;
  final String? initialProfilePhotoPath;
  final String? initialAvatarPublicUrl;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late String _currency;
  final ImagePicker _picker = ImagePicker();

  String? _photoPathInStorage;
  String? _avatarPublicUrl;
  Uint8List? _pickedPreviewBytes;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _emailCtrl = TextEditingController(
      text: Supabase.instance.client.auth.currentUser?.email ?? '',
    );
    _currency = (widget.initialCurrency != null && widget.initialCurrency!.trim().isNotEmpty)
        ? widget.initialCurrency!.trim().toUpperCase()
        : 'BHD';
    _photoPathInStorage = widget.initialProfilePhotoPath?.trim().isNotEmpty == true
        ? widget.initialProfilePhotoPath!.trim()
        : null;
    _avatarPublicUrl = widget.initialAvatarPublicUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _uploadingPhoto = true);
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (x == null || !mounted) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final bytes = await x.readAsBytes();
      final name = x.name.toLowerCase();
      final ext = name.endsWith('.png') ? 'png' : 'jpg';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final previousPath = _photoPathInStorage;
      final storagePath = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage.from(InfaqAvatarStorage.bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mime),
          );

      if (!mounted) return;
      setState(() {
        _pickedPreviewBytes = bytes;
        _photoPathInStorage = storagePath;
        _avatarPublicUrl = InfaqAvatarStorage.publicUrl(Supabase.instance.client, storagePath);
        _uploadingPhoto = false;
      });

      await Supabase.instance.client.from('users').update({'profile_photo_path': storagePath}).eq('id', user.id);
      if (previousPath != null && previousPath.isNotEmpty && previousPath != storagePath) {
        try {
          await Supabase.instance.client.storage.from(InfaqAvatarStorage.bucket).remove([previousPath]);
        } catch (_) {
          // Ignore cleanup failure; profile now points to the new photo.
        }
      }
    } catch (e) {
      if (mounted) {
        showInfaqSnack(context, 'Could not update photo: $e');
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  Future<void> _onAvatarTap() async {
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
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showInfaqSnack(context, 'Please enter a name.');
      return;
    }

    setState(() => _saving = true);
    try {
      final patch = <String, Object?>{
        'name': name,
        'currency': _currency,
      };
      if (_photoPathInStorage != null && _photoPathInStorage!.isNotEmpty) {
        patch['profile_photo_path'] = _photoPathInStorage;
      }

      await Supabase.instance.client.from('users').update(patch).eq('id', user.id);

      if (!mounted) return;
      showInfaqSnack(context, 'Profile saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final p = newCtrl.text;
              final c = confirmCtrl.text;
              if (p != c) {
                showInfaqSnack(ctx, 'Passwords do not match.');
                return;
              }
              if (p.length < 6) {
                showInfaqSnack(ctx, 'Use at least 6 characters.');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: newCtrl.text));
      if (mounted) showInfaqSnack(context, 'Password updated');
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not update password: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your profile row and signs you out. Your login may still exist on the server unless an admin deletes it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      final path = _photoPathInStorage;
      if (path != null && path.isNotEmpty) {
        await Supabase.instance.client.storage.from(InfaqAvatarStorage.bucket).remove([path]);
      }
    } catch (_) {}

    try {
      await Supabase.instance.client.from('users').delete().eq('id', user.id);
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not remove profile: $e');
    }

    await Supabase.instance.client.auth.signOut();
  }

  ImageProvider<Object>? _avatarImageProvider() {
    if (_pickedPreviewBytes != null) return MemoryImage(_pickedPreviewBytes!);
    final u = _avatarPublicUrl?.trim();
    if (u != null && u.isNotEmpty) return NetworkImage(u);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1A2520) : const Color(0xFFE8F2EA);
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: headerBg,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: cs.surface,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(false),
                          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface),
                        ),
                        Text(
                          'Edit Profile',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _uploadingPhoto ? null : _onAvatarTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.shadow.withValues(alpha: isDark ? 0.28 : 0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Builder(
                                  builder: (_) {
                                    final img = _avatarImageProvider();
                                    return Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 32,
                                          backgroundColor: cs.surfaceContainerHighest,
                                          backgroundImage: img,
                                          child: img == null
                                              ? Icon(Icons.add_a_photo_outlined, color: cs.onSurface.withValues(alpha: 0.65))
                                              : null,
                                        ),
                                        if (_uploadingPhoto)
                                          SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(width: 14),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Your name',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              children: [
                Text('Email', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
                const SizedBox(height: 8),
                _pillField(
                  child: TextField(
                    controller: _emailCtrl,
                    readOnly: true,
                    showCursor: false,
                    enableInteractiveSelection: true,
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.85)),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.55)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Edit name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
                const SizedBox(height: 8),
                _pillField(
                  child: TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: cs.onSurface),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Name',
                      isDense: true,
                      hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.55)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Edit currency', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
                const SizedBox(height: 8),
                _pillField(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _kCurrencyCodes.contains(_currency) ? _currency : _kCurrencyCodes.first,
                      isExpanded: true,
                      dropdownColor: cs.surfaceContainerHigh,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.primary),
                      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
                      items: [
                        for (final c in _kCurrencyCodes)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    elevation: 3,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _changePassword,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    elevation: 3,
                  ),
                  child: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                  label: const Text('Log out'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? cs.surfaceContainerHighest : const Color(0xFF707070),
                    foregroundColor: isDark ? cs.onSurface : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _deleteAccount,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  child: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _pillField({required Widget child}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.22 : 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.15)),
      ),
      child: child,
    );
  }
}
