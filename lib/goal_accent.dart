import 'package:flutter/material.dart';

/// Accent derived from goal title — same on goals list, add goal, and edit goal.
Color accentColorForGoalTitle(String title) {
  final h = title.hashCode.abs();
  const colors = [
    Color(0xFFFF9F6B),
    Color(0xFF6BB3F0),
    Color(0xFFFF8FB8),
    Color(0xFF7FD8BE),
    Color(0xFFB39DFF),
    Color(0xFFFFB86C),
  ];
  return colors[h % colors.length];
}
