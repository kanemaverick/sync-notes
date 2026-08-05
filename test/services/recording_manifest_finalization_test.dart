import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sync_notes/services/background_recording_service.dart';

void main() {
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
