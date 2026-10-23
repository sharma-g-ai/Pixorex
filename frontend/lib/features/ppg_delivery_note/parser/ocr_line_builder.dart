import '../domain/models.dart';

/// Rebuild OCR lines from word-level ML Kit elements using geometry.
class OcrLineBuilder {
  /// Group words whose vertical centers are close into left-to-right lines.
  static List<OcrLine> buildLines(
    List<OcrElement> words, {
    double yToleranceFactor = 0.6,
  }) {
    if (words.isEmpty) return const [];

    final sorted = List<OcrElement>.from(words)
      ..sort((a, b) {
        final dy = a.centerY.compareTo(b.centerY);
        if (dy != 0) return dy;
        return a.left.compareTo(b.left);
      });

    final lines = <List<OcrElement>>[];
    for (final w in sorted) {
      if (lines.isEmpty) {
        lines.add([w]);
        continue;
      }
      final current = lines.last;
      final ref = current.first;
      final tol = (ref.height * yToleranceFactor).clamp(8.0, 28.0);
      if ((w.centerY - ref.centerY).abs() <= tol) {
        current.add(w);
      } else {
        lines.add([w]);
      }
    }

    return lines.map((group) {
      group.sort((a, b) => a.left.compareTo(b.left));
      final text = group.map((e) => e.text.trim()).where((t) => t.isNotEmpty).join(' ');
      final left = group.map((e) => e.left).reduce((a, b) => a < b ? a : b);
      final top = group.map((e) => e.top).reduce((a, b) => a < b ? a : b);
      final right = group.map((e) => e.right).reduce((a, b) => a > b ? a : b);
      final bottom = group.map((e) => e.bottom).reduce((a, b) => a > b ? a : b);
      return OcrLine(
        text: text,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        words: List.unmodifiable(group),
      );
    }).toList();
  }
}

class OcrLine {
  OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.words,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<OcrElement> words;

  OcrElement get asElement => OcrElement(
        text: text,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      );
}
