import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/app_theme_mode.dart';
import 'package:infaq/screens/ai_usage_debug_screen.dart';
import 'package:infaq/screens/notification_settings_screen.dart';
import 'package:infaq/screens/profile_info_screens.dart';
import 'package:infaq/services/notification_preferences_service.dart';

const Color _kPrimary = Color(0xFF4D6658);
const Color _kProfileHeaderGreen = Color(0xFFE8F5E9);
/// Soft sage ring for the name pill (light mode); aligns with primary green, not blue.
const Color _kNamePillBorderLight = Color(0xFF9DB5A3);
const Color _kLogoutBg = Color(0xFF707070);

/// Main **Profile** tab (bottom nav). Matches app mock: header, user pill, settings, privacy, logout.
class ProfileTabScreen extends StatefulWidget {
  const ProfileTabScreen({
    super.key,
    required this.displayName,
    required this.avatarPublicUrl,
    required this.onOpenEditProfile,
    required this.onDataRefresh,
    this.onHelpAndSupport,
    this.onDataAndPrivacy,
  });

  final String? displayName;
  final String? avatarPublicUrl;
  final Future<void> Function() onOpenEditProfile;
  final VoidCallback onDataRefresh;
  final VoidCallback? onHelpAndSupport;
  final VoidCallback? onDataAndPrivacy;

  @override
  State<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends State<ProfileTabScreen> {
  bool? _profileNotificationsOn;

  @override
  void initState() {
    super.initState();
    _refreshNotificationSummary();
  }

  Future<void> _refreshNotificationSummary() async {
    final on = await NotificationPreferencesService.instance.profileNotificationsEnabled();
    if (mounted) setState(() => _profileNotificationsOn = on);
  }

  Future<void> _openNotificationSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationSettingsScreen(),
      ),
    );
    await _refreshNotificationSummary();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSystem = AppThemeMode.instance.isSystem;
    final name = widget.displayName?.trim();
    final label = (name != null && name.isNotEmpty) ? name : 'Your profile';

    final headerBg = isDark ? const Color(0xFF1A2420) : _kProfileHeaderGreen;
    final titleColor = isDark ? cs.primary : _kPrimary;
    final pillBg = isDark ? cs.surfaceContainerHigh : Colors.white;
    final pillBorder = isDark ? cs.outline.withValues(alpha: 0.35) : _kNamePillBorderLight;
    final onSurface = cs.onSurface;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: titleColor),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () async {
                              await widget.onOpenEditProfile();
                              if (mounted) widget.onDataRefresh();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: pillBg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: pillBorder, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _Avatar(url: widget.avatarPublicUrl, radius: 26),
                                  const SizedBox(width: 12),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 200),
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.chevron_right_rounded, color: onSurface.withValues(alpha: 0.35)),
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
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _shadowCard(
                  context,
                  child: Column(
                    children: [
                      _notificationsRow(context),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _toggleTile(
                        context,
                        title: 'Use device theme',
                        value: isSystem,
                        onChanged: (v) => AppThemeMode.instance.setSystem(v),
                      ),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _toggleTile(
                        context,
                        title: 'Dark mode',
                        value: isDark,
                        onChanged: isSystem ? null : (v) => AppThemeMode.instance.setDark(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _shadowCard(
                  context,
                  child: Column(
                    children: [
                      _navTile(context, title: 'Help and support', onTap: widget.onHelpAndSupport ?? () {}),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _navTile(context, title: 'Data and privacy', onTap: widget.onDataAndPrivacy ?? () {}),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _navTile(
                        context,
                        title: 'AI usage (debug)',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const AiUsageDebugScreen(),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _iconNavTile(
                        context,
                        icon: Icons.shield_outlined,
                        title: 'Privacy Policy',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const PrivacyPolicyScreen(),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _iconNavTile(
                        context,
                        icon: Icons.info_outline_rounded,
                        title: 'About INFAQ',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const AboutInfaqScreen(),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
                      _iconNavTile(
                        context,
                        icon: Icons.help_outline_rounded,
                        title: 'FAQ',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const FaqScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? cs.surfaceContainerHigh : const Color(0xFFEEF7F0),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? cs.outline.withValues(alpha: 0.35) : const Color(0xFFD4E3D8)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: isDark ? cs.primary : _kPrimary, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Data is Private',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isDark ? cs.primary : _kPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'We use AI to analyze your spending locally. Your financial data is encrypted and never shared with third parties.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'v$kInfaqAppVersionLabel',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.35)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    label: const Text('Log out'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF5A5A5A) : _kLogoutBg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      elevation: 2,
                      shadowColor: Colors.black26,
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _shadowCard(BuildContext context, {required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: isDark ? Border.all(color: cs.outline.withValues(alpha: 0.2)) : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
    );
  }

  Widget _toggleTile(
    BuildContext context, {
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
      ),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: isDark(context) ? cs.primary : _kPrimary,
      inactiveThumbColor: Colors.grey.shade400,
      inactiveTrackColor: Colors.grey.shade300,
      onChanged: onChanged,
    );
  }

  bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  Widget _notificationsRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = _profileNotificationsOn == null
        ? '…'
        : (_profileNotificationsOn! ? 'On' : 'Off');
    return ListTile(
      title: Text(
        'Notifications',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
      ),
      subtitle: Text(
        sub,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.35)),
      onTap: _openNotificationSettings,
    );
  }

  Widget _navTile(BuildContext context, {required String title, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface)),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.35)),
      onTap: onTap,
    );
  }

  Widget _iconNavTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? cs.primary : _kPrimary;
    return ListTile(
      leading: Icon(icon, size: 24, color: iconColor),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface)),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.35)),
      onTap: onTap,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.radius});

  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      backgroundImage: u != null && u.isNotEmpty ? NetworkImage(u) : null,
      child: u == null || u.isEmpty ? Icon(Icons.person_rounded, size: radius * 1.1, color: muted) : null,
    );
  }
}
