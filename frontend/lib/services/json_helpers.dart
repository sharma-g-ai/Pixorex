import 'dart:convert';

Map<String, dynamic> normalizeDynamicMap(dynamic value) {
  if (value == null) return <String, dynamic>{};
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

Map<String, dynamic> normalizeExtraFields(dynamic value) {
  if (value == null) return <String, dynamic>{};
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = json.decode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Keep manually-entered text instead of silently dropping it.
    }
    return <String, dynamic>{'value': text};
  }
  return <String, dynamic>{'value': value};
}
