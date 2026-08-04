import 'dart:convert';

List<String> parseSubCategories(dynamic raw) {
  if (raw == null) return [];
  final text = raw.toString().trim();
  if (text.isEmpty || text == '[]' || text == 'null') return [];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
  } catch (_) {}
  return [];
}
