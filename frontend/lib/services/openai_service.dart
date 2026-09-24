// ignore_for_file: use_null_aware_elements

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config.dart';

class OpenAiService {
  static const _knownSchemaNames = [
    'motor',
    'generator',
    'transformer',
    'chiller',
    'equipment_label',
    'paint_label',
    'other',
  ];

  static const _schemaConfidenceValues = ['high', 'medium', 'low'];
  static const _genericSchemaMatchTokens = {
    'nameplate',
    'equipment',
    'label',
    'data',
    'plate',
    'rating',
    'serial',
    'asset',
    'tag',
    'schema',
    'custom',
    'standard',
    'industrial',
    'product',
  };

  static const _mismatchHandlingRules = '''
Mismatch handling:
If _image_match is false, the image belongs to a different category than the selected schema.

- Do not force values into selected-schema fields just because this prompt asks for that schema.
- Fill a selected-schema field only when the value is directly visible and genuinely matches the same semantic concept as the field name.
- Cross-schema fields such as manufacturer, made_in, serial_no, volts, hz, barcode, or UPC may be filled when they are clearly visible and semantically correct.
- Schema-specific fields must stay null unless they are clearly present for this image. For example, if a user selected Motor but the image is a transformer plate, do not invent rpm, hp, frame_no, nema_des, or motor-only fields.
- Always return _image_match, _detected_type, _suggested_schema, and _schema_confidence so the app can route the record correctly.''';

  static const _fieldConfidenceRules = '''
Field confidence:
- Return _field_confidence as a JSON object for populated fields only.
- Prefer this shape: {"field_name": {"level": "high|medium|low", "score": 0.0-1.0}}.
- Use high / 0.85-1.0 only when the value is clearly visible and directly read from the image.
- Use medium / 0.70-0.84 when the value is mostly clear but has minor ambiguity.
- Use low / below 0.70 when the value is partially occluded, blurry, inferred from context, conflicting across images, or contains ? placeholders.
- Return _field_review_notes as a JSON object containing only low-confidence fields, with a short reason for each.
- Do not mark null/missing fields as low confidence. Review is only for extracted values that may be wrong.''';

  String _fieldListForPrompt(Map<String, dynamic> schema) {
    final fields = (schema['fields'] as List).cast<String>();
    final descriptionsRaw = schema['field_descriptions'];
    final descriptions = descriptionsRaw is Map
        ? descriptionsRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    return fields
        .map((field) {
          final description = descriptions[field]?.trim();
          if (description != null && description.isNotEmpty) {
            return '- $field: $description';
          }
          return '- $field';
        })
        .join('\n');
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((v) => v?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  List<Map<String, dynamic>> _schemaCatalogRows(Map<String, dynamic> schema) {
    final raw = schema['schema_catalog'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .where((row) {
          final name = row['schema_name']?.toString().trim() ?? '';
          return name.isNotEmpty;
        })
        .toList();
  }

  String _schemaCatalogForPrompt(Map<String, dynamic> schema) {
    final rows = _schemaCatalogRows(schema);
    if (rows.isEmpty) {
      return 'Allowed schema names: ${_knownSchemaNamesFor(schema).join(', ')}';
    }

    return rows
        .map((row) {
          final name = row['schema_name']?.toString().trim() ?? '';
          final displayName = row['display_name']?.toString().trim();
          final description = row['description']?.toString().trim();
          final fields = _stringList(row['fields']);
          final mandatoryFields = _stringList(row['mandatory_fields']);
          final keyFields = <String>[...mandatoryFields, ...fields];
          final uniqueKeyFields = <String>[];
          for (final field in keyFields) {
            if (!uniqueKeyFields.contains(field)) uniqueKeyFields.add(field);
            if (uniqueKeyFields.length >= 10) break;
          }

          final label = displayName != null && displayName.isNotEmpty
              ? '$name ($displayName)'
              : name;
          final descriptionPart = description != null && description.isNotEmpty
              ? ': $description'
              : '';
          final keyFieldPart = uniqueKeyFields.isNotEmpty
              ? ' Key fields: ${uniqueKeyFields.join(', ')}'
              : '';
          return '- $label$descriptionPart$keyFieldPart';
        })
        .join('\n');
  }

  List<String> _knownSchemaNamesFor(Map<String, dynamic> schema) {
    final raw = schema['known_schema_names'];
    if (raw is List) {
      final names = raw
          .map((v) => v?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names;
    }
    return _knownSchemaNames;
  }

  String _normalizeSchemaText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Set<String> _schemaMatchTokens(String value) {
    final matches = RegExp(r'[a-z0-9]+').allMatches(value.toLowerCase());
    return matches
        .map((m) => m.group(0) ?? '')
        .where(
          (token) =>
              token.length > 2 && !_genericSchemaMatchTokens.contains(token),
        )
        .toSet();
  }

  String? _customSchemaMatchFromEvidence(
    String evidence,
    List<String> knownSchemaNames,
    List<Map<String, dynamic>> schemaCatalog,
  ) {
    final evidenceTokens = _schemaMatchTokens(evidence);
    if (evidenceTokens.isEmpty) return null;

    String? bestSchema;
    var bestScore = 0;
    var ambiguous = false;

    for (final row in schemaCatalog) {
      if (row['is_system'] == true) continue;
      final schemaName = row['schema_name']?.toString().trim() ?? '';
      if (!knownSchemaNames.contains(schemaName)) continue;

      final schemaEvidence = [
        schemaName,
        row['display_name']?.toString() ?? '',
        row['description']?.toString() ?? '',
      ].join(' ');
      final schemaTokens = _schemaMatchTokens(schemaEvidence);
      final score = schemaTokens
          .where((token) => evidenceTokens.contains(token))
          .length;
      if (score > bestScore) {
        bestScore = score;
        bestSchema = schemaName;
        ambiguous = false;
      } else if (score == bestScore && score > 0) {
        ambiguous = true;
      }
    }

    return !ambiguous && bestScore > 0 ? bestSchema : null;
  }

  String _buildValidationContract(Map<String, dynamic> schema) {
    final displayName = schema['display_name'];
    final knownSchemaNames = _knownSchemaNamesFor(schema);
    return '''Allowed schema catalog for _suggested_schema:
${_schemaCatalogForPrompt(schema)}

Also include these VALIDATION fields:
- _image_match: true if the image matches the expected schema "$displayName", false if it does not.
- _detected_type: a short description of what you actually see in the image (e.g., "Motor Nameplate", "Transformer Rating Plate", "Paint Label", "Not a label/nameplate")
- _suggested_schema: one of ${knownSchemaNames.join(', ')}. Use this decision rule:
  * First compare the image against the allowed schema catalog above. Prefer the most specific matching schema over a generic schema.
  * If the image shows a paint, chemical, sealant, adhesive, coating, primer, hardener, or similar product container label, return "paint_label".
  * If it shows an industrial equipment nameplate (motor, generator, transformer, chiller, or similar data plate), return the matching equipment schema name ("motor", "generator", "transformer", or "chiller").
  * If it matches a client-defined custom schema in the catalog, return that custom schema name. For example, a pump nameplate should use a pump-specific custom schema when one exists, not generic "equipment_label".
  * If it shows a general equipment serial/asset/part label that does not belong to a specific equipment nameplate category, return "equipment_label".
  * For any other product or label that does not fit the above (apparel tags, retail packaging, signs, documents), return "other".
- _schema_confidence: one of ${_schemaConfidenceValues.join(', ')}. Confidence that _suggested_schema is the right schema for the image(s).''';
  }

  String _buildJsonReturnContract() {
    return '''Return ONLY a JSON object with the schema field names plus validation fields. Schema values must be strings, null, or an object for extra_fields. _image_match must be boolean. _field_confidence and _field_review_notes must be JSON objects. Do not include any explanation, markdown, or extra text — just the JSON object.''';
  }

  String? _buildPromptFromTemplate(Map<String, dynamic> schema) {
    final templateRaw = schema['prompt_template'];
    if (templateRaw is! String || templateRaw.trim().isEmpty) return null;

    final fields = (schema['fields'] as List).cast<String>();
    final replacements = {
      '{{schema_name}}': (schema['schema_name'] ?? schema['equipment_type'])
          .toString(),
      '{{display_name}}': (schema['display_name'] ?? '').toString(),
      '{{schema_description}}': (schema['description'] ?? '').toString(),
      '{{field_list}}': _fieldListForPrompt(schema),
      '{{field_csv}}': fields.join(', '),
      '{{validation_contract}}': _buildValidationContract(schema),
      '{{mismatch_handling_rules}}': _mismatchHandlingRules,
      '{{field_confidence_rules}}': _fieldConfidenceRules,
      '{{json_return_contract}}': _buildJsonReturnContract(),
    };

    var prompt = templateRaw;
    for (final entry in replacements.entries) {
      prompt = prompt.replaceAll(entry.key, entry.value);
    }
    return prompt;
  }

  String? _normalizeSuggestedSchema(
    dynamic value,
    List<String> knownSchemaNames,
    List<Map<String, dynamic>> schemaCatalog, {
    dynamic detectedType,
  }) {
    final raw = value?.toString().trim().toLowerCase() ?? '';
    final evidence = '$raw ${detectedType?.toString() ?? ''}';
    if (raw.isEmpty) {
      return _customSchemaMatchFromEvidence(
        evidence,
        knownSchemaNames,
        schemaCatalog,
      );
    }
    final normalized = _normalizeSchemaText(raw);

    // Alias map for GPT's free-form _suggested_schema output. Keys are the
    // raw (normalized) values we have observed or expect from GPT; values
    // are one of _knownSchemaNames.
    //
    // Deliberate omission: bare "nameplate" / "data_plate" / "rating_plate"
    // are NOT aliased. Those are ambiguous — they might be a motor, a
    // generator, a chiller, or a generic asset plate. Letting them fall
    // through to null keeps the user's manually-selected schema in charge
    // rather than silently downgrading a motor scan into equipment_label.
    const aliases = {
      // Industrial equipment nameplates → specific schema
      'motor_nameplate': 'motor',
      'induction_motor_nameplate': 'motor',
      'ac_generator_nameplate': 'generator',
      'generator_nameplate': 'generator',
      'current_transformer_nameplate': 'transformer',
      'transformer_nameplate': 'transformer',
      'hvac_chiller_nameplate': 'chiller',
      'chiller_nameplate': 'chiller',

      // General equipment data/asset/serial plates → equipment_label
      'equipment_nameplate': 'equipment_label',
      'equipment_data_plate': 'equipment_label',
      'equipment_serial_plate': 'equipment_label',
      'asset_tag': 'equipment_label',
      'serial_plate': 'equipment_label',

      // Paint / chemical / coating product containers → paint_label
      'paint_chemical_label': 'paint_label',
      'paint_can_label': 'paint_label',
      'chemical_label': 'paint_label',
      'sealant_tube': 'paint_label',
      'sealant_label': 'paint_label',
      'adhesive_label': 'paint_label',
      'adhesive_tube': 'paint_label',
      'coating_label': 'paint_label',
      'primer_label': 'paint_label',
      'hardener_label': 'paint_label',
      'threadlocker_label': 'paint_label',

      // Ambiguous retail / product / apparel labels → quarantine in other
      'label': 'other',
      'generic_label': 'other',
      'product_label': 'other',
      'product_tag': 'other',
      'retail_label': 'other',
      'retail_tag': 'other',
      'apparel_label': 'other',
      'apparel_tag': 'other',
      'clothing_tag': 'other',
      'garment_tag': 'other',
      'sku_label': 'other',
      'packaging_label': 'other',
      'box_label': 'other',

      // Explicit non-matches → quarantine rather than drop
      'not_a_label': 'other',
      'not_a_nameplate': 'other',
      'not_a_product': 'other',
      'random_object': 'other',
      'no_label': 'other',
      'no_text': 'other',
      'blank': 'other',
      'empty': 'other',
      'illegible': 'other',
      'unreadable': 'other',
      'unknown': 'other',
      'none': 'other',
    };

    final candidate = aliases[normalized] ?? normalized;
    final customMatch = _customSchemaMatchFromEvidence(
      evidence,
      knownSchemaNames,
      schemaCatalog,
    );

    // Preserve exact/specific known suggestions. For generic suggestions,
    // allow a matching custom schema to win. Example: GPT detects "pump
    // equipment nameplate" but returns generic equipment_label; if a custom
    // pump schema exists, route to that schema so the user can re-extract
    // with the right field set.
    if (knownSchemaNames.contains(candidate) &&
        candidate != 'equipment_label' &&
        candidate != 'other') {
      return candidate;
    }
    if (customMatch != null) return customMatch;
    return knownSchemaNames.contains(candidate) ? candidate : null;
  }

  String? _normalizeSchemaConfidence(dynamic value) {
    if (value == null) return null;
    final confidence = value.toString().trim().toLowerCase();
    return _schemaConfidenceValues.contains(confidence) ? confidence : null;
  }

  Map<String, dynamic> _normalizeFieldConfidence(
    dynamic value,
    Iterable<String> knownFields,
  ) {
    final allowedFields = knownFields.toSet();
    final result = <String, dynamic>{};
    if (value is! Map) return result;

    for (final entry in value.entries) {
      final field = entry.key.toString();
      if (!allowedFields.contains(field)) continue;

      String? level;
      double? score;
      final raw = entry.value;
      if (raw is Map) {
        final rawLevel = raw['level']?.toString().trim().toLowerCase();
        if (rawLevel != null && _schemaConfidenceValues.contains(rawLevel)) {
          level = rawLevel;
        }
        final rawScore = raw['score'];
        if (rawScore is num) {
          score = rawScore.toDouble().clamp(0.0, 1.0).toDouble();
        } else if (rawScore is String) {
          final parsed = double.tryParse(rawScore.trim());
          if (parsed != null) {
            score = parsed.clamp(0.0, 1.0).toDouble();
          }
        }
      } else if (raw is num) {
        score = raw.toDouble().clamp(0.0, 1.0).toDouble();
      } else {
        final rawLevel = raw?.toString().trim().toLowerCase();
        if (rawLevel != null && _schemaConfidenceValues.contains(rawLevel)) {
          level = rawLevel;
        }
      }

      if (level == null && score != null) {
        level = score < 0.70
            ? 'low'
            : score < 0.85
            ? 'medium'
            : 'high';
      }
      if (score == null && level != null) {
        score = level == 'low'
            ? 0.60
            : level == 'medium'
            ? 0.78
            : 0.92;
      }
      if (level == null && score == null) continue;

      result[field] = {
        if (level != null) 'level': level,
        if (score != null) 'score': score,
      };
    }
    return result;
  }

  Map<String, String> _normalizeFieldReviewNotes(
    dynamic value,
    Iterable<String> knownFields,
  ) {
    final allowedFields = knownFields.toSet();
    final result = <String, String>{};
    if (value is! Map) return result;

    for (final entry in value.entries) {
      final field = entry.key.toString();
      final note = entry.value?.toString().trim();
      if (!allowedFields.contains(field)) continue;
      if (note == null || note.isEmpty) continue;
      result[field] = note;
    }
    return result;
  }

  /// Build review flags from two independent signals:
  /// Review flags come only from GPT low-confidence metadata.
  /// Missing mandatory fields are tracked separately via
  /// [_getMissingRequiredFields] and surfaced in the UI with a distinct
  /// "REQUIRED" badge, so the two signals stay visually and semantically
  /// independent.
  Map<String, dynamic> _getReviewFlags(
    Map<String, dynamic> fields,
    Map<String, dynamic> fieldConfidence,
    Map<String, String> fieldReviewNotes,
  ) {
    final flags = <String, dynamic>{};

    for (final entry in fieldConfidence.entries) {
      final info = entry.value;
      final level = info is Map ? info['level']?.toString() : null;
      final scoreRaw = info is Map ? info['score'] : null;
      final score = scoreRaw is num ? scoreRaw.toDouble() : null;
      final shouldReview = level == 'low' || (score != null && score < 0.70);
      if (!shouldReview) continue;
      final value = fields[entry.key];
      if (value == null || value.toString().trim().isEmpty) continue;
      flags[entry.key] = {
        'confidence': level ?? 'low',
        if (score != null) 'score': score,
        if (fieldReviewNotes[entry.key]?.isNotEmpty == true)
          'reason': fieldReviewNotes[entry.key],
      };
    }

    return flags;
  }

  /// Return the list of mandatory fields that are missing or empty in the
  /// extracted output. This is a deterministic schema-level check — it does
  /// not depend on GPT confidence at all.
  List<String> _getMissingRequiredFields(
    Map<String, dynamic> fields,
    List<String> mandatoryFields,
  ) {
    final missing = <String>[];
    for (final field in mandatoryFields) {
      final value = fields[field];
      final isMissing = value == null || value.toString().trim().isEmpty;
      if (isMissing) missing.add(field);
    }
    return missing;
  }

  /// Extract fields from one or more images — calls OpenAI directly.
  Future<Map<String, dynamic>> extractFields(
    List<File> imageFiles,
    String equipmentType, {
    Map<String, dynamic>? schemaOverride,
  }) async {
    final schema = schemaOverride;
    if (schema == null) {
      throw Exception(
        'Schema "$equipmentType" must be loaded from Supabase before extraction.',
      );
    }
    var prompt = _buildPromptFromTemplate(schema);
    if (prompt == null) {
      throw Exception(
        'Schema setup is incomplete for "$equipmentType". Please contact your administrator.',
      );
    }

    if (imageFiles.length > 1 && equipmentType != 'paint_label') {
      prompt +=
          '\n\nYou are given ${imageFiles.length} images of the same label/nameplate (different angles, closeups, front/back). Combine information from ALL images into a single extraction. If the same field is visible in multiple images, use the clearest/most legible one.';
    }

    // Build content array: text + images
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];

    for (final file in imageFiles) {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = file.path.split('.').last.toLowerCase();
      final mimeMap = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'gif': 'image/gif',
      };
      final mime = mimeMap[ext] ?? 'image/jpeg';
      content.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,$b64'},
      });
    }

    // Call OpenAI API
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $openAiApiKey',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': openAiModel,
        'messages': [
          {'role': 'user', 'content': content},
        ],
        'max_completion_tokens': 4096,
        'temperature': 0,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Extraction service error (${response.statusCode}). Please try again.',
      );
    }

    final responseJson = json.decode(response.body) as Map<String, dynamic>;
    var rawText =
        (responseJson['choices'] as List)[0]['message']['content'] as String;
    rawText = rawText.trim();

    // Strip markdown code fences if present
    if (rawText.startsWith('```')) {
      final lines = rawText.split('\n');
      final cleaned = lines.where((l) => !l.startsWith('```')).join('\n');
      rawText = cleaned;
    }

    final extractedFields = json.decode(rawText) as Map<String, dynamic>;

    // Extract validation fields
    final imageMatchRaw = extractedFields.remove('_image_match');
    final detectedType = extractedFields.remove('_detected_type');
    final knownSchemaNames = _knownSchemaNamesFor(schema);
    final schemaCatalog = _schemaCatalogRows(schema);
    final suggestedSchema = _normalizeSuggestedSchema(
      extractedFields.remove('_suggested_schema'),
      knownSchemaNames,
      schemaCatalog,
      detectedType: detectedType,
    );
    final schemaConfidence = _normalizeSchemaConfidence(
      extractedFields.remove('_schema_confidence'),
    );
    final fieldConfidence = _normalizeFieldConfidence(
      extractedFields.remove('_field_confidence'),
      extractedFields.keys,
    );
    final fieldReviewNotes = _normalizeFieldReviewNotes(
      extractedFields.remove('_field_review_notes'),
      extractedFields.keys,
    );

    // Normalize _image_match (GPT may return string or bool).
    // If GPT omits it, infer from _suggested_schema or _detected_type.
    bool imageMatch;
    if (imageMatchRaw == null) {
      // GPT omitted the field — prefer the machine-readable schema suggestion,
      // then fall back to the free-text detected type.
      if (suggestedSchema != null) {
        imageMatch = suggestedSchema == equipmentType;
      } else if (detectedType != null &&
          detectedType is String &&
          detectedType.toString().trim().isNotEmpty) {
        final detected = detectedType.toString().toLowerCase();
        final selected = (schema['display_name'] as String).toLowerCase();
        final selectedType = equipmentType.toLowerCase();
        imageMatch =
            detected.contains(selectedType) ||
            detected.contains(selected) ||
            selected.contains(detected);
      } else {
        imageMatch = true; // No info at all, assume match
      }
    } else if (imageMatchRaw is String) {
      imageMatch = ['true', 'yes', '1'].contains(imageMatchRaw.toLowerCase());
    } else {
      imageMatch = imageMatchRaw == true;
    }

    final mandatoryRaw = schema['mandatory_fields'];
    final mandatoryFields = mandatoryRaw is List
        ? mandatoryRaw.map((v) => v.toString()).toList()
        : const <String>[];
    final reviewFlags = _getReviewFlags(
      extractedFields,
      fieldConfidence,
      fieldReviewNotes,
    );
    final missingRequired = _getMissingRequiredFields(
      extractedFields,
      mandatoryFields,
    );

    final result = <String, dynamic>{
      'fields': extractedFields,
      'review_flags': reviewFlags,
      'missing_required_fields': missingRequired,
      'mandatory_fields': mandatoryFields,
      'equipment_type': equipmentType,
    };

    if (suggestedSchema != null) {
      result['suggested_schema'] = suggestedSchema;
    }
    if (schemaConfidence != null) {
      result['schema_confidence'] = schemaConfidence;
    }
    if (fieldConfidence.isNotEmpty) {
      result['field_confidence'] = fieldConfidence;
    }
    if (fieldReviewNotes.isNotEmpty) {
      result['field_review_notes'] = fieldReviewNotes;
    }

    if (!imageMatch) {
      final suggestion = suggestedSchema == null
          ? ''
          : ' Suggested schema: $suggestedSchema${schemaConfidence == null ? '' : ' ($schemaConfidence confidence)'}.';
      result['mismatch_warning'] =
          'Image appears to be: ${detectedType ?? "unknown"}. You selected: ${schema["display_name"]}.$suggestion';
      result['detected_type'] = detectedType;
    }

    return result;
  }
}
