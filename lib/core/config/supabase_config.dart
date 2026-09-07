import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase project credentials loaded from `.env`.
abstract final class SupabaseConfig {
  static String get url {
    final value = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    if (value.isEmpty || value.contains('YOUR_PROJECT')) {
      throw StateError(
        'Задайте SUPABASE_URL в файле .env (см. .env.example).',
      );
    }
    return value;
  }

  static String get anonKey {
    final value = dotenv.env['SUPABASE_ANON_KEY']?.trim() ??
        dotenv.env['SUPABASE_PUBLISHABLE_KEY']?.trim() ??
        '';
    if (value.isEmpty || value.contains('YOUR_SUPABASE')) {
      throw StateError(
        'Задайте SUPABASE_ANON_KEY (или SUPABASE_PUBLISHABLE_KEY) в файле .env.',
      );
    }
    return value;
  }

  /// Alias for newer supabase_flutter API.
  static String get publishableKey => anonKey;

  /// Synthetic email domain for phone+password Auth.
  static const phoneAuthDomain = 'phone.local';
}
