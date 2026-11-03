import 'package:flutter/material.dart';

/// How a scan's two statuses read on Home and My Scans (design 14, 47).
class ScanStatusLook {
  const ScanStatusLook(this.label, this.background, this.foreground, {this.needsAction = false});
  final String label;
  final Color background;
  final Color foreground;

  /// Drawn with an orange outline: the technician has something to do.
  final bool needsAction;

  static const _blue = (Color(0xFFEAF0FB), Color(0xFF2E3192));
  static const _grey = (Color(0xFFEEF1F4), Color(0xFF5B6672));
  static const _red = (Color(0xFFFDECEA), Color(0xFFC0392B));

  factory ScanStatusLook.of(String processingStatus, String reviewStatus) => switch (reviewStatus) {
        'approved' => const ScanStatusLook('Approved', Color(0xFFE4F5E5), Color(0xFF2C7A30)),
        'waiting_for_approval' => ScanStatusLook('Submitted', _grey.$1, _blue.$2),
        'rejected' => ScanStatusLook('Rejected', _red.$1, _red.$2, needsAction: true),
        'closed' => ScanStatusLook('Closed', _grey.$1, _grey.$2),
        'discarded' => ScanStatusLook('Discarded', _grey.$1, _grey.$2),
        _ => switch (processingStatus) {
            'ready_to_review' =>
              const ScanStatusLook('Ready to Review', Color(0xFFFCEFD9), Color(0xFFB4540A), needsAction: true),
            'failed' => ScanStatusLook('Extraction failed', _red.$1, _red.$2, needsAction: true),
            'retake_required' => ScanStatusLook('Retake needed', _red.$1, _red.$2, needsAction: true),
            'uploading' => ScanStatusLook('Uploading', _blue.$1, _blue.$2),
            _ => ScanStatusLook('Extracting', _blue.$1, _blue.$2),
          },
      };
}

class ScanStatusPill extends StatelessWidget {
  const ScanStatusPill(this.look, {super.key});
  final ScanStatusLook look;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: look.background, borderRadius: BorderRadius.circular(999)),
        child: Text(look.label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: look.foreground)),
      );
}
