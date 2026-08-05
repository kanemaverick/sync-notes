import 'package:flutter/services.dart';

abstract interface class MonotonicClock {
  Future<int> nowMs();
}

class PlatformMonotonicClock implements MonotonicClock {
  static const _channel = MethodChannel('sync_notes/clock');
  static final Stopwatch _fallback = Stopwatch()..start();

  @override
  Future<int> nowMs() async {
    try {
      final value = await _channel.invokeMethod<int>('elapsedRealtimeMs');
      return value ?? _fallback.elapsedMilliseconds;
    } on PlatformException {
      return _fallback.elapsedMilliseconds;
    } on MissingPluginException {
      return _fallback.elapsedMilliseconds;
    }
  }
}

class TimelineClock {
  TimelineClock(this._clock);

  final MonotonicClock _clock;
  int _accumulatedMs = 0;
  int? _activeSinceMs;

  bool get isRunning => _activeSinceMs != null;

  Future<void> start({int initialOffsetMs = 0}) async {
    _accumulatedMs = initialOffsetMs;
    _activeSinceMs = await _clock.nowMs();
  }

  Future<int> pause() async {
    if (_activeSinceMs == null) return _accumulatedMs;
    final now = await _clock.nowMs();
    _accumulatedMs += now - _activeSinceMs!;
    _activeSinceMs = null;
    return _accumulatedMs;
  }

  Future<void> resume() async {
    if (_activeSinceMs != null) return;
    _activeSinceMs = await _clock.nowMs();
  }

  Future<int> offsetMs() async {
    if (_activeSinceMs == null) return _accumulatedMs;
    return _accumulatedMs + (await _clock.nowMs()) - _activeSinceMs!;
  }
}

class SegmentSeekTarget {
  const SegmentSeekTarget({required this.index, required this.positionMs});
  final int index;
  final int positionMs;
}

class SegmentTimelineMapper {
  SegmentTimelineMapper(List<int> durationsMs)
    : _durationsMs = List.unmodifiable(durationsMs);

  final List<int> _durationsMs;

  int get totalDurationMs => _durationsMs.fold(0, (sum, item) => sum + item);

  SegmentSeekTarget mapGlobalPosition(int globalMs) {
    if (_durationsMs.isEmpty) {
      return const SegmentSeekTarget(index: 0, positionMs: 0);
    }
    var remaining = globalMs.clamp(0, totalDurationMs);
    for (var index = 0; index < _durationsMs.length; index++) {
      final duration = _durationsMs[index];
      if (remaining < duration || index == _durationsMs.length - 1) {
        return SegmentSeekTarget(
          index: index,
          positionMs: remaining.clamp(0, duration),
        );
      }
      remaining -= duration;
    }
    return SegmentSeekTarget(
      index: _durationsMs.length - 1,
      positionMs: _durationsMs.last,
    );
  }

  int mapLocalPosition({required int index, required int positionMs}) {
    final prefix = _durationsMs
        .take(index.clamp(0, _durationsMs.length))
        .fold(0, (a, b) => a + b);
    return prefix + positionMs;
  }
}

String formatDuration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
