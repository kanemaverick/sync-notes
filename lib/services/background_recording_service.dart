import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../data/app_repository.dart';
import '../models/entities.dart';
import 'cloud_realtime_transcription.dart';
import 'cloud_transcription_settings.dart';
import 'live_transcription_service.dart';
import 'local_asr_worker.dart';
import 'media_storage.dart';

const _sessionIdKey = 'recording.sessionId';
const _sessionDirKey = 'recording.sessionDir';
const _activeOffsetKey = 'recording.activeOffsetMs';
const _asrEncoderKey = 'recording.asrEncoder';
const _asrDecoderKey = 'recording.asrDecoder';
const _asrJoinerKey = 'recording.asrJoiner';
const _asrTokensKey = 'recording.asrTokens';
const _cloudEnabledKey = 'recording.cloudEnabled';
const _cloudProxyUrlKey = 'recording.cloudProxyUrl';
const _cloudAccessTokenKey = 'recording.cloudAccessToken';

@pragma('vm:entry-point')
void startRecordingService() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

class BackgroundRecordingService {
  BackgroundRecordingService({
    required this.repository,
    required this.storage,
    required this.cloudSettings,
  });

  final AppRepository repository;
  final MediaStorage storage;
  final CloudTranscriptionSettingsStore cloudSettings;
  final StreamController<Object> _taskData =
      StreamController<Object>.broadcast();

  Stream<Object> get taskDataStream => _taskData.stream;

  void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sync_notes_recording',
        channelName: '同步讲记录音',
        channelDescription: '录音期间保持显示，点击可返回记录页面。',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  void _onTaskData(Object data) => _taskData.add(data);

  Future<void> requestNotificationPermission() async {
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  Future<void> start(
    Session session, {
    bool requestNotifications = true,
  }) async {
    if (requestNotifications) await requestNotificationPermission();
    final recorder = AudioRecorder();
    final permitted = await recorder.hasPermission();
    await recorder.dispose();
    if (!permitted) throw const RecordingException('需要麦克风权限才能开始记录。');
    if (await FlutterForegroundTask.isRunningService) {
      throw const RecordingException('已有一条记录正在录音，请先结束它。');
    }
    final root = await storage.sessionDirectory(session.id);
    TranscriptionModelFiles? model;
    try {
      model = await prepareTranscriptionModel();
    } catch (_) {
      // Missing/corrupt model assets must never prevent microphone recording.
    }
    final cloud = await cloudSettings.load();
    await FlutterForegroundTask.saveData(key: _sessionIdKey, value: session.id);
    await FlutterForegroundTask.saveData(key: _sessionDirKey, value: root.path);
    await FlutterForegroundTask.saveData(key: _activeOffsetKey, value: 0);
    await FlutterForegroundTask.saveData(
      key: _asrEncoderKey,
      value: model?.encoder ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: _asrDecoderKey,
      value: model?.decoder ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: _asrJoinerKey,
      value: model?.joiner ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: _asrTokensKey,
      value: model?.tokens ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: _cloudEnabledKey,
      value: cloud.isConfigured,
    );
    await FlutterForegroundTask.saveData(
      key: _cloudProxyUrlKey,
      value: cloud.proxyUrl.trim(),
    );
    await FlutterForegroundTask.saveData(
      key: _cloudAccessTokenKey,
      value: cloud.accessToken.trim(),
    );
    final result = await FlutterForegroundTask.startService(
      serviceId: 2408,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: '正在录音 · ${session.title}',
      notificationText: '00:00 · 点击返回同步讲记',
      notificationInitialRoute: '/recording',
      callback: startRecordingService,
    );
    if (result is ServiceRequestFailure) {
      throw RecordingException(result.error.toString());
    }
  }

  void pause() => FlutterForegroundTask.sendDataToTask({'command': 'pause'});
  void resume() => FlutterForegroundTask.sendDataToTask({'command': 'resume'});

  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    final sessionDir = await FlutterForegroundTask.getData<String>(
      key: _sessionDirKey,
    );
    final expectedOffsetMs = await activeOffsetMs();
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      throw RecordingException(result.error.toString());
    }
    if (sessionDir != null) {
      await waitForFinalizedRecordingManifest(
        sessionDirectory: Directory(sessionDir),
        expectedOffsetMs: expectedOffsetMs,
      );
    }
  }

  Future<int> activeOffsetMs() async =>
      await FlutterForegroundTask.getData<int>(key: _activeOffsetKey) ?? 0;

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<void> syncManifest(String sessionId) async {
    final root = await storage.sessionDirectory(sessionId);
    final manifest = File(p.join(root.path, 'recording_manifest.json'));
    if (!await manifest.exists()) return;
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    for (final item in (json['segments'] as List<dynamic>? ?? const [])) {
      final map = item as Map<String, dynamic>;
      await repository.upsertAudioSegment(
        AudioSegment(
          id: map['id'] as String,
          sessionId: sessionId,
          filePath: map['filePath'] as String,
          timelineStartMs: map['timelineStartMs'] as int,
          durationMs: map['durationMs'] as int,
          sequence: map['sequence'] as int,
        ),
      );
    }
    for (final item in (json['events'] as List<dynamic>? ?? const [])) {
      final map = item as Map<String, dynamic>;
      await repository.insertTimelineEvent(
        TimelineEvent(
          id: map['id'] as String,
          sessionId: sessionId,
          type: TimelineEventType.interruption,
          offsetMs: map['offsetMs'] as int,
          title: map['title'] as String?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            map['createdAt'] as int,
          ),
        ),
      );
    }
    final transcripts = <TranscriptSegment>[];
    for (final item in (json['transcripts'] as List<dynamic>? ?? const [])) {
      final map = item as Map<String, dynamic>;
      transcripts.add(
        TranscriptSegment(
          id: map['id'] as String,
          sessionId: sessionId,
          startMs: map['startMs'] as int,
          endMs: map['endMs'] as int,
          text: map['text'] as String,
          speakerLabel: map['speakerLabel'] as String?,
        ),
      );
    }
    await repository.replaceTranscripts(sessionId, transcripts);
  }

  Future<void> recoverInterruptedSessions() async {
    final currentServiceSession = await FlutterForegroundTask.getData<String>(
      key: _sessionIdKey,
    );
    final running = await isRunning;
    for (final session in await repository.listIncompleteSessions()) {
      if (running && currentServiceSession == session.id) {
        continue;
      }
      await syncManifest(session.id);
      await _recoverOrphanSegments(session.id);
      final segments = await repository.listAudioSegments(session.id);
      final duration = segments.fold(
        0,
        (sum, segment) => sum + segment.durationMs,
      );
      await repository.insertTimelineEvent(
        TimelineEvent(
          id: 'recovery-${session.id}-$duration',
          sessionId: session.id,
          type: TimelineEventType.interruption,
          offsetMs: duration,
          title: 'App或录音服务异常结束，已恢复此前落盘数据',
          createdAt: DateTime.now(),
        ),
      );
      await repository.updateSession(
        session.copyWith(
          status: SessionStatus.interrupted,
          durationMs: duration,
        ),
      );
    }
  }

  Future<void> _recoverOrphanSegments(String sessionId) async {
    final audioDir = await storage.audioDirectory(sessionId);
    final files = await audioDir
        .list()
        .where(
          (entity) =>
              entity is File &&
              {'.m4a', '.wav'}.contains(p.extension(entity.path)),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final known = {
      for (final segment in await repository.listAudioSegments(sessionId))
        segment.filePath: segment,
    };
    var timelineStartMs = 0;
    for (var sequence = 0; sequence < files.length; sequence++) {
      final file = files[sequence];
      var durationMs = known[file.path]?.durationMs;
      if (durationMs == null) {
        final player = AudioPlayer();
        try {
          durationMs =
              (await player.setFilePath(file.path))?.inMilliseconds ?? 0;
        } catch (_) {
          durationMs = 0;
        } finally {
          await player.dispose();
        }
      }
      if (durationMs > 0) {
        await repository.upsertAudioSegment(
          AudioSegment(
            id: '$sessionId-segment-$sequence',
            sessionId: sessionId,
            filePath: file.path,
            timelineStartMs: timelineStartMs,
            durationMs: durationMs,
            sequence: sequence,
          ),
        );
        timelineStartMs += durationMs;
      }
    }
  }
}

class RecordingException implements Exception {
  const RecordingException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<void> waitForFinalizedRecordingManifest({
  required Directory sessionDirectory,
  required int expectedOffsetMs,
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final manifest = File(
    p.join(sessionDirectory.path, 'recording_manifest.json'),
  );
  final deadline = DateTime.now().add(timeout);
  Object? lastError;

  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await manifest.exists()) {
        final json =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        final segments = json['segments'] as List<dynamic>? ?? const [];
        final finalizedDurationMs = segments.fold<int>(0, (sum, item) {
          final map = item as Map<String, dynamic>;
          return sum + (map['durationMs'] as int? ?? 0);
        });
        // The service persists its active offset once per second. Final media
        // must cover at least that saved position before review can load it.
        if (segments.isNotEmpty && finalizedDurationMs >= expectedOffsetMs) {
          return;
        }
      }
    } catch (error) {
      // The manifest is replaced atomically, but tolerate a transient read
      // while a vendor filesystem completes the rename.
      lastError = error;
    }
    await Future<void>.delayed(pollInterval);
  }

  throw RecordingException(
    '录音服务已停止，但最后音频分片未在${timeout.inSeconds}秒内完成落盘'
    '${lastError == null ? '' : '：$lastError'}',
  );
}

class RecordingTaskHandler extends TaskHandler {
  static const _segmentLengthMs = 5 * 60 * 1000;
  static const _bytesPerSample = 2;

  final AudioRecorder _recorder = AudioRecorder();
  final List<Map<String, Object?>> _segments = [];
  final List<Map<String, Object?>> _events = [];
  final List<Map<String, Object?>> _transcripts = [];

  StreamSubscription<RecordState>? _stateSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  RandomAccessFile? _audioFile;
  LocalAsrWorker? _localAsr;
  CloudRealtimeTranscriber? _cloudTranscriber;

  String _sessionId = '';
  String _sessionDir = '';
  String _currentAudioPath = '';
  String _cloudProxyUrl = '';
  String _cloudAccessToken = '';
  int _timelineSamples = 0;
  int _segmentStartSamples = 0;
  int _segmentSamples = 0;
  int _sequence = 0;
  int _transcriptSequence = 0;
  int _nextCloudRetryMs = 0;
  int _cloudRetrySeconds = 2;
  int _cloudConnectionSequence = 0;
  bool _paused = false;
  bool _manualTransition = false;
  bool _segmentOpen = false;
  bool _manifestDirty = false;
  bool _cloudEnabled = false;
  bool _cloudConnecting = false;
  bool _cloudConnected = false;
  bool _destroyed = false;
  Future<void> _manifestWrites = Future<void>.value();

  int get _timelineMs => _timelineSamples * 1000 ~/ asrSampleRate;
  int get _segmentStartMs => _segmentStartSamples * 1000 ~/ asrSampleRate;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _sessionId =
        await FlutterForegroundTask.getData<String>(key: _sessionIdKey) ?? '';
    _sessionDir =
        await FlutterForegroundTask.getData<String>(key: _sessionDirKey) ?? '';
    if (_sessionId.isEmpty || _sessionDir.isEmpty) {
      throw StateError('缺少录音服务配置');
    }
    await Directory(p.join(_sessionDir, 'audio')).create(recursive: true);
    await _restoreExistingManifest();
    _stateSubscription = _recorder.onStateChanged().listen(_onRecorderState);
    await _loadCloudConfiguration();
    _localAsr = LocalAsrWorker(onEvent: _onLocalAsrEvent);
    await _startSegment();
    unawaited(_initializeRecognizer());
    if (_cloudEnabled) unawaited(_connectCloud());
  }

  Future<void> _restoreExistingManifest() async {
    final manifest = File(p.join(_sessionDir, 'recording_manifest.json'));
    if (!await manifest.exists()) return;
    try {
      final data =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final segments = (data['segments'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final segment in segments) {
        _segments.add(Map<String, Object?>.from(segment));
      }
      for (final event in (data['events'] as List<dynamic>? ?? const [])) {
        _events.add(Map<String, Object?>.from(event as Map));
      }
      for (final transcript
          in (data['transcripts'] as List<dynamic>? ?? const [])) {
        _transcripts.add(Map<String, Object?>.from(transcript as Map));
      }
      final durationMs = segments.fold<int>(
        0,
        (sum, segment) => sum + ((segment['durationMs'] as num?)?.round() ?? 0),
      );
      _timelineSamples = durationMs * asrSampleRate ~/ 1000;
      _sequence = segments.length;
      _transcriptSequence = _transcripts.length;
    } catch (_) {
      // A malformed manifest must not prevent a new recoverable segment.
    }
  }

  Future<void> _loadCloudConfiguration() async {
    _cloudEnabled =
        await FlutterForegroundTask.getData<bool>(key: _cloudEnabledKey) ??
        false;
    _cloudProxyUrl =
        await FlutterForegroundTask.getData<String>(key: _cloudProxyUrlKey) ??
        '';
    _cloudAccessToken =
        await FlutterForegroundTask.getData<String>(
          key: _cloudAccessTokenKey,
        ) ??
        '';
    _cloudEnabled =
        _cloudEnabled &&
        _cloudProxyUrl.isNotEmpty &&
        _cloudAccessToken.isNotEmpty;
    FlutterForegroundTask.sendDataToMain({
      'type': 'cloudTranscriptionStatus',
      'state': _cloudEnabled ? 'connecting' : 'disabled',
    });
  }

  Future<void> _initializeRecognizer() async {
    try {
      final encoder = await FlutterForegroundTask.getData<String>(
        key: _asrEncoderKey,
      );
      final decoder = await FlutterForegroundTask.getData<String>(
        key: _asrDecoderKey,
      );
      final joiner = await FlutterForegroundTask.getData<String>(
        key: _asrJoinerKey,
      );
      final tokens = await FlutterForegroundTask.getData<String>(
        key: _asrTokensKey,
      );
      if (_destroyed) return;
      if ([
        encoder,
        decoder,
        joiner,
        tokens,
      ].any((value) => value == null || value.isEmpty)) {
        throw StateError('缺少实时转写模型');
      }
      final worker = _localAsr!;
      await worker.start(
        TranscriptionModelFiles(
          encoder: encoder!,
          decoder: decoder!,
          joiner: joiner!,
          tokens: tokens!,
        ),
      );
    } catch (error) {
      _disableRecognizer(error);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_onTick());

  Future<void> _onTick() async {
    if (_destroyed) return;
    await _rewriteWavHeader(flush: true);
    if (_manifestDirty) {
      _manifestDirty = false;
      await _writeManifest();
    }
    await FlutterForegroundTask.saveData(
      key: _activeOffsetKey,
      value: _timelineMs,
    );
    await FlutterForegroundTask.updateService(
      notificationText:
          '${_format(_timelineMs)} · ${_paused ? '已暂停' : '录音与转写中'}',
    );
    if (!_paused && _timelineMs - _segmentStartMs >= _segmentLengthMs) {
      await _completeSegment();
      await _startSegment();
    }
    if (_cloudEnabled &&
        !_paused &&
        !_cloudConnected &&
        !_cloudConnecting &&
        _timelineMs >= _nextCloudRetryMs) {
      unawaited(_connectCloud());
    }
  }

  Future<void> _startSegment() async {
    _segmentStartSamples = _timelineSamples;
    _segmentSamples = 0;
    _currentAudioPath = p.join(
      _sessionDir,
      'audio',
      'segment_${_sequence.toString().padLeft(4, '0')}.wav',
    );
    _audioFile = await File(_currentAudioPath).open(mode: FileMode.write);
    _audioFile!.writeFromSync(createWavHeader(dataLength: 0));
    _segmentOpen = true;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: asrSampleRate,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.pause,
      ),
    );
    _audioSubscription = stream.listen(
      _onAudioData,
      onError: (Object error) => unawaited(_handleAudioError(error)),
    );
  }

  void _onAudioData(Uint8List data) {
    if (!_segmentOpen || data.length < _bytesPerSample) return;
    final usableLength = data.length - (data.length % _bytesPerSample);
    final bytes = usableLength == data.length
        ? data
        : Uint8List.sublistView(data, 0, usableLength);
    final startMs = _timelineMs;
    _audioFile?.writeFromSync(bytes);
    final samples = usableLength ~/ _bytesPerSample;
    _segmentSamples += samples;
    _timelineSamples += samples;
    if (_cloudConnected) _cloudTranscriber?.addPcm(bytes);

    _localAsr?.addPcm(bytes, startMs: startMs, endMs: _timelineMs);
  }

  void _onLocalAsrEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'ready':
        FlutterForegroundTask.sendDataToMain({
          'type': 'transcriptionStatus',
          'ready': true,
        });
      case 'error':
        _disableRecognizer(event['error'] ?? '本地字幕不可用');
      case 'partial':
        if (!_cloudConnected) {
          FlutterForegroundTask.sendDataToMain({
            ...event,
            'type': 'transcriptPartial',
            'source': 'local',
          });
        }
      case 'final':
        _saveTranscript(
          event['text']! as String,
          event['startMs']! as int,
          event['endMs']! as int,
        );
    }
  }

  void _saveTranscript(String text, int startMs, int endMs) {
    // A late worker result must not reintroduce text already replaced by cloud ASR.
    if (_transcripts.any(
      (item) =>
          item['speakerLabel'] != '本地初稿' &&
          (item['startMs']! as int) < endMs &&
          (item['endMs']! as int) > startMs,
    ))
      return;
    if (text.isNotEmpty) {
      final item = <String, Object?>{
        'id': '$_sessionId-transcript-$_transcriptSequence',
        'startMs': startMs,
        'endMs': endMs,
        'text': text,
        'speakerLabel': '本地初稿',
      };
      _transcriptSequence++;
      _transcripts.add(item);
      _manifestDirty = true;
      if (!_cloudConnected) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'transcriptFinal',
          'source': 'local',
          ...item,
        });
      }
    }
  }

  Future<void> _flushRecognition() async {
    await _localAsr?.flush();
  }

  void _disableRecognizer(Object error) {
    _localAsr?.close();
    FlutterForegroundTask.sendDataToMain({
      'type': 'transcriptionStatus',
      'ready': false,
      'error': error.toString(),
    });
  }

  Future<void> _connectCloud() async {
    if (!_cloudEnabled || _paused || _cloudConnecting || _cloudConnected) {
      return;
    }
    _cloudConnecting = true;
    _cloudConnectionSequence++;
    final connectionSequence = _cloudConnectionSequence;
    final client = CloudRealtimeTranscriber(
      proxyUrl: _cloudProxyUrl,
      accessToken: _cloudAccessToken,
      sessionId: _sessionId,
      baseOffsetMs: _timelineMs,
      onEvent: (event) =>
          _onCloudEvent(clientSequence: connectionSequence, event: event),
    );
    _cloudTranscriber = client;
    FlutterForegroundTask.sendDataToMain({
      'type': 'cloudTranscriptionStatus',
      'state': 'connecting',
    });
    try {
      await client.connect();
    } catch (error) {
      await client.close();
      if (_cloudConnectionSequence != connectionSequence) return;
      _cloudTranscriber = null;
      _cloudConnecting = false;
      _scheduleCloudRetry('云端连接失败：$error');
    }
  }

  void _onCloudEvent({
    required int clientSequence,
    required CloudProxyEvent event,
  }) {
    if (clientSequence != _cloudConnectionSequence) return;
    switch (event) {
      case CloudProxyReady():
        _cloudConnecting = false;
        _cloudConnected = true;
        _cloudRetrySeconds = 2;
        FlutterForegroundTask.sendDataToMain({
          'type': 'cloudTranscriptionStatus',
          'state': 'connected',
        });
      case CloudTranscriptUpdate():
        if (event.isFinal) {
          _saveCloudTranscript(event, clientSequence);
        } else {
          FlutterForegroundTask.sendDataToMain({
            'type': 'transcriptPartial',
            'source': 'cloud',
            'startMs': event.startMs,
            'endMs': event.endMs,
            'text': event.text,
          });
        }
      case CloudProxyFinished():
        _cloudConnecting = false;
        _cloudConnected = false;
      case CloudProxyFailure():
        _cloudConnecting = false;
        _cloudConnected = false;
        final failedClient = _cloudTranscriber;
        _cloudTranscriber = null;
        unawaited(failedClient?.close());
        _scheduleCloudRetry(event.message);
    }
  }

  void _saveCloudTranscript(
    CloudTranscriptUpdate update,
    int connectionSequence,
  ) {
    final startMs = update.startMs.clamp(0, _timelineMs);
    final endMs = update.endMs.clamp(startMs, _timelineMs);
    _transcripts.removeWhere((item) {
      final isLocal = item['speakerLabel'] == '本地初稿';
      final itemStart = item['startMs']! as int;
      final itemEnd = item['endMs']! as int;
      return isLocal && itemStart < endMs && itemEnd > startMs;
    });
    final item = <String, Object?>{
      'id': '$_sessionId-cloud-$connectionSequence-${update.sentenceId}',
      'startMs': startMs,
      'endMs': endMs,
      'text': update.text,
      'speakerLabel': update.speakerId == null || update.speakerId! < 0
          ? '腾讯云'
          : '讲解人${update.speakerId! + 1}',
    };
    _transcripts.removeWhere((existing) => existing['id'] == item['id']);
    _transcripts.add(item);
    _transcripts.sort(
      (a, b) => (a['startMs']! as int).compareTo(b['startMs']! as int),
    );
    _manifestDirty = true;
    FlutterForegroundTask.sendDataToMain({
      'type': 'transcriptFinal',
      'source': 'cloud',
      'replaceLocal': true,
      ...item,
    });
  }

  void _scheduleCloudRetry(String message) {
    _nextCloudRetryMs = _timelineMs + _cloudRetrySeconds * 1000;
    _cloudRetrySeconds = (_cloudRetrySeconds * 2).clamp(2, 30);
    FlutterForegroundTask.sendDataToMain({
      'type': 'cloudTranscriptionStatus',
      'state': 'fallback',
      'error': message,
      'retryInSeconds': _cloudRetrySeconds,
    });
  }

  Future<void> _finishCloud() async {
    final client = _cloudTranscriber;
    _cloudTranscriber = null;
    _cloudConnecting = false;
    _cloudConnected = false;
    if (client != null) await client.finish();
  }

  Future<void> _handleAudioError(Object error) async {
    if (_paused) return;
    _paused = true;
    await _finishCloud();
    await _addEvent('录音数据流中断：$error');
    FlutterForegroundTask.sendDataToMain({
      'type': 'interruption',
      'offsetMs': _timelineMs,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _completeSegment() async {
    if (!_segmentOpen) return;
    _segmentOpen = false;
    await _recorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _rewriteWavHeader(flush: true);
    await _audioFile?.close();
    _audioFile = null;

    if (_segmentSamples > 0 && await File(_currentAudioPath).exists()) {
      final durationMs = _segmentSamples * 1000 ~/ asrSampleRate;
      _segments.add({
        'id': '$_sessionId-segment-$_sequence',
        'filePath': _currentAudioPath,
        'timelineStartMs': _segmentStartMs,
        'durationMs': durationMs,
        'sequence': _sequence,
      });
      _sequence++;
      await _writeManifest();
      FlutterForegroundTask.sendDataToMain({
        'type': 'segment',
        'offsetMs': _timelineMs,
      });
    }
  }

  Future<void> _rewriteWavHeader({required bool flush}) async {
    final file = _audioFile;
    if (file == null) return;
    final end = file.positionSync();
    file
      ..setPositionSync(0)
      ..writeFromSync(
        createWavHeader(dataLength: _segmentSamples * _bytesPerSample),
      )
      ..setPositionSync(end);
    if (flush) file.flushSync();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final command = data['command'];
    if (command == 'pause') unawaited(_pause());
    if (command == 'resume') unawaited(_resume());
  }

  Future<void> _pause() async {
    if (_paused) return;
    _manualTransition = true;
    await _recorder.pause();
    _paused = true;
    await _finishCloud();
    await _flushRecognition();
    await _rewriteWavHeader(flush: true);
    await _addEvent('用户暂停录音');
    _manualTransition = false;
  }

  Future<void> _resume() async {
    if (!_paused) return;
    _manualTransition = true;
    await _recorder.resume();
    _paused = false;
    if (_cloudEnabled) unawaited(_connectCloud());
    await _addEvent('用户继续录音');
    _manualTransition = false;
  }

  void _onRecorderState(RecordState state) {
    if (_manualTransition) return;
    if (state == RecordState.pause && !_paused) {
      _paused = true;
      unawaited(_flushRecognition());
      unawaited(_finishCloud());
      unawaited(_addEvent('麦克风被电话或其他应用占用，录音已中断'));
      FlutterForegroundTask.sendDataToMain({
        'type': 'interruption',
        'offsetMs': _timelineMs,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _addEvent(String title) async {
    _events.add({
      'id': '$_sessionId-service-${DateTime.now().microsecondsSinceEpoch}',
      'offsetMs': _timelineMs,
      'title': title,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeManifest();
  }

  Future<void> _writeManifest() {
    final snapshot = jsonEncode({
      'segments': _segments,
      'events': _events,
      'transcripts': _transcripts,
    });
    final write = _manifestWrites.then((_) async {
      final target = File(p.join(_sessionDir, 'recording_manifest.json'));
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      // Atomic replacement on Android/iOS. Never delete the last good manifest.
      await temporary.rename(target.path);
    });
    _manifestWrites = write.catchError((Object _) {});
    return write;
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _destroyed = true;
    await _completeSegment();
    await _flushRecognition();
    await _finishCloud();
    await _writeManifest();
    await _stateSubscription?.cancel();
    await _recorder.dispose();
    _localAsr?.close();
    await FlutterForegroundTask.saveData(
      key: _activeOffsetKey,
      value: _timelineMs,
    );
  }

  String _format(int value) {
    final seconds = value ~/ 1000;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

Uint8List createWavHeader({
  required int dataLength,
  int sampleRate = asrSampleRate,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final bytesPerSecond = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final data = ByteData(44);

  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, bytesPerSecond, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  return data.buffer.asUint8List();
}
