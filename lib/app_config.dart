/// Configuration centrale de l'application.
///
/// Toutes les valeurs sensibles arrivent via `--dart-define` pour ne jamais
/// être codées en dur dans le dépôt. Les valeurs par défaut ci-dessous sont
/// des ESPACES RÉSERVÉS : remplace-les par les tiennes (Project Settings >
/// API dans Supabase) avant de lancer l'application.
class AppConfig {
  AppConfig._();

  /// Project URL — Supabase > Project Settings > API > Project URL
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://TON-PROJET.supabase.co',
  );

  /// Clé "anon" "public" — faite pour être publique, jamais la clé
  /// "service_role" et jamais le mot de passe de la base.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'TON-ANON-KEY',
  );

  /// Bascule vers Cloudflare R2 pour les images publiques une fois configuré.
  /// Par défaut : les images restent servies par Supabase Storage.
  static const bool useR2 = bool.fromEnvironment('USE_R2', defaultValue: false);

  static const String r2PublicBaseUrl = String.fromEnvironment(
    'R2_PUBLIC_BASE_URL',
    defaultValue: '',
  );

  static const String currencyCode = 'MRU';
  static const String currencySymbol = 'UM';
  static const int pageSize = 20;

  static bool get isConfigured =>
      !supabaseUrl.contains('TON-PROJET') && !supabaseAnonKey.contains('TON-ANON-KEY');
}
