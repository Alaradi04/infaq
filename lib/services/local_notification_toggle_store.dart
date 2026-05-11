import 'package:shared_preferences/shared_preferences.dart';

/// Local-only toggles for INFAQ local notifications (does not change Supabase).
class LocalNotificationToggles {
  const LocalNotificationToggles({
    required this.transaction,
    required this.budget,
    required this.category,
    required this.subscription,
  });

  final bool transaction;
  final bool budget;
  final bool category;
  final bool subscription;
}

class LocalNotificationToggleStore {
  LocalNotificationToggleStore._();
  static const _kTx = 'ln_toggle_transaction';
  static const _kBudget = 'ln_toggle_budget';
  static const _kCategory = 'ln_toggle_category';
  static const _kSubscription = 'ln_toggle_subscription';

  /// One SharedPreferences read for all toggles (used after saves, not in [build]).
  static Future<LocalNotificationToggles> readAll() async {
    final p = await SharedPreferences.getInstance();
    return LocalNotificationToggles(
      transaction: p.getBool(_kTx) ?? true,
      budget: p.getBool(_kBudget) ?? true,
      category: p.getBool(_kCategory) ?? true,
      subscription: p.getBool(_kSubscription) ?? true,
    );
  }

  static Future<bool> transactionAlertsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kTx) ?? true;

  static Future<bool> budgetAlertsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kBudget) ?? true;

  static Future<bool> categoryAlertsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kCategory) ?? true;

  static Future<bool> subscriptionRemindersEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kSubscription) ?? true;

  static Future<void> setTransactionAlertsEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTx, v);
  }

  static Future<void> setBudgetAlertsEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBudget, v);
  }

  static Future<void> setCategoryAlertsEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCategory, v);
  }

  static Future<void> setSubscriptionRemindersEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSubscription, v);
  }
}
