/// App environment configuration.
/// Environment is selected at build time via `--dart-define=ENV=dev|staging|prod`.
class AppConfig {
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  static String get baseUrl {
    switch (env) {
      case 'prod':
        return 'https://chat-backend-production-c7cd.up.railway.app';
      case 'staging':
        return 'https://chat-backend-staging.up.railway.app';
      case 'dev':
      default:
        return 'https://5dn4bj2m-8000.inc1.devtunnels.ms';
    }
  }

  static String get wsBaseUrl {
    switch (env) {
      case 'prod':
        return 'wss://chat-backend-production-c7cd.up.railway.app';
      case 'staging':
        return 'wss://chat-backend-staging.up.railway.app';
      case 'dev':
      default:
        return 'wss://betunnel.worldstories.net';
    }
  }

  static String get envLabel => env.toUpperCase();
  static bool get isDev => env == 'dev';
  static bool get isStaging => env == 'staging';
  static bool get isProd => env == 'prod';

  /// Web OAuth client ID used as the server client for native Google Sign-In.
  ///
  /// Pass with:
  /// --dart-define=GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
}
