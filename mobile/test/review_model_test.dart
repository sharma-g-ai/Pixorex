import 'package:flutter_test/flutter_test.dart';
import 'package:pixorex_mobile/features/scan/review_model.dart';
import 'package:pixorex_mobile/features/scan/scan_models.dart';

AiField field(String key, String? value,
        {List<String> flags = const [], double? confidence, bool required = false, bool critical = false}) =>
    AiField(
      fieldKey: key,
      label: key,
      dataType: 'text',
      isRequired: required,
      isCritical: critical,
      aiValue: value,
      confidence: confidence,
      flagReasons: flags,
    );

/// Design 57: two likely wrong, one without a score, two required and empty, two fine.
Scan valveScan() => Scan(
      scanId: 's1',
      recordNo: 'REC-71',
      buId: 'b1',
      equipmentTypeId: 't1',
      equipmentTypeName: 'Control Valve',
      locationPath: 'Plant 04 › Bin 05',
      processingStatus: 'ready_to_review',
      reviewStatus: 'draft',
      attemptsUsed: 1,
      fields: [
        field('model', 'CR 32-4-1 A-G-A-E-HQQE', flags: ['low_confidence'], confidence: 0.42),
        field('voltage', '4I5 V', flags: ['format_failed']),
        field('serial', '98274-A3', flags: ['no_confidence']),
        field('barcode', null, flags: ['missing_required'], required: true),
        field('primary_id', null, flags: ['critical_not_found'], required: true, critical: true),
        field('manufacturer', 'Grundfos', confidence: 0.97),
        field('flow', '32 m³/h · 41 m', confidence: 0.91),
      ],
    );

void main() {
  test('GIVEN flags WHEN described THEN level and text follow the design', () {
    final f = valveScan().fields;
    expect(flagText(f[0]), 'Low confidence · 42%');
    expect(flagLevel(f[0]), FlagLevel.likelyWrong);
    expect(flagText(f[1]), 'Format check failed');
    expect(flagText(f[2]), 'No confidence score from the reader');
    expect(flagLevel(f[2]), FlagLevel.checkThis);
    expect(flagText(f[3]), 'Missing · required for this type');
    expect(flagText(f[4]), 'Critical field · not found on photo');
  });

  test('GIVEN a fresh review WHEN counted THEN 0 of 5 checked, 3 left, submit blocked', () {
    final d = ReviewDraft(valveScan());
    expect(d.flagged, hasLength(5));
    expect(d.checked, 0);
    expect(d.leftToCheck, 3); // the two empty required ones are handled at submit
    expect(d.canSubmit, isFalse);
  });

  test('GIVEN fixes, a keep and an unreadable WHEN submitted THEN the body matches contract 3.2', () {
    final d = ReviewDraft(valveScan());
    final f = d.scan.fields;
    d
      ..answer(f[0], const FieldAnswer.corrected('CR 32-4-1 A-F-A-E-HQQE'))
      ..answer(f[1], const FieldAnswer.corrected('415 V'))
      ..answer(f[2], const FieldAnswer.accepted())
      ..answer(f[3], const FieldAnswer.unreadable(UnreadableReason.labelWorn));
    expect(d.checked, 4);
    expect(d.canSubmit, isTrue);
    expect(d.emptyRequired.map((x) => x.fieldKey), ['primary_id']);

    // Without submit_anyway the empty required field is sent as pending -> accepted;
    // the API answers 409 required-fields-empty, which the screen turns into the modal.
    expect(d.body(submitAnyway: true), {
      'fields': [
        {'field_key': 'model', 'verification_state': 'corrected', 'value': 'CR 32-4-1 A-F-A-E-HQQE'},
        {'field_key': 'voltage', 'verification_state': 'corrected', 'value': '415 V'},
        {'field_key': 'serial', 'verification_state': 'accepted'},
        {'field_key': 'barcode', 'verification_state': 'unreadable', 'unreadable_reason': 'label_worn'},
        {'field_key': 'primary_id', 'verification_state': 'left_empty'},
      ],
      'submit_anyway': true,
    });
  });

  test('GIVEN "other" WHEN marked unreadable THEN the note goes with it', () {
    final d = ReviewDraft(valveScan());
    d.answer(d.scan.fields[4], const FieldAnswer.unreadable(UnreadableReason.other, note: 'Painted over'));
    final sent = (d.body()['fields'] as List).last;
    expect(sent, {'field_key': 'primary_id', 'verification_state': 'unreadable', 'unreadable_reason': 'other', 'note': 'Painted over'});
    expect(d.emptyRequired.map((x) => x.fieldKey), ['barcode']);
  });

  test('GIVEN a required field corrected to a value WHEN checked THEN it is no longer empty', () {
    final d = ReviewDraft(valveScan());
    d.answer(d.scan.fields[3], const FieldAnswer.corrected('4006381333931'));
    expect(d.emptyRequired.map((x) => x.fieldKey), ['primary_id']);
    expect(d.valueOf(d.scan.fields[3]), '4006381333931');
  });

  test('GIVEN fields with no flags WHEN submitted THEN they are not sent (kept as read)', () {
    final d = ReviewDraft(valveScan());
    final keys = (d.body()['fields'] as List).map((e) => (e as Map)['field_key']);
    expect(keys, isNot(contains('manufacturer')));
    expect(d.answerFor(d.scan.fields[5]).verdict, Verdict.accepted);
  });
}
