import 'package:shared_preferences/shared_preferences.dart';

/// Dedupe keys stored only in SharedPreferences (exact key strings per product spec).
class LocalNotificationDedupeStore {
  LocalNotificationDedupeStore._();

  static String _prefKey(String logicalKey) => 'ln_dedupe_$logicalKey';

  static Future<bool> consumeIfNew(String logicalKey) async {
    final p = await SharedPreferences.getInstance();
    final k = _prefKey(logicalKey);
    if (p.getBool(k) == true) return false;
    await p.setBool(k, true);
    return true;
  }

  static Future<void> clearKey(String logicalKey) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefKey(logicalKey));
  }
}
