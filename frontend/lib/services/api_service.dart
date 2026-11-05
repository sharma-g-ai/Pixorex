import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // Using ADB reverse: phone's localhost:8002 → PC's localhost:8002 via USB
  static const String baseUrl = 'http://localhost:8002';
  // static const String baseUrl = 'http://10.0.2.2:8002'; // Android emulator
  // static const String baseUrl = 'http://192.168.1.36:8002'; // Physical device (needs firewall rule)

  /// Fetch list of available equipment schemas
  Future<List<Map<String, dynamic>>> getSchemas() async {
    final response = await http.get(Uri.parse('$baseUrl/schemas'));
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    throw Exception('Failed to load schemas: ${response.statusCode}');
  }

  /// Upload image(s) and extract fields
  Future<Map<String, dynamic>> extractFields({
    required List<File> imageFiles,
    required String equipmentType,
    required String userEmail,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/extract'),
    );
    request.fields['equipment_type'] = equipmentType;
    request.fields['user_email'] = userEmail;
    for (final imageFile in imageFiles) {
      request.files.add(
        await http.MultipartFile.fromPath('images', imageFile.path),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Extraction failed: ${response.body}');
  }

  /// Get all extractions
  Future<List<Map<String, dynamic>>> getExtractions() async {
    final response = await http.get(Uri.parse('$baseUrl/extractions'));
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    throw Exception('Failed to load extractions: ${response.statusCode}');
  }

  /// Get single extraction by ID
  Future<Map<String, dynamic>> getExtraction(String extractionId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/extractions/$extractionId'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Extraction not found: ${response.statusCode}');
  }

  /// Submit corrected fields
  Future<void> submitCorrections({
    required String extractionId,
    required Map<String, String> correctedFields,
    required String userEmail,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/review/correct'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'extraction_id': extractionId,
        'corrected_fields': correctedFields,
        'user_email': userEmail,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Correction failed: ${response.body}');
    }
  }

  /// Get image URL for display
  String getImageUrl(String filename) {
    return '$baseUrl/images/$filename';
  }

  /// Get Excel download URL
  String get downloadUrl => '$baseUrl/download';

  /// Get Google Sheet URL
  Future<String?> getSheetUrl() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sheet-url'));
      if (response.statusCode == 200) {
        return json.decode(response.body)['url'];
      }
    } catch (_) {}
    return null;
  }
}
