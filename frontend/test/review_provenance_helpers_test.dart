import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/services/json_helpers.dart';
import 'package:label_reader/services/review_provenance_helpers.dart';

void main() {
  group('normalizeDynamicMap', () {
    test('accepts maps and JSON object strings', () {
      expect(normalizeDynamicMap({'a': 1}), {'a': 1});
      expect(normalizeDynamicMap('{"a":1,"b":"two"}'), {
        'a': 1,
        'b': 'two',
      });
    });

    test('rejects null, empty strings, invalid JSON, and non-object JSON', () {
      expect(normalizeDynamicMap(null), isEmpty);
      expect(normalizeDynamicMap(''), isEmpty);
      expect(normalizeDynamicMap('not json'), isEmpty);
      expect(normalizeDynamicMap('[1,2,3]'), isEmpty);
    });
  });

  group('normalizeExtraFields', () {
    test('preserves object-shaped extra fields', () {
      expect(normalizeExtraFields({'lot_no': '123'}), {'lot_no': '123'});
      expect(normalizeExtraFields('{"lot_no":"123"}'), {'lot_no': '123'});
    });

    test('keeps free text extra fields instead of dropping them', () {
      expect(normalizeExtraFields('manual note'), {'value': 'manual note'});
    });
  });

  group('extra field edit mapping', () {
    test('flattens and rebuilds extra_fields with stable review paths', () {
      final editable = editableFieldsFromSchemaFields({
        'manufacturer': 'PPG',
        'extra_fields': {'lot_no': '123', 'date_of_packaging': '02/18'},
      });

      expect(editable['manufacturer'], 'PPG');
      expect(editable['extra_fields.lot_no'], '123');
      expect(editable['extra_fields.date_of_packaging'], '02/18');

      editable['extra_fields.lot_no'] = '124';
      final rebuilt = fieldsFromEditableFields(editable);

      expect(rebuilt['manufacturer'], 'PPG');
      expect(rebuilt['extra_fields'], {
        'lot_no': '124',
        'date_of_packaging': '02/18',
      });
    });
  });

  group('actualModifiedFields', () {
    test('filters no-op edits and includes nested extra_fields edits', () {
      final originalFields = {
        'manufacturer': 'PPG',
        'size': '1 GAL',
        'extra_fields': {'lot_no': '123', 'date_of_packaging': '02/18'},
      };
      final finalFields = {
        'manufacturer': 'PPG',
        'size': '1 QT',
        'extra_fields': {'lot_no': '124', 'date_of_packaging': '02/18'},
      };

      expect(
        actualModifiedFields(
          modifiedFields: {
            'manufacturer',
            'size',
            'extra_fields.lot_no',
            'extra_fields.date_of_packaging',
          },
          originalFields: originalFields,
          finalFields: finalFields,
        ),
        {'size', 'extra_fields.lot_no'},
      );
    });
  });

  group('fieldConfidenceWithOperatorEdits', () {
    test('marks fixed and extra-field edits as high-confidence operator edits', () {
      final updated = fieldConfidenceWithOperatorEdits(
        originalConfidence: {
          'size': {'level': 'low', 'score': 0.4},
          'manufacturer': {'level': 'high', 'score': 0.95},
        },
        actualModifiedFields: {'size', 'extra_fields.lot_no'},
      );

      expect(updated['manufacturer'], {'level': 'high', 'score': 0.95});
      expect(updated['size'], {
        'level': 'high',
        'score': 1.0,
        'provenance': 'operator_edit',
      });
      expect(updated['extra_fields.lot_no'], {
        'level': 'high',
        'score': 1.0,
        'provenance': 'operator_edit',
      });
    });
  });

  group('confidence fallback chain', () {
    test('uses current, then approved, then latest run confidence', () {
      expect(
        confidenceWithFallback(
          currentConfidence: {'current': true},
          approvedConfidence: {'approved': true},
          runConfidence: {'run': true},
        ),
        {'current': true},
      );
      expect(
        confidenceWithFallback(
          currentConfidence: {},
          approvedConfidence: {'approved': true},
          runConfidence: {'run': true},
        ),
        {'approved': true},
      );
      expect(
        confidenceWithFallback(
          currentConfidence: null,
          approvedConfidence: '{}',
          runConfidence: '{"run":true}',
        ),
        {'run': true},
      );
    });

    test('keeps review notes paired with their metadata source', () {
      expect(
        reviewNotesWithFallback(
          currentConfidence: {},
          currentReviewNotes: {},
          approvedConfidence: {'size': {'level': 'high'}},
          approvedReviewNotes: {},
          runReviewNotes: {'size': 'low model confidence'},
        ),
        isEmpty,
      );
      expect(
        reviewNotesWithFallback(
          currentConfidence: {},
          currentReviewNotes: {},
          approvedConfidence: {},
          approvedReviewNotes: {},
          runReviewNotes: {'size': 'low model confidence'},
        ),
        {'size': 'low model confidence'},
      );
    });
  });
}
