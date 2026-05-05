import 'package:flutter/material.dart';

const Color _kInfaqCardTint = Color(0xFFEEF5F0);
const Color _kInfaqPrimary = Color(0xFF3F5F4A);

/// Single AI insight card matching INFAQ home/insights style.
class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.title,
    required this.message,
    required this.insightType,
    required this.severity,
    this.forceIcon,
    this.forceShowProgress = false,
  });

  final String title;
  final String message;
  final String insightType;
  final String severity;
  final IconData? forceIcon;
  final bool forceShowProgress;

  factory AiInsightCard.fromMap(Map<String, dynamic> map) {
    return AiInsightCard(
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      insightType: (map['type'] ?? 'spending_behavior').toString(),
      severity: (map['severity'] ?? 'low').toString(),
    );
  }

  factory AiInsightCard.loading() {
    return const AiInsightCard(
      title: 'Loading insights…',
      message: 'Fetching personalized tips based on your activity.',
      insightType: 'spending_behavior',
      severity: 'low',
      forceShowProgress: true,
    );
  }

  factory AiInsightCard.fallback() {
    return const AiInsightCard(
      title: 'Smart insights',
      message: 'Add more transactions to unlock personalized insights.',
      insightType: 'spending_behavior',
      severity: 'low',
      forceIcon: Icons.lightbulb_outline_rounded,
    );
  }

  static IconData iconForType(String type) {
    switch (type) {
      case 'sustainability':
        return Icons.eco_rounded;
      case 'spending_behavior':
        return Icons.trending_up_rounded;
      case 'saving_tip':
        return Icons.savings_outlined;
      case 'budget_tip':
        return Icons.account_balance_wallet_outlined;
      case 'goal_tip':
        return Icons.flag_outlined;
      case 'subscription_tip':
        return Icons.subscriptions_outlined;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  static Color severityAccent(String severity) {
    switch (severity) {
      case 'high':
        return const Color(0xFFC62828);
      case 'medium':
        return const Color(0xFFE65100);
      case 'low':
      default:
        return const Color(0xFF2E7D32);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = severityAccent(severity);
    final icon = forceIcon ?? iconForType(insightType);
    final iconBg = accent.withValues(alpha: isDark ? 0.22 : 0.14);
    final borderTint = accent.withValues(alpha: isDark ? 0.55 : 0.35);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHigh : _kInfaqCardTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: borderTint,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: forceShowProgress
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: _kInfaqPrimary.withValues(alpha: isDark ? 0.9 : 1),
                      ),
                    )
                  : Icon(icon, color: isDark ? cs.primary : _kInfaqPrimary, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
