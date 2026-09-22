import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/share_file_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'config/google_oauth_config.dart';
import 'services/backup_service.dart';
import 'services/currency_service.dart';
import 'services/google_drive_backup_service.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';
import 'database_helper.dart';
import 'utils/category_utils.dart';
import 'utils/vault_pin_prefs.dart';
import 'widgets/about_app_card.dart';
import 'widgets/auto_backup_setup_dialog.dart';

class SettingsScreen extends StatefulWidget {
  static final GlobalKey<_SettingsScreenState> globalKey =
      GlobalKey<_SettingsScreenState>(); // NAYA: Global key

  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> diaryCategories;
  final Function loadAllData;
  final Function managePin;
  final Function deletePin;
  final Function editAccount;
  final Function addCategory;
  final Function addDiaryCategory;
  final Function deleteDiaryCategory;
  final Function confirmDelete;
  final Function confirmReset;
  final String activeProfileName;
  final String activeProfileId;
  final Future<void> Function() exportActiveProfileBackup;
  final Future<void> Function() importToActiveProfile;
  final Future<void> Function() onBackupRestored;

  const SettingsScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.diaryCategories,
    required this.loadAllData,
    required this.managePin,
    required this.deletePin,
    required this.editAccount,
    required this.addCategory,
    required this.addDiaryCategory,
    required this.deleteDiaryCategory,
    required this.confirmDelete,
    required this.confirmReset,
    required this.activeProfileName,
    required this.activeProfileId,
    required this.exportActiveProfileBackup,
    required this.importToActiveProfile,
    required this.onBackupRestored,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _notebookCategories = [];

  String? _driveAccountName;
  bool _driveBusy = false;
  bool _notificationsEnabled = true;
  int _notifyHour = 9;

  bool get _driveAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _loadNotebookCategories();
    _refreshDriveAccount();
    _loadNotificationPrefs();
  }

  Future<void> _loadNotificationPrefs() async {
    final enabled = await NotificationService.instance.enabled;
    final hour = await NotificationService.instance.notifyHour;
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _notifyHour = hour;
    });
  }

  Future<void> _refreshDriveAccount() async {
    if (!_driveAvailable) return;
    final user = await GoogleDriveBackupService.currentUser();
    if (mounted) {
      setState(() => _driveAccountName = user?.displayName ?? user?.email);
    }
  }

  Future<void> _runDriveTask(
    Future<void> Function() task, {
    required String success,
  }) async {
    setState(() => _driveBusy = true);
    try {
      await task();
      await _refreshDriveAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('Google Drive setup required') ||
          msg.contains('error 10')) {
        _showGoogleDriveSetupDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  Future<void> _syncToGoogleDrive() async {
    final json = await BackupService.buildAllProfilesBackupJson();
    await GoogleDriveBackupService.uploadBackup(json);
  }

  Future<void> _restoreFromGoogleDrive() async {
    final json = await GoogleDriveBackupService.downloadBackup();
    await BackupService.restoreFromBytes(Uint8List.fromList(utf8.encode(json)));
    await widget.onBackupRestored();
    await _loadNotebookCategories();
    if (mounted) setState(() {});
  }

  Future<void> _disconnectGoogleDrive() async {
    await GoogleDriveBackupService.signOut();
    if (mounted) setState(() => _driveAccountName = null);
  }

  void _showGoogleDriveSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Drive setup'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Error 10 = app not registered in Google Cloud.\n\n'
            'Package:\n${GoogleOAuthConfig.androidPackage}\n\n'
            'SHA-1 (copy this):\n${GoogleOAuthConfig.debugSha1}\n\n'
            'Steps:\n'
            '1. console.cloud.google.com\n'
            '2. Enable Google Drive API\n'
            '3. Credentials → OAuth Android client (package + SHA-1 above)\n'
            '4. Credentials → OAuth Web client (same project)\n'
            '5. Wait 10 min → clear app data → sync again',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(text: GoogleOAuthConfig.debugSha1),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SHA-1 copied')),
              );
            },
            child: const Text('Copy SHA-1'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleDriveCard() {
    if (!_driveAvailable) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.cloud_upload_outlined, color: Colors.blue),
              title: Text('Google Drive sync (optional)'),
              subtitle: Text(
                'Cloud backup only — WhatsApp & local share stay the same',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_driveAccountName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Connected: $_driveAccountName',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (_driveBusy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.sync, color: Colors.blue),
                title: const Text('Sync backup to Google Drive'),
                subtitle: const Text('Upload ALL profiles with pictures'),
                onTap: () => _runDriveTask(
                  _syncToGoogleDrive,
                  success: 'Backup synced to Google Drive',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined,
                    color: Colors.indigo),
                title: const Text('Restore from Google Drive'),
                subtitle: const Text('Restore ALL profiles from cloud'),
                onTap: () => _runDriveTask(
                  _restoreFromGoogleDrive,
                  success: 'All profiles restored from Google Drive',
                ),
              ),
              if (_driveAccountName != null)
                ListTile(
                  leading: const Icon(Icons.link_off, color: Colors.grey),
                  title: const Text('Disconnect Google Drive'),
                  onTap: () => _runDriveTask(
                    _disconnectGoogleDrive,
                    success: 'Google Drive disconnected',
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.orange),
                title: const Text('Drive sign-in not working?'),
                subtitle: const Text('Show SHA-1 & setup steps'),
                onTap: _showGoogleDriveSetupDialog,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadNotebookCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.activeProfileId}_notebook_categories';
    String? cats = prefs.getString(key) ?? prefs.getString('notebook_categories');
    if (cats != null) {
      _notebookCategories =
          List<Map<String, dynamic>>.from(jsonDecode(cats));
    }
    if (_notebookCategories.isEmpty) {
      _notebookCategories = [
        {'id': '1', 'name': 'General'},
        {'id': '2', 'name': 'Useful Links'},
      ];
      await prefs.setString(key, jsonEncode(_notebookCategories));
    }
    _notebookCategories.sort(compareNameMaps);
    if (mounted) setState(() {});
  }

  Future<void> restoreFromPath(String filePath) async {
    await BackupService.restoreFromPath(filePath);
  }

  void _showCategoryDialog({Map<String, dynamic>? editCat}) {
    final nameC = TextEditingController(text: editCat?['name'] ?? '');
    final budgetC =
        TextEditingController(text: editCat?['budget']?.toString() ?? '');
    final subCatC = TextEditingController();

    List<String> subCategories = [];
    if (editCat != null &&
        editCat['sub_categories'] != null &&
        editCat['sub_categories'] != '') {
      try {
        subCategories =
            List<String>.from(jsonDecode(editCat['sub_categories']));
      } catch (e) {}
    }

    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (context, setSt) => AlertDialog(
                    title: Text(
                        editCat == null ? "Add Category" : "Edit Category"),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          TextField(
                              controller: nameC,
                              decoration: const InputDecoration(
                                  labelText: "Category Name (e.g. Food)")),
                          TextField(
                              controller: budgetC,
                              decoration: const InputDecoration(
                                  labelText: "Monthly Budget (Optional)"),
                              keyboardType: TextInputType.number),
                          const SizedBox(height: 15),
                          const Text("Sub Categories",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo)),
                          const SizedBox(height: 5),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                    child: TextField(
                                        controller: subCatC,
                                        decoration: const InputDecoration(
                                            hintText:
                                                "e.g. Snacks, Groceries"))),
                                IconButton(
                                    icon: const Icon(Icons.add_circle,
                                        color: Colors.indigo, size: 30),
                                    onPressed: () {
                                      if (subCatC.text.trim().isNotEmpty) {
                                        setSt(() {
                                          subCategories
                                              .add(subCatC.text.trim());
                                          subCatC.clear();
                                        });
                                      }
                                    })
                              ]),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: subCategories
                                .map((sc) => Chip(
                                      label: Text(sc),
                                      deleteIcon:
                                          const Icon(Icons.cancel, size: 18),
                                      onDeleted: () =>
                                          setSt(() => subCategories.remove(sc)),
                                      backgroundColor: Colors.indigo.shade50,
                                    ))
                                .toList(),
                          )
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text("Cancel")),
                      ElevatedButton(
                          onPressed: () async {
                            if (nameC.text.isEmpty) return;
                            Map<String, dynamic> data = {
                              'name': nameC.text,
                              'budget': double.tryParse(budgetC.text) ?? 0.0,
                              'sub_categories': jsonEncode(subCategories)
                            };
                            if (editCat == null) {
                              await DatabaseHelper.instance
                                  .insert('categories', data);
                            } else {
                              await DatabaseHelper.instance
                                  .updateCategory(editCat['id'], data);
                            }
                            widget.loadAllData();
                            Navigator.pop(c);
                          },
                          child: const Text("Save"))
                    ])));
  }

  Future<void> _manageVaultPin() async {
    final currentPin = await VaultPinPrefs.getPin(widget.activeProfileId) ?? '';
    TextEditingController pinC = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(
                    currentPin.isEmpty ? "Set Vault PIN" : "Change Vault PIN"),
                content: TextField(
                    controller: pinC,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                        hintText: "Enter Secret PIN for Vault",
                        prefixIcon: Icon(Icons.password))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      onPressed: () async {
                        if (pinC.text.isNotEmpty) {
                          await VaultPinPrefs.setPin(
                              pinC.text, widget.activeProfileId);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text("Vault PIN Saved securely!")));
                          }
                          Navigator.pop(c);
                        }
                      },
                      child: const Text("Save"))
                ]));
  }

  Future<void> _deleteVaultPin() async {
    await VaultPinPrefs.clear(widget.activeProfileId);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Vault PIN Removed!")));
    }
  }

  Future<void> _addNotebookCategoryDialog() async {
    TextEditingController catC = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("Add Notebook Category"),
                content: TextField(
                    controller: catC,
                    decoration:
                        const InputDecoration(hintText: "Category Name")),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      onPressed: () async {
                        if (catC.text.isNotEmpty) {
                          final prefs = await SharedPreferences.getInstance();
                          final key =
                              '${widget.activeProfileId}_notebook_categories';
                          _notebookCategories.add({
                            'id': DateTime.now().millisecondsSinceEpoch,
                            'name': catC.text
                          });
                          _notebookCategories.sort(compareNameMaps);
                          await prefs.setString(
                              key, jsonEncode(_notebookCategories));
                          setState(() {});
                          Navigator.pop(c);
                        }
                      },
                      child: const Text("Save"))
                ]));
  }

  Future<void> _deleteNotebookCategory(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.activeProfileId}_notebook_categories';
    _notebookCategories.removeWhere((cat) => cat['id'] == id);
    await prefs.setString(key, jsonEncode(_notebookCategories));
    setState(() {});
  }

  Future<void> _shareBackup(BuildContext context) async {
    try {
      final fullBackup = await BackupService.buildAllProfilesBackupJson();
      final fileName = BackupService.timestampedBackupFileName();

      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: fullBackup));
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Backup copied to clipboard!")));
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        String? outputFile = await FilePicker.platform.saveFile(
            dialogTitle: 'Save Budget Pro Backup',
            fileName: fileName);
        if (outputFile != null) {
          await File(outputFile).writeAsString(fullBackup);
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("✅ Backup Saved: $outputFile")));
        }
      } else {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsString(fullBackup);
        await ShareFileHelper.share(
          path: file.path,
          fileName: fileName,
          mimeType: 'application/octet-stream',
          text: 'Budget Pro Backup (all profiles) — open in Budget Pro to restore',
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("❌ Backup Failed: $e"), backgroundColor: Colors.red));
    }
  }

  /// Restore into the active profile only (never wipes other profiles).
  Future<void> _restoreBackup(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
      if (result == null) return;

      Uint8List? bytes = result.files.first.bytes;
      if (bytes == null && result.files.first.path != null) {
        bytes = await File(result.files.first.path!).readAsBytes();
      }
      if (bytes == null) throw 'Could not read file data';

      String content = utf8.decode(bytes, allowMalformed: true);
      if (content.trim().startsWith('{')) {
        final map = Map<String, dynamic>.from(jsonDecode(content));
        if (map['backup_scope']?.toString() == 'all_profiles') {
          throw 'This is a full (all profiles) backup. Use "Restore all profiles" instead.';
        }
        await BackupService.restoreFromBytesForProfile(
          bytes,
          profileId: widget.activeProfileId,
        );
      } else {
        if (kIsWeb) throw 'SQLite restore not supported on Web';
        final db = await DatabaseHelper.instance.database;
        final directDbPath = db.path;
        await DatabaseHelper.instance.closeDb();
        await File(directDbPath).writeAsBytes(bytes, flush: true);
        await DatabaseHelper.instance.database;
      }

      await widget.onBackupRestored();
      await _loadNotebookCategories();
      if (mounted) setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "✅ Restored into profile: ${widget.activeProfileName}"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("❌ Restore Error: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restoreAsNewProfile(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
      if (result == null) return;

      Uint8List? bytes = result.files.first.bytes;
      if (bytes == null && result.files.first.path != null) {
        bytes = await File(result.files.first.path!).readAsBytes();
      }
      if (bytes == null) throw 'Could not read file data';

      final content = utf8.decode(bytes, allowMalformed: true);
      if (!content.trim().startsWith('{')) {
        throw 'Use a .budgetpro JSON backup for "Restore as new profile"';
      }

      final map = Map<String, dynamic>.from(jsonDecode(content));
      if (map['backup_scope']?.toString() == 'all_profiles') {
        throw 'This is a full backup. Use "Restore all profiles" instead.';
      }

      await BackupService.restoreFromBytesAsNewProfile(bytes);
      await widget.onBackupRestored();
      await _loadNotebookCategories();
      if (mounted) setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("✅ New profile created from backup"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("❌ Restore Error: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Restore every profile from a full shared/Drive-style backup file.
  Future<void> _restoreAllProfilesShare(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
      if (result == null) return;

      Uint8List? bytes = result.files.first.bytes;
      if (bytes == null && result.files.first.path != null) {
        bytes = await File(result.files.first.path!).readAsBytes();
      }
      if (bytes == null) throw 'Could not read file data';

      final content = utf8.decode(bytes, allowMalformed: true);
      if (!content.trim().startsWith('{')) {
        throw 'Use a full Budget Pro backup (.budgetpro)';
      }

      final map = Map<String, dynamic>.from(jsonDecode(content));
      if (map['backup_scope']?.toString() != 'all_profiles') {
        throw 'This is a single-profile backup. Use "Import into this profile" or "Restore as new profile".';
      }

      await BackupService.restoreFromBytes(bytes);
      await widget.onBackupRestored();
      await _loadNotebookCategories();
      if (mounted) setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("✅ All profiles restored"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("❌ Restore Error: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showCurrencyPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final current = CurrencyService.instance.code;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.currency_exchange, color: Colors.indigo),
                    SizedBox(width: 10),
                    Text('Select currency',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Default / home currency for this profile. Wallet totals use this currency. In New Transaction you can enter a foreign amount and convert at today’s rate.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: CurrencyService.currencies.length,
                  itemBuilder: (_, i) {
                    final c = CurrencyService.currencies[i];
                    final isSel = c.code == current;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSel
                            ? Colors.indigo.shade50
                            : Colors.grey.shade100,
                        child: Text(c.symbol,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSel
                                    ? Colors.indigo
                                    : Colors.grey.shade700)),
                      ),
                      title: Text(c.name),
                      subtitle: Text(
                          '${c.code} • ${CurrencyService.instance.formatFor(c, 12345)}'),
                      trailing: isSel
                          ? const Icon(Icons.check_circle, color: Colors.indigo)
                          : null,
                      onTap: () => Navigator.pop(ctx, c.code),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await CurrencyService.instance.setCurrency(
      selected,
      profileId: widget.activeProfileId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Currency set to ${CurrencyService.instance.current.label}'),
        backgroundColor: Colors.green,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currency = CurrencyService.instance.current;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Preferences",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Card(
          child: Column(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.currency_exchange, color: Colors.teal),
                title: const Text('Default currency'),
                subtitle: Text(
                  '${currency.label} • home currency for wallet & FX convert',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showCurrencyPicker,
              ),
              const Divider(height: 1),
              ListenableBuilder(
                listenable: ThemeController.instance,
                builder: (context, _) {
                  final mode = ThemeController.instance.themeMode;
                  String label;
                  switch (mode) {
                    case ThemeMode.dark:
                      label = 'Dark';
                      break;
                    case ThemeMode.light:
                      label = 'Light';
                      break;
                    case ThemeMode.system:
                      label = 'Follow system';
                  }
                  return Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          mode == ThemeMode.dark
                              ? Icons.dark_mode_rounded
                              : (mode == ThemeMode.light
                                  ? Icons.light_mode_rounded
                                  : Icons.brightness_auto_rounded),
                          color: Colors.indigo,
                        ),
                        title: const Text('Appearance'),
                        subtitle: Text(label),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('Auto'),
                              icon: Icon(Icons.brightness_auto, size: 18),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode, size: 18),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode, size: 18),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: (s) =>
                              ThemeController.instance.setMode(s.first),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined,
                    color: Colors.orange),
                title: const Text('Phone reminders'),
                subtitle: const Text(
                  'Recurring, CNIC expiry, birthdays, budget',
                ),
                value: _notificationsEnabled,
                onChanged: (v) async {
                  if (v) {
                    final ok = await NotificationService.instance
                        .requestPermission(forceAsk: true);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Allow notifications in system settings',
                          ),
                        ),
                      );
                    }
                  }
                  await NotificationService.instance.setEnabled(v);
                  if (mounted) setState(() => _notificationsEnabled = v);
                },
              ),
              if (_notificationsEnabled)
                ListTile(
                  leading: const Icon(Icons.schedule, color: Colors.blueGrey),
                  title: const Text('Reminder time'),
                  subtitle: Text(
                    '${_notifyHour.toString().padLeft(2, '0')}:00',
                  ),
                  trailing: DropdownButton<int>(
                    value: _notifyHour,
                    underline: const SizedBox.shrink(),
                    items: [for (var h = 7; h <= 21; h++) h]
                        .map((h) => DropdownMenuItem(
                              value: h,
                              child: Text('${h.toString().padLeft(2, '0')}:00'),
                            ))
                        .toList(),
                    onChanged: (h) async {
                      if (h == null) return;
                      await NotificationService.instance.setNotifyHour(h);
                      if (mounted) setState(() => _notifyHour = h);
                    },
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        const Text("Security",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.lock, color: Colors.indigo),
              title: const Text("Manage App Password"),
              trailing: Wrap(children: [
                IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => widget.managePin()),
                IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => widget.deletePin())
              ])),
          const Divider(height: 1),
          ListTile(
              leading: const Icon(Icons.security, color: Colors.deepPurple),
              title: const Text("Manage Vault Password"),
              subtitle: const Text("Double security for Vault"),
              trailing: Wrap(children: [
                IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _manageVaultPin()),
                IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteVaultPin())
              ]))
        ])),
        const Divider(),
        const Text("Backup & Restore",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Active: ${widget.activeProfileName}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
        AutoBackupSettingsCard(onRestored: widget.onBackupRestored),
        _buildGoogleDriveCard(),
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text('All profiles',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        ListTile(
            leading: const Icon(Icons.share, color: Colors.green),
            title: const Text("Backup all profiles"),
            subtitle: const Text(
                "Full backup + pictures — WhatsApp / Files / Drive share"),
            onTap: () => _shareBackup(context)),
        ListTile(
            leading: const Icon(Icons.unarchive_rounded, color: Colors.blue),
            title: const Text("Restore all profiles"),
            subtitle: const Text(
                "Open a full backup — replaces every profile on this device"),
            onTap: () => _restoreAllProfilesShare(context)),
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text('This profile only',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        ListTile(
          leading: const Icon(Icons.download_rounded, color: Colors.teal),
          title: const Text("Export this profile"),
          subtitle: const Text("Share or save only the current profile"),
          onTap: () async => await widget.exportActiveProfileBackup(),
        ),
        ListTile(
          leading:
              const Icon(Icons.upload_file_rounded, color: Colors.deepOrange),
          title: const Text("Import into this profile"),
          subtitle: Text(
              "Replace data in ${widget.activeProfileName} (other profiles stay)"),
          onTap: () async => await widget.importToActiveProfile(),
        ),
        ListTile(
            leading: const Icon(Icons.upload, color: Colors.orange),
            title: const Text("Restore file into this profile"),
            subtitle: const Text(
                "Pick a single-profile .budgetpro (or old SQLite file)"),
            onTap: () => _restoreBackup(context)),
        ListTile(
            leading: const Icon(Icons.person_add_alt_1, color: Colors.purple),
            title: const Text("Restore as new profile"),
            subtitle: const Text(
                "Creates a new profile from a single-profile backup"),
            onTap: () => _restoreAsNewProfile(context)),
        const Divider(),
        const Text("Accounts & Categories",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...widget.accounts.map((acc) => ListTile(
            title: Text(acc['name']),
            subtitle: Text(
                "Opening: ${CurrencyService.fmt((acc['initial_balance'] as num?)?.toDouble() ?? 0)}"),
            trailing: Wrap(children: [
              IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => widget.editAccount(acc)),
              IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => widget.confirmDelete(
                      () => DatabaseHelper.instance.deleteAccount(acc['id'])))
            ]))),
        ElevatedButton(
            onPressed: () => widget.editAccount(null),
            child: const Text("Add New Account")),
        ...widget.categories.map((cat) => ListTile(
            title: Text(cat['name']),
            subtitle: cat['sub_categories'] != null &&
                    cat['sub_categories'] != '[]'
                ? Text(
                    "Sub: ${List<String>.from(jsonDecode(cat['sub_categories'])).join(', ')}")
                : null,
            trailing: Wrap(children: [
              IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showCategoryDialog(editCat: cat)),
              IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => widget.confirmDelete(
                      () => DatabaseHelper.instance.deleteCategory(cat['id'])))
            ]))),
        ElevatedButton(
            onPressed: () => _showCategoryDialog(),
            child: const Text("Add Transaction Category")),
        const Divider(),
        const Text("Diary Categories",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (widget.diaryCategories.isEmpty)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text("No custom diary categories.",
                  style: TextStyle(color: Colors.grey))),
        ...widget.diaryCategories.map((cat) => ListTile(
            title: Text(cat['name']),
            leading: const Icon(Icons.menu_book, color: Colors.purple),
            trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => widget.deleteDiaryCategory(cat)))),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade50),
            onPressed: () => widget.addDiaryCategory(),
            child: const Text("Add Diary Category",
                style: TextStyle(color: Colors.purple))),
        const Divider(),
        const Text("Notebook Categories",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (_notebookCategories.isEmpty)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text("No custom notebook categories.",
                  style: TextStyle(color: Colors.grey))),
        ..._notebookCategories.map((cat) => ListTile(
            title: Text(cat['name']),
            leading: const Icon(Icons.note_alt, color: Colors.teal),
            trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteNotebookCategory(cat['id'])))),
        ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade50),
            onPressed: () => _addNotebookCategoryDialog(),
            child: const Text("Add Notebook Category",
                style: TextStyle(color: Colors.teal))),
        const Divider(),
        const Text("About App",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const AboutAppCard(),
        const Divider(),
        const Text("App Data Reset",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
        Card(
            color: Colors.red.shade50,
            child: Column(children: [
              ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text("Reset All Data",
                      style: TextStyle(color: Colors.red)),
                  onTap: () => widget.confirmReset(true)),
              ListTile(
                  leading:
                      const Icon(Icons.cleaning_services, color: Colors.orange),
                  title: const Text("Clear All Transactions",
                      style: TextStyle(color: Colors.orange)),
                  onTap: () => widget.confirmReset(false))
            ])),
      ],
    );
  }
}
