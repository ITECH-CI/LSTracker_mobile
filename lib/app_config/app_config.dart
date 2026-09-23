class AppConfig {
  // Défaut = émulateur Android. Sur un appareil physique en USB :
  //   adb reverse tcp:9200 tcp:<port serveur>
  //   flutter run --flavor dev --dart-define=API_BASE=http://localhost:9200
  static String apiBase = const String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:9200',
  );

  static const loginPath = '/api_v2/auth/login';
  static const refreshPath = '/api_v2/auth/refresh';
  static const metaFullPath = '/api_v2/meta/full';

  static const samplesPushPath = '/api_v2/sync/samples/push';
  static const samplesPullPath = '/api_v2/sync/samples/pull';

  static void overrideBase(String base) {
    apiBase = base;
  }
}
