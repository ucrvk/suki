/// Configuration for the self-hosted backend.
class BackendConfig {
  BackendConfig._();

  static const String baseUrl = String.fromEnvironment(
    'SYSBOOKING_BASE_URL',
    defaultValue: 'https://api.wenwen12305.top/suki',
  );

  static String get normalizedBaseUrl =>
      baseUrl.replaceFirst(RegExp(r'/+$'), '');
}
