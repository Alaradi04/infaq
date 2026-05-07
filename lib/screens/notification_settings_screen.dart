import 'package:flutter/material.dart';

import 'package:infaq/screens/notification_debug_screen.dart';
import 'package:infaq/services/bank_notification_sync_service.dart';
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

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  bool _allowNotifications = true;
  bool _smsAutoRecording = false;
  bool _savingNotifications = false;
  bool _savingSms = false;
  bool _listenerEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshListenerStatus();
      BankNotificationSyncService.instance.syncPendingBankTransactions(trigger: 'settings_resumed');
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await NotificationPreferencesService.instance.loadOrCreateForSettings();
      final enabled = await BankNotificationSyncService.instance.isNotificationListenerEnabled();
      if (!mounted) return;
      setState(() {
        _allowNotifications = p.notificationsEnabled;
        _smsAutoRecording = p.smsAutoRecordingEnabled;
        _listenerEnabled = enabled;
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
      if (v) {
        await BankNotificationSyncService.instance.syncPendingBankTransactions(
          trigger: 'auto_recording_enabled',
        );
      }
    } catch (e) {
      if (mounted) {
        showInfaqSnack(context, 'Could not save: $e');
        setState(() => _smsAutoRecording = !v);
      }
    } finally {
      if (mounted) setState(() => _savingSms = false);
    }
  }

  Future<void> _refreshListenerStatus() async {
    final enabled = await BankNotificationSyncService.instance.isNotificationListenerEnabled();
    if (!mounted) return;
    setState(() => _listenerEnabled = enabled);
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
                            'Automatic transaction recording',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Text(
                              'Allow INFAQ to detect bank transaction notifications and record expenses automatically.',
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
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _listenerEnabled
                                ? 'Notification access enabled'
                                : 'Notification access not enabled',
                            style: TextStyle(
                              color: _listenerEnabled ? cs.primary : cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: Icon(
                            _listenerEnabled ? Icons.check_circle : Icons.error_outline,
                            color: _listenerEnabled ? cs.primary : Colors.orange,
                          ),
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
                                  'To enable automatic recording:\n'
                                  '1. Turn on Automatic transaction recording.\n'
                                  '2. Tap Open Android settings.\n'
                                  '3. Choose INFAQ.\n'
                                  '4. Enable notification access.\n'
                                  '5. Keep bank app notifications enabled.',
                                  style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () async {
                            await BankNotificationSyncService.instance.openNotificationListenerSettings();
                          },
                          child: const Text('Open Android settings'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () async {
                            await BankNotificationSyncService.instance.syncPendingBankTransactions(
                              trigger: 'manual_settings',
                            );
                            await _refreshListenerStatus();
                            if (mounted) showInfaqSnack(context, 'Sync requested');
                          },
                          child: const Text('Sync Pending Transactions'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const NotificationDebugScreen(),
                              ),
                            );
                          },
                          child: const Text('Open Notification Debug'),
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
