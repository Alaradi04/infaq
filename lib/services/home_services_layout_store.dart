import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists visible Home "Services" shortcut keys (order + which are shown) per user.
class HomeServicesLayoutStore {
  HomeServicesLayoutStore._();

  static const List<String> defaultOrder = ['income', 'expense', 'subs', 'goals', 'categories'];
  static const int minVisible = 4;
  static const String _prefix = 'home_services_visible_v1_';

  static String _storageKey(String userId) => '$_prefix$userId';

  static (IconData icon, String label) meta(String key) {
    return switch (key) {
      'income' => (Icons.south_west_rounded, 'Income'),
      'expense' => (Icons.north_east_rounded, 'Expense'),
      'subs' => (Icons.subscriptions_outlined, 'Subs'),
      'goals' => (Icons.track_changes_rounded, 'Goals'),
      'categories' => (Icons.grid_view_rounded, 'Categories'),
      _ => (Icons.help_outline_rounded, key),
    };
  }

  static Future<List<String>?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, List<String> visibleKeysInOrder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(userId), jsonEncode(visibleKeysInOrder));
  }

  /// Dedupes, drops unknown keys, repairs lists that are too short.
  static List<String> normalize(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final k in raw) {
      if (defaultOrder.contains(k) && seen.add(k)) {
        out.add(k);
      }
    }
    if (out.isEmpty) {
      return List<String>.from(defaultOrder);
    }
    if (out.length < minVisible) {
      for (final k in defaultOrder) {
        if (out.length >= minVisible) break;
        if (!out.contains(k)) out.add(k);
      }
    }
    return out;
  }
}
