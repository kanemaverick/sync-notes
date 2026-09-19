import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/cloud_realtime_transcription.dart';
import 'package:sync_notes/services/cloud_transcription_settings.dart';

void main() {
  test('代理不返回就绪时超时回退而不是永久等待', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final serverTask = server.first.then((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.drain<void>();
    });
    final failure = Completer<CloudProxyFailure>();
    final client = CloudRealtimeTranscriber(
      proxyUrl: 'ws://127.0.0.1:${server.port}/asr',
      accessToken: 'test-token',
      sessionId: 'test-session',
      baseOffsetMs: 0,
      readyTimeout: const Duration(milliseconds: 30),
      onEvent: (event) {
        if (event is CloudProxyFailure && !failure.isCompleted) {
          failure.complete(event);
        }
      },
    );
    addTearDown(client.close);
    await client.connect();
    expect(
      (await failure.future.timeout(const Duration(seconds: 2))).message,
      contains('未及时就绪'),
    );
    await serverTask.timeout(const Duration(seconds: 2));
  });
  test('新安装默认使用 APK 内置的云转写配置', () {
    const bundled = CloudTranscriptionConfig(
      enabled: true,
      proxyUrl: 'wss://asr.example.com/v1/asr/tencent/realtime',
      accessToken: 'bundled-token',
    );

    final config = resolveCloudTranscriptionConfig(bundledConfig: bundled);

    expect(config.enabled, isTrue);
    expect(config.proxyUrl, bundled.proxyUrl);
    expect(config.accessToken, bundled.accessToken);
    expect(config.isConfigured, isTrue);
  });

  test('用户保存的设置可以覆盖 APK 内置配置', () {
    const bundled = CloudTranscriptionConfig(
      enabled: true,
      proxyUrl: 'wss://asr.example.com/v1/asr/tencent/realtime',
      accessToken: 'bundled-token',
    );

    final config = resolveCloudTranscriptionConfig(
      bundledConfig: bundled,
      savedEnabled: false,
      savedProxyUrl: 'wss://custom.example.com/asr',
      savedAccessToken: 'custom-token',
    );

    expect(config.enabled, isFalse);
    expect(config.proxyUrl, 'wss://custom.example.com/asr');
    expect(config.accessToken, 'custom-token');
  });
  test('腾讯云稳定句转换为带会话偏移的转写片段', () {
    final event = parseCloudProxyMessage(
      jsonEncode({
        'code': 0,
        'sentences': {
          'sentence': '这是云端识别结果',
          'sentence_type': 1,
          'sentence_id': 7,
          'speaker_id': 2,
          'start_time': 1200,
          'end_time': 2850,
        },
      }),
      baseOffsetMs: 10000,
    );
    expect(event, isA<CloudTranscriptUpdate>());
    final update = event! as CloudTranscriptUpdate;
    expect(update.text, '这是云端识别结果');
    expect(update.startMs, 11200);
    expect(update.endMs, 12850);
    expect(update.isFinal, isTrue);
    expect(update.speakerId, 2);
  });

  test('腾讯云错误码不会被误当作字幕', () {
    final event = parseCloudProxyMessage(
      jsonEncode({'code': 4004, 'message': '资源包耗尽'}),
      baseOffsetMs: 0,
    );
    expect(event, isA<CloudProxyFailure>());
    expect((event! as CloudProxyFailure).message, contains('4004'));
  });

  test('PCM被整理为腾讯建议的40毫秒1280字节帧', () {
    final buffer = PcmFrameBuffer();
    expect(buffer.add(Uint8List(640)), isEmpty);
    final frames = buffer.add(Uint8List(1920));
    expect(frames, hasLength(2));
    expect(frames.every((frame) => frame.length == 1280), isTrue);
    expect(buffer.takeRemainder(), isEmpty);
  });

  test('云端代理只接受WebSocket地址', () {
    expect(validateCloudProxyUrl('https://example.com/asr'), isNotNull);
    expect(validateCloudProxyUrl('wss://example.com/asr'), isNull);
  });

  test('云端客户端通过WebSocket发送授权和PCM并接收稳定句', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final audioReceived = Completer<int>();
    final serverTask = server.first.then((request) async {
      expect(request.headers.value('authorization'), 'Bearer proxy-token');
      expect(request.uri.queryParameters['session_id'], 'session-1');
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode({'type': 'proxy.ready'}));
      await for (final message in socket) {
        if (message is List<int>) {
          if (!audioReceived.isCompleted) {
            audioReceived.complete(message.length);
          }
        } else if (message is String &&
            (jsonDecode(message) as Map<String, dynamic>)['type'] == 'end') {
          socket.add(
            jsonEncode({
              'code': 0,
              'sentences': {
                'sentence': '网络稳定句',
                'sentence_type': 1,
                'sentence_id': 1,
                'start_time': 100,
                'end_time': 900,
              },
            }),
          );
          socket.add(jsonEncode({'code': 0, 'final': 1}));
          await socket.close();
        }
      }
    });
    addTearDown(() async => serverTask);

    final ready = Completer<void>();
    final updates = <CloudTranscriptUpdate>[];
    final client = CloudRealtimeTranscriber(
      proxyUrl:
          'ws://${InternetAddress.loopbackIPv4.address}:${server.port}/v1/asr/tencent/realtime',
      accessToken: 'proxy-token',
      sessionId: 'session-1',
      baseOffsetMs: 5000,
      onEvent: (event) {
        if (event is CloudProxyReady && !ready.isCompleted) ready.complete();
        if (event is CloudTranscriptUpdate) updates.add(event);
      },
    );
    addTearDown(client.close);
    await client.connect();
    await ready.future.timeout(const Duration(seconds: 2));
    // Recognition becomes ready 2.5 seconds after connection was attempted.
    client.addPcm(Uint8List(tencentPcmFrameBytes), startMs: 7500);
    expect(
      await audioReceived.future.timeout(const Duration(seconds: 2)),
      tencentPcmFrameBytes,
    );
    await client.finish();
    expect(updates.single.text, '网络稳定句');
    expect(updates.single.startMs, 7600);
    expect(updates.single.endMs, 8400);
  });
}
