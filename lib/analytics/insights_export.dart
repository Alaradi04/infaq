import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:infaq/analytics/insights_format.dart';
import 'package:infaq/analytics/insights_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

String buildInsightsCsv(InsightsPayload p) {
  final b = StringBuffer()
    ..writeln('INFAQ Analytics Export')
    ..writeln('Period,${p.periodLabel}')
    ..writeln('Currency,${p.currency}')
    ..writeln()
    ..writeln('Summary')
    ..writeln('Current balance,${p.balance}')
    ..writeln('Period income,${p.periodIncome}')
    ..writeln('Period expenses,${p.periodExpense}')
    ..writeln('Net savings,${p.periodNet}')
    ..writeln('Savings rate %,${p.savingsRatePct.toStringAsFixed(1)}')
    ..writeln()
    ..writeln('Month vs month')
    ..writeln('This month income,${p.monthComparison.thisMonthIncome}')
    ..writeln('Last month income,${p.monthComparison.lastMonthIncome}')
    ..writeln('This month expenses,${p.monthComparison.thisMonthExpense}')
    ..writeln('Last month expenses,${p.monthComparison.lastMonthExpense}')
    ..writeln('This month net,${p.monthComparison.thisMonthNet}')
    ..writeln('Last month net,${p.monthComparison.lastMonthNet}')
    ..writeln()
    ..writeln('Spending by category (${p.periodLabel})')
    ..writeln('Category,Amount');
  for (final c in p.categorySlices) {
    b.writeln('${_escapeCsv(c.name)},${c.amount}');
  }
  b
    ..writeln()
    ..writeln('Subscriptions summary')
    ..writeln('Active count,${p.subscriptionAnalytics.activeCount}')
    ..writeln('Inactive count,${p.subscriptionAnalytics.inactiveCount}')
    ..writeln('Est. monthly recurring,${p.subscriptionAnalytics.monthlyRecurringCost}')
    ..writeln('Est. yearly committed,${p.subscriptionAnalytics.yearlyCommittedCost}')
    ..writeln('Linked subscription expenses (period),${p.subscriptionAnalytics.subscriptionLinkedExpenseInPeriod}')
    ..writeln()
    ..writeln('Goals summary')
    ..writeln('Total goals,${p.goalAnalytics.totalGoals}')
    ..writeln('Total saved across goals,${p.goalAnalytics.totalSaved}');
  for (final g in p.goalAnalytics.rows) {
    b.writeln('${_escapeCsv(g.title)},progress ${g.progressPct.toStringAsFixed(1)}%');
  }
  return b.toString();
}

String _escapeCsv(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Plain-text body for PDF (no styling work on the UI isolate).
String buildInsightsPlainPdfText(InsightsPayload p, String currencyCode) {
  String m(double v) => formatInsightsMoney(currencyCode, v);
  final buf = StringBuffer()
    ..writeln('INFAQ — Insights')
    ..writeln('Period: ${p.periodLabel}')
    ..writeln('Currency: ${p.currency}')
    ..writeln()
    ..writeln('Summary')
    ..writeln('  Balance: ${m(p.balance)}')
    ..writeln('  Income: ${m(p.periodIncome)}')
    ..writeln('  Expenses: ${m(p.periodExpense)}')
    ..writeln('  Net: ${m(p.periodNet)}')
    ..writeln('  Savings rate: ${p.savingsRatePct.toStringAsFixed(1)}%')
    ..writeln()
    ..writeln('This month vs last month')
    ..writeln('  Income: ${m(p.monthComparison.thisMonthIncome)} vs ${m(p.monthComparison.lastMonthIncome)}')
    ..writeln('  Expenses: ${m(p.monthComparison.thisMonthExpense)} vs ${m(p.monthComparison.lastMonthExpense)}')
    ..writeln()
    ..writeln('Categories (${p.periodLabel})');
  if (p.categorySlices.isEmpty) {
    buf.writeln('  (none)');
  } else {
    for (final c in p.categorySlices) {
      buf.writeln('  • ${c.name}: ${m(c.amount)}');
    }
  }
  buf
    ..writeln()
    ..writeln('Subscriptions')
    ..writeln('  Active: ${p.subscriptionAnalytics.activeCount} · Inactive: ${p.subscriptionAnalytics.inactiveCount}')
    ..writeln('  Monthly recurring (est.): ${m(p.subscriptionAnalytics.monthlyRecurringCost)}')
    ..writeln('  Yearly committed (est.): ${m(p.subscriptionAnalytics.yearlyCommittedCost)}')
    ..writeln('  Subscription-tagged expenses: ${m(p.subscriptionAnalytics.subscriptionLinkedExpenseInPeriod)}')
    ..writeln()
    ..writeln('Goals')
    ..writeln('  Count: ${p.goalAnalytics.totalGoals} · Total saved: ${m(p.goalAnalytics.totalSaved)}');
  for (final g in p.goalAnalytics.rows) {
    buf.writeln('  • ${g.title}: ${g.progressPct.toStringAsFixed(0)}%');
  }
  return buf.toString();
}

Future<Uint8List> _encodePdfBytes(String plainBody) async {
  Future<Uint8List> buildDoc() async {
    final doc = pw.Document();
    final lines = plainBody.split('\n');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        maxPages: 40,
        build: (ctx) => [
          for (var i = 0; i < lines.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                lines[i],
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }

  if (kIsWeb) {
    return buildDoc();
  }
  return Isolate.run(buildDoc);
}

Future<void> shareInsightsCsv(InsightsPayload p) async {
  final csv = buildInsightsCsv(p);
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/infaq_insights_${DateTime.now().millisecondsSinceEpoch}.csv';
  final file = File(path);
  await file.writeAsString(csv);
  await Share.shareXFiles([XFile(path)], subject: 'INFAQ insights export');
}

Future<void> shareInsightsPdf(InsightsPayload p, String currencyCode) async {
  final plain = buildInsightsPlainPdfText(p, currencyCode);
  final bytes = await _encodePdfBytes(plain).timeout(
    const Duration(seconds: 45),
    onTimeout: () => throw TimeoutException('PDF generation took too long'),
  );
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/infaq_insights_${DateTime.now().millisecondsSinceEpoch}.pdf';
  final file = File(path);
  await file.writeAsBytes(bytes);
  await Share.shareXFiles(
    [XFile(path, mimeType: 'application/pdf')],
    subject: 'INFAQ insights PDF',
  );
}
