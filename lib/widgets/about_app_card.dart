import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_theme.dart';

/// Settings → About Budget Pro (developer & version).
class AboutAppCard extends StatefulWidget {
  const AboutAppCard({super.key});

  @override
  State<AboutAppCard> createState() => _AboutAppCardState();
}

class _AboutAppCardState extends State<AboutAppCard> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accent],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Budget Pro',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _aboutLine('Version', _versionLabel()),
              _aboutLine('Developer', 'Saleem Shalwani'),
              _aboutLine('Tagline', 'By Saleem Shalwani'),
              const SizedBox(height: 12),
              const Text(
                'Personal budget manager with Wallet, Reports, Investment '
                'Portfolio, Diary, Notes, secure Vault, multi-profile backup, '
                'and multi-currency support.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                '© ${DateTime.now().year} Saleem Shalwani. All rights reserved.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _versionLabel() {
    if (_version.isEmpty) return '…';
    if (_buildNumber.isEmpty) return _version;
    return '$_version (build $_buildNumber)';
  }

  Widget _aboutLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.15),
                AppTheme.accent.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.info_outline_rounded,
              color: AppTheme.primary),
        ),
        title: const Text('About Budget Pro',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          _version.isEmpty
              ? 'Developer: Saleem Shalwani'
              : 'v$_versionLabel() · By Saleem Shalwani',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _showAboutDialog,
      ),
    );
  }
}
