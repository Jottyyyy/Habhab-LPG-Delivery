import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/theme.dart';
import 'config.dart';
import 'launch.dart';
import 'session.dart';

/// "1.2.0" > "1.1.9"
bool isNewer(String latest, String current) {
  List<int> parts(String v) => v.split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final a = parts(latest);
  final b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Once per app start: if a newer APK is on the website, offer to download it.
/// (The app is installed from the website, not the Play Store, so it can't update by itself.)
Future<void> checkForUpdate(BuildContext context) async {
  try {
    final v = await session.api.get('/app/version');
    final latest = v['latestVersion'] as String?;
    if (latest == null || v['downloadUrl'] == null) return;
    final info = await PackageInfo.fromPlatform();
    if (!isNewer(latest, info.version)) return;
    final min = v['minVersion'] as String?;
    final mustUpdate = min != null && isNewer(min, info.version);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !mustUpdate,
      builder: (c) => AlertDialog(
        title: const Text('May bagong update!'),
        content: Text('Version $latest of the Habhab LPG app is ready (you have ${info.version}).\n\n'
            'Tap Download, open the file, then tap Update.'),
        actions: [
          if (!mustUpdate) TextButton(onPressed: () => Navigator.pop(c), child: const Text('Later')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44), backgroundColor: C.flame),
            onPressed: () => Launch.web('${AppConfig.siteOrigin}/download'),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  } catch (_) {
    // No internet: try again next time.
  }
}
