import 'dart:async';

/// Prevents duplicate / back-to-back heavy background AI work (e.g. leaf migration).
class AiBackgroundTasks {
  AiBackgroundTasks._();

  static bool _leafMigrationBusy = false;
  static DateTime? _lastLeafMigrationAt;

  /// Runs [work] at most once per [minGap], and never concurrently.
  static Future<void> runLeafMigrationThrottled(
    Future<void> Function() work, {
    Duration minGap = const Duration(seconds: 90),
  }) async {
    if (_leafMigrationBusy) return;
    final now = DateTime.now();
    if (_lastLeafMigrationAt != null &&
        now.difference(_lastLeafMigrationAt!) < minGap) {
      return;
    }
    _leafMigrationBusy = true;
    _lastLeafMigrationAt = now;
    try {
      await work();
    } finally {
      _leafMigrationBusy = false;
    }
  }
}
