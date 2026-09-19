import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'live_transcription_service.dart';

/// Recording owns the audio. This bounded, best-effort worker only owns captions.
/// At most one message is in flight, so a stalled decoder cannot grow its mailbox.
class LocalAsrWorker {
  LocalAsrWorker({
    required this.onEvent,
    this.maxPendingBytes = asrSampleRate * 2 * 8,
    this.timeout = const Duration(seconds: 8),
    this.entryPoint = localAsrEntryPoint,
  });

  final void Function(Map<String, Object?>) onEvent;
  final int maxPendingBytes;
  final Duration timeout;
  final void Function(Map<String, Object?>) entryPoint;
  final _queue = Queue<Map<String, Object?>>();
  final _flushes = <int, Completer<void>>{};
  final _responses = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  Isolate? _isolate;
  SendPort? _commands;
  Timer? _watchdog;
  bool _closed = false;
  bool _started = false;
  Map<String, Object?>? _inFlight;
  int _pendingBytes = 0;
  int _nextId = 0;

  bool get isClosed => _closed;
  int get pendingBytes => _pendingBytes;

  Future<void> start(TranscriptionModelFiles files) async {
    if (_closed || _started) return;
    _started = true;
    _responses.listen(_receive);
    _errors.listen((_) => _fail('本地识别异常，原始录音继续保存'));
    _exits.listen((_) {
      if (!_closed) _fail('本地识别进程已退出，原始录音继续保存');
    });
    _armWatchdog();
    try {
      final isolate = await Isolate.spawn(
        entryPoint,
        {'port': _responses.sendPort, 'files': files},
        onError: _errors.sendPort,
        onExit: _exits.sendPort,
      );
      if (_closed) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error) {
      _fail('本地识别启动失败：$error');
    }
  }

  /// Offsets come from written PCM samples, never message arrival/wall time.
  void addPcm(Uint8List bytes, {required int startMs, required int endMs}) {
    if (_closed || bytes.isEmpty) return;
    if (_pendingBytes + bytes.length > maxPendingBytes) {
      _fail('本地字幕积压超过 8 秒，已停用字幕以优先保留录音');
      return;
    }
    _pendingBytes += bytes.length;
    _queue.add({
      'type': 'pcm',
      'id': _nextId++,
      'bytes': Uint8List.fromList(bytes),
      'startMs': startMs,
      'endMs': endMs,
    });
    _pump();
  }

  /// A FIFO barrier: finish the old utterance before processing resumed audio.
  Future<void> flush() async {
    if (_closed) return;
    final id = _nextId++;
    final completion = Completer<void>();
    _flushes[id] = completion;
    _queue.add({'type': 'flush', 'id': id});
    _pump();
    await completion.future.timeout(
      timeout,
      onTimeout: () {
        _fail('本地字幕收尾超时，已保存的录音不受影响');
      },
    );
  }

  void _pump() {
    if (_closed || _commands == null || _inFlight != null || _queue.isEmpty) {
      return;
    }
    _inFlight = _queue.removeFirst();
    _commands!.send(_inFlight);
    _armWatchdog();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, () => _fail('本地识别响应超时，原始录音继续保存'));
  }

  void _receive(dynamic message) {
    if (_closed || message is! Map) return;
    switch (message['type']) {
      case 'ready':
        _watchdog?.cancel();
        _commands = message['port'] as SendPort;
        onEvent({'type': 'ready'});
        _pump();
      case 'ack':
        if (_inFlight?['id'] != message['id']) return;
        _watchdog?.cancel();
        final bytes = _inFlight?['bytes'] as Uint8List?;
        _pendingBytes -= bytes?.length ?? 0;
        _flushes.remove(message['id'])?.complete();
        _inFlight = null;
        _pump();
      case 'error':
        _fail(message['error'] as String? ?? '本地字幕不可用');
      default:
        onEvent(Map<String, Object?>.from(message));
    }
  }

  void _fail(String message) {
    if (_closed) return;
    close();
    onEvent({'type': 'error', 'error': message});
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _watchdog?.cancel();
    _commands?.send({'type': 'close'});
    // The worker normally frees native handles on close. The watchdog is only
    // a last resort; Dart isolates cannot contain a native process-level crash.
    final isolate = _isolate;
    if (isolate != null) {
      Timer(timeout, () => isolate.kill(priority: Isolate.immediate));
    }
    _responses.close();
    _errors.close();
    _exits.close();
    _queue.clear();
    _inFlight = null;
    _pendingBytes = 0;
    for (final completion in _flushes.values) {
      completion.complete();
    }
    _flushes.clear();
  }
}

/// No platform channels or microphone access in this isolate, only native ASR.
@pragma('vm:entry-point')
void localAsrEntryPoint(Map<String, Object?> boot) {
  final output = boot['port']! as SendPort;
  final input = ReceivePort();
  try {
    final recognizer = createOnlineRecognizer(
      boot['files']! as TranscriptionModelFiles,
    );
    var stream = recognizer.createStream();
    int? utteranceStartMs;
    var endMs = 0;
    var lastPartialMs = -1000;
    var lastText = '';
    void finish() {
      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty && utteranceStartMs != null) {
        output.send({
          'type': 'final',
          'text': text,
          'startMs': utteranceStartMs,
          'endMs': endMs,
        });
      }
      utteranceStartMs = null;
      lastText = '';
    }

    output.send({'type': 'ready', 'port': input.sendPort});
    input.listen((dynamic message) {
      if (message is! Map) return;
      try {
        if (message['type'] == 'close') {
          stream.free();
          recognizer.free();
          input.close();
          return;
        }
        if (message['type'] == 'pcm') {
          utteranceStartMs ??= message['startMs'] as int;
          endMs = message['endMs'] as int;
          stream.acceptWaveform(
            samples: pcm16BytesToFloat32(message['bytes'] as Uint8List),
            sampleRate: asrSampleRate,
          );
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          final text = recognizer.getResult(stream).text.trim();
          if (text != lastText && endMs - lastPartialMs >= 250) {
            output.send({
              'type': 'partial',
              'text': text,
              'startMs': utteranceStartMs,
              'endMs': endMs,
            });
            lastText = text;
            lastPartialMs = endMs;
          }
          if (recognizer.isEndpoint(stream)) {
            finish();
            recognizer.reset(stream);
          }
        } else if (message['type'] == 'flush') {
          stream.inputFinished();
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          finish();
          stream.free();
          stream = recognizer.createStream();
        }
        output.send({'type': 'ack', 'id': message['id']});
      } catch (error) {
        output.send({'type': 'error', 'error': '本地识别失败：$error'});
        stream.free();
        recognizer.free();
        input.close();
      }
    });
  } catch (error) {
    output.send({'type': 'error', 'error': '本地模型加载失败：$error'});
    input.close();
  }
}
