import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/timeline_clock.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';
import '../services/ai_processing_service.dart';
import '../services/background_recording_service.dart';
import '../services/gallery_photo_picker.dart';
import '../services/media_storage.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/text_input_dialog.dart';
import '../widgets/timeline_event_tile.dart';
import 'camera_capture_screen.dart';
import 'review_screen.dart';

class LiveRecordScreen extends StatefulWidget {
  const LiveRecordScreen({
    required this.session,
    required this.repository,
    required this.storage,
    required this.recording,
    required this.aiService,
    required this.autoStart,
    this.galleryPicker,
    super.key,
  });
  final Session session;
  final AppRepository repository;
  final MediaStorage storage;
  final BackgroundRecordingService recording;
  final AiProcessingService aiService;
  final bool autoStart;
  final GalleryPhotoPicker? galleryPicker;

  @override
  State<LiveRecordScreen> createState() => _LiveRecordScreenState();
}

class _LiveRecordScreenState extends State<LiveRecordScreen>
    with WidgetsBindingObserver {
  final _uuid = const Uuid();
  final TimelineClock _clock = TimelineClock(PlatformMonotonicClock());
  late final GalleryPhotoPicker _galleryPicker;
  late Session _session;
  List<TimelineEvent> _events = [];
  List<TranscriptSegment> _transcripts = [];
  Timer? _timer;
  StreamSubscription<Object>? _serviceSubscription;
  int _offsetMs = 0;
  int _photoCount = 0;
  String _currentChapter = '章节1';
  bool _busy = true;
  bool _transcriptionReady = false;
  String _cloudTranscriptionState = 'disabled';
  String _partialTranscript = '';
  String? _transcriptionError;
  String? _error;

  bool get _paused => _session.status == SessionStatus.paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _galleryPicker = widget.galleryPicker ?? ImagePickerGalleryPhotoPicker();
    _session = widget.session;
    _serviceSubscription = widget.recording.taskDataStream.listen(
      _onServiceData,
    );
    _initialize();
  }

  Future<void> _onServiceData(Object data) async {
    if (data is! Map) {
      return;
    }
    if (data['type'] == 'segment') {
      await widget.recording.syncManifest(_session.id);
      return;
    }
    if (data['type'] == 'transcriptionStatus') {
      if (mounted) {
        setState(() {
          _transcriptionReady = data['ready'] == true;
          _transcriptionError = data['error'] as String?;
        });
      }
      return;
    }
    if (data['type'] == 'cloudTranscriptionStatus') {
      if (mounted) {
        setState(() {
          _cloudTranscriptionState = data['state'] as String? ?? 'fallback';
        });
      }
      return;
    }
    if (data['type'] == 'transcriptPartial') {
      if (mounted) {
        setState(() => _partialTranscript = data['text'] as String? ?? '');
      }
      return;
    }
    if (data['type'] == 'transcriptFinal') {
      final startMs = data['startMs'] as int;
      final endMs = data['endMs'] as int;
      if (data['replaceLocal'] == true) {
        await widget.repository.deleteLocalTranscriptsOverlapping(
          sessionId: _session.id,
          startMs: startMs,
          endMs: endMs,
        );
      }
      final transcript = TranscriptSegment(
        id: data['id'] as String,
        sessionId: _session.id,
        startMs: startMs,
        endMs: endMs,
        text: data['text'] as String,
        speakerLabel: data['speakerLabel'] as String?,
      );
      await widget.repository.insertTranscript(transcript);
      final stored = await widget.repository.listTranscripts(_session.id);
      if (mounted) {
        setState(() {
          _transcripts = stored;
          _partialTranscript = '';
        });
      }
      return;
    }
    if (data['type'] == 'interruption') {
      await _clock.pause();
      _session = _session.copyWith(status: SessionStatus.paused);
      await widget.repository.updateSession(_session);
      await widget.recording.syncManifest(_session.id);
      _events = await widget.repository.listTimelineEvents(_session.id);
      _transcripts = await widget.repository.listTranscripts(_session.id);
      _transcripts = await widget.repository.listTranscripts(_session.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('麦克风被电话或其他应用占用，录音已暂停。请确认后点“继续”。'),
            duration: Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _initialize() async {
    try {
      _events = await widget.repository.listTimelineEvents(_session.id);
      _photoCount = _events
          .where((event) => event.type == TimelineEventType.photo)
          .length;
      final chapters = _events
          .where((event) => event.type == TimelineEventType.chapter)
          .toList();
      if (chapters.isNotEmpty) {
        _currentChapter = chapters.last.title ?? '章节${chapters.length}';
      }
      if (widget.autoStart) {
        _session = _session.copyWith(
          status: SessionStatus.recording,
          recordingStartedAt: DateTime.now(),
        );
        await widget.repository.updateSession(_session);
        await widget.recording.start(_session);
        await _clock.start();
        await _addEvent(
          TimelineEventType.chapter,
          title: '章节1',
          offsetOverride: 0,
        );
      } else {
        await widget.recording.syncManifest(_session.id);
        final existingOffset = await widget.recording.activeOffsetMs();
        await _clock.start(initialOffsetMs: existingOffset);
        if (_session.status == SessionStatus.paused) await _clock.pause();
      }
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshOffset(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      unawaited(_recoverLostGalleryPhoto());
    } catch (error) {
      _session = _session.copyWith(status: SessionStatus.failed);
      await widget.repository.updateSession(_session);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _refreshOffset() async {
    final value = await _clock.offsetMs();
    if (mounted) setState(() => _offsetMs = value);
  }

  Future<void> _addEvent(
    TimelineEventType type, {
    String? title,
    String? note,
    String? photoPath,
    String? thumbnailPath,
    int? offsetOverride,
  }) async {
    final event = TimelineEvent(
      id: _uuid.v4(),
      sessionId: _session.id,
      type: type,
      offsetMs: offsetOverride ?? await _clock.offsetMs(),
      title: title,
      note: note,
      photoPath: photoPath,
      thumbnailPath: thumbnailPath,
      createdAt: DateTime.now(),
    );
    await widget.repository.insertTimelineEvent(event);
    if (mounted) {
      setState(
        () =>
            _events = [..._events, event]
              ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs)),
      );
    }
  }

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<PhotoSourceChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const PhotoSourceSheet(),
    );
    if (!mounted || source == null) return;
    switch (source) {
      case PhotoSourceChoice.camera:
        await _takePhoto();
      case PhotoSourceChoice.gallery:
        await _importGalleryPhoto();
    }
  }

  Future<void> _takePhoto() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('需要相机权限才能拍照')));
      }
      return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<CameraCaptureResult>(
      MaterialPageRoute(
        builder: (_) => CameraCaptureScreen(offsetProvider: _clock.offsetMs),
      ),
    );
    if (result == null) return;
    try {
      await _persistPhoto(
        sourcePath: result.temporaryPath,
        offsetMs: result.offsetMs,
      );
    } catch (error) {
      _showPhotoError('照片保存失败', error);
    }
  }

  Future<void> _importGalleryPhoto() async {
    final offsetMs = await _clock.offsetMs();
    try {
      await widget.storage.writePendingGalleryImport(
        sessionId: _session.id,
        offsetMs: offsetMs,
      );
      final sourcePath = await _galleryPicker.pickImage();
      if (sourcePath == null) return;
      await _persistPhoto(sourcePath: sourcePath, offsetMs: offsetMs);
    } catch (error) {
      _showPhotoError('相册导入失败', error);
    } finally {
      await widget.storage.clearPendingGalleryImport(_session.id);
    }
  }

  Future<void> _recoverLostGalleryPhoto() async {
    try {
      final pendingOffset = await widget.storage.readPendingGalleryImportOffset(
        _session.id,
      );
      final paths = await _galleryPicker.retrieveLostImages();
      if (paths.isEmpty) return;
      await _persistPhoto(
        sourcePath: paths.first,
        offsetMs: pendingOffset ?? await _clock.offsetMs(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复上次未完成的相册照片导入')));
      }
    } catch (error) {
      _showPhotoError('恢复相册照片失败', error);
    } finally {
      await widget.storage.clearPendingGalleryImport(_session.id);
    }
  }

  Future<void> _persistPhoto({
    required String sourcePath,
    required int offsetMs,
  }) async {
    final stored = await widget.storage.storePhoto(
      sessionId: _session.id,
      sourcePath: sourcePath,
    );
    final note = mounted
        ? await _optionalTextDialog(title: '添加照片备注', hint: '一句话即可，也可以跳过')
        : null;
    await _addEvent(
      TimelineEventType.photo,
      title: '照片 ${_photoCount + 1}',
      note: note,
      photoPath: stored.path,
      thumbnailPath: stored.thumbnailPath,
      offsetOverride: offsetMs,
    );
    if (mounted) setState(() => _photoCount++);
  }

  void _showPhotoError(String title, Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title：$error')));
    }
  }

  Future<String?> _optionalTextDialog({
    required String title,
    required String hint,
  }) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => TextInputDialog(
        title: title,
        hintText: hint,
        maxLength: 80,
        cancelLabel: '跳过',
        submitLabel: '保存',
      ),
    );
    return result?.isEmpty == true ? null : result;
  }

  Future<void> _newChapter() async {
    final number =
        _events
            .where((event) => event.type == TimelineEventType.chapter)
            .length +
        1;
    final entered = await _optionalTextDialog(
      title: '新章节',
      hint: '留空则命名为“章节$number”',
    );
    final title = entered ?? '章节$number';
    await _addEvent(TimelineEventType.chapter, title: title);
    if (mounted) setState(() => _currentChapter = title);
  }

  Future<void> _togglePause() async {
    if (_paused) {
      widget.recording.resume();
      await _clock.resume();
      _session = _session.copyWith(status: SessionStatus.recording);
    } else {
      widget.recording.pause();
      await _clock.pause();
      _session = _session.copyWith(status: SessionStatus.paused);
    }
    await widget.repository.updateSession(_session);
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次记录？'),
        content: const Text('录音会停止并保存，之后可在回顾页播放和整理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续记录'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束并保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final offset = await _clock.pause();
    await widget.recording.stop();
    await widget.recording.syncManifest(_session.id);
    final segments = await widget.repository.listAudioSegments(_session.id);
    final mediaDuration = segments.fold(
      0,
      (sum, segment) => sum + segment.durationMs,
    );
    _session = _session.copyWith(
      status: SessionStatus.completed,
      durationMs: mediaDuration > 0 ? mediaDuration : offset,
    );
    await widget.repository.updateSession(_session);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          session: _session,
          repository: widget.repository,
          storage: widget.storage,
          aiService: widget.aiService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _serviceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('无法开始录音\n$_error', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_session.title),
          automaticallyImplyLeading: false,
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Card(
                        color: _paused
                            ? Colors.orange.shade100
                            : Colors.red.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                _paused
                                    ? Icons.pause_circle
                                    : Icons.fiber_manual_record,
                                color: _paused
                                    ? Colors.orange.shade900
                                    : Colors.red.shade800,
                                size: 34,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _paused ? '录音已暂停' : '正在录音',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      formatDuration(_offsetMs),
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Text('$_photoCount 张照片'),
                                  const SizedBox(height: 4),
                                  Text(_currentChapter),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _LiveTranscriptCard(
                        ready:
                            _transcriptionReady ||
                            _cloudTranscriptionState == 'connected',
                        paused: _paused,
                        cloudState: _cloudTranscriptionState,
                        partialText: _partialTranscript,
                        finalizedText: _transcripts.isEmpty
                            ? ''
                            : _transcripts.last.text,
                        error: _transcriptionError,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.05,
                        children: [
                          _ActionButton(
                            icon: Icons.add_photo_alternate_outlined,
                            label: '照片',
                            onPressed: _choosePhotoSource,
                            primary: true,
                          ),
                          _ActionButton(
                            icon: Icons.star,
                            label: '重点',
                            onPressed: () => _addEvent(
                              TimelineEventType.highlight,
                              title: '重点',
                            ),
                          ),
                          _ActionButton(
                            icon: Icons.help_outline,
                            label: '没听懂',
                            onPressed: () => _addEvent(
                              TimelineEventType.question,
                              title: '没听懂',
                            ),
                          ),
                          _ActionButton(
                            icon: Icons.bookmark_add_outlined,
                            label: '新章节',
                            onPressed: _newChapter,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _togglePause,
                              icon: Icon(_paused ? Icons.mic : Icons.pause),
                              label: Text(_paused ? '继续' : '暂停'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _finish,
                              icon: const Icon(Icons.stop),
                              label: const Text('结束'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '最近添加',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _events.isEmpty
                          ? const Center(child: Text('拍照或标记后会显示在这里'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: _events.length.clamp(0, 5),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) => TimelineEventTile(
                                event: _events.reversed.elementAt(index),
                                onTap: () {},
                              ),
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LiveTranscriptCard extends StatelessWidget {
  const _LiveTranscriptCard({
    required this.ready,
    required this.paused,
    required this.cloudState,
    required this.partialText,
    required this.finalizedText,
    required this.error,
  });

  final bool ready;
  final bool paused;
  final String cloudState;
  final String partialText;
  final String finalizedText;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = partialText.isNotEmpty
        ? partialText
        : finalizedText.isNotEmpty
        ? finalizedText
        : ready
        ? '说话后字幕会显示在这里'
        : error == null
        ? '正在加载本地转写模型…'
        : '转写暂不可用，原始录音仍在继续';
    return Semantics(
      liveRegion: true,
      label: '实时转写初稿：$text',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    error != null
                        ? Icons.subtitles_off_outlined
                        : Icons.subtitles_outlined,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '实时转写（初稿）',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    paused
                        ? '已暂停'
                        : switch (cloudState) {
                            'connected' => '腾讯云',
                            'connecting' => '连接云端',
                            'fallback' => '本地兜底',
                            _ => ready ? '离线识别' : '准备中',
                          },
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.35,
                  color: partialText.isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : FilledButton.tonal(onPressed: onPressed, child: child);
  }
}
