import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const tencentPcmFrameBytes = 1280;

sealed class CloudProxyEvent {
  const CloudProxyEvent();
}

class CloudProxyReady extends CloudProxyEvent {
  const CloudProxyReady();
}

class CloudProxyFinished extends CloudProxyEvent {
  const CloudProxyFinished();
}

class CloudProxyFailure extends CloudProxyEvent {
  const CloudProxyFailure(this.message);
  final String message;
}

class CloudTranscriptUpdate extends CloudProxyEvent {
  const CloudTranscriptUpdate({
    required this.sentenceId,
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.isFinal,
    this.speakerId,
  });

  final int sentenceId;
  final String text;
  final int startMs;
  final int endMs;
  final bool isFinal;
  final int? speakerId;
}

CloudProxyEvent? parseCloudProxyMessage(
  Object? message, {
  required int baseOffsetMs,
}) {
  if (message is! String) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(message);
  } catch (_) {
    return const CloudProxyFailure('云端返回了无法解析的数据');
  }
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  if (map['type'] == 'proxy.ready') return const CloudProxyReady();
  if (map['type'] == 'proxy.finished') return const CloudProxyFinished();
  // Provider adapters normalize timestamps relative to this connection's PCM.
  // Keep the legacy Tencent envelope below for already deployed proxies.
  if (map['type'] == 'transcript') {
    final text = map['text'];
    final id = _asInt(map['sentenceId']);
    final start = _asInt(map['startMs']);
    final end = _asInt(map['endMs']);
    if (text is! String ||
        id == null ||
        id < 0 ||
        start == null ||
        start < 0 ||
        end == null ||
        end < start ||
        map['isFinal'] is! bool) {
      return const CloudProxyFailure('云端转写片段格式或时间戳无效');
    }
    if (text.trim().isEmpty) return null;
    return CloudTranscriptUpdate(
      sentenceId: id,
      text: text.trim(),
      startMs: baseOffsetMs + start,
      endMs: baseOffsetMs + end,
      isFinal: map['isFinal'] as bool,
      speakerId: _asInt(map['speakerId']),
    );
  }
  if (map['type'] == 'proxy.error') {
    return CloudProxyFailure(map['message'] as String? ?? '云端代理连接失败');
  }
  final code = _asInt(map['code']);
  if (code != null && code != 0) {
    return CloudProxyFailure('腾讯云识别错误 $code：${map['message'] ?? '未知错误'}');
  }
  if (_asInt(map['final']) == 1) return const CloudProxyFinished();
  final rawSentence = map['sentences'];
  if (rawSentence is! Map) return null;
  final sentence = Map<String, dynamic>.from(rawSentence);
  final text = (sentence['sentence'] as String? ?? '').trim();
  if (text.isEmpty) return null;
  final start = _asInt(sentence['start_time']) ?? 0;
  final end = _asInt(sentence['end_time']) ?? start;
  return CloudTranscriptUpdate(
    sentenceId: _asInt(sentence['sentence_id']) ?? 0,
    text: text,
    startMs: baseOffsetMs + start,
    endMs: baseOffsetMs + end,
    isFinal: _asInt(sentence['sentence_type']) == 1,
    speakerId: _asInt(sentence['speaker_id']),
  );
}

int? _asInt(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text),
  _ => null,
};

class PcmFrameBuffer {
  PcmFrameBuffer({this.frameBytes = tencentPcmFrameBytes});

  final int frameBytes;
  Uint8List _pending = Uint8List(0);

  List<Uint8List> add(Uint8List bytes) {
    if (bytes.isEmpty) return const [];
    final combined = Uint8List(_pending.length + bytes.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + bytes.length, bytes);
    final frames = <Uint8List>[];
    var offset = 0;
    while (combined.length - offset >= frameBytes) {
      frames.add(Uint8List.sublistView(combined, offset, offset + frameBytes));
      offset += frameBytes;
    }
    _pending = Uint8List.fromList(combined.sublist(offset));
    return frames;
  }

  Uint8List takeRemainder() {
    final value = _pending;
    _pending = Uint8List(0);
    return value;
  }
}

class CloudRealtimeTranscriber {
  CloudRealtimeTranscriber({
    required this.proxyUrl,
    required this.accessToken,
    required this.sessionId,
    required this.baseOffsetMs,
    required this.onEvent,
    this.readyTimeout = const Duration(seconds: 10),
  });

  final String proxyUrl;
  final String accessToken;
  final String sessionId;
  final int baseOffsetMs;
  final void Function(CloudProxyEvent event) onEvent;
  final Duration readyTimeout;

  final PcmFrameBuffer _frames = PcmFrameBuffer();
  final Completer<void> _finalResponse = Completer<void>();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;
  bool _terminalReceived = false;
  Timer? _readyTimer;
  int? _audioBaseOffsetMs;

  Future<void> connect() async {
    final source = Uri.parse(proxyUrl);
    final uri = source.replace(
      queryParameters: {
        ...source.queryParameters,
        'session_id': sessionId,
        'base_offset_ms': '$baseOffsetMs',
      },
    );
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $accessToken'},
    ).timeout(const Duration(seconds: 8));
    if (_closed) {
      await socket.close();
      return;
    }
    socket.pingInterval = const Duration(seconds: 5);
    _socket = socket;
    _readyTimer = Timer(readyTimeout, () {
      if (_closed || _terminalReceived) return;
      _terminalReceived = true;
      if (!_finalResponse.isCompleted) _finalResponse.complete();
      onEvent(const CloudProxyFailure('云端服务未及时就绪，已回退本地字幕'));
      unawaited(close());
    });
    _subscription = socket.listen(
      (message) {
        final event = parseCloudProxyMessage(
          message,
          baseOffsetMs: _audioBaseOffsetMs ?? baseOffsetMs,
        );
        if (event != null) {
          if (event is CloudProxyReady ||
              event is CloudProxyFinished ||
              event is CloudProxyFailure) {
            _readyTimer?.cancel();
          }
          if (event is CloudProxyFinished || event is CloudProxyFailure) {
            _terminalReceived = true;
            if (!_finalResponse.isCompleted) _finalResponse.complete();
          }
          onEvent(event);
        }
      },
      onError: (Object error) {
        if (!_finalResponse.isCompleted) _finalResponse.complete();
        if (!_closed && !_terminalReceived) {
          onEvent(const CloudProxyFailure('云端连接中断，请检查网络或服务配置'));
        }
      },
      onDone: () {
        if (!_finalResponse.isCompleted) _finalResponse.complete();
        if (!_closed && !_terminalReceived) {
          onEvent(const CloudProxyFailure('云端连接已断开'));
        }
      },
      cancelOnError: false,
    );
  }

  void addPcm(Uint8List bytes, {int? startMs}) {
    final socket = _socket;
    if (_closed || socket == null || socket.readyState != WebSocket.open) {
      return;
    }
    if (bytes.isEmpty) return;
    // A provider may take seconds to become ready. Its zero is the first
    // submitted sample, not the earlier WebSocket connection attempt.
    _audioBaseOffsetMs ??= startMs ?? baseOffsetMs;
    for (final frame in _frames.add(bytes)) {
      socket.add(frame);
    }
  }

  Future<void> finish() async {
    if (_closed) return;
    final socket = _socket;
    final remainder = _frames.takeRemainder();
    if (socket != null && socket.readyState == WebSocket.open) {
      if (remainder.isNotEmpty) socket.add(remainder);
      socket.add(jsonEncode({'type': 'end'}));
      try {
        await _finalResponse.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Preserve recording shutdown even if the provider never sends final.
      }
    }
    await close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _readyTimer?.cancel();
    await _subscription?.cancel();
    await _socket?.close(WebSocketStatus.normalClosure);
  }
}
