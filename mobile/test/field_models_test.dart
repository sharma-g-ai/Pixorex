import 'package:flutter_test/flutter_test.dart';
import 'package:pixorex_mobile/features/scan/capture_models.dart';
import 'package:pixorex_mobile/features/scan/scan_models.dart';

// "Critical" and the format rule were removed on 18 Nov 2026 and fields got a description.
// The API keeps sending is_critical:false for a while, so older and newer answers both parse.

void main() {
  group('TypeField (contract 2.10)', () {
    final base = {
      'field_key': 'serial',
      'label': 'Serial',
      'data_type': 'text',
      'is_required': true,
    };

    test('GIVEN the new shape (description, no is_critical) THEN it reads', () {
      final f = TypeField.fromJson({...base, 'description': 'After S/N'});
      expect(f.description, 'After S/N');
      expect(f.isRequired, isTrue);
    });

    test(
      'GIVEN the old shape (is_critical, no description) THEN it still reads, ignoring it',
      () {
        final f = TypeField.fromJson({...base, 'is_critical': true});
        expect(f.description, isNull);
        expect(f.label, 'Serial');
      },
    );

    test('GIVEN a null description THEN there is none', () {
      expect(
        TypeField.fromJson({...base, 'description': null}).description,
        isNull,
      );
    });
  });

  group('AiField (contract 2.24)', () {
    final base = {
      'field_key': 'voltage',
      'label': 'Voltage',
      'data_type': 'number',
      'is_required': false,
      'ai_value': '480',
      'confidence': 0.9,
      'flag_reasons': <String>[],
    };

    test('GIVEN the new shape THEN description and flags read', () {
      final f = AiField.fromJson({
        ...base,
        'description': 'Rated volts',
        'flag_reasons': ['format_failed'],
      });
      expect(f.description, 'Rated volts');
      expect(f.isFlagged, isTrue);
    });

    test('GIVEN the old shape with is_critical THEN it still reads', () {
      final f = AiField.fromJson({...base, 'is_critical': false});
      expect(f.description, isNull);
      expect(f.aiValue, '480');
      expect(f.isFlagged, isFalse);
    });

    test(
      'GIVEN an old scan flagged critical_not_found THEN it is still a flag',
      () {
        final f = AiField.fromJson({
          ...base,
          'ai_value': null,
          'flag_reasons': ['critical_not_found'],
        });
        expect(f.isFlagged, isTrue);
      },
    );
  });
}
