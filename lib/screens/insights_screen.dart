import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/analytics/insights_export.dart';
import 'package:infaq/analytics/insights_format.dart';
import 'package:infaq/analytics/insights_models.dart';
import 'package:infaq/analytics/insights_service.dart';
import 'package:infaq/ui/infaq_widgets.dart';
import 'package:infaq/ui/insights_export_period_sheet.dart';

const Color _kHeaderMint = Color(0xFFE8F2EA);

/// Analytics / Insights tab. Loads Supabase data for the signed-in user only.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    required this.refreshToken,
    this.currencyCode,
  });

  /// Bump when home refreshes transactions so this tab reloads.
  final int refreshToken;
  final String? currencyCode;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _service = InsightsService(Supabase.instance.client);
  InsightsTimeRange _presetRange = InsightsTimeRange.thisMonth;
  bool _customPeriodActive = false;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _customPeriodLabel;
  InsightsPayload? _data;
  bool _loading = true;
  String? _error;
  bool _exporting = false;

  String get _effectiveFilterDescription {
    if (_customPeriodActive && (_customPeriodLabel != null && _customPeriodLabel!.isNotEmpty)) {
      return _customPeriodLabel!;
    }
    return _presetRange.shortLabel;
  }

  String _trendSectionTitle(InsightsPayload p) {
    if (p.range == InsightsTimeRange.thisYear) return 'Spending by month';
    if (_customPeriodActive && p.trendBars.length > 6) return 'Spending by month';
    return 'Spending trend';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant InsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Not signed in';
          _data = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final InsightsPayload payload;
      if (_customPeriodActive &&
          _customStart != null &&
          _customEnd != null &&
          (_customPeriodLabel != null && _customPeriodLabel!.isNotEmpty)) {
        payload = await _service.loadForExportPeriod(
          userId: user.id,
          periodStart: _customStart!,
          periodEnd: _customEnd!,
          periodLabel: _customPeriodLabel!,
        );
      } else {
        payload = await _service.load(userId: user.id, range: _presetRange);
      }
      if (!mounted) return;
      setState(() {
        _data = payload;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _data = null;
      });
    }
  }

  Future<void> _onPresetChanged(InsightsTimeRange r) async {
    if (!_customPeriodActive && r == _presetRange) return;
    setState(() {
      _presetRange = r;
      _customPeriodActive = false;
      _customStart = null;
      _customEnd = null;
      _customPeriodLabel = null;
    });
    await _load();
  }

  Future<void> _openCustomPeriodPicker() async {
    final sel = await showInsightsExportPeriodSheet(
      context,
      currentFilterDescription: _effectiveFilterDescription,
      showUseCurrentFilterOption: false,
      title: 'Choose period',
      subtitle: 'Select a year, month, single day, or custom date range for Insights.',
      continueButtonLabel: 'Apply',
    );
    if (!mounted || sel == null || sel.useCurrentScreenFilter) return;
    setState(() {
      _customPeriodActive = true;
      _customStart = sel.start;
      _customEnd = sel.end;
      _customPeriodLabel = sel.label;
    });
    await _load();
  }

  String _fmt(double v) => formatInsightsMoney(widget.currencyCode ?? _data?.currency, v);

  Future<void> _exportWithFormat(bool asPdf) async {
    if (_exporting) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      showInfaqSnack(context, 'Not signed in');
      return;
    }

    final sel = await showInsightsExportPeriodSheet(
      context,
      currentFilterDescription: _effectiveFilterDescription,
    );
    if (!mounted || sel == null) return;

    setState(() => _exporting = true);
    try {
      late final InsightsPayload payload;
      if (sel.useCurrentScreenFilter) {
        final p = _data;
        if (p == null) {
          if (mounted) showInfaqSnack(context, 'Insights still loading. Try again in a moment.');
          return;
        }
        payload = p;
      } else {
        payload = await _service.loadForExportPeriod(
          userId: user.id,
          periodStart: sel.start!,
          periodEnd: sel.end!,
          periodLabel: sel.label,
        );
      }

      final code = widget.currencyCode ?? payload.currency;
      if (asPdf) {
        await shareInsightsPdf(payload, code);
      } else {
        await shareInsightsCsv(payload);
      }
    } catch (e) {
      if (mounted) {
        showInfaqSnack(
          context,
          asPdf ? 'Could not export PDF: $e' : 'Could not export CSV: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = _data;

    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isDark ? const Color(0xFF1A2520) : _kHeaderMint,
                  cs.surface,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Insights',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Spending overview & trends',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _loading ? null : _openCustomPeriodPicker,
                          iconSize: 25,
                          icon: Icon(Icons.schedule_rounded, color: cs.primary),
                          tooltip: _customPeriodActive && (_customPeriodLabel != null && _customPeriodLabel!.isNotEmpty)
                              ? _customPeriodLabel!
                              : 'Date range',
                        ),
                      ],
                    ),
                    if (_customPeriodActive &&
                        _customPeriodLabel != null &&
                        _customPeriodLabel!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _customPeriodLabel!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.primary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final r in InsightsTimeRange.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(r.shortLabel),
                                selected: !_customPeriodActive && _presetRange == r,
                                onSelected: _loading ? null : (_) => _onPresetChanged(r),
                                selectedColor: cs.primary.withValues(alpha: 0.22),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: (!_customPeriodActive && _presetRange == r)
                                      ? cs.primary
                                      : cs.onSurface.withValues(alpha: 0.75),
                                  fontSize: 13,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: cs.primary,
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(_error!, style: TextStyle(color: cs.onSurface)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    )
                  : _loading && p == null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 80),
                              child: Center(child: CircularProgressIndicator(color: cs.primary)),
                            ),
                          ],
                        )
                      : p == null
                          ? const SizedBox.shrink()
                          : ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                              children: [
                                if (_loading)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      borderRadius: BorderRadius.circular(99),
                                      color: cs.primary,
                                    ),
                                  ),
                                if (!p.hasAnyTransactions) ...[
                                  _EmptyTxBanner(cs: cs),
                                  const SizedBox(height: 16),
                                ],
                                _SummaryStrip(payload: p, format: _fmt, cs: cs),
                                const SizedBox(height: 20),
                                _SectionTitle('Spending by category', cs),
                                const SizedBox(height: 10),
                                _CategoryCard(payload: p, format: _fmt, cs: cs),
                                const SizedBox(height: 20),
                                _SectionTitle(_trendSectionTitle(p), cs),
                                const SizedBox(height: 10),
                                _TrendCard(payload: p, format: _fmt, cs: cs),
                                const SizedBox(height: 20),
                                _SectionTitle('This month vs last month', cs),
                                const SizedBox(height: 10),
                                _CompareCard(payload: p, format: _fmt, cs: cs),
                                const SizedBox(height: 20),
                                _SectionTitle('Subscriptions', cs),
                                const SizedBox(height: 10),
                                _SubscriptionCard(payload: p, format: _fmt, cs: cs),
                                const SizedBox(height: 20),
                                _SectionTitle('Goals', cs),
                                const SizedBox(height: 10),
                                _GoalsCard(payload: p, format: _fmt, cs: cs),
                                const SizedBox(height: 20),
                                _SectionTitle('Smart insights', cs),
                                const SizedBox(height: 10),
                                ...p.smartInsights.map(
                                  (i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _InsightTile(item: i, cs: cs),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _SectionTitle('Export', cs),
                                const SizedBox(height: 10),
                                _ExportCard(
                                  busy: _exporting,
                                  onCsv: () => _exportWithFormat(false),
                                  onPdf: () => _exportWithFormat(true),
                                  cs: cs,
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

class _EmptyTxBanner extends StatelessWidget {
  const _EmptyTxBanner({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, color: cs.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No transactions found in your history window. Add income and expenses in Management to unlock charts and comparisons.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.cs);
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.payload, required this.format, required this.cs});

  final InsightsPayload payload;
  final String Function(double) format;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Balance', format(payload.balance)),
      ('Income', format(payload.periodIncome)),
      ('Expenses', format(payload.periodExpense)),
      ('Net', format(payload.periodNet)),
      ('Savings rate', '${payload.savingsRatePct.toStringAsFixed(1)}%'),
    ];
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (label, value) = items[i];
          return Container(
            width: 132,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const Spacer(),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.payload, required this.format, required this.cs});

  final InsightsPayload payload;
  final String Function(double) format;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final slices = payload.categorySlices;
    final total = slices.fold<double>(0, (a, b) => a + b.amount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6B9BD1).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Expense categories · ${payload.periodLabel}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (slices.isEmpty || total < 1e-6)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No expense categories in this period.',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 1,
                  centerSpaceRadius: 48,
                  sections: [
                    for (final s in slices)
                      PieChartSectionData(
                        color: s.color,
                        value: s.amount,
                        title: '${(s.amount / total * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        radius: 52,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...slices.take(8).map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          format(s.amount),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.payload, required this.format, required this.cs});

  final InsightsPayload payload;
  final String Function(double) format;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final bars = payload.trendBars;
    if (bars.isEmpty) {
      return _mutedCard(
        cs,
        child: Center(
          child: Text(
            'No expense data for this view.',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    final maxY = bars.fold<double>(0, (m, e) => e.amount > m ? e.amount : m);
    final top = maxY <= 0 ? 100.0 : maxY * 1.15;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            maxY: top,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: top > 0 ? top / 4 : 1,
              getDrawingHorizontalLine: (v) => FlLine(
                color: cs.outline.withValues(alpha: 0.12),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (v, m) => Text(
                    v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                    style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        bars[i].label,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < bars.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: bars[i].amount,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      color: cs.primary,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _mutedCard(ColorScheme cs, {required Widget child}) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.payload, required this.format, required this.cs});

  final InsightsPayload payload;
  final String Function(double) format;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final c = payload.monthComparison;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          _cmpRow(
            cs,
            format,
            'Income',
            format(c.thisMonthIncome),
            format(c.lastMonthIncome),
            c.incomeDiff,
            c.pctIncome,
            expenseSemantics: false,
          ),
          const Divider(height: 20),
          _cmpRow(
            cs,
            format,
            'Expenses',
            format(c.thisMonthExpense),
            format(c.lastMonthExpense),
            c.expenseDiff,
            c.pctExpense,
            expenseSemantics: true,
          ),
          const Divider(height: 20),
          _cmpRow(
            cs,
            format,
            'Net savings',
            format(c.thisMonthNet),
            format(c.lastMonthNet),
            c.netDiff,
            c.pctNet,
            expenseSemantics: false,
          ),
        ],
      ),
    );
  }

  Widget _cmpRow(
    ColorScheme cs,
    String Function(double) format,
    String label,
    String thisM,
    String lastM,
    double diff,
    double? pct, {
    required bool expenseSemantics,
  }) {
    final upIsGood = !expenseSemantics;
    final diffPositive = diff > 0;
    final good = upIsGood ? diffPositive : !diffPositive;
    final diffColor = good ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final sign = diff >= 0 ? '+' : '−';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'This: $thisM',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.65)),
              ),
            ),
            Expanded(
              child: Text(
                'Last: $lastM',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.65)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Δ $sign${format(diff.abs())}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: diffColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              pct != null ? formatInsightsPercent(pct) : '— %',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.payload, required this.format, required this.cs});

  final InsightsPayload payload;
  final String Function(double) format;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final s = payload.subscriptionAnalytics;
    final next = s.nextPayment;
    final nextLine = next == null
        ? 'No upcoming payment on file'
        : 'Next: ${s.nextPaymentSubscriptionName ?? 'Subscription'} · ${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(cs, 'Active subscriptions', '${s.activeCount}'),
          _kv(cs, 'Inactive', '${s.inactiveCount}'),
          _kv(cs, 'Est. monthly cost', format(s.monthlyRecurringCost)),
          _kv(cs, 'Est. yearly commitment', format(s.yearlyCommittedCost)),
          _kv(cs, 'Subscription-tagged spend', format(s.subscriptionLinkedExpenseInPeriod)),
          const SizedBox(height: 8),
          Text(
            nextLine,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }

  Widget _kv(ColorScheme cs, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55)),
            ),
          ),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.primary)),
        ],
      ),
    );
  }
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.payload, required this.format, required this.cs});

  final InsightsPayload payload;
  final String Function(double) format;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final g = payload.goalAnalytics;
    if (g.totalGoals == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Text(
          'No goals yet. Create one from Management.',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), fontWeight: FontWeight.w600),
        ),
      );
    }
    final near = g.nearestDeadline;
    final nearLine = near == null
        ? null
        : 'Nearest deadline: ${g.nearestDeadlineTitle ?? 'Goal'} · ${near.year}-${near.month.toString().padLeft(2, '0')}-${near.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GoalsCard._kv(cs, 'Goals', '${g.totalGoals}'),
          _GoalsCard._kv(cs, 'Total saved', format(g.totalSaved)),
          if (g.showLowProgressDeadlineWarning) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'A goal has a close deadline with low progress — consider topping up.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          ],
          if (nearLine != null) ...[
            const SizedBox(height: 8),
            Text(
              nearLine,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55)),
            ),
          ],
          const SizedBox(height: 12),
          ...g.rows.take(6).map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.title,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.onSurface),
                            ),
                          ),
                          Text(
                            '${r.progressPct.toStringAsFixed(0)}%',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (r.progressPct / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${format(r.currentAmount)} / ${format(r.targetAmount)}',
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static Widget _kv(ColorScheme cs, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55)),
            ),
          ),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.primary)),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.item, required this.cs});

  final SmartInsightItem item;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.iconBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
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
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.busy,
    required this.onCsv,
    required this.onPdf,
    required this.cs,
  });

  final bool busy;
  final VoidCallback onCsv;
  final VoidCallback onPdf;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Download data',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 8),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: onCsv,
              icon: const Icon(Icons.table_chart_outlined, size: 20),
              label: const Text('Export CSV'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: const Text('Export PDF'),
            ),
          ],
        ],
      ),
    );
  }
}
