import 'dart:convert';

/// Case-insensitive alphabetical compare for account/category names.
int compareNames(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

int compareNameMaps(Map<String, dynamic> a, Map<String, dynamic> b) =>
    compareNames(a['name']?.toString() ?? '', b['name']?.toString() ?? '');

List<String> parseSubCategories(dynamic raw) {
  if (raw == null) return [];
  final text = raw.toString().trim();
  if (text.isEmpty || text == '[]' || text == 'null') return [];
  List<String> result = [];
  if (raw is List) {
    result = raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  } else {
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        result =
            decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
  }
  result.sort(compareNames);
  return result;
}
