import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF3F5F4A);
const Color _kProfileHeaderGreen = Color(0xFFE8F5E9);
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
  bool _notificationsOn = true;
  bool _darkModeOn = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.displayName?.trim();
    final label = (name != null && name.isNotEmpty) ? name : 'Your profile';

    return ColoredBox(
      color: Colors.white,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _kProfileHeaderGreen,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profile',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _kPrimary),
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0xFF64B5F6), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
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
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.chevron_right_rounded, color: Colors.black.withValues(alpha: 0.35)),
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
                  child: Column(
                    children: [
                      _toggleTile(
                        title: 'Notifications',
                        value: _notificationsOn,
                        onChanged: (v) => setState(() => _notificationsOn = v),
                      ),
                      Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                      _toggleTile(
                        title: 'Dark mode',
                        value: _darkModeOn,
                        onChanged: (v) => setState(() => _darkModeOn = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _shadowCard(
                  child: Column(
                    children: [
                      _navTile(title: 'Help and support', onTap: widget.onHelpAndSupport ?? () {}),
                      Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                      _navTile(title: 'Data and privacy', onTap: widget.onDataAndPrivacy ?? () {}),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF7F0),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD4E3D8)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: _kPrimary, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Data is Private',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _kPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'We use AI to analyze your spending locally. Your financial data is encrypted and never shared with third parties.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: Colors.black.withValues(alpha: 0.5),
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
                  'v0.1.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.35)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    label: const Text('Log out'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kLogoutBg,
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

  static Widget _shadowCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
    );
  }

  Widget _toggleTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      value: value,
      activeColor: Colors.white,
      activeTrackColor: _kPrimary,
      inactiveThumbColor: Colors.grey.shade400,
      inactiveTrackColor: Colors.grey.shade300,
      onChanged: onChanged,
    );
  }

  Widget _navTile({required String title, required VoidCallback onTap}) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.black.withValues(alpha: 0.35)),
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
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE0E0E0),
      backgroundImage: u != null && u.isNotEmpty ? NetworkImage(u) : null,
      child: u == null || u.isEmpty ? Icon(Icons.person_rounded, size: radius * 1.1, color: Colors.white) : null,
    );
  }
}
