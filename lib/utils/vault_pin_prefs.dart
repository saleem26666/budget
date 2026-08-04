import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';

/// Profile-scoped vault PIN with legacy `vault_pin` fallback.
class VaultPinPrefs {
  static String _key(String profileId) => '${profileId}_vault_pin';

  static Future<String?> getPin([String? profileId]) async {
    final prefs = await SharedPreferences.getInstance();
    final id = profileId ?? DatabaseHelper.instance.activeProfileId;
    final scoped = prefs.getString(_key(id));
    if (scoped != null && scoped.isNotEmpty) return scoped;
    final legacy = prefs.getString('vault_pin');
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return null;
  }

  static Future<bool> isSet([String? profileId]) async {
    final pin = await getPin(profileId);
    return pin != null && pin.isNotEmpty;
  }

  static Future<void> setPin(String pin, [String? profileId]) async {
    final prefs = await SharedPreferences.getInstance();
    final id = profileId ?? DatabaseHelper.instance.activeProfileId;
    await prefs.setString(_key(id), pin);
    // Keep legacy key in sync for older code paths / backups.
    await prefs.setString('vault_pin', pin);
  }

  static Future<void> clear([String? profileId]) async {
    final prefs = await SharedPreferences.getInstance();
    final id = profileId ?? DatabaseHelper.instance.activeProfileId;
    final scoped = prefs.getString(_key(id));
    await prefs.remove(_key(id));
    // Only clear legacy key if it matched this profile (don't wipe other profiles).
    final legacy = prefs.getString('vault_pin');
    if (legacy != null && scoped != null && legacy == scoped) {
      await prefs.remove('vault_pin');
    }
  }

  static Future<bool> verify(String entered, [String? profileId]) async {
    final pin = await getPin(profileId);
    if (pin == null || pin.isEmpty) return true;
    return entered == pin;
  }
}
