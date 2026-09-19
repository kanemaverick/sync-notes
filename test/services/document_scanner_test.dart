import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/document_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sync_notes/document_scanner');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('扫描结果保留入口音频位置及设备时间范围，不伪造快门时刻', () async {
    final startedAt = DateTime(2026, 9, 20, 10);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments['offsetMs'], 1000);
      return jsonEncode({
        'id': 'scan-1',
        'path': '/private/scan.jpg',
        'offsetMs': call.arguments['offsetMs'],
        'deviceTimeMs': call.arguments['deviceTimeMs'],
        'completedAtMs': startedAt
            .add(const Duration(seconds: 25))
            .millisecondsSinceEpoch,
      });
    });
    final scan = await DocumentScanner().scan(
      sessionId: 'session-1',
      offsetMs: 1000,
      deviceTime: startedAt,
    );
    expect(scan!.offsetMs, 1000);
    expect(scan.completedAt.difference(scan.startedAt).inSeconds, 25);
  });
  test('用户取消扫描不创建照片', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await DocumentScanner().scan(
        sessionId: 's',
        offsetMs: 0,
        deviceTime: DateTime.now(),
      ),
      isNull,
    );
  });
  test('重启后可以读取待导入扫描，并在保存后确认清理', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'pending') {
        return [
          jsonEncode({
            'id': '1',
            'path': '/scan.jpg',
            'offsetMs': 0,
            'deviceTimeMs': 1,
            'completedAtMs': 2,
          }),
        ];
      }
      expect(call.arguments['id'], '1');
      return null;
    });
    final scanner = DocumentScanner();
    final scan = (await scanner.pending('s')).single;
    await scanner.acknowledge(scan.id);
    expect(calls, ['pending', 'acknowledge']);
  });
}
