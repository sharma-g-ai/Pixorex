// MLKit document-scanner research benchmark (Android only, needs a person).
//
// Pick a delivery note and a scanner mode, scan every page in one pass, and
// each returned page is OCR'd through the app's `ppg_ocr` channel. Pages are
// saved as DN<n>_<dn>_p<page>_scan-<mode>.jpg with MLKit output and timings in
// <app external files>/mlkit_bench/results/scanner_<mode>/, ready for
// mlkit_research/tools/score.py.
//
//   flutter run -t tool/doc_scanner_benchmark.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _scanner = MethodChannel('com.amzur.equiptrack/document_scanner');
const _ocr = MethodChannel('com.amzur.equiptrack/ppg_ocr');

const _notes = {
  'DN1': (number: '5319358250', pages: 6),
  'DN2': (number: '5319364114', pages: 4),
};
const _modes = {'base': 'BASE', 'base_with_filter': 'FILTER', 'full': 'FULL'};

void main() => runApp(const MaterialApp(home: _ScannerBenchmark()));

class _ScannerBenchmark extends StatefulWidget {
  const _ScannerBenchmark();

  @override
  State<_ScannerBenchmark> createState() => _ScannerBenchmarkState();
}

class _ScannerBenchmarkState extends State<_ScannerBenchmark> {
  String _note = 'DN1';
  bool _busy = false;
  final _log = <String>[];

  /// Next printed page per note + mode, so one page per scan still numbers
  /// pages 1, 2, 3… instead of restarting at 1 and overwriting.
  final _nextPage = <String, int>{};
  int _next(String mode) => _nextPage['$_note-$mode'] ?? 1;

  Future<void> _run(String mode) async {
    final note = _notes[_note]!;
    setState(() => _busy = true);
    try {
      final firstPage = _next(mode);
      final scanWatch = Stopwatch()..start();
      final paths = await _scanner.invokeListMethod<String>(
        'scanDocumentPages',
        {'pageLimit': note.pages - firstPage + 1, 'mode': mode},
      );
      final scanMs = scanWatch.elapsedMilliseconds;
      if (paths == null) {
        setState(() => _log.insert(0, '$_note ${_modes[mode]}: cancelled'));
        return;
      }

      final root = (await getExternalStorageDirectory())!.path;
      final results = Directory('$root/mlkit_bench/results/scanner_$mode')..createSync(recursive: true);
      var ocrTotalMs = 0;
      for (var i = 0; i < paths.length; i++) {
        final name = '${_note}_${note.number}_p${firstPage + i}_scan-$mode';
        final image = File(paths[i]).copySync('${results.path}/$name.jpg');
        final watch = Stopwatch()..start();
        final out = await _ocr.invokeMapMethod<String, dynamic>(
          'recognize',
          {'imagePath': image.path, 'includeSymbols': false},
        );
        final roundTripMs = watch.elapsedMilliseconds;
        ocrTotalMs += roundTripMs;
        File('${results.path}/$name.json').writeAsStringSync(jsonEncode({
          'image': '$name.jpg',
          'runs': [
            {
              'roundTripMs': roundTripMs,
              'decodeMs': out!['decodeMs'] as int? ?? -1,
              'ocrMs': out['ocrMs'] as int? ?? -1,
              'packMs': out['packMs'] as int? ?? -1,
            },
          ],
          'output': out,
        }));
      }

      // One summary per mode folder; each scan appends its timings.
      final summaryFile = File('${results.path}/_summary.json');
      final summary = summaryFile.existsSync()
          ? jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>
          : {
              'device': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
              'coldStartMs': -1,
              'runsPerImage': 1,
              'scans': <dynamic>[],
            };
      _nextPage['$_note-$mode'] = firstPage + paths.length;
      (summary['scans'] as List).add({
        'note': _note,
        'mode': mode,
        'firstPage': firstPage,
        'pagesExpected': note.pages,
        'pagesReturned': paths.length,
        'scanMs': scanMs,
        'ocrTotalMs': ocrTotalMs,
      });
      summaryFile.writeAsStringSync(jsonEncode(summary));

      setState(() => _log.insert(
            0,
            '$_note ${_modes[mode]}: ${paths.length}/${note.pages} pages · '
            'scan ${(scanMs / 1000).toStringAsFixed(1)} s · OCR ${(ocrTotalMs / 1000).toStringAsFixed(1)} s',
          ));
      debugPrint('SCANNER_BENCH_SAVED $_note $mode ${paths.length} $scanMs $ocrTotalMs');
    } on PlatformException catch (e) {
      setState(() => _log.insert(0, '$_note ${_modes[mode]}: error ${e.code} ${e.message}'));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _notes[_note]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Document scanner benchmark')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: [for (final k in _notes.keys) ButtonSegment(value: k, label: Text(k))],
              selected: {_note},
              onSelectionChanged: _busy ? null : (s) => setState(() => _note = s.first),
            ),
            const SizedBox(height: 8),
            Text('Scan the pages in order (all in one pass, or one per scan), then tap Done.'),
            const SizedBox(height: 16),
            for (final entry in _modes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  onPressed: _busy || _next(entry.key) > note.pages ? null : () => _run(entry.key),
                  child: Text('Scan $_note with ${entry.value} mode · from page ${_next(entry.key)} of ${note.pages}'),
                ),
              ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _nextPage.removeWhere((k, _) => k.startsWith('$_note-'))),
              child: Text('Start $_note again from page 1'),
            ),
            const Divider(height: 32),
            Expanded(child: ListView(children: [for (final line in _log) Text(line)])),
          ],
        ),
      ),
    );
  }
}
