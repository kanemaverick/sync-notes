import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/live_transcription_service.dart';
import 'package:sync_notes/services/local_asr_worker.dart';

const files = TranscriptionModelFiles(
  encoder: '',
  decoder: '',
  joiner: '',
  tokens: '',
);

void fakeWorker(Map<String, Object?> boot) {
  final output = boot['port']! as SendPort;
  final input = ReceivePort();
  output.send({'type': 'ready', 'port': input.sendPort});
  input.listen((dynamic message) {
    if (message['type'] == 'close') {
      input.close();
      return;
    }
    if (message['type'] == 'pcm') {
      // Deliberately synchronous: a busy decoder must not block the caller.
      sleep(const Duration(milliseconds: 80));
      output.send({
        'type': 'final',
        'startMs': message['startMs'],
        'endMs': message['endMs'],
        'text': 'PPT AI',
      });
    }
    output.send({'type': 'ack', 'id': message['id']});
  });
}

void hungWorker(Map<String, Object?> boot) {
  final output = boot['port']! as SendPort;
  final input = ReceivePort();
  output.send({'type': 'ready', 'port': input.sendPort});
  input.listen((dynamic message) {
    if (message['type'] == 'close') input.close();
  });
}

void exitedWorker(Map<String, Object?> boot) => Isolate.exit();

void main() {
  test('同步解码不会阻塞录音线程，结果保留采样时间而不是到达时间', () async {
    final events = <Map<String, Object?>>[];
    final worker = LocalAsrWorker(onEvent: events.add, entryPoint: fakeWorker);
    addTearDown(worker.close);
    await worker.start(files);
    worker.addPcm(Uint8List(3200), startMs: 5000, endMs: 5100);
    var timerRan = false;
    Timer(const Duration(milliseconds: 10), () => timerRan = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(timerRan, isTrue);
    await worker.flush();
    final result = events.singleWhere((e) => e['type'] == 'final');
    expect(result['startMs'], 5000);
    expect(result['endMs'], 5100);
    expect(worker.pendingBytes, 0);
  });

  test('暂停收尾屏障和继续后的PCM按FIFO顺序处理', () async {
    final events = <Map<String, Object?>>[];
    final worker = LocalAsrWorker(onEvent: events.add, entryPoint: fakeWorker);
    addTearDown(worker.close);
    await worker.start(files);
    worker.addPcm(Uint8List(3200), startMs: 0, endMs: 100);
    final paused = worker.flush();
    worker.addPcm(Uint8List(3200), startMs: 100, endMs: 200);
    await paused;
    expect(events.where((e) => e['type'] == 'final'), hasLength(1));
    await worker.flush();
    expect(events.where((e) => e['type'] == 'final').map((e) => e['startMs']), [
      0,
      100,
    ]);
  });

  test('积压有上限，失败只关闭字幕且待收尾任务不会悬挂', () async {
    final events = <Map<String, Object?>>[];
    final worker = LocalAsrWorker(
      onEvent: events.add,
      entryPoint: hungWorker,
      maxPendingBytes: 3200,
    );
    addTearDown(worker.close);
    await worker.start(files);
    worker.addPcm(Uint8List(3200), startMs: 0, endMs: 100);
    final flushed = worker.flush();
    worker.addPcm(Uint8List(2), startMs: 100, endMs: 101);
    await flushed;
    expect(worker.isClosed, isTrue);
    expect(worker.pendingBytes, 0);
    expect(events.where((e) => e['type'] == 'error'), hasLength(1));
    await worker.flush();
  });

  test('工作线程意外退出时报告错误', () async {
    final error = Completer<void>();
    final worker = LocalAsrWorker(
      onEvent: (e) {
        if (e['type'] == 'error') error.complete();
      },
      entryPoint: exitedWorker,
    );
    addTearDown(worker.close);
    await worker.start(files);
    await error.future.timeout(const Duration(seconds: 2));
    expect(worker.isClosed, isTrue);
  });

  test('无响应的字幕收尾有超时上限', () async {
    final worker = LocalAsrWorker(
      onEvent: (_) {},
      entryPoint: hungWorker,
      timeout: const Duration(milliseconds: 100),
    );
    addTearDown(worker.close);
    await worker.start(files);
    await worker.flush().timeout(const Duration(seconds: 1));
    expect(worker.isClosed, isTrue);
  });
}
