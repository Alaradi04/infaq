import 'package:flutter/material.dart';

/// Spending vs monthly budget — same layout and styling as the Transactions tab summary card.
class MonthlySpendingBudgetCard extends StatelessWidget {
  const MonthlySpendingBudgetCard({
    super.key,
    required this.periodTitle,
    this.onPrev,
    this.onNext,
    required this.onEditBudget,
    required this.spentLabel,
    required this.budgetLabel,
    required this.showRemainingLine,
    required this.spent,
    required this.budget,
    required this.format,
  });

  static const double _cardRadius = 16;
  static const double _amountSize = 17;

  final String periodTitle;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onEditBudget;
  final String spentLabel;
  final String budgetLabel;
  final bool showRemainingLine;
  final double spent;
  final double budget;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = cs.onSurface;
    final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    final remaining = budget - spent;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.22 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (onPrev != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onPrev,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: cs.primary,
                    size: 22,
                  ),
                )
              else
                const SizedBox(width: 40),
              Expanded(
                child: Text(
                  periodTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: cs.primary,
                  ),
                ),
              ),
              if (onNext != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onNext,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.primary,
                    size: 22,
                  ),
                )
              else
                const SizedBox(width: 40),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onEditBudget,
                icon: Icon(Icons.edit_outlined, color: cs.primary, size: 20),
                tooltip: 'Edit budget',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spentLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        format(spent),
                        style: TextStyle(
                          fontSize: _amountSize,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: Container(
                      width: 1,
                      height: 36,
                      color: cs.outline.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      budgetLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        budget > 0 ? format(budget) : '—',
                        style: TextStyle(
                          fontSize: _amountSize,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withValues(alpha: 0.5),
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: budget > 0 ? progress.clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
          if (showRemainingLine) ...[
            const SizedBox(height: 10),
            if (budget > 0)
              Text(
                remaining >= 0
                    ? 'Remaining: ${format(remaining)}'
                    : 'Over budget by ${format(-remaining)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: remaining >= 0
                      ? onSurface.withValues(alpha: 0.48)
                      : cs.error,
                ),
              )
            else
              Text(
                'Set a monthly budget from Transactions (pencil icon).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: onSurface.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
