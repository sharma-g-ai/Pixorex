import 'scan_models.dart';

/// Why a value can't be read (contract 3.2 `unreadable_reason`), with the design's wording.
enum UnreadableReason {
  labelWorn('label_worn', 'Label worn or damaged'),
  notOnNameplate('not_on_nameplate', 'Not on this nameplate'),
  coveredOrUnreachable('covered_or_unreachable', 'Covered or out of reach'),
  other('other', 'Other — add a note');

  const UnreadableReason(this.code, this.label);
  final String code;
  final String label;
}

/// How bad a flag looks (design 57 legend): red "Likely wrong", amber "Check this".
enum FlagLevel { likelyWrong, checkThis }

enum Verdict { pending, accepted, corrected, unreadable }

/// The technician's answer for one field.
class FieldAnswer {
  const FieldAnswer.pending() : this._(Verdict.pending);
  const FieldAnswer.accepted() : this._(Verdict.accepted);
  const FieldAnswer.corrected(String value) : this._(Verdict.corrected, value: value);
  const FieldAnswer.unreadable(UnreadableReason reason, {String? note}) : this._(Verdict.unreadable, reason: reason, note: note);
  const FieldAnswer._(this.verdict, {this.value, this.reason, this.note});

  final Verdict verdict;
  final String? value;
  final UnreadableReason? reason;
  final String? note;
}

/// Self-review of a scan before it goes to a reviewer (design 57-62, docs/mobile-api.md
/// section 6). Only flagged fields need an answer; the rest are kept as the AI read them.
class ReviewDraft {
  ReviewDraft(this.scan) : _answers = {for (final f in scan.fields) if (f.isFlagged) f.fieldKey: const FieldAnswer.pending()};

  final Scan scan;
  final Map<String, FieldAnswer> _answers;

  List<AiField> get flagged => scan.fields.where((f) => f.isFlagged).toList();

  FieldAnswer answerFor(AiField f) => _answers[f.fieldKey] ?? const FieldAnswer.accepted();

  void answer(AiField f, FieldAnswer a) => _answers[f.fieldKey] = a;

  int get checked => _answers.values.where((a) => a.verdict != Verdict.pending).length;

  /// The value the reviewer will see, or null when the field ends up empty.
  String? valueOf(AiField f) {
    final a = answerFor(f);
    return switch (a.verdict) {
      Verdict.corrected => a.value,
      Verdict.unreadable => null,
      _ => (f.aiValue?.trim().isEmpty ?? true) ? null : f.aiValue,
    };
  }

  /// Required fields that would be sent empty (marked unreadable doesn't count as empty).
  List<AiField> get emptyRequired => scan.fields
      .where((f) => f.isRequired && answerFor(f).verdict != Verdict.unreadable && valueOf(f) == null)
      .toList();

  /// Flagged fields still waiting for an answer, other than empty ones the
  /// required-fields check deals with at submit.
  int get leftToCheck => flagged
      .where((f) => answerFor(f).verdict == Verdict.pending && !(f.isRequired && valueOf(f) == null))
      .length;

  bool get canSubmit => leftToCheck == 0;

  /// Body of `POST /scans/{scanId}/revisions`. With [submitAnyway], empty required
  /// fields are sent as `left_empty`.
  Map<String, dynamic> body({bool submitAnyway = false}) {
    final empty = {for (final f in emptyRequired) f.fieldKey};
    return {
      'fields': [
        for (final f in flagged)
          if (submitAnyway && empty.contains(f.fieldKey) && answerFor(f).verdict == Verdict.pending)
            {'field_key': f.fieldKey, 'verification_state': 'left_empty'}
          else
            _verdict(f, answerFor(f)),
      ],
      'submit_anyway': submitAnyway,
    };
  }

  Map<String, dynamic> _verdict(AiField f, FieldAnswer a) => switch (a.verdict) {
        Verdict.corrected => {'field_key': f.fieldKey, 'verification_state': 'corrected', 'value': a.value},
        Verdict.unreadable => {
            'field_key': f.fieldKey,
            'verification_state': 'unreadable',
            'unreadable_reason': a.reason!.code,
            if (a.note != null && a.note!.isNotEmpty) 'note': a.note,
          },
        _ => {'field_key': f.fieldKey, 'verification_state': 'accepted'},
      };
}

/// Red for a value that is probably wrong, amber for one that only lacks a score.
FlagLevel flagLevel(AiField f) => f.flagReasons.every((r) => r == 'no_confidence') ? FlagLevel.checkThis : FlagLevel.likelyWrong;

/// "Low confidence · 42%" etc. (design 57): the first reason, as the technician reads it.
String flagText(AiField f) {
  final r = f.flagReasons.firstOrNull;
  return switch (r) {
    'low_confidence' => f.confidence == null ? 'Low confidence' : 'Low confidence · ${(f.confidence! * 100).round()}%',
    'format_failed' => 'Format check failed',
    'no_confidence' => 'No confidence score from the reader',
    'missing_required' => 'Missing · required for this type',
    'critical_not_found' => 'Critical field · not found on photo',
    _ => 'Flagged',
  };
}

/// Fixing a rejected scan (design 69): every field starts as the technician last sent it,
/// and any of them can be corrected again before it goes back to the reviewer.
class RejectionFix {
  RejectionFix(this.scan);

  final Scan scan;
  final Map<String, String> _fixes = {};

  /// Fields the technician answered in the rejected revision, in the type's order.
  List<AiField> get fields => scan.fields.where((f) => f.submitted != null).toList();

  /// What was sent last time: the corrected value, or the AI value when it was kept.
  String? sentValue(AiField f) => switch (f.submitted?.verificationState) {
        'corrected' => f.submitted!.value,
        'accepted' => f.submitted!.value ?? f.aiValue,
        _ => null,
      };

  String? fixOf(AiField f) => _fixes[f.fieldKey];

  /// An empty or unchanged value undoes the fix.
  void fix(AiField f, String value) {
    final v = value.trim();
    if (v.isEmpty || v == sentValue(f)) {
      _fixes.remove(f.fieldKey);
    } else {
      _fixes[f.fieldKey] = v;
    }
  }

  void undo(AiField f) => _fixes.remove(f.fieldKey);

  int get corrected => _fixes.length;

  /// Required fields that would still go back empty.
  bool get _leavesRequiredEmpty =>
      fields.any((f) => f.isRequired && fixOf(f) == null && f.submitted!.verificationState == 'left_empty');

  /// Body of `POST /scans/{scanId}/revisions`: the new fixes, and every other field
  /// answered as it was before (the API needs an answer for each flagged field again).
  Map<String, dynamic> body() => {
        'fields': [
          for (final f in fields)
            if (fixOf(f) != null)
              {'field_key': f.fieldKey, 'verification_state': 'corrected', 'value': fixOf(f)}
            else
              _resend(f, f.submitted!),
        ],
        'submit_anyway': _leavesRequiredEmpty,
      };

  Map<String, dynamic> _resend(AiField f, SubmittedField s) => switch (s.verificationState) {
        'corrected' => {'field_key': f.fieldKey, 'verification_state': 'corrected', 'value': s.value},
        'unreadable' => {
            'field_key': f.fieldKey,
            'verification_state': 'unreadable',
            'unreadable_reason': s.unreadableReason,
            if (s.note != null && s.note!.isNotEmpty) 'note': s.note,
          },
        'left_empty' => {'field_key': f.fieldKey, 'verification_state': 'left_empty'},
        _ => {'field_key': f.fieldKey, 'verification_state': 'accepted'},
      };
}
