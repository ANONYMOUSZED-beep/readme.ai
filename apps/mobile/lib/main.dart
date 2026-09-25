import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/storage/preferences_store.dart';

/// Application entry point.
///
/// Initialises Firebase/Google Sign-In and opens preference storage, then
/// wraps the app in a [ProviderScope] so Riverpod serves as both the state
/// container and the dependency-injection root. Neither step can stop the app
/// from starting: without Firebase configuration it lands on the login screen
/// (sign-in then reports the missing configuration), and without preference
/// storage settings simply are not remembered.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In development mode Firebase is bypassed entirely (mock auth).
  if (!AppConfig.fromEnvironment().devAuth) {
    try {
      await FirebaseBootstrap.ensureInitialized();
    } on Object catch (error) {
      debugPrint('Firebase initialisation skipped: $error');
    }
  }

  LicenseRegistry.addLicense(_bundledFontLicenses);

  PreferencesStore? preferences;
  try {
    preferences = SharedPreferencesStore(await SharedPreferences.getInstance());
  } on Object catch (error) {
    debugPrint('Preferences unavailable; settings will not persist: $error');
  }

  runApp(
    ProviderScope(
      overrides: [
        if (preferences != null)
          preferencesStoreProvider.overrideWithValue(preferences),
      ],
      child: const ReadMeApp(),
    ),
  );
}

/// Lists the bundled Lora typeface's licence on the app's licence page.
Stream<LicenseEntry> _bundledFontLicenses() async* {
  final text = await rootBundle.loadString('assets/fonts/OFL.txt');
  yield LicenseEntryWithLineBreaks(const ['Lora'], text);
}
