import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'json_helpers.dart';
import 'review_provenance_helpers.dart';

const _uuid = Uuid();

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  List<String> _stringList(dynamic value) {
    if (value == null) return <String>[];
    if (value is List) {
      return value
          .map((v) => v?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return <String>[];
      try {
        final decoded = json.decode(trimmed);
        if (decoded is List) return _stringList(decoded);
      } catch (_) {}
      return trimmed
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  Map<String, String> _stringMap(dynamic value) {
    if (value == null) return <String, String>{};
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return <String, String>{};
      try {
        final decoded = json.decode(trimmed);
        if (decoded is Map) return _stringMap(decoded);
      } catch (_) {}
    }
    return <String, String>{};
  }

  Map<String, dynamic> _embeddedOne(dynamic value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _latestEmbeddedRun(dynamic value) {
    if (value is List && value.isNotEmpty) {
      final runs = value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort((a, b) {
          final aCreated = a['created_at']?.toString() ?? '';
          final bCreated = b['created_at']?.toString() ?? '';
          return bCreated.compareTo(aCreated);
        });
      return runs.isEmpty ? <String, dynamic>{} : runs.first;
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  /// Load schema + prompt templates from Supabase.
  ///
  /// Throws if the DB source-of-truth tables are not deployed yet. The app
  /// intentionally does not fall back to bundled schemas/prompts.
  Future<List<Map<String, dynamic>>> getSchemaTemplates({
    String? userEmail,
  }) async {
    final promptRows = await _client
        .from('prompt_templates')
        .select('prompt_key, version, template_body')
        .eq('is_active', true);
    final prompts = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(promptRows)) {
      final key = row['prompt_key']?.toString();
      final version = row['version']?.toString() ?? '1.0';
      final body = row['template_body']?.toString();
      if (key != null && key.isNotEmpty && body != null && body.isNotEmpty) {
        prompts['$key@$version'] = body;
      }
    }

    final schemaRows = await _client
        .from('schema_templates')
        .select('''
          schema_name,
          display_name,
          description,
          fields,
          field_descriptions,
          mandatory_fields,
          prompt_key,
          prompt_version,
          schema_version,
          is_system,
          is_active,
          client_email
        ''')
        .eq('is_active', true)
        .order('is_system', ascending: false)
        .order('display_name');

    final schemasByName = <String, Map<String, dynamic>>{};

    for (final row in List<Map<String, dynamic>>.from(schemaRows)) {
      final schemaName = row['schema_name']?.toString().trim();
      if (schemaName == null || schemaName.isEmpty) continue;

      final promptKey = row['prompt_key']?.toString();
      final promptVersion = row['prompt_version']?.toString() ?? '1.0';
      final promptLookupKey = promptKey == null || promptKey.isEmpty
          ? null
          : '$promptKey@$promptVersion';
      schemasByName[schemaName] = {
        'equipment_type': schemaName,
        'schema_name': schemaName,
        'display_name': row['display_name']?.toString() ?? schemaName,
        'description': row['description']?.toString(),
        'fields': _stringList(row['fields']),
        'field_descriptions': _stringMap(row['field_descriptions']),
        'mandatory_fields': _stringList(row['mandatory_fields']),
        'prompt_key': promptKey,
        'prompt_version': promptVersion,
        'prompt_template':
            promptLookupKey == null ? null : prompts[promptLookupKey],
        'schema_version': row['schema_version']?.toString() ?? '1.0',
        'is_system': row['is_system'] == true,
        'schema_source': 'supabase',
      };
    }

    final schemas = schemasByName.values.toList()
      ..sort((a, b) {
        final aSystem = a['is_system'] == true ? 0 : 1;
        final bSystem = b['is_system'] == true ? 0 : 1;
        if (aSystem != bSystem) return aSystem.compareTo(bSystem);
        return (a['display_name'] as String)
            .compareTo(b['display_name'] as String);
      });
    return schemas;
  }

  String _mimeTypeForExt(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  /// Save a completed extraction to Supabase.
  ///
  /// Creates records, uploads images, stores the extraction run,
  /// and populates record_current. Returns the Supabase record_id.
  Future<String> saveExtraction({
    required String userEmail,
    required String equipmentType,
    required String schemaName,
    required List<File> imageFiles,
    required Map<String, dynamic> fields,
    required Map<String, dynamic> extraFields,
    required Map<String, dynamic> reviewFlags,
    required bool imageMatch,
    required String? detectedType,
    String schemaVersion = '1.0',
    String? suggestedSchema,
    String? schemaConfidence,
    String? promptKey,
    String promptVersion = '1.0',
    Map<String, dynamic>? fieldConfidence,
    Map<String, dynamic>? fieldReviewNotes,
    String? rawResponse,
    int? latencyMs,
    String model = 'gpt-5.4',
  }) async {
    final recordId = _uuid.v4();
    final runId = _uuid.v4();
    final uploadedPaths = <String>[];
    final needsReview = reviewFlags.isNotEmpty;

    try {
      // 1. INSERT records
      await _client.from('records').insert({
        'id': recordId,
        'record_type': equipmentType,
        'schema_name': schemaName,
        'schema_version': schemaVersion,
        'user_email': userEmail,
        'status': needsReview ? 'review_required' : 'extracted',
      });

      // 2. Upload images to Storage + INSERT record_images
      for (var i = 0; i < imageFiles.length; i++) {
        final file = imageFiles[i];
        final ext = file.path.split('.').last.toLowerCase();
        final storagePath = '$recordId/${i + 1}_image.$ext';

        await _client.storage.from('scans').upload(
              storagePath,
              file,
              fileOptions: FileOptions(
                upsert: true,
                contentType: _mimeTypeForExt(ext),
              ),
            );
        uploadedPaths.add(storagePath);

        await _client.from('record_images').insert({
          'record_id': recordId,
          'image_order': i + 1,
          'storage_path': storagePath,
          'original_filename': file.path.split('/').last,
          'mime_type': _mimeTypeForExt(ext),
        });
      }

      // 3. INSERT extraction_runs
      final runPayload = {
        'id': runId,
        'record_id': recordId,
        'provider': 'openai',
        'model': model,
        'method': 'vision_direct',
        'schema_name': schemaName,
        'prompt_key': promptKey,
        'prompt_version': promptVersion,
        'input_image_count': imageFiles.length,
        'raw_output_text': rawResponse,
        'parsed_output': fields,
        'image_match': imageMatch,
        'detected_type': detectedType,
        'suggested_schema': suggestedSchema,
        'schema_confidence': schemaConfidence,
        'field_confidence': fieldConfidence,
        'field_review_notes': fieldReviewNotes,
        'latency_ms': latencyMs,
      };

      try {
        await _client.from('extraction_runs').insert(runPayload);
      } catch (e) {
        final message = e.toString();
        final metadataColumnMissing =
            message.contains('suggested_schema') ||
                message.contains('schema_confidence') ||
                message.contains('prompt_key') ||
                message.contains('prompt_version') ||
                message.contains('field_confidence') ||
                message.contains('field_review_notes');
        if (!metadataColumnMissing) rethrow;

        // Backward compatibility for Supabase projects that have not yet
        // re-run 01_complete_setup.sql with the schema metadata columns.
        runPayload.remove('suggested_schema');
        runPayload.remove('schema_confidence');
        runPayload.remove('prompt_key');
        runPayload.remove('prompt_version');
        runPayload.remove('field_confidence');
        runPayload.remove('field_review_notes');
        await _client.from('extraction_runs').insert(runPayload);
      }

      // 4. UPSERT record_current
      final filledCount =
          fields.values.where((v) => v != null && v.toString().isNotEmpty).length;

      await _client.from('record_current').upsert({
        'record_id': recordId,
        'extraction_run_id': runId,
        'fields': fields,
        'extra_fields': extraFields,
        'review_flags': reviewFlags,
        'field_confidence': fieldConfidence ?? <String, dynamic>{},
        'field_review_notes': fieldReviewNotes ?? <String, dynamic>{},
        'filled_field_count': filledCount,
        'review_required': needsReview,
      });

      return recordId;
    } catch (e) {
      for (final path in uploadedPaths) {
        try {
          await _client.storage.from('scans').remove([path]);
        } catch (_) {}
      }
      try {
        await _client.from('records').delete().eq('id', recordId);
      } catch (_) {}
      rethrow;
    }
  }

  /// Submit human corrections for an extraction.
  ///
  /// Uses the locally reviewed payload, creates a record_approved entry,
  /// and updates the record status to 'approved'.
  Future<void> submitCorrections({
    required String recordId,
    required Map<String, dynamic> approvedFields,
    required Map<String, dynamic> approvedExtraFields,
    required String userEmail,
    Map<String, dynamic>? fieldConfidence,
    Map<String, dynamic>? fieldReviewNotes,
  }) async {
    // 1. Update record_current using the locally reviewed payload.
    await _client.from('record_current').update({
      'fields': approvedFields,
      'extra_fields': approvedExtraFields,
      'review_flags': <String, dynamic>{},
      'field_confidence': fieldConfidence ?? <String, dynamic>{},
      'field_review_notes': fieldReviewNotes ?? <String, dynamic>{},
      'review_required': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('record_id', recordId);

    // 2. UPSERT record_approved
    await _client.from('record_approved').upsert({
      'record_id': recordId,
      'approved_fields': approvedFields,
      'approved_extra_fields': approvedExtraFields,
      'field_confidence': fieldConfidence ?? <String, dynamic>{},
      'field_review_notes': fieldReviewNotes ?? <String, dynamic>{},
      'approved_by': userEmail,
      'approved_at': DateTime.now().toIso8601String(),
    });

    // 3. Update record status + set client_email for portal RLS
    await _client.from('records').update({
      'status': 'approved',
      'client_email': defaultClientEmail,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', recordId);
  }

  /// Load extraction history from Supabase for a given user.
  Future<List<Map<String, dynamic>>> getExtractions(String userEmail) async {
    final result = await _client
        .from('records')
        .select('''
          id,
          record_type,
          status,
          created_at,
          record_current(fields, extra_fields, review_flags, field_confidence, field_review_notes, review_required, updated_at),
          record_approved(approved_fields, approved_extra_fields, field_confidence, field_review_notes),
          extraction_runs(field_confidence, field_review_notes, created_at),
          record_images(storage_path, image_order)
        ''')
        .eq('user_email', userEmail)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(result);
    final mapped = <Map<String, dynamic>>[];

    for (final row in rows) {
      final recordId = row['id']?.toString() ?? '';
      final recordType = row['record_type']?.toString() ?? 'unknown';
      final status = row['status']?.toString() ?? 'pending';
      final timestamp = row['created_at']?.toString() ?? '';

      final recordCurrent = _embeddedOne(row['record_current']);
      final recordApproved = _embeddedOne(row['record_approved']);
      final latestRun = _latestEmbeddedRun(row['extraction_runs']);

      final currentFields = normalizeDynamicMap(recordCurrent['fields']);
      final approvedFields =
          normalizeDynamicMap(recordApproved['approved_fields']);
      final currentExtraFields =
          normalizeExtraFields(recordCurrent['extra_fields']);
      final approvedExtraFields =
          normalizeExtraFields(recordApproved['approved_extra_fields']);

      final useApproved = status == 'approved' &&
          (approvedFields.isNotEmpty || approvedExtraFields.isNotEmpty);
      final fields = Map<String, dynamic>.from(
        useApproved ? approvedFields : currentFields,
      );
      final extraFields = useApproved ? approvedExtraFields : currentExtraFields;
      if (extraFields.isNotEmpty) {
        fields[extraFieldsKey] = extraFields;
      }

      final reviewFlags = normalizeDynamicMap(recordCurrent['review_flags']);

      final fieldConfidence = confidenceWithFallback(
        currentConfidence: recordCurrent['field_confidence'],
        approvedConfidence: recordApproved['field_confidence'],
        runConfidence: latestRun['field_confidence'],
      );

      final fieldReviewNotes = reviewNotesWithFallback(
        currentConfidence: recordCurrent['field_confidence'],
        currentReviewNotes: recordCurrent['field_review_notes'],
        approvedConfidence: recordApproved['field_confidence'],
        approvedReviewNotes: recordApproved['field_review_notes'],
        runReviewNotes: latestRun['field_review_notes'],
      );

      String? imageUrl;
      final imageUrls = <String>[];
      final imagesRaw = row['record_images'];
      if (imagesRaw is List && imagesRaw.isNotEmpty) {
        final imageMaps = imagesRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
          ..sort((a, b) {
            final aOrder = (a['image_order'] as num?)?.toInt() ?? 0;
            final bOrder = (b['image_order'] as num?)?.toInt() ?? 0;
            return aOrder.compareTo(bOrder);
          });
        for (final img in imageMaps) {
          final path = img['storage_path']?.toString();
          if (path != null && path.isNotEmpty) {
            try {
              final url = await getImageUrl(path);
              imageUrls.add(url);
            } catch (_) {}
          }
        }
        if (imageUrls.isNotEmpty) {
          imageUrl = imageUrls.first;
        }
      }

      mapped.add({
        'extraction_id': recordId,
        'supabase_record_id': recordId,
        'equipment_type': recordType,
        'status': status,
        'timestamp': timestamp,
        'fields': fields,
        'review_flags': reviewFlags,
        'field_confidence': fieldConfidence,
        'field_review_notes': fieldReviewNotes,
        'image_url': imageUrl,
        'image_urls': imageUrls,
      });
    }

    return mapped;
  }

  /// Get a signed URL for an image in Storage.
  Future<String> getImageUrl(String storagePath) async {
    return _client.storage
        .from('scans')
        .createSignedUrl(storagePath, 3600);
  }
}
