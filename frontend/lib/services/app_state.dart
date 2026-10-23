import 'dart:io';
import 'package:flutter/material.dart';
import 'config.dart';
import 'json_helpers.dart';
import 'openai_service.dart';
import 'local_store.dart';
import 'review_provenance_helpers.dart';
import 'supabase_service.dart';

class AppState extends ChangeNotifier {
  final OpenAiService _openAi = OpenAiService();
  final LocalStore _store = LocalStore();
  final SupabaseService _supabase = SupabaseService();

  // User email
  String _userEmail = '';
  String get userEmail => _userEmail;

  void setUserEmail(String email) {
    _userEmail = email;
    notifyListeners();
    // Load extractions now that we have the email for Supabase queries
    loadExtractions();
  }

  // Schemas
  List<Map<String, dynamic>> _schemas = [];
  List<Map<String, dynamic>> get schemas => _schemas;

  // Extractions history
  List<Map<String, dynamic>> _extractions = [];
  List<Map<String, dynamic>> get extractions => _extractions;

  // Current extraction result
  Map<String, dynamic>? _currentResult;
  Map<String, dynamic>? get currentResult => _currentResult;

  // Track the latest extraction ID for highlight
  String? _lastExtractionId;
  String? get lastExtractionId => _lastExtractionId;

  void clearLastExtractionId() {
    _lastExtractionId = null;
  }

  // Loading states
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isExtracting = false;
  bool get isExtracting => _isExtracting;

  String? _error;
  String? get error => _error;

  /// Load schemas and prompts from Supabase source-of-truth tables.
  Future<void> loadSchemas() async {
    try {
      if (!hasSupabaseConfig) {
        throw Exception('Supabase config is required for schema templates.');
      }
      _schemas = await _supabase.getSchemaTemplates(userEmail: _userEmail);
      if (_schemas.isEmpty) {
        throw Exception(
          'No active schema templates are available. Please contact your administrator.',
        );
      }
      final missingPrompt = _schemas
          .where(
            (s) =>
                s['prompt_template'] == null ||
                s['prompt_template'].toString().trim().isEmpty,
          )
          .map((s) => s['equipment_type'])
          .join(', ');
      if (missingPrompt.isNotEmpty) {
        throw Exception(
          'Schema setup is incomplete. Please contact your administrator.',
        );
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      _schemas = [];
      _error = e.toString();
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _schemaCatalogForPrompt() {
    return _schemas.map((schema) {
      return {
        'schema_name': schema['schema_name'] ?? schema['equipment_type'],
        'display_name': schema['display_name'],
        'description': schema['description'],
        'fields': schema['fields'],
        'mandatory_fields': schema['mandatory_fields'],
        'is_system': schema['is_system'] == true,
      };
    }).toList();
  }

  /// Load extraction history — merges Supabase + local so nothing is lost.
  Future<void> loadExtractions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      List<Map<String, dynamic>> supabaseExtractions = [];
      List<Map<String, dynamic>> localExtractions = [];

      // Always load local records
      try {
        localExtractions = await _store.getAllExtractions();
      } catch (_) {}

      // Load Supabase records if configured
      if (_userEmail.isNotEmpty && hasSupabaseConfig) {
        try {
          supabaseExtractions = await _supabase.getExtractions(_userEmail);
        } catch (e) {
          debugPrint('Supabase load failed, using local only: $e');
        }
      }

      if (supabaseExtractions.isNotEmpty) {
        // Build a set of Supabase record IDs for fast lookup
        final supabaseIds = <String>{};
        for (final e in supabaseExtractions) {
          final id = e['extraction_id']?.toString() ?? '';
          if (id.isNotEmpty) supabaseIds.add(id);
        }

        // Add local-only records (not yet synced to Supabase)
        for (final local in localExtractions) {
          final localId = local['extraction_id']?.toString() ?? '';
          final supabaseRecordId =
              local['supabase_record_id']?.toString() ?? '';
          // Include if neither local ID nor its supabase_record_id is in Supabase
          if (localId.isNotEmpty &&
              !supabaseIds.contains(localId) &&
              !supabaseIds.contains(supabaseRecordId)) {
            supabaseExtractions.add(local);
          }
        }
        _extractions = supabaseExtractions;
      } else {
        _extractions = localExtractions;
      }

      _extractions.sort(
        (a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''),
      );
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Extract fields from image(s) — calls OpenAI only.
  ///
  /// Does NOT persist anywhere. Data is saved only on submit.
  Future<bool> extractFields({
    required List<File> imageFiles,
    required String equipmentType,
  }) async {
    _isExtracting = true;
    _error = null;
    _currentResult = null;
    notifyListeners();

    try {
      final schema = _schemaFor(equipmentType);
      if (schema == null) {
        throw Exception('Schema "$equipmentType" is not loaded from Supabase.');
      }
      final schemaForExtraction = Map<String, dynamic>.from(schema);
      schemaForExtraction['known_schema_names'] = _schemas
          .map((s) => s['equipment_type']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      schemaForExtraction['schema_catalog'] = _schemaCatalogForPrompt();

      // Call OpenAI directly using the DB-loaded schema and prompt template.
      final result = await _openAi.extractFields(
        imageFiles,
        equipmentType,
        schemaOverride: schemaForExtraction,
      );

      // Save primary image locally (for display in results screen)
      final imagePath = await _store.saveImage(imageFiles.first);
      result['image_path'] = imagePath;
      result['equipment_type'] = equipmentType;
      result['schema_version'] = schemaForExtraction['schema_version'] ?? '1.0';
      result['prompt_key'] = schemaForExtraction['prompt_key'];
      result['prompt_version'] = schemaForExtraction['prompt_version'] ?? '1.0';

      _currentResult = result;
      _isExtracting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isExtracting = false;
      notifyListeners();
      return false;
    }
  }

  /// Sync extraction to Supabase. Returns record_id on success, null on failure.
  Future<String?> _syncToSupabase({
    required String extractionId,
    required String equipmentType,
    required List<File> imageFiles,
    required Map<String, dynamic> result,
  }) async {
    if (!hasSupabaseConfig) return null;

    final fields = Map<String, dynamic>.from(
      result['fields'] as Map<String, dynamic>,
    );
    final reviewFlags = result['review_flags'] as Map<String, dynamic>;

    // Separate extra_fields if present
    final extraFields = <String, dynamic>{};
    if (fields.containsKey('extra_fields') && fields['extra_fields'] != null) {
      extraFields.addAll(normalizeExtraFields(fields['extra_fields']));
      fields.remove('extra_fields');
    }

    try {
      final supabaseRecordId = await _supabase.saveExtraction(
        userEmail: _userEmail,
        equipmentType: equipmentType,
        schemaName: equipmentType,
        imageFiles: imageFiles,
        fields: fields,
        extraFields: extraFields,
        reviewFlags: reviewFlags,
        imageMatch: result['mismatch_warning'] == null,
        detectedType: result['detected_type'] as String?,
        schemaVersion: result['schema_version']?.toString() ?? '1.0',
        suggestedSchema: result['suggested_schema'] as String?,
        schemaConfidence: result['schema_confidence'] as String?,
        promptKey: result['prompt_key'] as String?,
        promptVersion: result['prompt_version']?.toString() ?? '1.0',
        fieldConfidence: result['field_confidence'] is Map
            ? Map<String, dynamic>.from(result['field_confidence'] as Map)
            : null,
        fieldReviewNotes: result['field_review_notes'] is Map
            ? Map<String, dynamic>.from(result['field_review_notes'] as Map)
            : null,
        rawResponse: null,
        latencyMs: null,
        model: openAiModel,
      );

      await _store.setSupabaseRecordId(extractionId, supabaseRecordId);
      debugPrint('Supabase sync OK: $supabaseRecordId');
      return supabaseRecordId;
    } catch (e) {
      debugPrint('Supabase sync failed: $e');
      return null;
    }
  }

  /// Submit extraction — saves locally and syncs to Supabase.
  ///
  /// Called from results screen after user reviews/edits and clicks submit.
  Future<bool> submitExtraction({
    required Map<String, dynamic> result,
    required List<File> imageFiles,
    required Map<String, dynamic> finalFields,
    Set<String> modifiedFields = const <String>{},
  }) async {
    try {
      final equipmentType = result['equipment_type'] as String;
      final imagePath = result['image_path'] as String? ?? '';
      final reviewFlags = normalizeDynamicMap(result['review_flags']);
      final fieldConfidence = normalizeDynamicMap(result['field_confidence']);
      final fieldReviewNotes = normalizeDynamicMap(
        result['field_review_notes'],
      );

      // Merge finalFields into the original extracted fields
      final fields = Map<String, dynamic>.from(
        result['fields'] as Map<String, dynamic>? ?? {},
      );
      final originalFields = Map<String, dynamic>.from(fields);
      fields.addAll(finalFields);
      if (fields.containsKey('extra_fields')) {
        final extraFields = normalizeExtraFields(fields['extra_fields']);
        if (extraFields.isEmpty) {
          fields.remove('extra_fields');
        } else {
          fields['extra_fields'] = extraFields;
        }
      }
      final actualEditedFields = actualModifiedFields(
        modifiedFields: modifiedFields,
        originalFields: originalFields,
        finalFields: fields,
      );
      final adjustedReviewFlags = removeEditedReviewFlags(
        originalFlags: reviewFlags,
        actualModifiedFields: actualEditedFields,
      );
      final adjustedFieldConfidence = fieldConfidenceWithOperatorEdits(
        originalConfidence: fieldConfidence,
        actualModifiedFields: actualEditedFields,
      );
      final adjustedFieldReviewNotes = removeEditedReviewNotes(
        originalNotes: fieldReviewNotes,
        actualModifiedFields: actualEditedFields,
      );

      // 1. Save to local store
      final extractionId = await _store.saveExtraction(
        equipmentType: equipmentType,
        imagePath: imagePath,
        fields: fields,
        reviewFlags: adjustedReviewFlags,
        userEmail: _userEmail,
      );

      // 2. Sync to Supabase (primary remote)
      final supabaseResult = Map<String, dynamic>.from(result);
      supabaseResult['fields'] = fields;
      supabaseResult['review_flags'] = adjustedReviewFlags;
      supabaseResult['field_confidence'] = adjustedFieldConfidence;
      supabaseResult['field_review_notes'] = adjustedFieldReviewNotes;
      final syncRecordId = await _syncToSupabase(
        extractionId: extractionId,
        equipmentType: equipmentType,
        imageFiles: imageFiles,
        result: supabaseResult,
      );
      if (hasSupabaseConfig && syncRecordId == null) {
        throw Exception(
          'Supabase sync failed. The record was saved locally but was not uploaded for the client portal.',
        );
      }

      // Mark as approved in Supabase
      if (syncRecordId != null) {
        final supaFields = Map<String, dynamic>.from(fields);
        final approvedExtraFields = <String, dynamic>{};
        if (supaFields.containsKey('extra_fields')) {
          approvedExtraFields.addAll(
            normalizeExtraFields(supaFields['extra_fields']),
          );
        }
        supaFields.remove('extra_fields');

        try {
          await _supabase.submitCorrections(
            recordId: syncRecordId,
            approvedFields: supaFields,
            approvedExtraFields: approvedExtraFields,
            userEmail: _userEmail,
            fieldConfidence: adjustedFieldConfidence,
            fieldReviewNotes: adjustedFieldReviewNotes,
          );
        } catch (e) {
          debugPrint('Supabase approval failed: $e');
          if (hasSupabaseConfig) {
            throw Exception(
              'Supabase approval failed. The record was uploaded but was not approved for the client portal: $e',
            );
          }
        }
      }
      await _store.setStatus(extractionId, 'approved');

      _lastExtractionId = syncRecordId ?? extractionId;
      await loadExtractions();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  Map<String, dynamic>? _schemaFor(String equipmentType) {
    for (final schema in _schemas) {
      if (schema['equipment_type'] == equipmentType ||
          schema['schema_name'] == equipmentType) {
        return schema;
      }
    }
    return null;
  }
}
