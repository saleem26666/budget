import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Detects and opens http(s), www, YouTube, and youtu.be links in notes.
class LinkHelper {
  static final RegExp urlPattern = RegExp(
    r'(https?:\/\/[^\s<>"\]]+|www\.[^\s<>"\]]+|(?:youtube\.com|youtu\.be)\/[^\s<>"\]]+)',
    caseSensitive: false,
  );

  static List<String> extractUrls(String text) {
    if (text.trim().isEmpty) return const [];
    final found = <String>[];
    for (final match in urlPattern.allMatches(text)) {
      final url = match.group(0)?.trim();
      if (url != null && url.isNotEmpty && !found.contains(url)) {
        found.add(url);
      }
    }
    return found;
  }

  static String normalizeUrl(String raw) {
    var url = raw.trim();
    while (url.isNotEmpty && '.,);]'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    if (url.startsWith('www.')) return 'https://$url';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'https://$url';
    }
    return url;
  }

  static bool isYoutube(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  static String labelFor(String url) {
    if (isYoutube(url)) return 'YouTube';
    try {
      final host = Uri.parse(normalizeUrl(url)).host;
      if (host.startsWith('www.')) return host.substring(4);
      return host.isEmpty ? 'Website' : host;
    } catch (_) {
      return 'Website';
    }
  }

  static Future<bool> open(String raw) async {
    final uri = Uri.tryParse(normalizeUrl(raw));
    if (uri == null) return false;
    try {
      if (kIsWeb) {
        return await launchUrl(uri, webOnlyWindowName: '_blank');
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
