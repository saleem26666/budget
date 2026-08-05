import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../database_helper.dart';

class BackupService {
  static const int backupVersion = 3;
  static const String _defaultProfile = 'default';
  static const String _profilesKey = 'bp_profiles';
  static const String _activeProfileKey = 'bp_active_profile';

  /// e.g. BudgetPro_FullBackup_04Aug26_1045.budgetpro
  static String timestampedBackupFileName({String label = 'FullBackup'}) {
    final safe = label
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final stamp = DateFormat('ddMMMyy_HHmm').format(DateTime.now());
    final part = safe.isEmpty ? 'Backup' : safe;
    return 'BudgetPro_${part}_$stamp.budgetpro';
  }

  static String _profilePrefKey(String profileId, String key) =>
      '${profileId}_$key';

  static String _profileDbFileName(String profileId) {
    if (profileId == _defaultProfile) return 'budget_pro.db';
    final safe = profileId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'budget_pro_$safe.db';
  }

  static Future<String> _currentProfileId(SharedPreferences prefs) async {
    final id = (prefs.getString(_activeProfileKey) ?? _defaultProfile).trim();
    return id.isEmpty ? _defaultProfile : id;
  }

  static Future<List<Map<String, String>>> _readProfileList(
      SharedPreferences prefs) async {
    final raw = prefs.getString(_profilesKey);
    List<Map<String, String>> parsed = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
        parsed = list
            .map((e) => {
                  'id': (e['id'] ?? '').toString(),
                  'name': (e['name'] ?? '').toString(),
                })
            .where((e) => e['id']!.isNotEmpty && e['name']!.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    if (parsed.isEmpty) {
      parsed = [
        {'id': _defaultProfile, 'name': 'Personal'},
      ];
    }
    if (!parsed.any((p) => p['id'] == _defaultProfile)) {
      parsed.insert(0, {'id': _defaultProfile, 'name': 'Personal'});
    }
    return parsed;
  }

  static Future<void> _saveProfileList(
    SharedPreferences prefs,
    List<Map<String, String>> profiles,
    String activeId,
  ) async {
    var list = List<Map<String, String>>.from(profiles);
    if (!list.any((p) => p['id'] == _defaultProfile)) {
      list.insert(0, {'id': _defaultProfile, 'name': 'Personal'});
    }
    final active =
        list.any((p) => p['id'] == activeId) ? activeId : list.first['id']!;
    await prefs.setString(_profilesKey, jsonEncode(list));
    await prefs.setString(_activeProfileKey, active);
  }

  /// Upsert one profile into the on-device registry so it appears in the UI.
  static Future<void> upsertProfileRegistry({
    required String profileId,
    required String profileName,
    bool makeActive = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProfileList(prefs);
    final name = profileName.trim().isEmpty ? profileId : profileName.trim();
    final idx = list.indexWhere((p) => p['id'] == profileId);
    if (idx >= 0) {
      list[idx] = {'id': profileId, 'name': name};
    } else {
      list.add({'id': profileId, 'name': name});
    }
    final active = makeActive
        ? profileId
        : await _currentProfileId(prefs);
    await _saveProfileList(prefs, list, active);
  }

  static Future<Map<String, dynamic>> _collectProfilePayload({
    required String profileId,
    required String profileName,
  }) async {
    await DatabaseHelper.instance.setProfile(profileId);
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();
    final backupData = <String, dynamic>{};

    final transactions = (await db.query('transactions'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final diaryEntries = (await db.query('diary'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final vaultItems = (await db.query('vault_items'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final cards = (await db.query('cards'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final familyVault = (await db.query('family_vault'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    List<Map<String, dynamic>> businessCards = [];
    try {
      businessCards = (await db.query('business_cards'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    final accounts = (await db.query('accounts'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final categories = (await db.query('categories'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final notes = (await db.query('notes'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final investments = (await db.query('investments'))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final notebookCats = prefs
        .getString(_profilePrefKey(profileId, 'notebook_categories'));
    if (notebookCats != null) {
      backupData['notebook_categories'] = jsonDecode(notebookCats);
    }
    final diaryCats =
        prefs.getString(_profilePrefKey(profileId, 'diary_categories'));
    if (diaryCats != null) {
      backupData['diary_categories'] = jsonDecode(diaryCats);
    }
    final vaultPin = prefs.getString(_profilePrefKey(profileId, 'vault_pin')) ??
        prefs.getString('vault_pin');
    if (vaultPin != null && vaultPin.isNotEmpty) {
      backupData['vault_pin'] = vaultPin;
    }
    final appPassword =
        prefs.getString(_profilePrefKey(profileId, 'app_password'));
    if (appPassword != null) backupData['app_password'] = appPassword;
    final passwordMode =
        prefs.getString(_profilePrefKey(profileId, 'password_mode'));
    if (passwordMode != null) backupData['password_mode'] = passwordMode;
    final biometricEnabled =
        prefs.getBool(_profilePrefKey(profileId, 'biometric_enabled'));
    if (biometricEnabled != null) {
      backupData['biometric_enabled'] = biometricEnabled;
    }
    final currencyCode =
        prefs.getString(_profilePrefKey(profileId, 'currency_code'));
    if (currencyCode != null && currencyCode.isNotEmpty) {
      backupData['currency_code'] = currencyCode;
    }

    Future<void> embedImages(
      Map<String, dynamic> item,
      String pathsKey,
      String base64Key,
    ) async {
      if (item[pathsKey] == null ||
          item[pathsKey].toString().isEmpty ||
          item[pathsKey] == '[]') {
        return;
      }
      try {
        final imgPaths =
            List<String>.from(jsonDecode(item[pathsKey].toString()));
        final base64Images = <String>[];
        for (final path in imgPaths) {
          try {
            final imgFile = File(path);
            if (await imgFile.exists()) {
              base64Images.add(base64Encode(await imgFile.readAsBytes()));
            }
          } catch (_) {}
        }
        if (base64Images.isNotEmpty) {
          item[base64Key] = jsonEncode(base64Images);
        }
      } catch (_) {}
    }

    for (final tx in transactions) {
      await embedImages(tx, 'imgs', 'imgs_base64');
    }
    for (final entry in diaryEntries) {
      await embedImages(entry, 'imgs', 'imgs_base64');
    }
    for (final doc in familyVault) {
      await embedImages(doc, 'images', 'images_base64');
    }

    for (final card in cards) {
      try {
        if (card['front_image'] != null &&
            card['front_image'].toString().isNotEmpty) {
          final imgFile = File(card['front_image']);
          if (await imgFile.exists()) {
            card['front_image_base64'] =
                base64Encode(await imgFile.readAsBytes());
          }
        }
      } catch (_) {}
      try {
        if (card['back_image'] != null &&
            card['back_image'].toString().isNotEmpty) {
          final imgFile = File(card['back_image']);
          if (await imgFile.exists()) {
            card['back_image_base64'] =
                base64Encode(await imgFile.readAsBytes());
          }
        }
      } catch (_) {}
    }

    for (final card in businessCards) {
      try {
        if (card['image_path'] != null &&
            card['image_path'].toString().isNotEmpty) {
          final imgFile = File(card['image_path']);
          if (await imgFile.exists()) {
            card['image_base64'] = base64Encode(await imgFile.readAsBytes());
          }
        }
      } catch (_) {}
    }

    backupData['profile_id'] = profileId;
    backupData['profile_name'] = profileName;
    backupData['transactions'] = transactions;
    backupData['accounts'] = accounts;
    backupData['categories'] = categories;
    backupData['notes'] = notes;
    backupData['cards'] = cards;
    backupData['family_vault'] = familyVault;
    backupData['business_cards'] = businessCards;
    backupData['diary'] = diaryEntries;
    backupData['vault_items'] = vaultItems;
    backupData['investments'] = investments;
    return backupData;
  }

  /// Single-profile backup (Export Active Profile / per-profile share).
  static Future<String> buildFullBackupJson({String? profileId}) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = await _currentProfileId(prefs);
    final profiles = await _readProfileList(prefs);
    final resolvedProfileId = (profileId ?? previous).trim().isEmpty
        ? _defaultProfile
        : (profileId ?? previous).trim();
    final name = profiles
            .firstWhere(
              (p) => p['id'] == resolvedProfileId,
              orElse: () => {
                'id': resolvedProfileId,
                'name': resolvedProfileId == _defaultProfile
                    ? 'Personal'
                    : resolvedProfileId,
              },
            )['name'] ??
        'Personal';

    try {
      final backupData = await _collectProfilePayload(
        profileId: resolvedProfileId,
        profileName: name,
      );
      backupData['backup_version'] = backupVersion;
      backupData['backup_scope'] = 'single_profile';
      return jsonEncode(backupData);
    } finally {
      await DatabaseHelper.instance.setProfile(previous);
    }
  }

  /// All profiles in one file — used by Backup & Share and Google Drive.
  static Future<String> buildAllProfilesBackupJson() async {
    final prefs = await SharedPreferences.getInstance();
    final previous = await _currentProfileId(prefs);
    final profiles = await _readProfileList(prefs);

    try {
      final payloads = <Map<String, dynamic>>[];
      for (final profile in profiles) {
        final id = profile['id']!;
        final name = profile['name']!;
        final data = await _collectProfilePayload(
          profileId: id,
          profileName: name,
        );
        data['backup_version'] = backupVersion;
        data['backup_scope'] = 'single_profile';
        payloads.add(data);
      }
      return jsonEncode({
        'backup_version': backupVersion,
        'backup_scope': 'all_profiles',
        'active_profile_id': previous,
        'profiles': payloads,
      });
    } finally {
      await DatabaseHelper.instance.setProfile(previous);
    }
  }

  static Future<void> restoreFromBytes(Uint8List bytes) async {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      throw 'File decode failed';
    }
    if (!content.trim().startsWith('{')) {
      throw 'Invalid backup file format';
    }
    final map = Map<String, dynamic>.from(jsonDecode(content));
    if (map['backup_scope']?.toString() == 'all_profiles') {
      await _restoreAllProfiles(map);
    } else {
      // Old single-profile files: always restore into the CURRENTLY ACTIVE
      // profile so a 2nd file does not overwrite the 1st (same profile_id).
      final prefs = await SharedPreferences.getInstance();
      final active = await _currentProfileId(prefs);
      await _restoreJson(map, targetProfileId: active);
      final pname = (map['profile_name']?.toString() ?? '').trim();
      if (pname.isNotEmpty) {
        await upsertProfileRegistry(
          profileId: active,
          profileName: pname,
          makeActive: true,
        );
      }
      await DatabaseHelper.instance.setProfile(active, forceReopen: true);
    }
  }

  /// Creates a new profile from a single-profile backup and restores into it.
  static Future<String> restoreFromBytesAsNewProfile(Uint8List bytes) async {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      throw 'File decode failed';
    }
    if (!content.trim().startsWith('{')) {
      throw 'Invalid backup file format';
    }
    final map = Map<String, dynamic>.from(jsonDecode(content));
    if (map['backup_scope']?.toString() == 'all_profiles') {
      await _restoreAllProfiles(map);
      final prefs = await SharedPreferences.getInstance();
      return await _currentProfileId(prefs);
    }

    final preferredName = (map['profile_name']?.toString() ??
            map['profile_id']?.toString() ??
            'Restored')
        .trim();
    final newId = 'p${DateTime.now().millisecondsSinceEpoch}';
    final name = preferredName.isEmpty ? 'Restored' : preferredName;

    await upsertProfileRegistry(
      profileId: newId,
      profileName: name,
      makeActive: true,
    );
    await _restoreJson(map, targetProfileId: newId);
    await DatabaseHelper.instance.setProfile(newId, forceReopen: true);
    return newId;
  }

  static Future<void> restoreFromPath(String filePath) async {
    final file = File(filePath);
    await restoreFromBytes(await file.readAsBytes());
  }

  static Future<void> restoreFromBytesForProfile(
    Uint8List bytes, {
    required String profileId,
  }) async {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      throw 'File decode failed';
    }
    if (!content.trim().startsWith('{')) {
      throw 'Invalid backup file format';
    }
    final map = Map<String, dynamic>.from(jsonDecode(content));
    if (map['backup_scope']?.toString() == 'all_profiles') {
      // Importing a multi backup into one active profile: use matching id or first.
      final list = (map['profiles'] as List?) ?? [];
      Map<String, dynamic>? chosen;
      for (final raw in list) {
        final item = Map<String, dynamic>.from(raw as Map);
        final id = (item['profile_id'] ?? item['id'] ?? '').toString();
        if (id == profileId) {
          chosen = item.containsKey('data')
              ? Map<String, dynamic>.from(item['data'] as Map)
              : item;
          break;
        }
      }
      chosen ??= list.isEmpty
          ? null
          : (Map<String, dynamic>.from(list.first as Map).containsKey('data')
              ? Map<String, dynamic>.from(
                  (list.first as Map)['data'] as Map)
              : Map<String, dynamic>.from(list.first as Map));
      if (chosen == null) throw 'Backup has no profile data';
      await _restoreJson(chosen, targetProfileId: profileId);
    } else {
      await _restoreJson(map, targetProfileId: profileId);
    }
  }

  static Future<void> restoreFromPathForProfile(
    String filePath, {
    required String profileId,
  }) async {
    final file = File(filePath);
    await restoreFromBytesForProfile(
      await file.readAsBytes(),
      profileId: profileId,
    );
  }

  static Future<void> _restoreAllProfiles(Map<String, dynamic> backup) async {
    final rawList = backup['profiles'];
    if (rawList is! List || rawList.isEmpty) {
      throw 'Backup has no profiles';
    }

    final registry = <Map<String, String>>[];
    for (final raw in rawList) {
      final item = Map<String, dynamic>.from(raw as Map);
      final data = item.containsKey('data') && item['data'] is Map
          ? Map<String, dynamic>.from(item['data'] as Map)
          : item;
      final id = (data['profile_id'] ?? item['id'] ?? _defaultProfile)
          .toString()
          .trim();
      final name = (data['profile_name'] ??
              item['name'] ??
              (id == _defaultProfile ? 'Personal' : id))
          .toString()
          .trim();
      final profileId = id.isEmpty ? _defaultProfile : id;
      await _restoreJson(data, targetProfileId: profileId);
      registry.add({
        'id': profileId,
        'name': name.isEmpty ? profileId : name,
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final activeRaw =
        (backup['active_profile_id']?.toString() ?? _defaultProfile).trim();
    final active = registry.any((p) => p['id'] == activeRaw)
        ? activeRaw
        : registry.first['id']!;
    await _saveProfileList(prefs, registry, active);
    await DatabaseHelper.instance.setProfile(active);
  }

  static Future<void> _restoreJson(
    Map<String, dynamic> backup, {
    String? targetProfileId,
  }) async {
    final profileId =
        (targetProfileId ?? backup['profile_id']?.toString() ?? _defaultProfile)
                .trim()
                .isEmpty
            ? _defaultProfile
            : (targetProfileId ??
                    backup['profile_id']?.toString() ??
                    _defaultProfile)
                .trim();
    await DatabaseHelper.instance.setProfile(profileId);
    await DatabaseHelper.instance.resetDatabase();

    Directory appDir =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            ? await getApplicationSupportDirectory()
            : await getApplicationDocumentsDirectory();

    final imagesDir = Directory('${appDir.path}/budget_pro_images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

    Future<void> restoreImages(
      Map<String, dynamic> item,
      String base64Key,
      String pathKey,
      String filePrefix,
    ) async {
      if (item[base64Key] == null) return;
      try {
        final base64Images =
            List<String>.from(jsonDecode(item[base64Key].toString()));
        final newPaths = <String>[];
        for (var i = 0; i < base64Images.length; i++) {
          final imgFile = File(
              '${imagesDir.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
          await imgFile.writeAsBytes(base64Decode(base64Images[i]));
          newPaths.add(imgFile.path);
        }
        item[pathKey] = jsonEncode(newPaths);
      } catch (_) {}
      item.remove(base64Key);
    }

    for (final table in [
      'transactions',
      'accounts',
      'categories',
      'diary',
      'family_vault',
      'cards',
      'business_cards',
      'notes',
      'vault_items',
      'investments',
    ]) {
      if (!backup.containsKey(table)) continue;
      for (final raw in backup[table] as List) {
        try {
          final item = Map<String, dynamic>.from(raw);
          if (table == 'transactions') {
            await restoreImages(item, 'imgs_base64', 'imgs', 'tx');
          } else if (table == 'diary') {
            await restoreImages(item, 'imgs_base64', 'imgs', 'diary');
          } else if (table == 'family_vault') {
            await restoreImages(item, 'images_base64', 'images', 'doc');
          } else if (table == 'cards') {
            if (item['front_image_base64'] != null) {
              final imgFile = File(
                  '${imagesDir.path}/card_${DateTime.now().millisecondsSinceEpoch}_front.jpg');
              await imgFile
                  .writeAsBytes(base64Decode(item['front_image_base64']));
              item['front_image'] = imgFile.path;
            }
            if (item['back_image_base64'] != null) {
              final imgFile = File(
                  '${imagesDir.path}/card_${DateTime.now().millisecondsSinceEpoch}_back.jpg');
              await imgFile
                  .writeAsBytes(base64Decode(item['back_image_base64']));
              item['back_image'] = imgFile.path;
            }
            item.remove('front_image_base64');
            item.remove('back_image_base64');
          } else if (table == 'business_cards') {
            if (item['image_base64'] != null) {
              final imgFile = File(
                  '${imagesDir.path}/biz_card_${DateTime.now().millisecondsSinceEpoch}.jpg');
              await imgFile.writeAsBytes(base64Decode(item['image_base64']));
              item['image_path'] = imgFile.path;
            }
            item.remove('image_base64');
          }
          item.remove('id');
          await DatabaseHelper.instance.insert(table, item);
        } catch (_) {}
      }
    }

    // Force flush so data survives profile switch / app background.
    await DatabaseHelper.instance.closeDb();
    await DatabaseHelper.instance.setProfile(profileId, forceReopen: true);

    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'notebook_categories',
      'diary_categories',
      'vault_pin',
      'app_password',
      'password_mode',
    ]) {
      if (backup.containsKey(key)) {
        final value = backup[key];
        if (value is String) {
          await prefs.setString(_profilePrefKey(profileId, key), value);
        } else {
          await prefs.setString(
            _profilePrefKey(profileId, key),
            jsonEncode(value),
          );
        }
      }
    }
    if (backup.containsKey('biometric_enabled')) {
      final value = backup['biometric_enabled'];
      final boolValue =
          value is bool ? value : value.toString().toLowerCase() == 'true';
      await prefs.setBool(
          _profilePrefKey(profileId, 'biometric_enabled'), boolValue);
    }
    if (backup.containsKey('currency_code')) {
      final code = backup['currency_code']?.toString() ?? '';
      if (code.isNotEmpty) {
        await prefs.setString(
            _profilePrefKey(profileId, 'currency_code'), code);
      }
    }
  }

  static Future<void> importLegacySqliteFileForProfile(
    Uint8List bytes, {
    required String profileId,
  }) async {
    if (kIsWeb) throw 'SQLite restore not supported on Web';
    await DatabaseHelper.instance.closeDb();
    String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final directory = await getApplicationSupportDirectory();
      dbPath = directory.path;
    } else {
      dbPath = await getDatabasesPath();
    }
    final path = p.join(dbPath, _profileDbFileName(profileId));
    await File(path).writeAsBytes(bytes, flush: true);
    await DatabaseHelper.instance.setProfile(profileId);
    await DatabaseHelper.instance.database;
  }
}
