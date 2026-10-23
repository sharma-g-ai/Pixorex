import 'models.dart';

/// Deliberately conservative: require the printed Article anchor. Never infer
/// an article from a barcode, a batch, or a similar current-DN number.
class CanArticleReader {
  static final _anchor = RegExp(
    r'\barticle\s*(?:(?:number|no|nr)\.?)?\s*[:#.-]?\s*',
    caseSensitive: false,
  );
  static final _digits = RegExp(r'^\d+(?:[ \t]+\d+)*$');
  static final _value = RegExp(r'^(\d+(?:[ \t]+\d+)*)(?=\s+[A-Za-z]|$)');

  Set<String> candidates({
    required List<OcrElement> lines,
    required Set<String> dnArticles,
    required int width,
    required int height,
  }) {
    bool usable(OcrElement line) =>
        line.height >= 10 &&
        line.left > 2 &&
        line.top > 2 &&
        line.right < width - 2 &&
        line.bottom < height - 2 &&
        (line.confidence == null || line.confidence! >= .7);
    String? number(String text) {
      final match = _value.firstMatch(text.trim());
      if (match == null) return null;
      final raw = match.group(1)!;
      final parts = raw.split(RegExp(r'\s+'));
      final joined = parts.join();
      // Joining split digits requires an exact DN match, never an invented ID.
      return parts.length == 1 || dnArticles.contains(joined) ? joined : null;
    }

    final found = <String>{};
    for (final anchor in lines.where(usable)) {
      final match = _anchor.firstMatch(anchor.text);
      if (match == null) continue;
      final tail = anchor.text.substring(match.end).trim();
      if (tail.isNotEmpty) {
        final candidate = number(tail);
        if (candidate != null) found.add(candidate);
        continue;
      }
      // ML Kit can split Article / no. / digits across adjacent OCR lines.
      final neighbours = lines.where((line) {
        if (identical(line, anchor) || !usable(line)) return false;
        final h = anchor.height;
        final right =
            (line.centerY - anchor.centerY).abs() < h &&
            line.left >= anchor.right - h &&
            line.left - anchor.right < h * 4;
        final below =
            line.top >= anchor.bottom - 2 &&
            line.top - anchor.bottom < h * 3 &&
            (line.left - anchor.left).abs() < h * 3;
        return right || below;
      });
      for (final line in neighbours) {
        final distractor = lines.any(
          (other) =>
              RegExp(
                r'\b(?:batch|ean|barcode|ufi|un|date|voc|shade)\b',
                caseSensitive: false,
              ).hasMatch(other.text) &&
              (other.centerY - line.centerY).abs() < line.height &&
              other.right <= line.left &&
              line.left - other.right < line.height * 5,
        );
        if (distractor) continue;
        var text = line.text.trim().replaceFirst(
          RegExp(r'^(?:no|nr)\.?\s*[:#]?\s*', caseSensitive: false),
          '',
        );
        if (!_digits.hasMatch(text)) continue;
        final candidate = number(text);
        if (candidate != null) found.add(candidate);
      }
    }
    return found;
  }
}

/// Independent, fresh frames are required; any disagreement clears consensus.
class CanArticleConsensus {
  String? _article;
  DateTime? _lastSeen;
  int _count = 0;
  bool conflict = false;
  String? get candidate => _article;
  int get observations => _count;

  void reset() {
    _article = null;
    _lastSeen = null;
    _count = 0;
    conflict = false;
  }

  String? observe(Set<String> candidates, DateTime now) {
    if (candidates.length != 1) {
      reset();
      conflict = candidates.length > 1;
      return null;
    }
    final next = candidates.single;
    if (_lastSeen != null && now.difference(_lastSeen!).inMilliseconds < 200) {
      return null;
    }
    if (_article != null && _article != next) {
      reset();
      conflict = true;
      return null;
    }
    if (_lastSeen == null || now.difference(_lastSeen!).inSeconds >= 3) {
      _count = 0;
    }
    conflict = false;
    _article = next;
    _lastSeen = now;
    _count++;
    return _count >= 3 ? next : null;
  }
}
