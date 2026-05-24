/// Minimum length for a valid INFAQ password.
const int kInfaqPasswordMinLength = 8;

enum InfaqPasswordStrength {
  weak,
  moderate,
  strong,
}

/// Shared password rules for signup, reset, and profile updates.
class InfaqPasswordRules {
  InfaqPasswordRules._();

  static bool hasMinLength(String password) =>
      password.length >= kInfaqPasswordMinLength;

  static bool hasUppercase(String password) =>
      RegExp(r'[A-Z]').hasMatch(password);

  static bool hasLowercase(String password) =>
      RegExp(r'[a-z]').hasMatch(password);

  static bool hasNumber(String password) => RegExp(r'\d').hasMatch(password);

  static bool hasSymbol(String password) =>
      RegExp(r'[^A-Za-z0-9]').hasMatch(password);

  static int metRuleCount(String password) {
    var count = 0;
    if (hasMinLength(password)) count++;
    if (hasUppercase(password)) count++;
    if (hasLowercase(password)) count++;
    if (hasNumber(password)) count++;
    if (hasSymbol(password)) count++;
    return count;
  }

  /// All required rules satisfied (signup / reset gate).
  static bool isValid(String password) => metRuleCount(password) == 5;

  static InfaqPasswordStrength evaluateStrength(String password) {
    if (password.isEmpty) return InfaqPasswordStrength.weak;

    final met = metRuleCount(password);
    if (met == 5) {
      return InfaqPasswordStrength.strong;
    }
    if (met >= 2) {
      return InfaqPasswordStrength.moderate;
    }
    return InfaqPasswordStrength.weak;
  }
}

/// Whether [password] meets all required signup / reset rules.
bool isInfaqPasswordValid(String password) => InfaqPasswordRules.isValid(password);

InfaqPasswordStrength infaqPasswordStrength(String password) =>
    InfaqPasswordRules.evaluateStrength(password);

String infaqPasswordStrengthLabel(InfaqPasswordStrength strength) {
  switch (strength) {
    case InfaqPasswordStrength.weak:
      return 'Weak';
    case InfaqPasswordStrength.moderate:
      return 'Moderate';
    case InfaqPasswordStrength.strong:
      return 'Strong';
  }
}

String? infaqPasswordRequirementMessage(String password) {
  if (password.isEmpty) return null;
  final missing = <String>[];
  if (!InfaqPasswordRules.hasMinLength(password)) {
    missing.add('at least $kInfaqPasswordMinLength characters');
  }
  if (!InfaqPasswordRules.hasUppercase(password)) {
    missing.add('an uppercase letter');
  }
  if (!InfaqPasswordRules.hasLowercase(password)) {
    missing.add('a lowercase letter');
  }
  if (!InfaqPasswordRules.hasNumber(password)) missing.add('a number');
  if (!InfaqPasswordRules.hasSymbol(password)) missing.add('a symbol');
  if (missing.isEmpty) return null;
  return 'Password must include ${missing.join(', ')}.';
}

bool isValidEmailFormat(String email) {
  return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
}
