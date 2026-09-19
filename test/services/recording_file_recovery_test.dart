import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/background_recording_service.dart';
import 'package:sync_notes/services/recording_file_recovery.dart';

void main() {
  late Directory root;
  late Directory audio;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('recording_recovery_');
    audio = await Directory('${root.path}/audio').create();
  });
  tearDown(() => root.delete(recursive: true));
  Future<File> wav(int sequence, int ms, {bool staleHeader = false}) async {
    final file = File(
      '${audio.path}/segment_${sequence.toString().padLeft(4, '0')}.wav',
    );
    final length = ms * 32;
    await file.writeAsBytes([
      ...createWavHeader(dataLength: staleHeader ? 0 : length),
      ...List.filled(length, sequence + 1),
    ]);
    return file;
  }

  Future<Map<String, dynamic>> recover() =>
      reconcileRecordingFiles(directory: root, sessionId: 'qa');

  test('清单没有当前WAV时仍恢复时长，下一分片不覆盖原音频', () async {
    final first = await wav(0, 1000);
    final original = await first.readAsBytes();
    await File('${root.path}/recording_manifest.json').writeAsString(
      jsonEncode({'segments': [], 'events': [], 'transcripts': []}),
    );
    final recovered = await recover();
    expect((recovered['segments'] as List).single['durationMs'], 1000);
    final reserved = await reserveAudioFile(
      audio,
      recovered['nextSequence'] as int,
    );
    expect(reserved.sequence, 1);
    expect(await first.readAsBytes(), original);
  });
  test('多次中断继续累加音频，重复恢复幂等', () async {
    await wav(0, 1000);
    await recover();
    await wav(1, 2000);
    final result = await recover();
    expect((result['segments'] as List).map((e) => e['timelineStartMs']), [
      0,
      1000,
    ]);
    expect((result['segments'] as List).map((e) => e['durationMs']), [
      1000,
      2000,
    ]);
    expect(result['nextSequence'], 2);
    expect(await recover(), result);
  });
  test('按实际PCM修复落后WAV头，不改变payload或文件长度', () async {
    final file = await wav(0, 1500, staleHeader: true);
    final before = await file.readAsBytes();
    final result = await recover();
    final after = await file.readAsBytes();
    expect(after.length, before.length);
    expect(after.sublist(44), before.sublist(44));
    expect(ByteData.sublistView(after).getUint32(40, Endian.little), 48000);
    expect((result['segments'] as List).single['durationMs'], 1500);
  });
  test('已登记但时长错误也以WAV实际数据纠正，保留字幕和事件', () async {
    final file = await wav(0, 1000);
    await File('${root.path}/recording_manifest.json').writeAsString(
      jsonEncode({
        'segments': [
          {'filePath': file.path, 'durationMs': 8000},
        ],
        'events': [
          {'title': '重点'},
        ],
        'transcripts': [
          {'text': 'PPT'},
        ],
      }),
    );
    final data = await recover();
    expect((data['segments'] as List).single['durationMs'], 1000);
    expect((data['events'] as List).single['title'], '重点');
    expect((data['transcripts'] as List).single['text'], 'PPT');
  });
  test('清单损坏仍保留备份；空文件及编号空洞不能导致覆盖', () async {
    await wav(4, 1000);
    await File('${audio.path}/segment_0007.wav').create();
    await File('${root.path}/recording_manifest.json').writeAsString('{broken');
    final data = await recover();
    expect(data['nextSequence'], 8);
    expect((data['segments'] as List).single['sequence'], 4);
    expect(await root.list().any((f) => f.path.contains('.corrupt-')), isTrue);
  });
  test('即使序号错误，独占创建也绝不截断现有音频', () async {
    final first = await wav(0, 1000);
    final before = await first.readAsBytes();
    final reserved = await reserveAudioFile(audio, 0);
    expect(reserved.sequence, 1);
    expect(await first.readAsBytes(), before);
  });
  test('旧m4a和WAV同名时使用不同且稳定的序号', () async {
    await wav(0, 1000);
    await File('${audio.path}/segment_0000.m4a').writeAsBytes([1, 2, 3]);
    final first = await reconcileRecordingFiles(
      directory: root,
      sessionId: 'qa',
      legacyDuration: (_) async => 500,
    );
    expect(
      (first['segments'] as List).map((e) => e['sequence']).toSet().length,
      2,
    );
    expect(first['nextSequence'], 2);
    expect(await recover(), first);
  });
}
