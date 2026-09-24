import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'config.dart';

class SheetsService {
  sheets.SheetsApi? _sheetsApi;

  Future<sheets.SheetsApi> _getApi() async {
    if (_sheetsApi != null) return _sheetsApi!;

    final credentialsJson =
        await rootBundle.loadString('assets/credentials.json');
    final credentials =
        ServiceAccountCredentials.fromJson(json.decode(credentialsJson));
    final scopes = [sheets.SheetsApi.spreadsheetsScope];
    final client = await clientViaServiceAccount(credentials, scopes);
    _sheetsApi = sheets.SheetsApi(client);
    return _sheetsApi!;
  }

  /// Get or create a worksheet for the equipment type.
  Future<String> _getOrCreateWorksheet(
      sheets.SheetsApi api, String equipmentType) async {
    final title = equipmentType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');

    // Check existing sheets
    final spreadsheet = await api.spreadsheets.get(googleSheetId);
    for (final sheet in spreadsheet.sheets ?? []) {
      if (sheet.properties?.title == title) {
        return title;
      }
    }

    // Create new worksheet
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: title),
            ),
          ),
        ],
      ),
      googleSheetId,
    );
    return title;
  }

  /// Sync a new extraction to Google Sheets.
  Future<void> syncExtraction({
    required String extractionId,
    required String equipmentType,
    required Map<String, dynamic> fields,
    required Map<String, dynamic> reviewFlags,
    required String userEmail,
    String status = 'pending',
  }) async {
    try {
      final api = await _getApi();
      final wsTitle = await _getOrCreateWorksheet(api, equipmentType);

      // Read existing header
      List<String> header;
      try {
        final existing = await api.spreadsheets.values
            .get(googleSheetId, '$wsTitle!1:1');
        header = (existing.values?.first ?? []).cast<String>();
      } catch (_) {
        header = [];
      }

      final fieldNames = fields.keys.toList()..sort();

      if (header.isEmpty) {
        // Create header row
        header = [
          'user_email',
          'uuid',
          'timestamp',
          'equipment_type',
          'status',
          ...fieldNames,
          'review_flags',
        ];
        await api.spreadsheets.values.update(
          sheets.ValueRange(values: [header]),
          googleSheetId,
          '$wsTitle!A1',
          valueInputOption: 'USER_ENTERED',
        );
      } else {
        // Rename extraction_id → uuid if present
        final eidIdx = header.indexOf('extraction_id');
        if (eidIdx != -1) {
          header[eidIdx] = 'uuid';
        } else if (!header.contains('uuid')) {
          // Add uuid column after user_email if missing entirely
          final emailIdx = header.indexOf('user_email');
          header.insert(emailIdx + 1, 'uuid');
        }

        // Add any new fields not in header
        final newFields = fieldNames.where((f) => !header.contains(f)).toList();
        if (newFields.isNotEmpty) {
          header.addAll(newFields);
        }

        // Always update header to persist rename/additions
        await api.spreadsheets.values.update(
          sheets.ValueRange(values: [header]),
          googleSheetId,
          '$wsTitle!A1',
          valueInputOption: 'USER_ENTERED',
        );
      }

      // Build row matching header order
      final row = <String>[];
      for (final col in header) {
        switch (col) {
          case 'uuid':
            row.add(extractionId);
          case 'timestamp':
            row.add(DateTime.now().toIso8601String());
          case 'equipment_type':
            row.add(equipmentType);
          case 'status':
            row.add(status);
          case 'user_email':
            row.add(userEmail);
          case 'review_flags':
            row.add(json.encode(reviewFlags));
          default:
            final val = fields[col];
            row.add(val != null ? val.toString() : '');
        }
      }

      await api.spreadsheets.values.append(
        sheets.ValueRange(values: [row]),
        googleSheetId,
        '$wsTitle!A1',
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      // Don't block the extraction flow if Sheets sync fails
      // ignore: avoid_print
      print('Google Sheets sync failed: $e');
    }
  }

  /// Update an existing extraction in Google Sheets after review.
  Future<void> updateExtraction({
    required String extractionId,
    required Map<String, String> correctedFields,
    required String userEmail,
  }) async {
    try {
      final api = await _getApi();
      final spreadsheet = await api.spreadsheets.get(googleSheetId);

      for (final sheet in spreadsheet.sheets ?? []) {
        final title = sheet.properties?.title ?? '';
        if (title.isEmpty) continue;

        // Search for the extraction_id in this sheet
        sheets.ValueRange allValues;
        try {
          allValues =
              await api.spreadsheets.values.get(googleSheetId, '$title!A:ZZ');
        } catch (_) {
          continue;
        }

        final rows = allValues.values;
        if (rows == null || rows.isEmpty) continue;

        final header = rows.first.cast<String>();
        var idCol = header.indexOf('uuid');
        if (idCol == -1) idCol = header.indexOf('extraction_id');
        if (idCol == -1) continue;

        for (var i = 1; i < rows.length; i++) {
          if (i < rows.length && rows[i].length > idCol &&
              rows[i][idCol] == extractionId) {
            // Found the row — update fields
            final rowValues =
                List<String>.from(rows[i].map((v) => v.toString()));
            while (rowValues.length < header.length) {
              rowValues.add('');
            }

            for (final entry in correctedFields.entries) {
              final colIdx = header.indexOf(entry.key);
              if (colIdx != -1) {
                rowValues[colIdx] = entry.value;
              }
            }

            // Update status
            final statusIdx = header.indexOf('status');
            if (statusIdx != -1) rowValues[statusIdx] = 'reviewed';

            // Add reviewed_by
            var reviewedByIdx = header.indexOf('reviewed_by');
            if (reviewedByIdx == -1) {
              header.add('reviewed_by');
              await api.spreadsheets.values.update(
                sheets.ValueRange(values: [header]),
                googleSheetId,
                '$title!A1',
                valueInputOption: 'USER_ENTERED',
              );
              reviewedByIdx = header.length - 1;
              while (rowValues.length < header.length) {
                rowValues.add('');
              }
            }
            rowValues[reviewedByIdx] = userEmail;

            await api.spreadsheets.values.update(
              sheets.ValueRange(values: [rowValues]),
              googleSheetId,
              '$title!A${i + 1}',
              valueInputOption: 'USER_ENTERED',
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Google Sheets update failed: $e');
    }
  }

  /// Read all extractions from all tabs in Google Sheets.
  Future<List<Map<String, dynamic>>> getAllExtractions() async {
    final results = <Map<String, dynamic>>[];
    try {
      final api = await _getApi();
      final spreadsheet = await api.spreadsheets.get(googleSheetId);

      for (final sheet in spreadsheet.sheets ?? []) {
        final title = sheet.properties?.title ?? '';
        if (title.isEmpty) continue;

        // Derive equipment_type from tab name (e.g. "Paint Label" → "paint_label")
        final tabEquipmentType = title.trim().toLowerCase().replaceAll(' ', '_');

        sheets.ValueRange allValues;
        try {
          allValues =
              await api.spreadsheets.values.get(googleSheetId, '$title!A:ZZ');
        } catch (_) {
          continue;
        }

        final rows = allValues.values;
        if (rows == null || rows.length < 2) continue;

        final header = rows.first.cast<String>();

        // Find key column indices
        final emailIdx = header.indexOf('user_email');
        var idIdx = header.indexOf('uuid');
        if (idIdx == -1) idIdx = header.indexOf('extraction_id');
        final tsIdx = header.indexOf('timestamp');
        final typeIdx = header.indexOf('equipment_type');
        final statusIdx = header.indexOf('status');
        final reviewFlagsIdx = header.indexOf('review_flags');

        // Field columns = everything that's not a fixed column
        const fixedCols = {
          'user_email', 'uuid', 'extraction_id', 'timestamp',
          'equipment_type', 'status', 'review_flags', 'image_filename',
          'reviewed_by',
        };

        for (var i = 1; i < rows.length; i++) {
          final row = rows[i];
          if (row.isEmpty) continue;

          // Safely get value at index
          String val(int idx) =>
              idx >= 0 && idx < row.length ? row[idx].toString() : '';

          // Build fields map from non-fixed columns
          final fields = <String, dynamic>{};
          for (var c = 0; c < header.length && c < row.length; c++) {
            if (!fixedCols.contains(header[c]) && row[c].toString().isNotEmpty) {
              fields[header[c]] = row[c].toString();
            }
          }

          // Parse review_flags
          Map<String, dynamic> reviewFlags = {};
          final rfStr = val(reviewFlagsIdx);
          if (rfStr.isNotEmpty) {
            try {
              reviewFlags = json.decode(rfStr) as Map<String, dynamic>;
            } catch (_) {}
          }

          // Use column value if present, otherwise derive from tab name
          final rawType = val(typeIdx).trim();
          final rawStatus = val(statusIdx).trim().toLowerCase();

          results.add({
            'extraction_id': val(idIdx),
            'timestamp': val(tsIdx),
            'equipment_type': rawType.isEmpty ? tabEquipmentType : rawType,
            'status': rawStatus.isEmpty ? 'pending' : rawStatus,
            'user_email': val(emailIdx),
            'fields': fields,
            'review_flags': reviewFlags,
          });
        }
      }
    } catch (e) {
      debugPrint('Google Sheets read failed: $e');
    }
    return results;
  }
}
