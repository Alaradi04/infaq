import 'package:flutter/material.dart';

import 'package:infaq/services/notification_preferences_service.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const Color _kPrimary = Color(0xFF4D6658);
const Color _kHeaderMint = Color(0xFFE8F2EA);
const Color _kHeaderMintDark = Color(0xFF1A2520);

/// Notification prefs only: no push, SMS, or AI pipeline.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _loading = true;
  String? _error;
  bool _allowNotifications = true;
  bool _smsAutoRecording = false;
  bool _savingNotifications = false;
  bool _savingSms = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await NotificationPreferencesService.instance.loadOrCreateForSettings();
      if (!mounted) return;
      setState(() {
        _allowNotifications = p.notificationsEnabled;
        _smsAutoRecording = p.smsAutoRecordingEnabled;
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

  Future<void> _onAllowNotificationsChanged(bool v) async {
    setState(() {
      _allowNotifications = v;
      _savingNotifications = true;
    });
    try {
      await NotificationPreferencesService.instance.updateNotificationsEnabled(v);
    } catch (e) {
      if (mounted) {
        showInfaqSnack(context, 'Could not save: $e');
        setState(() => _allowNotifications = !v);
      }
    } finally {
      if (mounted) setState(() => _savingNotifications = false);
    }
  }

  Future<void> _onSmsChanged(bool v) async {
    setState(() {
      _smsAutoRecording = v;
      _savingSms = true;
    });
    try {
      await NotificationPreferencesService.instance.updateSmsAutoRecordingEnabled(v);
    } catch (e) {
      if (mounted) {
        showInfaqSnack(context, 'Could not save: $e');
        setState(() => _smsAutoRecording = !v);
      }
    } finally {
      if (mounted) setState(() => _savingSms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? _kHeaderMintDark : _kHeaderMint;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final guidanceBg = isDark ? cs.surfaceContainerHigh : const Color(0xFFEEF7F0);
    final guidanceBorder = isDark ? cs.outline.withValues(alpha: 0.35) : const Color(0xFFD4E3D8);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfaqServiceFormHeader(
            backgroundColor: headerBg,
            title: 'Notification settings',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load settings.\n$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Allow notifications',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Text(
                              'Receive important alerts, reminders, and AI insights.',
                              style: TextStyle(fontSize: 13, height: 1.35, color: muted),
                            ),
                          ),
                          value: _allowNotifications,
                          onChanged: _savingNotifications ? null : _onAllowNotificationsChanged,
                          activeTrackColor: isDark ? cs.primary : _kPrimary,
                          activeThumbColor: Colors.white,
                          inactiveTrackColor: Colors.grey.shade300,
                          inactiveThumbColor: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'SMS auto recording',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Text(
                              'Allow INFAQ to detect bank SMS messages and record transactions automatically.',
                              style: TextStyle(fontSize: 13, height: 1.35, color: muted),
                            ),
                          ),
                          value: _smsAutoRecording,
                          onChanged: _savingSms ? null : _onSmsChanged,
                          activeTrackColor: isDark ? cs.primary : _kPrimary,
                          activeThumbColor: Colors.white,
                          inactiveTrackColor: Colors.grey.shade300,
                          inactiveThumbColor: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: guidanceBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: guidanceBorder),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: isDark ? cs.primary : _kPrimary, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'To use SMS auto recording, allow SMS permission and background access in your phone settings.',
                                  style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
                                ),
                              ),
                            ],
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
