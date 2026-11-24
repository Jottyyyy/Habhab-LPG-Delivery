import 'package:url_launcher/url_launcher.dart';

/// Phone calls, texts and Google Maps directions (free: they open the phone's own apps).
abstract final class Launch {
  static Future<bool> call(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));
  static Future<bool> sms(String phone) => launchUrl(Uri(scheme: 'sms', path: phone));

  /// Directions to a pin in Google Maps (or any maps app).
  static Future<bool> directions(double lat, double lng) async {
    final nav = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    try {
      if (await launchUrl(nav, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
    return launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
        mode: LaunchMode.externalApplication);
  }

  static Future<bool> web(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
