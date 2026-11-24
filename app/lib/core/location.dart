import 'package:geolocator/geolocator.dart';

/// GPS helpers. Only used while a screen that needs it is open (no background location).
abstract final class Gps {
  /// Ask for permission if needed. Returns a message to show when it cannot be used.
  static Future<String?> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on Location (GPS) on your phone, then try again.';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied) return 'Allow location so the app can find you on the map.';
    if (p == LocationPermission.deniedForever) {
      return 'Location is blocked for this app. Open Settings → Apps → Habhab LPG → Permissions → Location → Allow.';
    }
    return null;
  }

  static Future<Position?> current() async {
    if (await ensureReady() != null) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  /// Position updates every few meters (rider sharing).
  static Stream<Position> stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      );

  static Future<void> openSettings() => Geolocator.openAppSettings();
}
