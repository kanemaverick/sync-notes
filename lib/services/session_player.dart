import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../core/timeline_clock.dart';
import '../models/entities.dart';

class SessionPlayer {
  final AudioPlayer _player = AudioPlayer();
  SegmentTimelineMapper _mapper = SegmentTimelineMapper(const []);
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  final StreamController<int> _globalPosition =
      StreamController<int>.broadcast();
  int _index = 0;

  Stream<int> get globalPositionStream => _globalPosition.stream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  bool get isPlaying => _player.playing;
  int get totalDurationMs => _mapper.totalDurationMs;

  Future<void> load(List<AudioSegment> segments) async {
    final ordered = [...segments]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    _mapper = SegmentTimelineMapper(
      ordered.map((segment) => segment.durationMs).toList(),
    );
    await _player.setAudioSources(
      ordered
          .map((segment) => AudioSource.uri(Uri.file(segment.filePath)))
          .toList(),
    );
    _indexSubscription = _player.currentIndexStream.listen((index) {
      _index = index ?? 0;
      _emit(_player.position);
    });
    _positionSubscription = _player.positionStream.listen(_emit);
  }

  void _emit(Duration position) {
    if (!_globalPosition.isClosed) {
      _globalPosition.add(
        _mapper.mapLocalPosition(
          index: _index,
          positionMs: position.inMilliseconds,
        ),
      );
    }
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> seekGlobal(int positionMs) async {
    final target = _mapper.mapGlobalPosition(positionMs);
    await _player.seek(
      Duration(milliseconds: target.positionMs),
      index: target.index,
    );
  }

  Future<void> skipBy(int deltaMs, int currentMs) =>
      seekGlobal((currentMs + deltaMs).clamp(0, totalDurationMs));

  Future<void> dispose() async {
    await _indexSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _player.dispose();
    await _globalPosition.close();
  }
}
