import '../config/supabase_config.dart';

/// Phone normalization and Auth identity helpers.
abstract final class PhoneUtils {
  /// Digits only, with leading country code. Default RU (+7).
  static String normalize(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    if (digits.length == 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
      return '7${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '7$digits';
    }
    return digits;
  }

  /// Display format: +7 (999) 123-45-67
  static String formatDisplay(String input) {
    final n = normalize(input);
    if (n.length != 11 || !n.startsWith('7')) {
      return input.trim();
    }
    final a = n.substring(1, 4);
    final b = n.substring(4, 7);
    final c = n.substring(7, 9);
    final d = n.substring(9, 11);
    return '+7 ($a) $b-$c-$d';
  }

  /// E.164-like: +79001234567
  static String toE164(String input) {
    final n = normalize(input);
    if (n.isEmpty) return '';
    return '+$n';
  }

  /// Synthetic email for Supabase email+password Auth.
  static String toAuthEmail(String phone) {
    final n = normalize(phone);
    return '$n@${SupabaseConfig.phoneAuthDomain}';
  }

  static bool isValidRuMobile(String input) {
    final n = normalize(input);
    return RegExp(r'^7\d{10}$').hasMatch(n);
  }
}
