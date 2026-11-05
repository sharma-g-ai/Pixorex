import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class LocalStore {
  static const _fileName = 'extractions.json';
  static const _imageDir = 'images';

  Future<String> get _dirPath async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<File> get _file async {
    final path = await _dirPath;
    return File('$path/$_fileName');
  }

  Future<Directory> get _imagesDir async {
    final path = await _dirPath;
    final dir = Directory('$path/$_imageDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copy captured image to persistent storage, return saved path.
  Future<String> saveImage(File sourceFile) async {
    final dir = await _imagesDir;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = sourceFile.path.split('.').last;
    final destPath = '${dir.path}/${timestamp}_image.$ext';
    await sourceFile.copy(destPath);
    return destPath;
  }

  /// Load all extractions from local JSON file.
  Future<List<Map<String, dynamic>>> getAllExtractions() async {
    final file = await _file;
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.isEmpty) return [];
    final list = json.decode(content) as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Save a new extraction, returns the extraction_id.
  Future<String> saveExtraction({
    required String equipmentType,
    required String imagePath,
    required Map<String, dynamic> fields,
    required Map<String, dynamic> reviewFlags,
    required String userEmail,
  }) async {
    final extractions = await getAllExtractions();
    final extractionId = _uuid.v4();
    final timestamp = DateTime.now().toIso8601String();

    extractions.add({
      'extraction_id': extractionId,
      'timestamp': timestamp,
      'equipment_type': equipmentType,
      'image_path': imagePath,
      'fields': fields,
      'review_flags': reviewFlags,
      'status': 'pending',
      'user_email': userEmail,
    });

    final file = await _file;
    await file.writeAsString(json.encode(extractions));
    return extractionId;
  }

  /// Update extraction fields after review/correction.
  Future<bool> updateExtraction(
      String extractionId, Map<String, String> correctedFields) async {
    final extractions = await getAllExtractions();
    var found = false;

    for (final ext in extractions) {
      if (ext['extraction_id'] == extractionId) {
        final fields = Map<String, dynamic>.from(ext['fields'] as Map);
        fields.addAll(correctedFields);
        ext['fields'] = fields;
        ext['status'] = 'reviewed';
        found = true;
        break;
      }
    }

    if (found) {
      final file = await _file;
      await file.writeAsString(json.encode(extractions));
    }
    return found;
  }

  /// Store the Supabase record_id for a local extraction.
  Future<void> setSupabaseRecordId(
      String extractionId, String supabaseRecordId) async {
    final extractions = await getAllExtractions();
    for (final ext in extractions) {
      if (ext['extraction_id'] == extractionId) {
        ext['supabase_record_id'] = supabaseRecordId;
        break;
      }
    }
    final file = await _file;
    await file.writeAsString(json.encode(extractions));
  }

  /// Get the Supabase record_id for a local extraction.
  Future<String?> getSupabaseRecordId(String extractionId) async {
    final extractions = await getAllExtractions();
    for (final ext in extractions) {
      if (ext['extraction_id'] == extractionId) {
        return ext['supabase_record_id'] as String?;
      }
    }
    return null;
  }

  /// Get a single extraction by ID.
  Future<Map<String, dynamic>?> getExtraction(String extractionId) async {
    final extractions = await getAllExtractions();
    for (final ext in extractions) {
      if (ext['extraction_id'] == extractionId) {
        return Map<String, dynamic>.from(ext);
      }
    }
    return null;
  }

  /// Update the status of a local extraction.
  Future<void> setStatus(String extractionId, String status) async {
    final extractions = await getAllExtractions();
    var changed = false;
    for (final ext in extractions) {
      if (ext['extraction_id'] == extractionId) {
        ext['status'] = status;
        changed = true;
        break;
      }
    }
    if (changed) {
      final file = await _file;
      await file.writeAsString(json.encode(extractions));
    }
  }
}
