/// Shared password rules (matches register flow).
const int kInfaqPasswordMinLength = 12;

bool isInfaqPasswordStrong(String password) {
  if (password.length < kInfaqPasswordMinLength) return false;
  if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
  if (!RegExp(r'[a-z]').hasMatch(password)) return false;
  if (!RegExp(r'\d').hasMatch(password)) return false;
  return true;
}

String? infaqPasswordRequirementMessage(String password) {
  if (password.isEmpty) return null;
  final missing = <String>[];
  if (password.length < kInfaqPasswordMinLength) {
    missing.add('at least $kInfaqPasswordMinLength characters');
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) missing.add('an uppercase letter');
  if (!RegExp(r'[a-z]').hasMatch(password)) missing.add('a lowercase letter');
  if (!RegExp(r'\d').hasMatch(password)) missing.add('a number');
  if (missing.isEmpty) return null;
  return 'Password must include ${missing.join(', ')}.';
}

bool isValidEmailFormat(String email) {
  return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
}
