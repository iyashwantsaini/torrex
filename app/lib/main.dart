import 'package:flutter/material.dart';

import 'app.dart';
import 'core/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();
  runApp(TorrexApp(settings: settings));
}
