/// App environment configuration.
/// Environment is selected at build time via `--dart-define=ENV=dev|staging|prod`.
class AppConfig {
  static const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');
  static const String _apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL');
  static const String _wsBaseUrlOverride =
      String.fromEnvironment('WS_BASE_URL');
  static const String _rawEnv = String.fromEnvironment(
    'ENV',
    defaultValue: _isReleaseBuild ? 'prod' : 'dev',
  );

  static String get env {
    final normalized = _rawEnv.trim().toLowerCase();
    if (normalized == 'production') return 'prod';
    if (normalized == 'stage') return 'staging';
    if (normalized == 'development') return 'dev';
    if (normalized == 'prod' ||
        normalized == 'staging' ||
        normalized == 'dev') {
      return normalized;
    }
    return _isReleaseBuild ? 'prod' : 'dev';
  }

  static String get baseUrl {
    if (_apiBaseUrlOverride.trim().isNotEmpty) {
      return _apiBaseUrlOverride.trim();
    }

    switch (env) {
      case 'prod':
        return 'https://chat-backend-production-c7cd.up.railway.app';
      case 'staging':
        return 'https://chat-backend-staging.up.railway.app';
      case 'dev':
      default:
        return 'https://dev.hrlzone.com';
    }
  }

  static String get wsBaseUrl {
    if (_wsBaseUrlOverride.trim().isNotEmpty) {
      return _wsBaseUrlOverride.trim();
    }

    switch (env) {
      case 'prod':
        return 'wss://chat-backend-production-c7cd.up.railway.app';
      case 'staging':
        return 'wss://chat-backend-staging.up.railway.app';
      case 'dev':
      default:
        return 'wss://dev.hrlzone.com';
    }
  }

  static String get envLabel => env.toUpperCase();
  static bool get isDev => env == 'dev';
  static bool get isStaging => env == 'staging';
  static bool get isProd => env == 'prod';
  static String get diagnostics =>
      'ENV=$env API=$baseUrl WS=$wsBaseUrl rawEnv=$_rawEnv '
      'release=$_isReleaseBuild apiOverride=${_apiBaseUrlOverride.isNotEmpty} '
      'wsOverride=${_wsBaseUrlOverride.isNotEmpty}';

  /// Web OAuth client ID used as the server client for native Google Sign-In.
  ///
  /// Pass with:
  /// --dart-define=GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
}
