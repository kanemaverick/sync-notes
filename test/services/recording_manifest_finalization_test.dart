import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sync_notes/services/background_recording_service.dart';

void main() {
  test('音频已落盘仍需等待最后字幕收尾标记，兼容空录音', () async {
    final root = await Directory.systemTemp.createTemp(
      'sync_notes_final_captions_',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File(p.join(root.path, 'recording_manifest.json'));
    await file.writeAsString(jsonEncode({'segments': [], 'finalized': false}));
    var finished = false;
    final pending = waitForFinalizedRecordingManifest(
      sessionDirectory: root,
      expectedOffsetMs: 0,
      timeout: const Duration(seconds: 1),
      pollInterval: const Duration(milliseconds: 5),
    ).then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(finished, isFalse);
    await file.writeAsString(jsonEncode({'segments': [], 'finalized': true}));
    await pending;
    expect(finished, isTrue);
  });
  test('等待最终音频分片覆盖停止前的录音位置', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sync_notes_manifest_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manifest = File(p.join(directory.path, 'recording_manifest.json'));

    await manifest.writeAsString(
      jsonEncode({
        'segments': [
          {'durationMs': 1000},
        ],
      }),
    );

    final update = Timer(const Duration(milliseconds: 40), () async {
      await manifest.writeAsString(
        jsonEncode({
          'segments': [
            {'durationMs': 1000},
            {'durationMs': 4200},
          ],
        }),
        flush: true,
      );
    });
    addTearDown(update.cancel);

    await waitForFinalizedRecordingManifest(
      sessionDirectory: directory,
      expectedOffsetMs: 5000,
      timeout: const Duration(seconds: 1),
      pollInterval: const Duration(milliseconds: 10),
    );

    expect(update.isActive, isFalse);
  });
}
