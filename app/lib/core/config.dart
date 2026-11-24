/// Build-time settings and business identity.
abstract final class AppConfig {
  /// API base URL. Release builds use the live server; for the local test server build with
  /// `--dart-define=API_BASE_URL=http://10.0.2.2:8787/api`.
  static const _apiFromEnv = String.fromEnvironment('API_BASE_URL');
  static const productionApi = 'https://habhab-lpg.vercel.app/api';
  static String get apiBaseUrl => _apiFromEnv.isNotEmpty ? _apiFromEnv : productionApi;

  /// Origin of the API (for the download link, "https://habhab-lpg.vercel.app").
  static String get siteOrigin => Uri.parse(apiBaseUrl).replace(path: '').toString().replaceAll(RegExp(r'/$'), '');

  static const storeName = 'Habhab LPG';
  static const storeLegalName = 'Habhab LPG Trading';
  static const tagline = 'Your RESCUE in COOKING';
  static const defaultStorePhone = '09978049635';

  /// Android package name, sent to OpenStreetMap as the map's user agent (their tile policy).
  static const packageName = 'com.studentwebsolutions.habhablpg';

  /// Where the map opens when there is no pin yet (Philippines).
  static const defaultLat = 14.5995;
  static const defaultLng = 120.9842;
}
