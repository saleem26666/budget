import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../config/google_oauth_config.dart';

/// Optional cloud sync — only files created by this app (drive.file scope).
class GoogleDriveBackupService {
  static const backupFileName = 'BudgetPro_FullBackup.budgetpro';

  static final GoogleSignIn _signIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
    serverClientId: GoogleOAuthConfig.webClientId,
  );

  static Future<GoogleSignInAccount?> currentUser() =>
      _signIn.signInSilently();

  /// User-facing message when OAuth is misconfigured (error 10).
  static String get setupHelpMessage =>
      'Google Drive setup required (error 10):\n\n'
      '1. Google Cloud Console → enable Google Drive API\n'
      '2. Create Android OAuth client:\n'
      '   Package: ${GoogleOAuthConfig.androidPackage}\n'
      '   SHA-1: ${GoogleOAuthConfig.debugSha1}\n'
      '3. Create Web OAuth client (same project)\n'
      '4. Wait 10 min, clear app data, try again.\n\n'
      'Full guide: docs/GOOGLE_DRIVE_SETUP.md in project folder.';

  static bool _isDeveloperError(Object e) {
    final s = e.toString();
    return s.contains('10') ||
        s.contains('sign_in_failed') ||
        s.contains('DEVELOPER_ERROR');
  }

  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _signIn.signInSilently() ?? await _signIn.signIn();
    } on PlatformException catch (e) {
      if (_isDeveloperError(e)) throw setupHelpMessage;
      throw 'Google sign-in failed: ${e.message ?? e.code}';
    } catch (e) {
      if (_isDeveloperError(e)) throw setupHelpMessage;
      throw 'Google sign-in failed: $e';
    }
  }

  static Future<void> signOut() => _signIn.disconnect();

  static Future<drive.DriveApi> _api() async {
    final account = await signIn();
    if (account == null) {
      throw 'Sign-in cancelled';
    }
    final client = await _signIn.authenticatedClient();
    if (client == null) {
      throw 'Could not authorize Google Drive';
    }
    return drive.DriveApi(client);
  }

  static Future<drive.File?> _findBackup(drive.DriveApi api) async {
    final list = await api.files.list(
      q: "name = '$backupFileName' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime)',
      pageSize: 1,
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }

  /// Upload or overwrite backup on Google Drive.
  static Future<DateTime?> uploadBackup(String jsonContent) async {
    final api = await _api();
    final bytes = utf8.encode(jsonContent);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/octet-stream',
    );

    final existing = await _findBackup(api);
    drive.File result;
    if (existing?.id != null) {
      result = await api.files.update(
        drive.File()..name = backupFileName,
        existing!.id!,
        uploadMedia: media,
      );
    } else {
      result = await api.files.create(
        drive.File()
          ..name = backupFileName
          ..mimeType = 'application/octet-stream',
        uploadMedia: media,
      );
    }
    return result.modifiedTime;
  }

  /// Download backup JSON from Google Drive.
  static Future<String> downloadBackup() async {
    final api = await _api();
    final file = await _findBackup(api);
    if (file?.id == null) {
      throw 'No backup found on Google Drive. Sync a backup first.';
    }

    final media = await api.files.get(
      file!.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks);
  }
}
