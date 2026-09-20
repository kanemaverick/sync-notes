import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/cloud_realtime_transcription.dart';

void main() {
  test(
    'Tencent observed result envelope preserves partial/final revisions and offsets',
    () {
      for (final slice in [0, 1, 2]) {
        final result =
            parseCloudProxyMessage(
                  jsonEncode({
                    'code': 0,
                    'message': 'success',
                    'result': {
                      'slice_type': slice,
                      'index': 1,
                      'start_time': 3520,
                      'end_time': 10053,
                      'voice_text_str': 'Today is礼拜二。',
                      'speaker_info': null,
                    },
                  }),
                  baseOffsetMs: 300000,
                )
                as CloudTranscriptUpdate;
        expect(result.sentenceId, 1);
        expect(result.startMs, 303520);
        expect(result.endMs, 310053);
        expect(result.isFinal, slice == 2);
        expect(result.text, 'Today is礼拜二。');
      }
    },
  );
  test(
    'bad timestamps report a failure instead of silently losing subtitles',
    () {
      expect(
        parseCloudProxyMessage(
          jsonEncode({
            'code': 0,
            'result': {
              'slice_type': 2,
              'index': 0,
              'start_time': 2000,
              'end_time': 1,
              'voice_text_str': '测试',
            },
          }),
          baseOffsetMs: 0,
        ),
        isA<CloudProxyFailure>(),
      );
    },
  );
  test(
    'success handshake, quota error and stream termination remain distinct',
    () {
      expect(
        parseCloudProxyMessage(
          '{"code":0,"message":"success"}',
          baseOffsetMs: 0,
        ),
        isNull,
      );
      expect(
        parseCloudProxyMessage(
          '{"code":4004,"message":"资源包耗尽"}',
          baseOffsetMs: 0,
        ),
        isA<CloudProxyFailure>(),
      );
      expect(
        parseCloudProxyMessage('{"code":0,"final":1}', baseOffsetMs: 0),
        isA<CloudProxyFinished>(),
      );
    },
  );
}
