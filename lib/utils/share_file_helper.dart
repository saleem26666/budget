import 'package:share_plus/share_plus.dart';

/// Share export files so Android shows more apps (Drive, WPS, Chrome, Office, etc.).
class ShareFileHelper {
  ShareFileHelper._();

  static Future<void> share({
    required String path,
    required String fileName,
    String? mimeType,
    String? text,
  }) async {
    await Share.shareXFiles(
      [XFile(path, name: fileName, mimeType: mimeType)],
      text: text ?? fileName,
      subject: fileName,
    );
  }
}
