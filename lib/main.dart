import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:table_calendar/table_calendar.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'reports_screen.dart';
import 'search_screen.dart';
import 'services/backup_service.dart';
import 'services/budget_alert_service.dart';
import 'services/currency_service.dart';
import 'settings_screen.dart';
import 'utils/category_utils.dart';
import 'utils/image_helper.dart';
import 'utils/profile_templates.dart';
import 'utils/share_file_helper.dart';
import 'vault_screen.dart';
import 'portfolio_screen.dart';
import 'widgets/family_expiry_panel.dart';
import 'widgets/full_screen_image.dart';
import 'widgets/import_family_image_sheet.dart';
import 'widgets/journal_hub.dart';
import 'widgets/notifications_panel.dart';
import 'widgets/share_attach_picker_sheet.dart';
import 'widgets/share_image_destination_sheet.dart';
import 'widgets/transaction_sheet.dart';
import 'widgets/vault_pin_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Budget Pro',
    theme: AppTheme.light,
    home: const MainScreen(),
  ));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  static const String _profilesKey = 'bp_profiles';
  static const String _activeProfileKey = 'bp_active_profile';
  int _selectedIndex = 0;
  int _vaultRefreshNonce = 0;
  int _notebookShareNonce = 0;
  List<String>? _notebookShareImages;
  int? _notebookShareNoteId;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _diaryEntries = [];
  List<Map<String, dynamic>> _diaryCategories = [];
  List<Map<String, dynamic>> _notes = [];

  String? _appPassword;
  List<Map<String, String>> _profiles = const [];
  String _activeProfileId = 'default';
  String _passwordMode = 'strong';
  bool _biometricEnabled = false;
  bool _isLocked = false;
  bool _lockDialogVisible = false;
  bool _isFirstStart = true;
  DateTime _lastUserActivity = DateTime.now();
  DateTime? _lastPausedAt;
  static const Duration _lockAfterIdle = Duration(minutes: 3);
  String _appVersion = '';
  List<BudgetAlert> _budgetAlerts = [];
  StreamSubscription? _shareSub;
  Timer? _idleLockTimer;
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _biometricInProgress = false;

  double _balance = 0, _income = 0, _expense = 0;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  String _txSearchQuery = "";
  final TextEditingController _txSearchController = TextEditingController();
  bool _showWalletSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  Future<void> _initApp() async {
    final info = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    await _loadProfiles(prefs);
    await DatabaseHelper.instance.setProfile(_activeProfileId);
    await CurrencyService.instance.loadForProfile(_activeProfileId);
    if (mounted) {
      setState(() {
        _appVersion = 'v${info.version}';
        _passwordMode =
            prefs.getString(_profilePrefKey('password_mode')) ?? 'strong';
        _biometricEnabled =
            prefs.getBool(_profilePrefKey('biometric_enabled')) ?? false;
      });
    }
    await _loadAllData();
    if (_hasAppPassword()) _scheduleIdleLock();
    _listenForSharedBackup();
  }

  Future<void> _loadProfiles(SharedPreferences prefs) async {
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
      parsed = const [
        {'id': 'default', 'name': 'Personal'},
      ];
    }
    if (!parsed.any((p) => p['id'] == 'default')) {
      parsed.insert(0, const {'id': 'default', 'name': 'Personal'});
    }
    final active = prefs.getString(_activeProfileKey) ?? 'default';
    _profiles = parsed;
    _activeProfileId =
        parsed.any((p) => p['id'] == active) ? active : parsed.first['id']!;
    await prefs.setString(_activeProfileKey, _activeProfileId);
    await prefs.setString(_profilesKey, jsonEncode(_profiles));
  }

  String _activeProfileName() {
    final p = _profiles.where((e) => e['id'] == _activeProfileId).toList();
    return p.isEmpty ? 'Personal' : p.first['name']!;
  }

  String _profilePrefKey(String key, {String? profileId}) =>
      '${profileId ?? _activeProfileId}_$key';

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilesKey, jsonEncode(_profiles));
    await prefs.setString(_activeProfileKey, _activeProfileId);
  }

  Future<void> _switchProfile(String profileId) async {
    if (profileId == _activeProfileId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileKey, profileId);
    await DatabaseHelper.instance.setProfile(profileId);
    await CurrencyService.instance.loadForProfile(profileId);
    if (!mounted) return;
    setState(() {
      _activeProfileId = profileId;
      _passwordMode = prefs.getString(
              _profilePrefKey('password_mode', profileId: profileId)) ??
          'strong';
      _biometricEnabled = prefs.getBool(
              _profilePrefKey('biometric_enabled', profileId: profileId)) ??
          false;
    });
    await _loadAllData();
  }

  Future<void> _renameProfile(String id, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) return;
    setState(() {
      _profiles = _profiles
          .map((p) => p['id'] == id ? {'id': p['id']!, 'name': name} : p)
          .toList();
    });
    await _saveProfiles();
  }

  Future<void> _deleteProfile(String id) async {
    if (id == 'default') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default profile cannot be deleted')),
      );
      return;
    }
    final exists = _profiles.any((p) => p['id'] == id);
    if (!exists) return;
    final fallback = _profiles.firstWhere((p) => p['id'] == 'default',
        orElse: () => _profiles.first);
    final wasActive = id == _activeProfileId;
    setState(() {
      _profiles = _profiles.where((p) => p['id'] != id).toList();
      if (_profiles.isEmpty) {
        _profiles = const [
          {'id': 'default', 'name': 'Personal'}
        ];
      }
      if (wasActive) {
        _activeProfileId = fallback['id']!;
      }
    });
    await _saveProfiles();
    await DatabaseHelper.instance.deleteProfileDatabase(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profilePrefKey('app_password', profileId: id));
    await prefs.remove(_profilePrefKey('password_mode', profileId: id));
    await prefs.remove(_profilePrefKey('biometric_enabled', profileId: id));
    await prefs.remove(_profilePrefKey('diary_categories', profileId: id));
    await prefs.remove(_profilePrefKey('currency_code', profileId: id));
    await prefs.remove(_profilePrefKey('notebook_categories', profileId: id));
    await prefs.remove('${id}_vault_pin');
    if (wasActive) {
      await DatabaseHelper.instance.setProfile(_activeProfileId);
      await _loadAllData();
    }
  }

  Future<void> _exportProfileBackup(
      String profileId, String profileName) async {
    try {
      final backupJson =
          await BackupService.buildFullBackupJson(profileId: profileId);
      final fileName = BackupService.timestampedBackupFileName(
        label: '${profileName}_Profile',
      );
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: backupJson));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup copied to clipboard')),
          );
        }
        return;
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Profile Backup',
          fileName: fileName,
        );
        if (outputFile != null) {
          await File(outputFile).writeAsString(backupJson);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Backup saved: $outputFile')),
            );
          }
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(backupJson);
      await ShareFileHelper.share(
        path: file.path,
        fileName: fileName,
        mimeType: 'application/octet-stream',
        text: 'Budget Pro profile backup',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _importProfileBackup(String profileId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null) return;
      Uint8List? bytes = result.files.first.bytes;
      if (bytes == null && result.files.first.path != null) {
        bytes = await File(result.files.first.path!).readAsBytes();
      }
      if (bytes == null) throw 'Could not read file data';

      final content = utf8.decode(bytes, allowMalformed: true);
      if (content.trim().startsWith('{')) {
        await BackupService.restoreFromBytesForProfile(
          bytes,
          profileId: profileId,
        );
      } else {
        await BackupService.importLegacySqliteFileForProfile(
          bytes,
          profileId: profileId,
        );
      }

      if (_activeProfileId == profileId) {
        await DatabaseHelper.instance.setProfile(profileId, forceReopen: true);
        await CurrencyService.instance.loadForProfile(profileId);
        await _loadAllData();
      } else {
        await DatabaseHelper.instance.setProfile(_activeProfileId, forceReopen: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile restored successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Import failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showProfilesSheet() async {
    final nameC = TextEditingController();
    final nameFocus = FocusNode();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String template = 'Personal';
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Profiles',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Personal, Shop, Pharmacy — each has its own data & currency',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    ..._profiles.map((p) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p['name']!),
                          subtitle: Text(p['id']!),
                          leading: Icon(
                            p['id'] == _activeProfileId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: AppTheme.primary,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'export') {
                                await _exportProfileBackup(
                                    p['id']!, p['name']!);
                                return;
                              }
                              if (action == 'import') {
                                await _importProfileBackup(p['id']!);
                                return;
                              }
                              if (action == 'rename') {
                                final c =
                                    TextEditingController(text: p['name']);
                                await showDialog(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('Rename profile'),
                                    content: TextField(
                                      controller: c,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Profile name',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dCtx),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () async {
                                          await _renameProfile(
                                              p['id']!, c.text);
                                          if (dCtx.mounted) Navigator.pop(dCtx);
                                          setSheet(() {});
                                        },
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                return;
                              }
                              if (action == 'delete') {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('Delete profile'),
                                    content: const Text(
                                      'Is profile ka sara data delete ho jayega.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dCtx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dCtx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await _deleteProfile(p['id']!);
                                  if (!ctx.mounted) return;
                                  setSheet(() {});
                                }
                              }
                            },
                            itemBuilder: (menuCtx) => [
                              const PopupMenuItem(
                                value: 'export',
                                child: Text('Export backup'),
                              ),
                              const PopupMenuItem(
                                value: 'import',
                                child: Text('Import backup'),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              if (p['id'] != 'default')
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                            ],
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _switchProfile(p['id']!);
                          },
                        )),
                    const Divider(),
                    TextField(
                      controller: nameC,
                      focusNode: nameFocus,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'New profile name',
                        prefixIcon: Icon(Icons.add_business),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: template,
                      items: ProfileTemplates.choices
                          .map((t) =>
                              DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) =>
                          setSheet(() => template = v ?? 'Personal'),
                      decoration: const InputDecoration(
                        labelText: 'Starter template',
                        prefixIcon: Icon(Icons.dashboard_customize_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () async {
                        final name = nameC.text.trim();
                        if (name.isEmpty) return;
                        if (_profiles.any((p) =>
                            p['name']!.toLowerCase() == name.toLowerCase())) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile name already exists'),
                              ),
                            );
                          }
                          return;
                        }
                        final chosenTemplate = template;
                        final id =
                            'p${DateTime.now().millisecondsSinceEpoch.toString()}';
                        final next = [
                          ..._profiles,
                          {'id': id, 'name': name}
                        ];
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(_profilesKey, jsonEncode(next));
                        if (!mounted) return;
                        setState(() => _profiles = next);
                        Navigator.pop(ctx);
                        await _switchProfile(id);
                        await ProfileTemplates.apply(chosenTemplate);
                        await _loadAllData();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create and switch'),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    nameFocus.dispose();
    nameC.dispose();
  }

  void _listenForSharedBackup() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (files.isNotEmpty) _handleSharedMedia(files);
      }).catchError((_) {});
      _shareSub =
          ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        if (files.isNotEmpty) _handleSharedMedia(files);
      }, onError: (_) {});
    } catch (_) {}
  }

  bool _isImagePath(String path, {String? mimeType}) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.startsWith('image/')) return true;
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.heic');
  }

  bool _isBackupPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.budgetpro') || lower.endsWith('.json');
  }

  Future<bool> _looksLikeBackupJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final len = await file.length();
      if (len <= 0 || len > 50 * 1024 * 1024) return false;
      final head = await file.openRead(0, 64).transform(utf8.decoder).join();
      final trimmed = head.trimLeft();
      return trimmed.startsWith('{') || trimmed.startsWith('[');
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> files) async {
    if (!mounted || files.isEmpty) return;

    final imagePaths = <String>[];
    String? backupPath;

    for (final f in files) {
      final path = f.path;
      if (path.isEmpty) continue;
      final mime = f.mimeType;
      if (f.type == SharedMediaType.image ||
          _isImagePath(path, mimeType: mime)) {
        imagePaths.add(path);
        continue;
      }
      if (_isBackupPath(path) || await _looksLikeBackupJson(path)) {
        backupPath ??= path;
        continue;
      }
    }

    if (imagePaths.isNotEmpty) {
      await _routeSharedImages(imagePaths);
      return;
    }
    if (backupPath != null) {
      await _restoreSharedFile(backupPath);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unsupported file')),
      );
    }
  }

  Future<void> _routeSharedImages(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final dest = await ShareImageDestinationSheet.show(
      context,
      imagePaths: paths,
    );
    if (!mounted || dest == null) return;
    switch (dest) {
      case ShareImageDestination.transaction:
        await _importSharedImageToTransaction(paths);
      case ShareImageDestination.vault:
        await _importSharedImageToVault(paths);
      case ShareImageDestination.notebook:
        await _importSharedImageToNotebook(paths);
    }
  }

  Future<void> _importSharedImageToTransaction(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final items = _transactions.take(20).map((tx) {
      final id = (tx['id'] as num?)?.toInt() ?? 0;
      final title = (tx['title'] ?? tx['category'] ?? 'Transaction').toString();
      final date = (tx['date'] ?? '').toString();
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      final type = (tx['type'] ?? '').toString();
      return ShareAttachItem(
        id: id,
        title: title,
        subtitle: date.isEmpty ? type : '$type · $date',
        trailing: CurrencyService.fmt(amount),
      );
    }).toList();

    final picked = await ShareAttachPickerSheet.show(
      context,
      title: 'Add photo to transaction',
      newLabel: 'New transaction',
      items: items,
    );
    if (!mounted || picked == null) return;

    Map<String, dynamic>? editTx;
    if (picked != -1) {
      try {
        editTx = _transactions.firstWhere((t) => t['id'] == picked);
      } catch (_) {
        editTx = null;
      }
    }

    setState(() => _selectedIndex = 0);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    _showAddTxModal(editTx: editTx, initialImages: paths);
  }

  Future<void> _importSharedImageToNotebook(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final notes = _notes.isNotEmpty
        ? _notes
        : await DatabaseHelper.instance.getNotes();
    if (_notes.isEmpty && notes.isNotEmpty && mounted) {
      setState(() => _notes = notes);
    }

    final items = notes.take(20).map((n) {
      final id = (n['id'] as num?)?.toInt() ?? 0;
      final title = (n['title'] ?? 'Note').toString();
      final cat = (n['cat'] ?? '').toString();
      final date = (n['date'] ?? '').toString();
      return ShareAttachItem(
        id: id,
        title: title,
        subtitle: [cat, date].where((s) => s.isNotEmpty).join(' · '),
      );
    }).toList();

    final picked = await ShareAttachPickerSheet.show(
      context,
      title: 'Add photo to note',
      newLabel: 'New note',
      items: items,
    );
    if (!mounted || picked == null) return;

    setState(() {
      _selectedIndex = 3; // Journal → Notes tab
      _notebookShareImages = paths;
      _notebookShareNoteId = picked == -1 ? null : picked;
      _notebookShareNonce++;
    });
  }

  Future<void> _importSharedImageToVault(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final unlocked = await VaultPinGate.unlock(context);
    if (!unlocked || !mounted) return;

    final saved = await ImportFamilyImageSheet.show(
      context,
      imagePaths: paths,
    );
    if (!saved || !mounted) return;

    setState(() {
      _selectedIndex = 4; // Vault
      _vaultRefreshNonce++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved to Family Documents'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _restoreSharedFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await BackupService.restoreFromPath(path);
      await _reloadAfterRestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup restored from shared file'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Restore failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _txSearchController.dispose();
    _shareSub?.cancel();
    _idleLockTimer?.cancel();
    super.dispose();
  }

  String _screenTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Wallet';
      case 1:
        return 'Reports';
      case 2:
        return 'Portfolio';
      case 3:
        return 'Journal';
      case 4:
        return 'Vault';
      case 5:
        return 'Settings';
      default:
        return 'Budget Pro';
    }
  }

  Map<String, double> _liveAccountBalances() {
    final balances = <String, double>{};
    for (final a in _accounts) {
      balances[a['name'].toString()] =
          (a['initial_balance'] as num?)?.toDouble() ?? 0.0;
    }
    for (final t in _transactions) {
      final type = t['type']?.toString() ?? '';
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      final acc = t['account']?.toString() ?? '';
      final toAcc = t['toAccount']?.toString() ?? '';
      if (type == 'Income' && balances.containsKey(acc)) {
        balances[acc] = balances[acc]! + amt;
      } else if (type == 'Expense' && balances.containsKey(acc)) {
        balances[acc] = balances[acc]! - amt;
      } else if (type == 'Transfer') {
        if (balances.containsKey(acc)) balances[acc] = balances[acc]! - amt;
        if (balances.containsKey(toAcc)) {
          balances[toAcc] = balances[toAcc]! + amt;
        }
      }
    }
    return balances;
  }

  List<Map<String, dynamic>> _transactionsForAccount(String accountName) {
    final list = _transactions.where((t) {
      final type = t['type']?.toString() ?? '';
      final acc = t['account']?.toString() ?? '';
      final toAcc = t['toAccount']?.toString() ?? '';
      if (type == 'Transfer') {
        return acc == accountName || toAcc == accountName;
      }
      return acc == accountName;
    }).toList();
    list.sort((a, b) {
      try {
        return DateTime.parse(b['date'].toString())
            .compareTo(DateTime.parse(a['date'].toString()));
      } catch (_) {
        return 0;
      }
    });
    return list;
  }

  void _openAccountDetail(String accountName) {
    Map<String, dynamic>? acc;
    for (final a in _accounts) {
      if (a['name']?.toString() == accountName) {
        acc = a;
        break;
      }
    }
    final opening = (acc?['initial_balance'] as num?)?.toDouble() ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        final balance = _liveAccountBalances()[accountName] ?? 0.0;
        final txs = _transactionsForAccount(accountName);
        final income = txs
            .where((t) => t['type'] == 'Income')
            .fold<double>(
                0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));
        final expense = txs
            .where((t) => t['type'] == 'Expense')
            .fold<double>(
                0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));
        final height = MediaQuery.of(sheetCtx).size.height * 0.92;

        return SizedBox(
          height: height,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                    Expanded(
                      child: Text(
                        accountName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (acc != null)
                      IconButton(
                        tooltip: 'Edit account',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _editAccountDialog(acc);
                        },
                      ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyService.fmt(balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'In +${CurrencyService.fmt(income)}',
                            style: const TextStyle(
                                color: Color(0xFFA7F3D0), fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Out -${CurrencyService.fmt(expense)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Color(0xFFFCA5A5), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Opening ${CurrencyService.fmt(opening)}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${txs.length} transaction${txs.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: txs.isEmpty
                    ? const Center(
                        child: Text(
                          'No transactions in this account',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: txs.length,
                        itemBuilder: (_, i) => _buildTxTile(txs[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _touchUserActivity() {
    _lastUserActivity = DateTime.now();
    _scheduleIdleLock();
  }

  void _scheduleIdleLock() {
    _idleLockTimer?.cancel();
    if (!_hasAppPassword()) return;
    _idleLockTimer = Timer(_lockAfterIdle, () {
      if (mounted && !_lockDialogVisible) {
        _requestAppLock(idleLock: true);
      }
    });
  }

  bool _hasAppPassword() => _appPassword != null && _appPassword!.isNotEmpty;

  bool _idleLongEnough() =>
      DateTime.now().difference(_lastUserActivity) >= _lockAfterIdle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasAppPassword()) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _lastPausedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final pausedAt = _lastPausedAt;
        _lastPausedAt = null;
        if (pausedAt != null &&
            DateTime.now().difference(pausedAt) >= _lockAfterIdle) {
          _requestAppLock(idleLock: true);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _loadAllData() async {
    final tx = await DatabaseHelper.instance.getTransactions();
    final acc = await DatabaseHelper.instance.getAccounts();
    final cat = await DatabaseHelper.instance.getCategories();
    final notes = await DatabaseHelper.instance.getNotes();
    final diary = await DatabaseHelper.instance.getDiary();

    final prefs = await SharedPreferences.getInstance();
    String dCatStr =
        prefs.getString(_profilePrefKey('diary_categories')) ?? "[]";
    String? pass = prefs.getString(_profilePrefKey('app_password'));

    if (mounted) {
      setState(() {
        _transactions = tx;
        _accounts = acc;
        _categories = cat;
        _notes = notes;
        _diaryEntries = diary;
        _appPassword = pass;

        var loadedDCats = List<Map<String, dynamic>>.from(jsonDecode(dCatStr));
        if (loadedDCats.isEmpty) {
          _diaryCategories = [
            {'name': 'General'},
            {'name': 'Personal'},
            {'name': 'Work'}
          ];
        } else {
          _diaryCategories = loadedDCats;
        }
        _diaryCategories.sort(compareNameMaps);

        _calculateTotals();
        _budgetAlerts = BudgetAlertService.evaluate(
          transactions: _transactions,
          categories: _categories,
        );
      });

      if (_isFirstStart) {
        _isFirstStart = false;
        if (_appPassword != null && _appPassword!.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _requestAppLock(coldStart: true);
          });
        }
      }
    }
  }

  /// After backup restore: reload profile list + switch to restored active DB.
  Future<void> _reloadAfterRestore() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadProfiles(prefs);
    await DatabaseHelper.instance.setProfile(_activeProfileId);
    await CurrencyService.instance.loadForProfile(_activeProfileId);
    if (!mounted) return;
    setState(() {
      _passwordMode = prefs.getString(
              _profilePrefKey('password_mode', profileId: _activeProfileId)) ??
          'strong';
      _biometricEnabled = prefs.getBool(_profilePrefKey('biometric_enabled',
              profileId: _activeProfileId)) ??
          false;
    });
    await _loadAllData();
  }

  Future<bool> _canUseBiometric() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      if (await _localAuth.canCheckBiometrics) return true;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Runs system biometric without a Flutter dialog on top (required on many Android OEMs).
  Future<bool> _authenticateBiometric({bool showErrors = true}) async {
    if (_biometricInProgress) return false;
    _biometricInProgress = true;
    try {
      if (!await _canUseBiometric()) {
        if (showErrors && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Biometric not available. Add fingerprint/face in phone Settings first.',
              ),
            ),
          );
        }
        return false;
      }

      try {
        await _localAuth.stopAuthentication();
      } catch (_) {}

      return await _localAuth.authenticate(
        localizedReason: 'Unlock Budget Pro',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Budget Pro',
            biometricHint: 'Touch fingerprint sensor',
            cancelButton: 'Use password',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: false,
          biometricOnly: true,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );
    } on PlatformException catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric failed: ${e.message ?? e.code}')),
        );
      }
      return false;
    } catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric error: $e')),
        );
      }
      return false;
    } finally {
      _biometricInProgress = false;
    }
  }

  Future<void> _unlockAfterBiometric(BuildContext? dialogContext) async {
    if (!mounted) return;
    setState(() => _isLocked = false);
    _touchUserActivity();
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _tryBiometricFromDialog(BuildContext dialogContext) async {
    final ok = await _authenticateBiometric();
    if (ok) await _unlockAfterBiometric(dialogContext);
  }

  Future<void> _requestAppLock({
    bool coldStart = false,
    bool idleLock = false,
  }) async {
    if (!_hasAppPassword()) return;
    if (_isLocked || _lockDialogVisible) return;

    if (!coldStart) {
      if (idleLock) {
        if (!_idleLongEnough()) return;
      } else {
        return;
      }
    }

    await _checkAppLock();
  }

  Future<void> _checkAppLock() async {
    if (_isLocked || _lockDialogVisible) return;

    setState(() => _isLocked = true);

    if (_biometricEnabled) {
      final ok = await _authenticateBiometric(showErrors: false);
      if (ok && mounted) {
        setState(() => _isLocked = false);
        _touchUserActivity();
        return;
      }
    }

    if (!mounted) return;
    _showPasswordLockDialog();
  }

  void _showPasswordLockDialog() {
    final passC = TextEditingController();
    bool isObscure = true;
    _lockDialogVisible = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: StatefulBuilder(builder: (context, setStateSB) {
          return AlertDialog(
            title: const Text("App Locked",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passC,
                  obscureText: isObscure,
                  decoration: InputDecoration(
                    labelText: "Enter Password to Unlock",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          isObscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setStateSB(() {
                          isObscure = !isObscure;
                        });
                      },
                    ),
                  ),
                ),
                if (_biometricEnabled) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _tryBiometricFromDialog(c),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use Biometric'),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SystemNavigator.pop();
                },
                child: const Text("Exit App",
                    style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (passC.text == _appPassword) {
                    setState(() => _isLocked = false);
                    _touchUserActivity();
                    Navigator.pop(c);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Wrong Password! Try Again.")),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                child:
                    const Text("Unlock", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }),
      ),
    ).then((_) {
      _lockDialogVisible = false;
    });
  }

  void _calculateTotals() {
    _income = _transactions
        .where((t) => t['type'] == 'Income')
        .fold(0.0, (sum, t) => sum + (t['amount'] ?? 0).toDouble());
    _expense = _transactions
        .where((t) => t['type'] == 'Expense')
        .fold(0.0, (sum, t) => sum + (t['amount'] ?? 0).toDouble());
    double initialTotal = _accounts.fold(
        0.0, (sum, acc) => sum + (acc['initial_balance'] ?? 0.0).toDouble());
    _balance = initialTotal + _income - _expense;
  }

  Widget _getIndexedScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildWalletView();
      case 1:
        return AdvancedReports(
          transactions: _transactions,
          accounts: _accounts,
          categories: _categories,
          diaryEntries: _diaryEntries,
          onEditTransaction: (tx) => _showAddTxModal(editTx: tx),
        );
      case 2:
        return const PortfolioScreen();
      case 3:
        return JournalHub(
          diaryEntries: _diaryEntries,
          diaryCategories: _diaryCategories,
          activeProfileId: _activeProfileId,
          sharedImages: _notebookShareImages,
          sharedNoteId: _notebookShareNoteId,
          sharedNonce: _notebookShareNonce,
          onSharedConsumed: () {
            if (!mounted) return;
            setState(() {
              _notebookShareImages = null;
              _notebookShareNoteId = null;
            });
          },
        );
      case 4:
        return VaultScreen(key: ValueKey(_vaultRefreshNonce));
      case 5:
        return SettingsScreen(
          accounts: _accounts,
          categories: _categories,
          diaryCategories: _diaryCategories,
          loadAllData: _loadAllData,
          managePin: _showPasswordManagementDialog,
          deletePin: _deletePassword,
          editAccount: _editAccountDialog,
          addCategory: _addCategoryDialog,
          addDiaryCategory: _addDiaryCategoryDialog,
          deleteDiaryCategory: _deleteDiaryCategory,
          confirmDelete: (fn) => _confirmDelete(() async {
            await fn();
          }),
          confirmReset: _confirmResetDialog,
          activeProfileName: _activeProfileName(),
          activeProfileId: _activeProfileId,
          exportActiveProfileBackup: () =>
              _exportProfileBackup(_activeProfileId, _activeProfileName()),
          importToActiveProfile: () => _importProfileBackup(_activeProfileId),
          onBackupRestored: _reloadAfterRestore,
        );
      default:
        return _buildWalletView();
    }
  }

  void _showPasswordManagementDialog() {
    final passC = TextEditingController();
    final confirmC = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool isObscureNew = true;
    bool isObscureConfirm = true;
    String mode = _passwordMode;
    bool useBio = _biometricEnabled;

    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(builder: (context, setStateSB) {
              return AlertDialog(
                title: Text(_appPassword == null
                    ? "Set App Password"
                    : "Change App Password"),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'strong', label: Text('Strong')),
                          ButtonSegment(value: 'simple', label: Text('Simple')),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) =>
                            setStateSB(() => mode = s.first),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mode == 'strong'
                            ? 'Strong: 8+ chars, A-Z, a-z, 0-9, symbol'
                            : 'Simple: minimum 4 characters',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: passC,
                        obscureText: isObscureNew,
                        decoration: InputDecoration(
                            labelText: "New Password",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                                icon: Icon(isObscureNew
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () {
                                  setStateSB(() {
                                    isObscureNew = !isObscureNew;
                                  });
                                })),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return "Enter password";
                          }
                          if (mode == 'simple') {
                            if (val.length < 4) return 'Minimum 4 characters';
                            return null;
                          }
                          String pattern =
                              r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~]).{8,}$';
                          if (!RegExp(pattern).hasMatch(val)) {
                            return "Password is too weak!";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: confirmC,
                        obscureText: isObscureConfirm,
                        decoration: InputDecoration(
                            labelText: "Confirm Password",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                                icon: Icon(isObscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () {
                                  setStateSB(() {
                                    isObscureConfirm = !isObscureConfirm;
                                  });
                                })),
                        validator: (val) {
                          if (val != passC.text)
                            return "Passwords do not match";
                          return null;
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Biometric unlock'),
                        subtitle: const Text('Fingerprint / Face unlock'),
                        value: useBio,
                        onChanged: (v) async {
                          if (v) {
                            final can = await _canUseBiometric();
                            if (!can) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Enable fingerprint/face in phone Settings first.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                          }
                          setStateSB(() => useBio = v);
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                              _profilePrefKey('app_password'), passC.text);
                          await prefs.setString(
                              _profilePrefKey('password_mode'), mode);
                          await prefs.setBool(
                              _profilePrefKey('biometric_enabled'), useBio);
                          setState(() {
                            _appPassword = passC.text;
                            _passwordMode = mode;
                            _biometricEnabled = useBio;
                          });
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Password Saved!")));
                        }
                      },
                      child: const Text("Save Password"))
                ],
              );
            }));
  }

  void _deletePassword() {
    if (_appPassword == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("No password set.")));
      return;
    }
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text("Remove Password"),
              content: const Text("Kya aap security hatana chahte hain?"),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c), child: const Text("No")),
                TextButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(_profilePrefKey('app_password'));
                      await prefs.remove(_profilePrefKey('biometric_enabled'));
                      setState(() {
                        _appPassword = null;
                        _biometricEnabled = false;
                      });
                      Navigator.pop(c);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Password Removed!")));
                    },
                    child:
                        const Text("Yes", style: TextStyle(color: Colors.red)))
              ],
            ));
  }

  Widget _buildWalletView() {
    var filtered = _transactions.where((t) {
      String q = _txSearchQuery.trim().toLowerCase();
      if (q.isEmpty) {
        DateTime dt = DateTime.parse(t['date']);
        return isSameDay(dt, _selectedDay);
      } else {
        String title = (t['title'] ?? "").toString().toLowerCase();
        String desc =
            (t['desc'] ?? t['description'] ?? "").toString().toLowerCase();
        String cat = (t['category'] ?? "").toString().toLowerCase();
        String accName = (t['account'] ?? "").toString().toLowerCase();
        String toAcc = (t['toAccount'] ?? "").toString().toLowerCase();
        String amt = (t['amount'] ?? "").toString();
        return title.contains(q) ||
            desc.contains(q) ||
            cat.contains(q) ||
            accName.contains(q) ||
            toAcc.contains(q) ||
            amt.contains(q);
      }
    }).toList();

    return Column(
      children: [
        _buildBalanceCard(),
        if (_showWalletSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: TextField(
              controller: _txSearchController,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search title, account, amount...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Full search',
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => const MasterSearchScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _showWalletSearch = false;
                        _txSearchQuery = '';
                        _txSearchController.clear();
                      }),
                    ),
                  ],
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _txSearchQuery = v),
            ),
          ),
        if (_budgetAlerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: InkWell(
              onTap: () async {
                await showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.savings_outlined),
                          title: const Text('Budget alerts'),
                          onTap: () {
                            Navigator.pop(ctx);
                            NotificationsPanel.show(context, _budgetAlerts);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.event_busy_rounded),
                          title: const Text('Family expiry center'),
                          subtitle: const Text('CNIC / docs / cards due soon'),
                          onTap: () {
                            Navigator.pop(ctx);
                            FamilyExpiryCenter.show(context);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _budgetAlerts.any((a) => a.isOverBudget)
                      ? AppTheme.expense.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _budgetAlerts.any((a) => a.isOverBudget)
                        ? AppTheme.expense.withValues(alpha: 0.4)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: _budgetAlerts.any((a) => a.isOverBudget)
                          ? AppTheme.expense
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_budgetAlerts.length} budget alert(s) — tap to view',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
        TableCalendar(
          firstDay: DateTime.utc(2020),
          lastDay: DateTime.utc(2030),
          focusedDay: _focusedDay,
          calendarFormat: CalendarFormat.week,
          headerVisible: false,
          rowHeight: 40,
          daysOfWeekHeight: 18,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (sel, foc) => setState(() {
            _selectedDay = sel;
            _focusedDay = foc;
            _txSearchQuery = '';
            _txSearchController.clear();
          }),
          calendarStyle: const CalendarStyle(
            cellMargin: EdgeInsets.all(2),
            selectedDecoration:
                BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(
                color: Colors.indigoAccent, shape: BoxShape.circle),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            weekendStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(
            children: [
              Text(
                DateFormat('EEE, dd MMM').format(_selectedDay),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· ${filtered.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_txSearchQuery.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _txSearchQuery = '';
                    _txSearchController.clear();
                  }),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear search', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _txSearchQuery.trim().isEmpty
                          ? 'No transactions\nUse + above to add'
                          : 'No matches',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _buildTxTile(filtered[i]))),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: AppTheme.balanceCardDecoration.copyWith(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Total Balance',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              Text(
                CurrencyService.fmt(_balance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          if (_accounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _liveAccountBalances().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openAccountDetail(e.key),
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${e.key}: ${CurrencyService.instance.formatNumber(e.value)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatChip(
                    label: 'Income',
                    value: '+${CurrencyService.fmt(_income)}',
                    color: AppTheme.income,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.white24,
                ),
                Expanded(
                  child: _buildStatChip(
                    label: 'Expense',
                    value: '-${CurrencyService.fmt(_expense)}',
                    color: const Color(0xFFFCA5A5),
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 3),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildTxTile(Map tx) {
    bool isInc = tx['type'] == 'Income';
    bool isTr = tx['type'] == 'Transfer';
    Color c =
        isTr ? AppTheme.transfer : (isInc ? AppTheme.income : AppTheme.expense);
    IconData icon = isTr
        ? Icons.sync_alt
        : (isInc ? Icons.arrow_downward : Icons.arrow_upward);

    List<String> images = ImageHelper.decodeImagePaths(tx['imgs']);
    String desc = (tx['desc'] ?? tx['description'] ?? "").toString();
    String dateStr = '';
    try {
      dateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(tx['date']));
    } catch (_) {}

    String catDisplay = tx['category'] ?? "";
    if (tx['sub_category'] != null &&
        tx['sub_category'].toString().isNotEmpty) {
      catDisplay += " - ${tx['sub_category']}";
    }
    if (isTr) {
      final effect = tx['category_effect']?.toString().trim();
      // Accept ASCII or Unicode minus stored values
      if (effect == '+' ||
          effect == '-' ||
          effect == '−' ||
          effect == '–') {
        final shown = (effect == '+' ) ? '+' : '-';
        catDisplay = "$catDisplay $shown";
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Column(
          children: [
            ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: c.withOpacity(0.1),
                  child: Icon(icon, color: c, size: 18)),
              title: Text(tx['title'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTr
                          ? "${tx['account']} -> ${tx['toAccount']} ($catDisplay)"
                          : "${tx['account']} | $catDisplay",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    if (dateStr.isNotEmpty)
                      Text(dateStr,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600)),
                    Builder(builder: (_) {
                      final lines = <Widget>[];
                      final fxCode = tx['fx_currency']?.toString() ?? '';
                      final fxAmt = tx['fx_amount'];
                      final home = CurrencyService.instance.code;
                      if (fxCode.isNotEmpty &&
                          fxAmt != null &&
                          fxCode.toUpperCase() != home) {
                        final fxNum = (fxAmt as num).toDouble();
                        lines.add(Text(
                          '$fxCode ${CurrencyService.instance.formatNumber(fxNum)} → ${CurrencyService.fmt((tx['amount'] as num).toDouble())}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.teal.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ));
                      }
                      final member = tx['member_name']?.toString() ?? '';
                      if (member.isNotEmpty) {
                        lines.add(Text(
                          '👤 $member',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.indigo.shade600,
                          ),
                        ));
                      }
                      if (lines.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: lines,
                      );
                    }),
                    if (desc.isNotEmpty)
                      Text(desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 11,
                              color: Colors.grey))
                  ]),
              trailing: Text(
                  "${isInc ? '+' : (isTr ? '' : '-')} ${CurrencyService.fmt((tx['amount'] as num).toDouble())}",
                  style: TextStyle(
                      color: c, fontWeight: FontWeight.bold, fontSize: 14)),
              onTap: () => _showAddTxModal(editTx: tx),
              onLongPress: () {
                _confirmDelete(() async {
                  await DatabaseHelper.instance.deleteTransaction(tx['id']);
                });
              },
            ),
            if (images.isNotEmpty)
              Container(
                  height: 56,
                  margin: const EdgeInsets.only(top: 2, bottom: 4),
                  child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      itemBuilder: (ctx, idx) => GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      FullScreenImage(imagePath: images[idx]))),
                          child: Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: Hero(
                                  tag: images[idx],
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: kIsWeb
                                          ? Image.network(images[idx],
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) =>
                                                  const Icon(Icons.image))
                                          : Image.file(File(images[idx]),
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) =>
                                                  const Icon(
                                                      Icons.image)))))))),
          ],
        ),
      ),
    );
  }

  void _editAccountDialog(Map? acc) {
    final nameC = TextEditingController(text: acc?['name'] ?? "");
    final balC =
        TextEditingController(text: acc?['initial_balance']?.toString() ?? "0");
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("Account"),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: nameC,
                      decoration: const InputDecoration(labelText: "Name")),
                  TextField(
                      controller: balC,
                      decoration: const InputDecoration(
                          labelText: "Opening balance"),
                      keyboardType: TextInputType.number)
                ]),
                actions: [
                  ElevatedButton(
                      onPressed: () async {
                        final newName = nameC.text.trim();
                        if (newName.isEmpty) return;
                        if (acc == null) {
                          await DatabaseHelper.instance.addAccount({
                            'name': newName,
                            'initial_balance':
                                double.tryParse(balC.text) ?? 0
                          });
                        } else {
                          final oldName = acc['name']?.toString() ?? '';
                          await DatabaseHelper.instance.updateAccount(
                              acc['id'], {
                            'name': newName,
                            'initial_balance':
                                double.tryParse(balC.text) ?? 0
                          });
                          if (oldName.isNotEmpty && oldName != newName) {
                            final db =
                                await DatabaseHelper.instance.database;
                            await db.rawUpdate(
                              'UPDATE transactions SET account = ? WHERE account = ?',
                              [newName, oldName],
                            );
                            await db.rawUpdate(
                              'UPDATE transactions SET toAccount = ? WHERE toAccount = ?',
                              [newName, oldName],
                            );
                          }
                        }
                        _loadAllData();
                        if (c.mounted) Navigator.pop(c);
                      },
                      child: const Text("Save"))
                ]));
  }

  void _addCategoryDialog({Map? editCat}) {
    final nameC = TextEditingController(text: editCat?['name'] ?? "");
    final budC =
        TextEditingController(text: editCat?['budget']?.toString() ?? "0");
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("Category"),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: nameC,
                      decoration: const InputDecoration(labelText: "Name")),
                  TextField(
                      controller: budC,
                      decoration: const InputDecoration(labelText: "Budget"),
                      keyboardType: TextInputType.number)
                ]),
                actions: [
                  ElevatedButton(
                      onPressed: () async {
                        if (editCat != null)
                          await DatabaseHelper.instance
                              .deleteCategory(editCat['id']);
                        await DatabaseHelper.instance.addCategory({
                          'name': nameC.text,
                          'budget': double.tryParse(budC.text) ?? 0
                        });
                        _loadAllData();
                        Navigator.pop(c);
                      },
                      child: const Text("Save"))
                ]));
  }

  void _addDiaryCategoryDialog({Map? editCat}) {
    final nameC = TextEditingController(text: editCat?['name'] ?? "");
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("Diary Category"),
                content: TextField(
                    controller: nameC,
                    decoration:
                        const InputDecoration(labelText: "Category Name")),
                actions: [
                  ElevatedButton(
                      onPressed: () async {
                        setState(() {
                          _diaryCategories.add({'name': nameC.text});
                          _diaryCategories.sort(compareNameMaps);
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                            _profilePrefKey('diary_categories'),
                            jsonEncode(_diaryCategories));
                        Navigator.pop(c);
                      },
                      child: const Text("Save"))
                ]));
  }

  void _deleteDiaryCategory(Map cat) async {
    setState(() => _diaryCategories.remove(cat));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _profilePrefKey('diary_categories'), jsonEncode(_diaryCategories));
  }

  void _confirmDelete(Future<void> Function() deleteAction) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("Confirm Delete"),
                content: const Text("Are you sure?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("No")),
                  TextButton(
                      onPressed: () async {
                        await deleteAction();
                        await _loadAllData();
                        Navigator.pop(c);
                      },
                      child: const Text("Yes",
                          style: TextStyle(color: Colors.red))),
                ]));
  }

  void _confirmResetDialog(bool full) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(title: const Text("Reset"), actions: [
              TextButton(
                  onPressed: () {
                    if (full)
                      DatabaseHelper.instance.resetDatabase();
                    else
                      DatabaseHelper.instance.clearTransactionsOnly();
                    _loadAllData();
                    Navigator.pop(c);
                  },
                  child: const Text("Yes"))
            ]));
  }

  Future<void> _showAddTxModal({Map? editTx, List<String>? initialImages}) async {
    final familyDocs = await DatabaseHelper.instance.getFamilyVault();
    final members = familyDocs
        .map((d) => (d['member_name'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (!mounted) return;
    await showTransactionSheet(
      context: context,
      transactions: _transactions,
      accounts: _accounts,
      categories: _categories,
      defaultDate: _selectedDay,
      editTx: editTx?.cast<String, dynamic>(),
      initialImages: initialImages,
      familyMembers: members,
      onCreateAccount: (name, openingBalance) async {
        final id = await DatabaseHelper.instance.addAccount({
          'name': name,
          'initial_balance': openingBalance,
        });
        await _loadAllData();
        return {
          'id': id,
          'name': name,
          'initial_balance': openingBalance,
        };
      },
      onSave: (data) async {
        if (editTx == null) {
          await DatabaseHelper.instance.addTransaction(data);
        } else {
          await DatabaseHelper.instance.updateTransaction(editTx['id'], data);
        }
        await _loadAllData();
        if (initialImages != null && initialImages.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo saved to transaction'),
              backgroundColor: Colors.green,
            ),
          );
        }
        final over = _budgetAlerts.where((a) => a.isOverBudget).toList();
        if (over.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.expense,
              content: Text('Budget alert: ${over.first.title} is over limit'),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CurrencyService.instance,
      builder: (context, _) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touchUserActivity(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${_screenTitle()} · ${_activeProfileName()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          titleSpacing: 12,
          actions: [
            IconButton(
              icon: const Icon(Icons.switch_account_rounded),
              tooltip: 'Switch profile',
              onPressed: _showProfilesSheet,
            ),
            if (_appVersion.isNotEmpty)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_appVersion,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70)),
                ),
              ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: 'Alerts',
                  onPressed: () async {
                    await showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.savings_outlined),
                              title: const Text('Budget alerts'),
                              onTap: () {
                                Navigator.pop(ctx);
                                NotificationsPanel.show(
                                    context, _budgetAlerts);
                              },
                            ),
                            ListTile(
                              leading:
                                  const Icon(Icons.event_busy_rounded),
                              title: const Text('Family expiry center'),
                              subtitle: const Text(
                                  'CNIC / docs / cards due soon'),
                              onTap: () {
                                Navigator.pop(ctx);
                                FamilyExpiryCenter.show(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (_budgetAlerts.any((a) => a.isOverBudget))
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppTheme.expense,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            if (_selectedIndex == 0) ...[
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                tooltip: 'Add transaction',
                onPressed: () => _showAddTxModal(),
              ),
              IconButton(
                icon: Icon(_showWalletSearch
                    ? Icons.search_off_rounded
                    : Icons.search_rounded),
                tooltip: _showWalletSearch ? 'Hide search' : 'Search',
                onPressed: () {
                  if (_showWalletSearch) {
                    setState(() {
                      _showWalletSearch = false;
                      _txSearchQuery = '';
                      _txSearchController.clear();
                    });
                  } else {
                    setState(() => _showWalletSearch = true);
                  }
                },
              ),
            ],
            IconButton(
              icon: const Icon(Icons.power_settings_new_rounded),
              tooltip: 'Exit App',
              onPressed: SystemNavigator.pop,
            ),
          ],
        ),
        body: _getIndexedScreen(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            _touchUserActivity();
            setState(() => _selectedIndex = i);
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Wallet'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'Reports'),
            NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings_rounded),
                label: 'Portfolio'),
            NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: 'Journal'),
            NavigationDestination(
                icon: Icon(Icons.lock_outline),
                selectedIcon: Icon(Icons.lock),
                label: 'Vault'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
        ),
      ),
    ),
    );
  }
}
