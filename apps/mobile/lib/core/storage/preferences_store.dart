import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store for user preferences (theme, reader typography).
///
/// Reads are synchronous so settings are applied on the very first frame;
/// writes are fire-and-forget from the caller's point of view.
abstract interface class PreferencesStore {
  /// The stored value for [key], or `null` when unset.
  String? getString(String key);

  /// Persist [value] under [key].
  Future<void> setString(String key, String value);
}

/// Keeps preferences for the lifetime of the process only.
///
/// The default (tests, and a fallback should platform storage fail to open),
/// so the app always works — it just forgets settings on restart.
class InMemoryPreferencesStore implements PreferencesStore {
  InMemoryPreferencesStore([Map<String, String>? initial])
    : _values = {...?initial};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}

/// [PreferencesStore] persisted with `shared_preferences`.
class SharedPreferencesStore implements PreferencesStore {
  const SharedPreferencesStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

/// Provides the preferences store. `main` overrides it with the persistent
/// implementation once platform storage has been opened.
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => InMemoryPreferencesStore(),
);
