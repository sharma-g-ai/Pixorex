// MLKit research benchmark (Android only).
//
// Every sub-folder of <app external files>/mlkit_bench/images is one image
// set. Each image runs through the same `ppg_ocr` channel the delivery-note
// flow uses; the raw MLKit output plus timings go to
// <app external files>/mlkit_bench/results/<set>/. A set whose name ends in
// `_nosym` asks the plugin to skip symbol geometry.
//
//   flutter run -t tool/mlkit_benchmark.dart
//
// Score the pulled results with mlkit_research/tools/score.py.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('com.amzur.equiptrack/ppg_ocr');

/// Repeats per image; the first run's output is kept, every run's timing is.
const _runsPerImage = 3;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier<String>('Starting…');
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, text, _) => Text(text, textAlign: TextAlign.center),
        ),
      ),
    ),
  ));

  final root = Directory('${(await getExternalStorageDirectory())!.path}/mlkit_bench');
  final sets = Directory('${root.path}/images').listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // The first call loads the model; record it separately as cold start.
  final firstImage = _images(sets.first).first;
  final coldWatch = Stopwatch()..start();
  await _recognize(firstImage.path, includeSymbols: true);
  final coldStartMs = coldWatch.elapsedMilliseconds;

  var total = 0;
  for (final set in sets) {
    final setName = set.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final includeSymbols = !setName.endsWith('_nosym');
    final images = _images(set);
    final results = Directory('${root.path}/results/$setName')..createSync(recursive: true);

    final summary = <Map<String, Object?>>[];
    for (var i = 0; i < images.length; i++) {
      final name = images[i].uri.pathSegments.last;
      status.value = 'MLKit benchmark\n$setName\n${i + 1} / ${images.length}\n$name';

      Map<String, dynamic>? firstOutput;
      final runs = <Map<String, int>>[];
      for (var r = 0; r < _runsPerImage; r++) {
        final watch = Stopwatch()..start();
        final out = await _recognize(images[i].path, includeSymbols: includeSymbols);
        runs.add({
          'roundTripMs': watch.elapsedMilliseconds,
          'decodeMs': out['decodeMs'] as int? ?? -1,
          'ocrMs': out['ocrMs'] as int? ?? -1,
          'packMs': out['packMs'] as int? ?? -1,
        });
        firstOutput ??= out;
      }
      File('${results.path}/${name.replaceAll('.jpg', '.json')}')
          .writeAsStringSync(jsonEncode({'image': name, 'runs': runs, 'output': firstOutput}));
      summary.add({'image': name, 'runs': runs});
    }

    File('${results.path}/_summary.json').writeAsStringSync(jsonEncode({
      'set': setName,
      'includeSymbols': includeSymbols,
      'device': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'coldStartMs': coldStartMs,
      'runsPerImage': _runsPerImage,
      'images': summary,
    }));
    total += images.length;
  }
  status.value = 'Done: $total images in ${sets.length} sets';
  // Marker the PC-side script waits for in logcat.
  debugPrint('MLKIT_BENCH_DONE $total');
}

List<File> _images(Directory set) => set
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.jpg'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

Future<Map<String, dynamic>> _recognize(String path, {required bool includeSymbols}) async {
  final out = await _channel.invokeMapMethod<String, dynamic>(
    'recognize',
    {'imagePath': path, 'includeSymbols': includeSymbols},
  );
  return out!;
}
