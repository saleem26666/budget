import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../database_helper.dart';
import '../services/local_auto_backup_service.dart';

class AutoBackupSetupDialog extends StatefulWidget {
  const AutoBackupSetupDialog({
    super.key,
    this.allowSkip = true,
    this.title = 'Auto backup location',
  });

  final bool allowSkip;
  final String title;

  static Future<BackupLocation?> show(
    BuildContext context, {
    bool allowSkip = true,
    String title = 'Auto backup location',
  }) {
    return showDialog<BackupLocation>(
      context: context,
      barrierDismissible: allowSkip,
      builder: (_) => AutoBackupSetupDialog(
        allowSkip: allowSkip,
        title: title,
      ),
    );
  }

  @override
  State<AutoBackupSetupDialog> createState() => _AutoBackupSetupDialogState();
}

class _AutoBackupSetupDialogState extends State<AutoBackupSetupDialog> {
  List<BackupLocation> _locations = const [];
  String? _selectedId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LocalAutoBackupService.instance.ensurePermission();
    final locations =
        await LocalAutoBackupService.instance.availableLocations();
    final status = await LocalAutoBackupService.instance.status();
    if (!mounted) return;

    final merged = List<BackupLocation>.from(locations);
    if (status.locationId == 'custom' &&
        status.folderPath != null &&
        status.folderPath!.trim().isNotEmpty) {
      merged.removeWhere((e) => e.id == 'custom');
      merged.add(
        LocalAutoBackupService.instance.customLocation(status.folderPath!),
      );
    }

    setState(() {
      _locations = merged;
      _selectedId = merged.any((e) => e.id == status.locationId)
          ? status.locationId
          : (merged.isNotEmpty ? merged.first.id : null);
      _loading = false;
    });
  }

  Future<void> _pickCustomFolder() async {
    setState(() => _error = null);
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose backup folder',
    );
    if (path == null || path.trim().isEmpty) return;
    if (!mounted) return;

    final custom = LocalAutoBackupService.instance.customLocation(path);
    setState(() {
      _locations = [
        ..._locations.where((e) => e.id != 'custom'),
        custom,
      ];
      _selectedId = 'custom';
    });
  }

  Future<void> _confirm() async {
    final chosen = _locations.where((e) => e.id == _selectedId);
    if (chosen.isEmpty) {
      setState(() => _error = 'Choose a backup location');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await LocalAutoBackupService.instance.ensurePermission();
    await LocalAutoBackupService.instance.setLocation(chosen.first);
    if (await DatabaseHelper.instance.isUserDataEmpty()) {
      await LocalAutoBackupService.instance.restoreFromDiskIfPresent();
    }
    final ok =
        await LocalAutoBackupService.instance.saveNow(ignoreEnabled: true);
    if (!mounted) return;
    if (!ok) {
      final status = await LocalAutoBackupService.instance.status();
      setState(() {
        _saving = false;
        _error = status.lastError ??
            'Could not write backup. Allow “All files access” for Budget Pro.';
      });
      return;
    }
    Navigator.pop(context, chosen.first);
  }

  IconData _iconFor(BackupLocation location) {
    if (location.isSdCard) return Icons.sd_card;
    if (location.isCustom) return Icons.folder_special;
    return Icons.phone_android;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Uninstall deletes app data. Choose phone storage, SD card, '
                      'or any folder you pick. Every time you open the app, backup '
                      'is updated there.\n\n'
                      'Android may ask for “All files access” — turn it on for Budget Pro '
                      'so the backup still works after reinstall.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    if (_locations.isEmpty)
                      const Text(
                        'No storage folder found. Grant file permission and try again.',
                      )
                    else
                      ..._locations.map(_locationTile),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickCustomFolder,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Choose my own folder'),
                    ),
                    if (!_locations.any((e) => e.isSdCard))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No SD card detected. You can still use phone storage or pick a folder.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        if (widget.allowSkip)
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    await LocalAutoBackupService.instance.markSetupDone();
                    await LocalAutoBackupService.instance.saveNow();
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Later'),
          ),
        FilledButton(
          onPressed: _saving || _loading ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save here'),
        ),
      ],
    );
  }

  Widget _locationTile(BackupLocation location) {
    final selected = location.id == _selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.08)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          selected: selected,
          enabled: !_saving,
          leading: Icon(
            _iconFor(location),
            color: selected ? AppTheme.primary : Colors.grey.shade700,
          ),
          title: Text(
            location.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            location.path,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? AppTheme.primary : Colors.grey,
          ),
          onTap: _saving
              ? null
              : () => setState(() => _selectedId = location.id),
        ),
      ),
    );
  }
}

class AutoBackupSettingsCard extends StatefulWidget {
  const AutoBackupSettingsCard({super.key, this.onRestored});

  final Future<void> Function()? onRestored;

  @override
  State<AutoBackupSettingsCard> createState() => _AutoBackupSettingsCardState();
}

class _AutoBackupSettingsCardState extends State<AutoBackupSettingsCard> {
  AutoBackupStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await LocalAutoBackupService.instance.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _subtitle(AutoBackupStatus status) {
    final when = status.lastSavedAt == null
        ? 'not saved yet'
        : DateFormat('dd MMM yyyy, hh:mm a').format(status.lastSavedAt!);
    final folder = status.folderPath ?? status.locationLabel;
    return '${status.locationLabel} · $when\n$folder';
  }

  @override
  Widget build(BuildContext context) {
    if (!LocalAutoBackupService.instance.isSupported) {
      return const SizedBox.shrink();
    }
    final status = _status;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.phonelink_setup, color: Colors.teal),
            title: const Text('Auto backup on this device'),
            subtitle: Text(
              status == null
                  ? 'Saves a copy when you open the app'
                  : _subtitle(status),
              style: const TextStyle(fontSize: 12),
            ),
            value: status?.enabled ?? true,
            onChanged: status == null
                ? null
                : (v) => _run(() async {
                      await LocalAutoBackupService.instance.setEnabled(v);
                      if (v) {
                        await LocalAutoBackupService.instance.saveNow(
                          ignoreEnabled: true,
                        );
                      }
                    }),
          ),
          if (status?.lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                status!.lastError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.indigo),
              title: const Text('Change backup location'),
              subtitle: const Text('Phone, SD card, or any folder you choose'),
              onTap: () => _run(() async {
                await AutoBackupSetupDialog.show(
                  context,
                  title: 'Where should auto backup be saved?',
                );
              }),
            ),
            ListTile(
              leading: const Icon(Icons.save, color: Colors.green),
              title: const Text('Update backup now'),
              onTap: () => _run(() async {
                final ok = await LocalAutoBackupService.instance.saveNow(
                  ignoreEnabled: true,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Auto backup updated'
                          : 'Backup failed — check file permission',
                    ),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              }),
            ),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.deepOrange),
              title: const Text('Restore from device backup'),
              subtitle: const Text(
                'Loads BudgetPro_AutoBackup.budgetpro from your chosen folder',
              ),
              onTap: () => _run(() async {
                final ok = await LocalAutoBackupService.instance
                    .restoreFromDiskIfPresent();
                if (ok) await widget.onRestored?.call();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Data restored from device backup'
                          : 'No auto backup file found',
                    ),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
