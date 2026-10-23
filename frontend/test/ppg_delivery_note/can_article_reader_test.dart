import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/can_article_reader.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';

OcrElement line(
  String text, {
  double x = 20,
  double y = 20,
  double right = 260,
  double confidence = .95,
}) => OcrElement(
  text: text,
  left: x,
  top: y,
  right: right,
  bottom: y + 20,
  confidence: confidence,
);

void main() {
  final reader = CanArticleReader();
  const articles = {
    '00240476',
    '121186',
    '00464138',
    '00220294',
    '30082418',
    '00121186',
    '30013603',
  };
  Set<String> read(List<OcrElement> lines) => reader.candidates(
    lines: lines,
    dnArticles: articles,
    width: 1000,
    height: 1000,
  );

  test(
    'all supplied article strings are preserved exactly with anchor variations',
    () {
      for (final article in articles) {
        for (final anchor in [
          'Article no.',
          'ARTICLE NO : ',
          'Article ',
          'Article No.',
        ]) {
          expect(read([line('$anchor$article')]), {article});
        }
      }
      expect(read([line('Article no. 0046 4138')]), {'00464138'});
    },
  );
  test(
    'distractors, low confidence and image-edge clipping cannot form a candidate',
    () {
      for (final text in [
        'Batch 00464138',
        'EAN 00464138',
        'UN1263',
        'UFI 00464138',
        '00464138',
        'Article no. 00464138X',
      ]) {
        expect(read([line(text)]), isEmpty);
      }
      expect(read([line('Article no. 00464138', confidence: .4)]), isEmpty);
      expect(read([line('Article no. 00464138', x: 0)]), isEmpty);
      expect(read([line('Article no. 00464138', right: 999)]), isEmpty);
    },
  );
  test(
    'nearby split anchor and digits work without selecting labelled batch numbers',
    () {
      expect(
        read([
          line('Article', right: 95),
          line('no.', y: 42, right: 50),
          line('00464138', y: 65),
        ]),
        {'00464138'},
      );
      expect(
        read([
          line('Article no.', right: 150),
          line('00464138', x: 170, right: 300),
        ]),
        {'00464138'},
      );
      expect(
        read([
          line('Article no.', right: 150),
          line('Batch', y: 48, right: 90),
          line('00464138', x: 100, y: 48),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'unknown anchored articles remain exact candidates and conflicts stay visible',
    () {
      expect(read([line('Article no. 00464188')]), {'00464188'});
      expect(
        read([
          line('Article no. 00464138'),
          line('Article no. 00464188', y: 100),
        ]),
        {'00464138', '00464188'},
      );
    },
  );
  test(
    'three fresh frames required; conflicts and unreadable frames reset agreement',
    () {
      final consensus = CanArticleConsensus();
      final start = DateTime.utc(2026);
      DateTime at(int ms) => start.add(Duration(milliseconds: ms));
      expect(consensus.observe({'00464138'}, at(0)), isNull);
      expect(consensus.observe({'00464138'}, at(650)), isNull);
      expect(consensus.observe({'00464188'}, at(1300)), isNull);
      expect(consensus.conflict, isTrue);
      expect(consensus.observe({'00464138'}, at(1950)), isNull);
      expect(consensus.observe({}, at(2600)), isNull);
      expect(consensus.observe({'00464138'}, at(3250)), isNull);
      expect(consensus.observe({'00464138'}, at(3900)), isNull);
      expect(consensus.observe({'00464138'}, at(4550)), '00464138');
      consensus.reset();
      expect(consensus.observe({'121186', '00121186'}, at(5200)), isNull);
      expect(consensus.conflict, isTrue);
    },
  );
  test('duplicate timestamps and stale observations never verify', () {
    final consensus = CanArticleConsensus();
    final start = DateTime.utc(2026);
    expect(consensus.observe({'121186'}, start), isNull);
    expect(consensus.observe({'121186'}, start), isNull);
    expect(
      consensus.observe({'121186'}, start.add(const Duration(seconds: 4))),
      isNull,
    );
    expect(consensus.observations, 1);
  });
}
