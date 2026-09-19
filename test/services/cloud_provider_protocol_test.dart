import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/cloud_realtime_transcription.dart';

void main() {
  Map<String, Object> sentence() => {
    'type': 'transcript',
    'sentenceId': 3,
    'text': ' Transformer 模型 ',
    'startMs': 100,
    'endMs': 900,
    'isFinal': false,
  };

  test('通用协议保留句ID并只加一次续录偏移', () {
    for (final finalResult in [false, true]) {
      final data = sentence()..['isFinal'] = finalResult;
      final result =
          parseCloudProxyMessage(jsonEncode(data), baseOffsetMs: 5000)!
              as CloudTranscriptUpdate;
      expect(result.sentenceId, 3);
      expect(result.text, 'Transformer 模型');
      expect(result.startMs, 5100);
      expect(result.endMs, 5900);
      expect(result.isFinal, finalResult);
    }
  });

  test('通用协议拒绝无效时间和稳定状态', () {
    for (final change in [
      {'startMs': -1},
      {'endMs': 0},
      {'sentenceId': -1},
      {'isFinal': 'false'},
      {'text': 42},
    ]) {
      expect(
        parseCloudProxyMessage(
          jsonEncode(sentence()..addAll(change)),
          baseOffsetMs: 0,
        ),
        isA<CloudProxyFailure>(),
      );
    }
  });

  test('通用协议结束消息与旧腾讯协议兼容', () {
    for (final message in [
      {'type': 'proxy.finished'},
      {'code': 0, 'final': 1},
    ]) {
      expect(
        parseCloudProxyMessage(jsonEncode(message), baseOffsetMs: 0),
        isA<CloudProxyFinished>(),
      );
    }
  });
}
