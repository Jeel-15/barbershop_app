/// Build-time configuration. Everything comes from `--dart-define`, so one
/// codebase builds for the local PC, the live server test and production:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20/rosen_barber/public/api/v1
///
/// On an Android emulator the PC is `10.0.2.2`; on a real phone use the PC's
/// Wi-Fi address, or `adb reverse tcp:80 tcp:80` and keep `localhost`.
enum Flavor { dev, staging, prod }

class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost/rosen_barber/public/api/v1',
  );

  static const _flavorName = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  static Flavor get flavor => Flavor.values.firstWhere(
    (f) => f.name == _flavorName,
    orElse: () => Flavor.dev,
  );

  /// All dates and times in the app are shop time, even if the phone is elsewhere.
  static const shopTimeZone = 'America/Edmonton';

  static bool get isProd => flavor == Flavor.prod;
}
