import '../domain/models.dart';
import 'ocr_line_builder.dart';

/// Deterministic PPG delivery-note template parser.
///
/// Accepts word-level ML Kit elements: rebuilds lines first, then parses.
/// Synthetic fixtures with whole-phrase elements still work.
class PpgTemplateParser {
  PpgTemplateParser();

  static final _articleRe = RegExp(r'^\d{4,10}$');
  static final _qtyTokenRe = RegExp(r'^(\d+)\s*PC$', caseSensitive: false);
  static final _pageRe = RegExp(
    r'\b(\d+)\s*(?:/|of)\s*(\d+)\b',
    caseSensitive: false,
  );
  static final _noteRe = RegExp(r'\b(53\d{8})\b');
  static final _pieceRe = RegExp(
    r'\bpieces?\s*[:.]?\s*(\d{1,7})\b',
    caseSensitive: false,
  );
  static final _setHintRe = RegExp(r'\bSET\b', caseSensitive: false);
  static final _eanLikeRe = RegExp(r'^\d{12,14}$');
  static final _materialLikeRe = RegExp(r'[A-Za-z]');
  static final _materialCodeRe = RegExp(r'^(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{8,}$');
  static final _pickingListRe = RegExp(
    r'\bpicking\s*list\b',
    caseSensitive: false,
  );

  ParsedPageResult parse({
    required OcrObservation observation,
    required int printedPageHint,
  }) {
    // The same printed table arrives at different camera resolutions. Scale
    // distances upward with the image instead of treating pixels as paper units.
    final xScale = (observation.imageWidth / 1224).clamp(1.0, 4.0);
    final yScale = (observation.imageHeight / 1584).clamp(1.0, 4.0);
    final words = List<OcrElement>.from(observation.elements);
    final lines = OcrLineBuilder.buildLines(words);
    final workElements = lines.isNotEmpty
        ? lines.map((l) => l.asElement).toList()
        : (List<OcrElement>.from(words)..sort((a, b) {
            final dy = a.top.compareTo(b.top);
            if (dy != 0) return dy;
            return a.left.compareTo(b.left);
          }));

    final fullText = workElements.map((e) => e.text).join(' ');
    final normalized = fullText.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final hasDeliveryTitle = _hasLabel(normalized, 'delivery', 'note');
    final hasTotalQty = _hasLabel(normalized, 'total', 'qty');
    final hasTableAnchors = _hasPpgDeliveryAnchors(workElements);
    final hasPieceLabel = _hasLabel(normalized, 'piece');
    final hasNetWeight = _hasLabel(normalized, 'net', 'weight');
    final hasGrossWeight = _hasLabel(normalized, 'gross', 'weight');
    final hasSummaryAnchors =
        (hasPieceLabel && (hasNetWeight || hasGrossWeight)) ||
        (hasNetWeight && hasGrossWeight);
    final pickingListLayout =
        _pickingListRe.hasMatch(normalized) ||
        (_hasLabel(normalized, 'order', 'qty') &&
            _hasLabel(normalized, 'batch', 'qty') &&
            normalized.contains('material'));
    final headerLines = workElements.where(
      (e) =>
          e.top < observation.imageHeight * 0.25 &&
          e.right > observation.imageWidth * 0.65,
    );
    RegExpMatch? pageMatch;
    for (final line in headerLines) {
      pageMatch = _pageRe.firstMatch(line.text);
      if (pageMatch != null) break;
    }
    final readPrinted = pageMatch == null
        ? null
        : int.tryParse(pageMatch.group(1)!);
    final readDeclared = pageMatch == null
        ? null
        : int.tryParse(pageMatch.group(2)!);
    // Reject implausible OCR counters before they can create a huge checklist.
    final validPageCounter =
        readPrinted != null &&
        readDeclared != null &&
        readPrinted >= 1 &&
        readDeclared >= readPrinted &&
        readDeclared <= 1000;
    final declared = validPageCounter ? readDeclared : null;
    final printed = validPageCounter ? readPrinted : printedPageHint;
    final note = _readDeliveryNoteNumber(lines);
    final pieceCount = int.tryParse(
      _pieceRe.firstMatch(fullText)?.group(1) ?? '',
    );

    if (pickingListLayout) {
      return ParsedPageResult(
        pageCaptureId: observation.pageCaptureId,
        printedPage: printed,
        printedPageDetected: validPageCounter,
        deliveryNoteNumber: note,
        pieceCount: pieceCount,
        declaredPageCount: declared,
        pageRole: 'rejected_non_ppg',
        occurrences: const [],
        issues: const ['Picking List is not supported. Scan a Delivery Note.'],
      );
    }

    if (!hasDeliveryTitle &&
        !hasTotalQty &&
        !hasTableAnchors &&
        !(note != null && validPageCounter && hasSummaryAnchors)) {
      return ParsedPageResult(
        pageCaptureId: observation.pageCaptureId,
        printedPage: printed,
        printedPageDetected: validPageCounter,
        deliveryNoteNumber: note,
        pieceCount: pieceCount,
        declaredPageCount: declared,
        pageRole: 'unverified_layout',
        occurrences: const [],
        issues: const [
          'Could not read enough Delivery Note labels. Check the crop and lighting, then retake this page.',
        ],
      );
    }

    final tableHeaderBottom = _tableHeaderBottom(lines);
    bool isArticleCandidate(OcrElement e) {
      if (tableHeaderBottom == null || e.top <= tableHeaderBottom) {
        return false;
      }
      final article = _extractArticleToken(e.text, note);
      return article != null;
    }

    String articleFrom(OcrElement e) => _extractArticleToken(e.text, note)!;

    final hasProductArticles = workElements.any(isArticleCandidate);

    // The summary can contain other six-digit numbers that look like articles.
    if (!hasTableAnchors &&
        validPageCounter &&
        printed == 1 &&
        (hasSummaryAnchors || (hasDeliveryTitle && hasPieceLabel))) {
      return ParsedPageResult(
        pageCaptureId: observation.pageCaptureId,
        printedPage: printed,
        printedPageDetected: validPageCounter,
        deliveryNoteNumber: note,
        pieceCount: pieceCount,
        declaredPageCount: declared,
        pageRole: 'header',
        occurrences: const [],
        issues: const [],
      );
    }

    if ((hasProductArticles && !hasTableAnchors) ||
        (hasTableAnchors && !hasProductArticles)) {
      return ParsedPageResult(
        pageCaptureId: observation.pageCaptureId,
        printedPage: printed,
        printedPageDetected: validPageCounter,
        deliveryNoteNumber: note,
        pieceCount: pieceCount,
        declaredPageCount: declared,
        pageRole: 'unverified_layout',
        occurrences: const [],
        issues: const [
          'Delivery Note table was only partly read. Check the crop and lighting, then retake this page.',
        ],
      );
    }

    if (!hasProductArticles) {
      return ParsedPageResult(
        pageCaptureId: observation.pageCaptureId,
        printedPage: printed,
        printedPageDetected: validPageCounter,
        deliveryNoteNumber: note,
        pieceCount: pieceCount,
        declaredPageCount: declared,
        pageRole: 'header',
        occurrences: const [],
        issues: const [],
      );
    }

    final qtyBandLeft = _inferQtyBandLeft(workElements, words, xScale, yScale);
    final articleBandLeft = _inferArticleBandLeft(
      workElements.where(isArticleCandidate).toList(),
      qtyBandLeft,
      xScale,
    );
    final descriptionBandLeft = _descriptionBandLeft(words);

    final occurrences = <ParsedOccurrence>[];
    final issues = <String>[];
    final usedQtyKeys = <String>{};

    final articleIndexes = <int>[];
    for (var i = 0; i < workElements.length; i++) {
      if (!isArticleCandidate(workElements[i])) continue;
      if (articleBandLeft != null &&
          (workElements[i].left < articleBandLeft - 80 * xScale ||
              workElements[i].left > articleBandLeft + 180 * xScale)) {
        continue;
      }
      articleIndexes.add(i);
    }

    for (final ai in articleIndexes) {
      final articleEl = workElements[ai];
      final article = articleFrom(articleEl);

      final description = _nearestDescriptionAbove(
        lines,
        articleEl,
        qtyBandLeft,
        descriptionBandLeft,
        xScale,
        yScale,
      );
      final context = description?.text;
      final isSet = context != null && _setHintRe.hasMatch(context);

      if (isSet) {
        occurrences.add(
          ParsedOccurrence(
            occurrenceId: _occurrenceId(observation.pageCaptureId, ai, article),
            pageCaptureId: observation.pageCaptureId,
            sourcePage: printed,
            articleNumber: article,
            role: OccurrenceRole.setHeaderNoPrintedQuantity,
            documentQuantity: null,
            productContext: context,
            blockTop: articleEl.top - 40 * yScale,
            blockBottom: articleEl.bottom + 10 * yScale,
          ),
        );
        continue;
      }

      // On the printed PPG table the Total Qty can sit on the description
      // line well above the article code. Keep enough room for that vertical
      // separation; `_associateTotalQty` still limits candidates to this
      // article block and rejects quantities below the article baseline
      // (where the Qty per Batch detail is printed).
      final blockTop = (articleEl.top - 180 * yScale).clamp(0, articleEl.top);
      final nextArticleTop = _nextArticleTop(
        workElements,
        ai,
        isArticleCandidate,
      );
      final blockBottom = nextArticleTop != null
          ? (nextArticleTop + articleEl.bottom) / 2
          : articleEl.bottom + 70 * yScale;

      // Batch exclusion only *inside this product block*, under the article line.
      if (_isBatchDetailArticleInBlock(
        workElements: workElements,
        articleEl: articleEl,
        blockTop: blockTop.toDouble(),
        blockBottom: blockBottom,
        yScale: yScale,
      )) {
        continue;
      }

      final qty = _associateTotalQty(
        elements: workElements,
        words: words,
        articleEl: articleEl,
        qtyBandLeft: qtyBandLeft,
        usedQtyKeys: usedQtyKeys,
        descriptionCenterY: description?.centerY,
        blockTop: blockTop.toDouble(),
        blockBottom: blockBottom,
        xScale: xScale,
        yScale: yScale,
      );

      final occurrenceId = _occurrenceId(
        observation.pageCaptureId,
        ai,
        article,
      );
      final fieldRead = observation.fieldQuantityReads[occurrenceId];
      if (fieldRead != null) {
        occurrences.add(
          ParsedOccurrence(
            occurrenceId: occurrenceId,
            pageCaptureId: observation.pageCaptureId,
            sourcePage: printed,
            articleNumber: article,
            role: OccurrenceRole.quantityBearing,
            documentQuantity: fieldRead,
            productContext: context,
            blockTop: blockTop.toDouble(),
            blockBottom: blockBottom,
            rowCenterY: description?.centerY,
            quantityColumnLeft: qtyBandLeft,
          ),
        );
        continue;
      }

      if (qty == null) {
        occurrences.add(
          ParsedOccurrence(
            occurrenceId: _occurrenceId(observation.pageCaptureId, ai, article),
            pageCaptureId: observation.pageCaptureId,
            sourcePage: printed,
            articleNumber: article,
            role: OccurrenceRole.unresolved,
            documentQuantity: null,
            productContext: context,
            issues: const ['UNRESOLVED_MISSING_TOTAL_QTY'],
            blockTop: blockTop.toDouble(),
            blockBottom: blockBottom,
            rowCenterY: description?.centerY,
            quantityColumnLeft: qtyBandLeft,
          ),
        );
        issues.add('Missing Total Qty for article $article');
        continue;
      }

      if (_isSuspiciousFusedQty(
        qty.value,
        context,
        qty.left,
        qtyBandLeft,
        xScale,
      )) {
        occurrences.add(
          ParsedOccurrence(
            occurrenceId: _occurrenceId(observation.pageCaptureId, ai, article),
            pageCaptureId: observation.pageCaptureId,
            sourcePage: printed,
            articleNumber: article,
            role: OccurrenceRole.unresolved,
            documentQuantity: null,
            productContext: context,
            issues: const ['AMBIGUOUS_COLOUR_QTY_BOUNDARY'],
            blockTop: blockTop.toDouble(),
            blockBottom: blockBottom,
            rowCenterY: description?.centerY,
            quantityColumnLeft: qtyBandLeft,
            suspectedQuantity: qty.value,
          ),
        );
        issues.add('Ambiguous quantity near colour text for $article');
        continue;
      }

      usedQtyKeys.add(qty.key);
      occurrences.add(
        ParsedOccurrence(
          occurrenceId: _occurrenceId(observation.pageCaptureId, ai, article),
          pageCaptureId: observation.pageCaptureId,
          sourcePage: printed,
          articleNumber: article,
          role: OccurrenceRole.quantityBearing,
          documentQuantity: qty.value,
          productContext: context,
          blockTop: blockTop.toDouble(),
          blockBottom: blockBottom,
          rowCenterY: description?.centerY,
          quantityColumnLeft: qtyBandLeft,
        ),
      );
    }

    return ParsedPageResult(
      pageCaptureId: observation.pageCaptureId,
      printedPage: printed,
      printedPageDetected: validPageCounter,
      deliveryNoteNumber: note,
      pieceCount: pieceCount,
      declaredPageCount: declared,
      pageRole: 'product_table',
      occurrences: occurrences,
      issues: issues,
    );
  }

  String _occurrenceId(
    String pageCaptureId,
    int sourceLineIndex,
    String article,
  ) => '$pageCaptureId:$sourceLineIndex:$article';

  bool _hasPpgDeliveryAnchors(List<OcrElement> elements) {
    final joined = elements.map((e) => e.text.toLowerCase()).join(' ');
    final normalized = joined.replaceAll(RegExp(r'\s+'), ' ');
    final hasTotalQty = _hasLabel(normalized, 'total', 'qty');
    final hasItem = _hasLabel(normalized, 'item');
    final hasDescription = _hasLabel(normalized, 'description');
    return hasTotalQty || (hasItem && hasDescription);
  }

  String? _readDeliveryNoteNumber(List<OcrLine> lines) {
    for (final line in lines) {
      final label = RegExp(
        r'delivery[\W_]*note',
        caseSensitive: false,
      ).firstMatch(line.text);
      if (label == null) continue;
      final onLabelLine = _noteRe
          .firstMatch(line.text.substring(label.end))
          ?.group(1);
      if (onLabelLine != null) return onLabelLine;
      // The number can be a separate OCR line just below the printed label.
      for (final nearby in lines) {
        if (identical(nearby, line)) continue;
        if (nearby.top < line.top - 5 || nearby.top > line.bottom + 45) {
          continue;
        }
        if (nearby.left < line.left - 20) continue;
        if (_hasLabel(nearby.text.toLowerCase(), 'order')) continue;
        final number = _noteRe.firstMatch(nearby.text)?.group(1);
        if (number != null) return number;
      }
    }
    // A bare number is usable only when it is unambiguous and not labelled
    // as an Order number elsewhere on the page.
    final candidates = <String>{};
    for (final line in lines) {
      if (_hasLabel(line.text.toLowerCase(), 'order')) continue;
      final nearOrderLabel = lines.any(
        (other) =>
            _hasLabel(other.text.toLowerCase(), 'order') &&
            (other.top - line.top).abs() <= 45 &&
            line.left >= other.left - 20,
      );
      if (nearOrderLabel) continue;
      for (final match in _noteRe.allMatches(line.text)) {
        candidates.add(match.group(1)!);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  double? _tableHeaderBottom(List<OcrLine> lines) {
    for (final line in lines) {
      final text = line.text.toLowerCase();
      if (_hasLabel(text, 'total', 'qty') ||
          (_hasLabel(text, 'item') && _hasLabel(text, 'description'))) {
        return line.bottom;
      }
    }
    return null;
  }

  double? _descriptionBandLeft(List<OcrElement> words) {
    for (final word in words) {
      if (_hasLabel(word.text.toLowerCase(), 'description')) {
        return word.left;
      }
    }
    return null;
  }

  bool _hasLabel(String text, String first, [String? second]) {
    final label = second == null ? first : '$first[\\W_]*$second';
    return RegExp('(?<![a-z])$label(?![a-z])').hasMatch(text);
  }

  double? _inferQtyBandLeft(
    List<OcrElement> lines,
    List<OcrElement> words,
    double xScale,
    double yScale,
  ) {
    // Anchor to the OCR word box, never to the midpoint of a whole table row.
    for (final e in words) {
      if (_hasLabel(e.text.trim().toLowerCase(), 'total', 'qty')) {
        return e.left;
      }
    }
    for (final total in words.where(
      (e) => e.text.trim().toLowerCase() == 'total',
    )) {
      for (final qty in words.where(
        (e) => e.text.trim().toLowerCase() == 'qty',
      )) {
        if (qty.left >= total.right &&
            qty.left - total.right < 80 * xScale &&
            (qty.centerY - total.centerY).abs() < 25 * yScale) {
          return total.left;
        }
      }
    }
    final qtyEls = <OcrElement>[];
    for (final e in words) {
      if (_parseQty(e.text) != null) qtyEls.add(e);
    }
    // Also digit+PC word pairs
    for (var i = 0; i < words.length - 1; i++) {
      if (RegExp(r'^\d+$').hasMatch(words[i].text.trim()) &&
          words[i + 1].text.trim().toUpperCase() == 'PC') {
        qtyEls.add(words[i]);
      }
    }
    if (qtyEls.isEmpty) return null;
    return qtyEls.map((e) => e.left).reduce((a, b) => a + b) / qtyEls.length;
  }

  double? _inferArticleBandLeft(
    List<OcrElement> elements,
    double? qtyBand,
    double xScale,
  ) {
    final candidates = elements.where((e) {
      final t = e.text.trim();
      final m = _articleRe.firstMatch(t);
      if (m == null) return false;
      final a = m.group(0)!;
      return !_eanLikeRe.hasMatch(a) && a.length < 8;
    }).toList();
    if (candidates.isEmpty) return null;
    if (qtyBand != null) {
      final leftOfQty = candidates
          .where((e) => e.centerX < qtyBand - 20 * xScale)
          .toList();
      if (leftOfQty.isNotEmpty) {
        return leftOfQty.map((e) => e.left).reduce((a, b) => a + b) /
            leftOfQty.length;
      }
    }
    return candidates.map((e) => e.left).reduce((a, b) => a + b) /
        candidates.length;
  }

  /// Prefer a leading short numeric article token on the line.
  String? _extractArticleToken(String text, String? note) {
    final tokens = text.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty) return null;
    final token = tokens.first;
    if (!_articleRe.hasMatch(token)) return null;
    if (_eanLikeRe.hasMatch(token)) return null;
    if (note != null && token == note) return null;
    if (token.length >= 8) return null;
    if (_materialLikeRe.hasMatch(token)) return null;
    return token;
  }

  ({String text, double centerY})? _nearestDescriptionAbove(
    List<OcrLine> lines,
    OcrElement article,
    double? qtyBandLeft,
    double? descriptionBandLeft,
    double xScale,
    double yScale,
  ) {
    OcrLine? best;
    String? bestText;
    for (final line in lines) {
      if (line.bottom > article.top + 8 * yScale ||
          article.top - line.bottom > 180 * yScale) {
        continue;
      }
      final rightLimit = qtyBandLeft == null
          ? article.right + 250 * xScale
          : qtyBandLeft - 20 * xScale;
      final leftLimit =
          (descriptionBandLeft ?? article.left - 80 * xScale) - 15 * xScale;
      final selected = line.words
          .where((w) => w.left < rightLimit && w.right >= leftLimit)
          .toList();
      final raw = selected.map((w) => w.text).join(' ').trim();
      if (raw.isEmpty || _extractArticleToken(raw, null) != null) continue;
      final tokens = raw.split(RegExp(r'\s+'));
      final materialIndex = tokens.indexWhere(
        (token) => _materialCodeRe.hasMatch(token),
      );
      final descriptionText =
          (materialIndex < 0 ? tokens : tokens.take(materialIndex)).join(' ');
      final candidate = descriptionText
          .replaceFirst(RegExp(r'^\d{1,3}\s+'), '')
          .replaceAll(RegExp(r'\b\d+\s*PC\b', caseSensitive: false), '')
          .trim();
      if (candidate.length < 3 ||
          candidate.toLowerCase().contains('qty per batch') ||
          candidate.toLowerCase().contains('total qty') ||
          candidate.toLowerCase().contains('description')) {
        continue;
      }
      if (best == null || line.bottom > best.bottom) {
        best = line;
        bestText = candidate;
      }
    }
    if (best == null || bestText == null) return null;
    return (text: bestText, centerY: (best.top + best.bottom) / 2);
  }

  double? _nextArticleTop(
    List<OcrElement> elements,
    int currentIndex,
    bool Function(OcrElement) isArticle,
  ) {
    for (var i = currentIndex + 1; i < elements.length; i++) {
      if (isArticle(elements[i])) return elements[i].top;
    }
    return null;
  }

  /// Batch rows sit *under* an article within its block, near "Qty per Batch".
  /// A page-level table header "Qty per Batch" above all products must NOT
  /// mark every product article as batch detail.
  bool _isBatchDetailArticleInBlock({
    required List<OcrElement> workElements,
    required OcrElement articleEl,
    required double blockTop,
    required double blockBottom,
    required double yScale,
  }) {
    // Look for a batch hint that is *inside this block* and *at or below*
    // the article baseline (detail lines), not the distant column header.
    OcrElement? localBatchHint;
    for (final e in workElements) {
      final t = e.text.toLowerCase();
      if (!(t.contains('qty per batch') ||
          (t.contains('batch') && t.contains('qty')))) {
        continue;
      }
      if (e.top < blockTop || e.bottom > blockBottom + 40 * yScale) continue;
      // Column header is usually near the top of the page table, far above
      // this article. Local batch detail is below the article line.
      if (e.top >= articleEl.top - 5 * yScale) {
        localBatchHint = e;
        break;
      }
    }
    if (localBatchHint == null) return false;
    // Article itself is the product key above batch lines — not a batch article.
    // Only skip if the article is *below* the local batch hint (unusual) or
    // shares the batch-detail band without a description (no product name).
    if (articleEl.top > localBatchHint.bottom) return true;
    return false;
  }

  int? _parseQty(String text) {
    final m = _qtyTokenRe.firstMatch(text.trim());
    if (m != null) return int.parse(m.group(1)!);
    // "15 PC" inside a longer line
    final embedded = RegExp(
      r'\b(\d+)\s*PC\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (embedded != null) return int.parse(embedded.group(1)!);
    return null;
  }

  ({int value, String key, double left})? _associateTotalQty({
    required List<OcrElement> elements,
    required List<OcrElement> words,
    required OcrElement articleEl,
    required double? qtyBandLeft,
    required Set<String> usedQtyKeys,
    required double? descriptionCenterY,
    required double blockTop,
    required double blockBottom,
    required double xScale,
    required double yScale,
  }) {
    ({int value, String key, double left, double score})? best;

    void consider(OcrElement e, int value, String key, {double? qtyX}) {
      if (usedQtyKeys.contains(key)) return;
      final x = qtyX ?? e.right;
      if (qtyBandLeft != null && x < qtyBandLeft - 80 * xScale) return;
      if (x < articleEl.centerX - 20 * xScale) return;
      // Prefer qty on description baseline (above article) within the block.
      if (e.centerY < blockTop - 20 * yScale || e.centerY > blockBottom) return;
      // The receiving quantity is printed on the product-description row.
      // A batch quantity may share the Total Qty column's x-coordinate, so
      // associate by the row baseline before considering vertical proximity
      // to the article code.
      if (descriptionCenterY != null &&
          (e.centerY - descriptionCenterY).abs() > 35 * yScale) {
        return;
      }
      final verticalGap = articleEl.centerY - e.centerY;
      if (verticalGap < -40 * yScale || verticalGap > 220 * yScale) return;

      var score = 100.0 - verticalGap.abs();
      if (verticalGap >= 0 && verticalGap <= 60 * yScale) score += 45;
      if (e.top < articleEl.top) score += 30;
      // Penalize qty well below article (batch lines).
      if (e.top > articleEl.bottom + 15 * yScale) score -= 50;

      if (best == null || score > best!.score) {
        best = (value: value, key: key, left: e.left, score: score);
      }
    }

    for (var i = 0; i < words.length; i++) {
      final e = words[i];
      final value = _parseQty(e.text);
      if (value == null) continue;
      // If qty is embedded in a wide description line, assume it sits on the right.
      final qtyX =
          e.text.trim().toUpperCase().endsWith('PC') ||
              e.text.contains(RegExp(r'\d+\s*PC', caseSensitive: false))
          ? e.right
          : e.left;
      consider(e, value, 'qty_$i:${e.left}:${e.top}:$value', qtyX: qtyX);
    }

    // Word-level digit + PC pairs
    final sortedWords = List<OcrElement>.from(words)
      ..sort((a, b) {
        final dy = a.centerY.compareTo(b.centerY);
        if (dy != 0) return dy;
        return a.left.compareTo(b.left);
      });
    for (var i = 0; i < sortedWords.length - 1; i++) {
      final a = sortedWords[i];
      final b = sortedWords[i + 1];
      if (!RegExp(r'^\d+$').hasMatch(a.text.trim())) continue;
      if (b.text.trim().toUpperCase() != 'PC') continue;
      if ((a.centerY - b.centerY).abs() > 25 * yScale) continue;
      if (b.left - a.right > 50 * xScale) continue;
      final value = int.parse(a.text.trim());
      consider(a, value, 'word_${a.left}_${a.top}_$value', qtyX: a.left);
    }

    return best == null
        ? null
        : (value: best!.value, key: best!.key, left: best!.left);
  }

  bool _isSuspiciousFusedQty(
    int qty,
    String? context,
    double qtyLeft,
    double? qtyBandLeft,
    double xScale,
  ) {
    if (context == null) return false;
    if (qty >= 10 &&
        qty <= 99 &&
        RegExp(
          r'\b(RED|BLUE|GREEN|GREY|GRAY|YEL)\b',
          caseSensitive: false,
        ).hasMatch(context)) {
      if (qtyBandLeft != null && qtyLeft >= qtyBandLeft - 20 * xScale) {
        return false;
      }
      final ones = qty % 10;
      final tens = qty ~/ 10;
      if (ones > 0 && tens >= 1 && tens <= 6) return true;
    }
    return false;
  }
}
