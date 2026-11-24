import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/session.dart';

/// Habhab LPG — one Android app for customers (order gasul, track the rider, listahan)
/// and the store (orders board, POS, utang, GCash checks, reports).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_US');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await session.start();
  runApp(const HabhabApp());
}
