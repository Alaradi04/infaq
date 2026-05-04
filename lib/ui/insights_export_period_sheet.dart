import 'package:flutter/material.dart';

/// Result of choosing what to export.
class InsightsExportSelection {
  /// Use the already-loaded [InsightsPayload] from the Insights tab (no refetch).
  const InsightsExportSelection.currentFilter()
      : useCurrentScreenFilter = true,
        start = null,
        end = null,
        label = '';

  InsightsExportSelection.custom({
    required DateTime start,
    required DateTime end,
    required this.label,
  })  : useCurrentScreenFilter = false,
        start = start,
        end = end;

  final bool useCurrentScreenFilter;
  final DateTime? start;
  final DateTime? end;
  final String label;
}

class InsightsExportPeriodSheet extends StatefulWidget {
  const InsightsExportPeriodSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.currentFilterDescription,
    this.showUseCurrentFilterOption = true,
    this.continueButtonLabel = 'Continue',
  });

  final String title;
  final String subtitle;
  /// Shown when “Use current filter” is enabled (Insights preset or custom label).
  final String currentFilterDescription;
  final bool showUseCurrentFilterOption;
  final String continueButtonLabel;

  @override
  State<InsightsExportPeriodSheet> createState() => _InsightsExportPeriodSheetState();
}

class _InsightsExportPeriodSheetState extends State<InsightsExportPeriodSheet> {
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// 0 = year, 1 = month, 2 = day, 3 = custom range
  int _mode = 1;
  late int _year;
  late int _month;
  DateTime? _singleDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _year = n.year;
    _month = n.month;
  }

  void _apply() {
    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);

    switch (_mode) {
      case 0:
        var start = DateTime(_year, 1, 1);
        var end = DateTime(_year, 12, 31);
        if (end.isAfter(todayD)) end = todayD;
        if (start.isAfter(end)) start = end;
        Navigator.pop(
          context,
          InsightsExportSelection.custom(
            start: start,
            end: end,
            label: 'Year $_year',
          ),
        );
        return;
      case 1:
        var start = DateTime(_year, _month, 1);
        var end = DateTime(_year, _month + 1, 0);
        if (end.isAfter(todayD)) end = todayD;
        if (start.isAfter(end)) start = end;
        Navigator.pop(
          context,
          InsightsExportSelection.custom(
            start: start,
            end: end,
            label: '${_months[_month - 1]} $_year',
          ),
        );
        return;
      case 2:
        final d = _singleDay ?? todayD;
        var day = DateTime(d.year, d.month, d.day);
        if (day.isAfter(todayD)) day = todayD;
        Navigator.pop(
          context,
          InsightsExportSelection.custom(
            start: day,
            end: day,
            label: '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          ),
        );
        return;
      case 3:
        var a = _rangeStart ?? todayD;
        var b = _rangeEnd ?? todayD;
        var s = DateTime(a.year, a.month, a.day);
        var e = DateTime(b.year, b.month, b.day);
        if (s.isAfter(e)) {
          final t = s;
          s = e;
          e = t;
        }
        if (e.isAfter(todayD)) e = todayD;
        if (s.isAfter(e)) s = e;
        Navigator.pop(
          context,
          InsightsExportSelection.custom(
            start: s,
            end: e,
            label: s == e
                ? '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}'
                : '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')} → ${e.year}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}',
          ),
        );
        return;
      default:
        return;
    }
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _singleDay ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _singleDay = d);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _rangeStart != null && _rangeEnd != null
          ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
          : null,
    );
    if (r != null) {
      setState(() {
        _rangeStart = r.start;
        _rangeEnd = r.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final years = [for (var y = DateTime.now().year; y >= 2000; y--) y];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.55), height: 1.3),
          ),
          const SizedBox(height: 16),
          if (widget.showUseCurrentFilterOption) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.tune_rounded, color: cs.primary),
              title: const Text('Use current Insights period'),
              subtitle: Text(
                widget.currentFilterDescription,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
              ),
              onTap: () => Navigator.pop(context, const InsightsExportSelection.currentFilter()),
            ),
            const Divider(height: 24),
          ],
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Year'), icon: Icon(Icons.calendar_today_outlined, size: 16)),
              ButtonSegment(value: 1, label: Text('Month'), icon: Icon(Icons.date_range_outlined, size: 16)),
              ButtonSegment(value: 2, label: Text('Day'), icon: Icon(Icons.event_outlined, size: 16)),
              ButtonSegment(value: 3, label: Text('Range'), icon: Icon(Icons.alt_route_outlined, size: 16)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 0) ...[
            DropdownButtonFormField<int>(
              value: _year,
              decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => setState(() => _year = v ?? _year),
            ),
          ],
          if (_mode == 1) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _month,
                    decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(_months[m - 1])),
                    ],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                    items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
              ],
            ),
          ],
          if (_mode == 2) ...[
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(
                _singleDay == null
                    ? 'Pick a day'
                    : '${_singleDay!.year}-${_singleDay!.month.toString().padLeft(2, '0')}-${_singleDay!.day.toString().padLeft(2, '0')}',
              ),
            ),
          ],
          if (_mode == 3) ...[
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_rounded),
              label: Text(
                _rangeStart == null || _rangeEnd == null
                    ? 'Choose start and end dates'
                    : '${_rangeStart!.year}-${_rangeStart!.month.toString().padLeft(2, '0')}-${_rangeStart!.day.toString().padLeft(2, '0')} → ${_rangeEnd!.year}-${_rangeEnd!.month.toString().padLeft(2, '0')}-${_rangeEnd!.day.toString().padLeft(2, '0')}',
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: cs.primary,
            ),
            child: Text(widget.continueButtonLabel),
          ),
        ],
      ),
    );
  }
}

Future<InsightsExportSelection?> showInsightsExportPeriodSheet(
  BuildContext context, {
  required String currentFilterDescription,
  bool showUseCurrentFilterOption = true,
  String title = 'Export data',
  String subtitle = 'Choose the year, month, day, or range to include in the file.',
  String continueButtonLabel = 'Continue',
}) {
  return showModalBottomSheet<InsightsExportSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => InsightsExportPeriodSheet(
      title: title,
      subtitle: subtitle,
      currentFilterDescription: currentFilterDescription,
      showUseCurrentFilterOption: showUseCurrentFilterOption,
      continueButtonLabel: continueButtonLabel,
    ),
  );
}
