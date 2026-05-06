import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for per-goal extras (icon + optional monthly). Keep in sync across app.
String goalLocalExtrasPrefsKey(String goalId) => 'goal_local_v1_$goalId';

Future<void> persistGoalLocalExtras({
  required String goalId,
  required int iconCodePoint,
  int? iconColorValue,
  double? monthly,
}) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(
    goalLocalExtrasPrefsKey(goalId),
    jsonEncode({
      'monthly': monthly,
      'icon': iconCodePoint,
      'icon_color': iconColorValue,
    }),
  );
}

Future<void> clearGoalLocalExtras(String goalId) async {
  final p = await SharedPreferences.getInstance();
  await p.remove(goalLocalExtrasPrefsKey(goalId));
}

Future<String?> readGoalLocalExtrasJson(String goalId) async {
  final p = await SharedPreferences.getInstance();
  return p.getString(goalLocalExtrasPrefsKey(goalId));
}
