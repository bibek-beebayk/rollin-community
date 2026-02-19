/// App environment configuration.
/// Environment is selected at build time via --dart-define=ENV=<env>
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
        return 'https://betunnel.worldstories.net';
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
}
