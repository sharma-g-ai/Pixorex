import 'json_helpers.dart';

const String extraFieldsKey = 'extra_fields';
const String extraFieldPathPrefix = '$extraFieldsKey.';

bool isExtraFieldPath(String fieldName) =>
    fieldName.startsWith(extraFieldPathPrefix) &&
    fieldName.length > extraFieldPathPrefix.length;

String extraFieldPath(String extraFieldKey) =>
    '$extraFieldPathPrefix$extraFieldKey';

String extraFieldKeyFromPath(String fieldName) =>
    fieldName.substring(extraFieldPathPrefix.length);

Map<String, String> editableFieldsFromSchemaFields(
  Map<String, dynamic> fields,
) {
  final editable = <String, String>{};
  for (final entry in fields.entries) {
    if (entry.key == extraFieldsKey) {
      final extraFields = normalizeExtraFields(entry.value);
      for (final extraEntry in extraFields.entries) {
        editable[extraFieldPath(extraEntry.key)] =
            extraEntry.value?.toString() ?? '';
      }
    } else {
      editable[entry.key] = entry.value?.toString() ?? '';
    }
  }
  return editable;
}

Map<String, dynamic> fieldsFromEditableFields(
  Map<String, String> editedFields,
) {
  final fields = <String, dynamic>{};
  final extraFields = <String, dynamic>{};

  for (final entry in editedFields.entries) {
    if (isExtraFieldPath(entry.key)) {
      extraFields[extraFieldKeyFromPath(entry.key)] = entry.value;
    } else {
      fields[entry.key] = entry.value;
    }
  }

  if (extraFields.isNotEmpty) {
    fields[extraFieldsKey] = extraFields;
  }
  return fields;
}

dynamic fieldValueForReviewPath(
  Map<String, dynamic> fields,
  String fieldName,
) {
  if (isExtraFieldPath(fieldName)) {
    return normalizeExtraFields(fields[extraFieldsKey])[
        extraFieldKeyFromPath(fieldName)];
  }
  return fields[fieldName];
}

Set<String> actualModifiedFields({
  required Set<String> modifiedFields,
  required Map<String, dynamic> originalFields,
  required Map<String, dynamic> finalFields,
}) {
  return modifiedFields.where((field) {
    final original = fieldValueForReviewPath(originalFields, field);
    final updated = fieldValueForReviewPath(finalFields, field);
    return (original?.toString() ?? '') != (updated?.toString() ?? '');
  }).toSet();
}

Map<String, dynamic> fieldConfidenceWithOperatorEdits({
  required Map<String, dynamic> originalConfidence,
  required Set<String> actualModifiedFields,
}) {
  final updated = Map<String, dynamic>.from(originalConfidence);
  for (final field in actualModifiedFields) {
    updated[field] = <String, dynamic>{
      'level': 'high',
      'score': 1.0,
      'provenance': 'operator_edit',
    };
  }
  return updated;
}

Map<String, dynamic> removeEditedReviewNotes({
  required Map<String, dynamic> originalNotes,
  required Set<String> actualModifiedFields,
}) {
  final updated = Map<String, dynamic>.from(originalNotes);
  for (final field in actualModifiedFields) {
    updated.remove(field);
  }
  return updated;
}

Map<String, dynamic> removeEditedReviewFlags({
  required Map<String, dynamic> originalFlags,
  required Set<String> actualModifiedFields,
}) {
  final updated = Map<String, dynamic>.from(originalFlags);
  for (final field in actualModifiedFields) {
    updated.remove(field);
  }
  return updated;
}

Map<String, dynamic> confidenceWithFallback({
  required dynamic currentConfidence,
  required dynamic approvedConfidence,
  required dynamic runConfidence,
}) {
  final current = normalizeDynamicMap(currentConfidence);
  if (current.isNotEmpty) return current;

  final approved = normalizeDynamicMap(approvedConfidence);
  if (approved.isNotEmpty) return approved;

  return normalizeDynamicMap(runConfidence);
}

Map<String, dynamic> reviewNotesWithFallback({
  required dynamic currentConfidence,
  required dynamic currentReviewNotes,
  required dynamic approvedConfidence,
  required dynamic approvedReviewNotes,
  required dynamic runReviewNotes,
}) {
  final currentConfidenceMap = normalizeDynamicMap(currentConfidence);
  final currentNotesMap = normalizeDynamicMap(currentReviewNotes);
  if (currentConfidenceMap.isNotEmpty || currentNotesMap.isNotEmpty) {
    return currentNotesMap;
  }

  final approvedConfidenceMap = normalizeDynamicMap(approvedConfidence);
  final approvedNotesMap = normalizeDynamicMap(approvedReviewNotes);
  if (approvedConfidenceMap.isNotEmpty || approvedNotesMap.isNotEmpty) {
    return approvedNotesMap;
  }

  return normalizeDynamicMap(runReviewNotes);
}
