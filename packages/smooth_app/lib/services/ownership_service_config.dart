/// Build-time configuration for [OwnershipService], read via `--dart-define`.
///
/// Never hardcode real secrets here. Run/build with e.g.:
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=ANTHROPIC_API_KEY=...`
class OwnershipServiceConfig {
  const OwnershipServiceConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String anthropicApiKey = String.fromEnvironment(
    'ANTHROPIC_API_KEY',
  );

  /// Sent as the Wikidata User-Agent per their bot-etiquette policy. Set a
  /// real contact at build time with `--dart-define=WIKIDATA_CONTACT=...`
  /// if you want Wikidata to be able to reach you about this traffic.
  static const String wikidataContact = String.fromEnvironment(
    'WIKIDATA_CONTACT',
    defaultValue: 'maintainer not configured',
  );

  static bool get hasCentralCache =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasAiFallback => anthropicApiKey.isNotEmpty;
}
