import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import 'backup_service.dart';

class BackupLocation {
  const BackupLocation({
    required this.id,
    required this.label,
    required this.path,
  });

  final String id;
  final String label;
  final String path;

  bool get isSdCard => id == 'sdcard';
  bool get isCustom => id == 'custom';
}

class AutoBackupStatus {
  const AutoBackupStatus({
    required this.enabled,
    required this.setupDone,
    required this.locationId,
    this.folderPath,
    this.lastSavedAt,
    this.lastError,
  });

  final bool enabled;
  final bool setupDone;
  final String locationId;
  final String? folderPath;
  final DateTime? lastSavedAt;
  final String? lastError;

  String get locationLabel {
    switch (locationId) {
      case 'sdcard':
        return 'SD card';
      case 'custom':
        return 'My folder';
      default:
        return 'Phone storage';
    }
  }
}

/// Writes a rolling backup outside app private storage so it survives uninstall.
class LocalAutoBackupService {
  LocalAutoBackupService._();
  static final LocalAutoBackupService instance = LocalAutoBackupService._();

  static const MethodChannel _channel = MethodChannel('budget_pro/storage');
  static const String autoFileName = 'BudgetPro_AutoBackup.budgetpro';
  static const String _enabledKey = 'bp_auto_backup_enabled';
  static const String _setupKey = 'bp_auto_backup_setup_done';
  static const String _locationKey = 'bp_auto_backup_location';
  static const String _pathKey = 'bp_auto_backup_path';
  static const String _lastAtKey = 'bp_auto_backup_last_at';
  static const String _lastErrorKey = 'bp_auto_backup_last_error';

  bool _saving = false;

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  Future<AutoBackupStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? lastAt;
    final raw = prefs.getString(_lastAtKey);
    if (raw != null && raw.isNotEmpty) {
      lastAt = DateTime.tryParse(raw);
    }
    return AutoBackupStatus(
      enabled: prefs.getBool(_enabledKey) ?? true,
      setupDone: prefs.getBool(_setupKey) ?? false,
      locationId: prefs.getString(_locationKey) ?? 'phone',
      folderPath: prefs.getString(_pathKey),
      lastSavedAt: lastAt,
      lastError: prefs.getString(_lastErrorKey),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  Future<void> setLocation(BackupLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupKey, true);
    await prefs.setBool(_enabledKey, true);
    await prefs.setString(_locationKey, location.id);
    await prefs.setString(_pathKey, location.path);
  }

  Future<void> markSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupKey, true);
  }

  Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final storage = await Permission.storage.request();
      if (await Permission.manageExternalStorage.isGranted) return true;
      final manage = await Permission.manageExternalStorage.request();
      return manage.isGranted || storage.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<List<BackupLocation>> availableLocations() async {
    if (kIsWeb) return const [];

    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMethod<List<dynamic>>(
          'getStorageLocations',
        );
        final fromNative = <BackupLocation>[];
        for (final item in raw ?? const []) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final id = (map['id'] ?? '').toString();
          final label = (map['label'] ?? '').toString();
          final path = (map['path'] ?? '').toString();
          if (id.isEmpty || path.isEmpty) continue;
          fromNative.add(BackupLocation(
            id: id,
            label: label.isEmpty ? id : label,
            path: path,
          ));
        }
        if (fromNative.isNotEmpty) return _uniqueById(fromNative);
      } catch (_) {}
      return _androidFallbackLocations();
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final docs = await getApplicationDocumentsDirectory();
      return [
        BackupLocation(
          id: 'phone',
          label: 'This computer',
          path: p.join(docs.path, 'BudgetPro'),
        ),
      ];
    }
    return const [];
  }

  List<BackupLocation> _uniqueById(List<BackupLocation> list) {
    final seen = <String>{};
    return list.where((e) {
      if (seen.contains(e.id)) return false;
      seen.add(e.id);
      return true;
    }).toList();
  }

  Future<List<BackupLocation>> _androidFallbackLocations() async {
    final list = <BackupLocation>[
      const BackupLocation(
        id: 'phone',
        label: 'Phone storage',
        path: '/storage/emulated/0/Documents/BudgetPro',
      ),
    ];
    final sd = await _findSdCardRoot();
    if (sd != null) {
      list.add(BackupLocation(
        id: 'sdcard',
        label: 'SD card',
        path: p.join(sd.path, 'BudgetPro'),
      ));
    }
    return list;
  }

  Future<Directory?> _findSdCardRoot() async {
    final storage = Directory('/storage');
    if (!await storage.exists()) return null;
    try {
      await for (final entity in storage.list()) {
        final name = p.basename(entity.path);
        if (RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(name)) {
          return Directory(entity.path);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _resolveFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pathKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return Directory(saved.trim());
    }
    final locations = await availableLocations();
    final id = prefs.getString(_locationKey) ?? 'phone';
    final match = locations.where((e) => e.id == id);
    if (match.isNotEmpty) return Directory(match.first.path);
    if (locations.isNotEmpty) return Directory(locations.first.path);
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Documents/BudgetPro');
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'BudgetPro'));
  }

  File autoBackupFileIn(Directory folder) =>
      File(p.join(folder.path, autoFileName));

  Future<File?> findExistingBackupFile() async {
    final locations = await availableLocations();
    final prefs = await SharedPreferences.getInstance();
    final preferred = prefs.getString(_pathKey);

    final candidates = <String>[
      if (preferred != null && preferred.isNotEmpty)
        p.join(preferred, autoFileName),
      ...locations.map((e) => p.join(e.path, autoFileName)),
      '/storage/emulated/0/Documents/BudgetPro/$autoFileName',
      '/storage/emulated/0/Download/BudgetPro/$autoFileName',
    ];

    File? best;
    DateTime? bestTime;
    for (final path in candidates.toSet()) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        if (await file.length() < 20) continue;
        final time = await file.lastModified();
        if (best == null || time.isAfter(bestTime!)) {
          best = file;
          bestTime = time;
        }
      } catch (_) {}
    }
    return best;
  }

  Future<bool> saveNow({bool ignoreEnabled = false}) async {
    if (!isSupported) return false;
    if (_saving) return false;
    final prefs = await SharedPreferences.getInstance();
    if (!ignoreEnabled && !(prefs.getBool(_enabledKey) ?? true)) return false;

    _saving = true;
    try {
      await ensurePermission();
      final empty = await DatabaseHelper.instance.isUserDataEmpty();
      if (empty) {
        final existing = await findExistingBackupFile();
        if (existing != null) return false;
      }
      final folder = await _resolveFolder();
      await folder.create(recursive: true);
      final json = await BackupService.buildAllProfilesBackupJson();
      final file = autoBackupFileIn(folder);
      await file.writeAsString(json, flush: true);
      await prefs.setString(_pathKey, folder.path);
      await prefs.setString(_lastAtKey, DateTime.now().toIso8601String());
      await prefs.remove(_lastErrorKey);
      return true;
    } catch (e) {
      await prefs.setString(_lastErrorKey, e.toString());
      return false;
    } finally {
      _saving = false;
    }
  }

  Future<void> saveInBackground() {
    return saveNow();
  }

  Future<bool> restoreFromDiskIfPresent() async {
    final file = await findExistingBackupFile();
    if (file == null) return false;
    await BackupService.restoreFromPath(file.path);
    final folder = file.parent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupKey, true);
    await prefs.setBool(_enabledKey, true);
    await prefs.setString(_pathKey, folder.path);
    final locations = await availableLocations();
    final match = locations.where((e) => e.path == folder.path);
    final locationId = match.isNotEmpty
        ? match.first.id
        : (folder.path.contains(RegExp(r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}'))
            ? 'sdcard'
            : 'custom');
    await prefs.setString(_locationKey, locationId);
    return true;
  }

  /// User-picked folder for auto backup (any writable path).
  BackupLocation customLocation(String folderPath) {
    return BackupLocation(
      id: 'custom',
      label: 'My folder',
      path: folderPath.trim(),
    );
  }
}
