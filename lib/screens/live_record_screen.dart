import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/timeline_clock.dart';
import '../core/user_facing_error.dart';
import '../core/widgets/permission_explanation_sheet.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';
import '../services/ai_processing_service.dart';
import '../services/background_recording_service.dart';
import '../services/gallery_photo_picker.dart';
import '../services/document_scanner.dart';
import '../services/media_storage.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/recording_quick_actions.dart';
import '../widgets/text_input_dialog.dart';
import '../widgets/timeline_event_tile.dart';
import 'camera_capture_screen.dart';

class LiveRecordScreen extends StatefulWidget {
  const LiveRecordScreen({
    required this.session,
    required this.repository,
    required this.storage,
    required this.recording,
    required this.aiService,
    required this.autoStart,
    this.galleryPicker,
    this.resumeOffsetMs,
    super.key,
  });
  final Session session;
  final AppRepository repository;
  final MediaStorage storage;
  final BackgroundRecordingService recording;
  final AiProcessingService aiService;
  final bool autoStart;
  final GalleryPhotoPicker? galleryPicker;
  final int? resumeOffsetMs;

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
      // The foreground task writes the interruption into its durable manifest;
      // syncing it here avoids creating a duplicate event in SQLite.
      await widget.recording.syncManifest(_session.id);
      _events = await widget.repository.listTimelineEvents(_session.id);
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
        final requestNotifications = await _prepareRecordingPermissions();
        _session = _session.copyWith(
          status: SessionStatus.recording,
          recordingStartedAt: DateTime.now(),
        );
        await widget.repository.updateSession(_session);
        await widget.recording.start(
          _session,
          requestNotifications: requestNotifications,
        );
        await _clock.start(initialOffsetMs: widget.resumeOffsetMs ?? 0);
        if (widget.resumeOffsetMs == null) {
          await _addEvent(
            TimelineEventType.chapter,
            title: '章节1',
            offsetOverride: 0,
          );
        } else {
          await _addEvent(
            TimelineEventType.interruption,
            title: '已从异常保存点继续录音',
            offsetOverride: widget.resumeOffsetMs,
          );
        }
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
      unawaited(_recoverDocumentScans());
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

  Future<bool> _prepareRecordingPermissions() async {
    var microphone = await Permission.microphone.status;
    if (!mounted) throw const RecordingException('页面已关闭，未开始录音。');
    if (!microphone.isGranted) {
      final proceed = await PermissionExplanationSheet.show(
        context,
        icon: Icons.mic_none_rounded,
        title: '允许使用麦克风',
        message: '麦克风用于持续录制这条本地讲记，并为实时字幕提供音频。原始录音不会被自动上传。',
        actionLabel: '继续授权',
      );
      if (!proceed) throw const RecordingException('未获得麦克风权限，录音尚未开始。');
      microphone = await Permission.microphone.request();
    }
    if (!microphone.isGranted) {
      throw const RecordingException('麦克风权限未开启。请在系统设置中允许后重新开始。');
    }

    if (await Permission.notification.isDenied && mounted) {
      final proceed = await PermissionExplanationSheet.show(
        context,
        icon: Icons.notifications_active_outlined,
        title: '显示录音通知',
        message: '持久通知用于明确提示后台录音状态，并让你从锁屏或其他应用快速返回。拒绝不会删除任何数据。',
        actionLabel: '允许通知',
      );
      if (!proceed) return false;
      return (await Permission.notification.request()).isGranted;
    }
    return true;
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
    String? photoSource,
    int? offsetOverride,
    DateTime? deviceTime,
    String? eventId,
  }) async {
    final event = TimelineEvent(
      id: eventId ?? _uuid.v4(),
      sessionId: _session.id,
      type: type,
      offsetMs: offsetOverride ?? await _clock.offsetMs(),
      title: title,
      note: note,
      photoPath: photoPath,
      thumbnailPath: thumbnailPath,
      photoSource: photoSource,
      // createdAt is the device wall-clock timestamp; offsetMs remains the
      // monotonic, pause-aware playback position.
      createdAt: deviceTime ?? DateTime.now(),
    );
    await widget.repository.insertTimelineEvent(event);
    if (mounted) {
      // The camera shows its own durable saved-count. A global snackbar would
      // cover its shutter for two seconds and swallow the next capture tap.
      final cameraPhoto =
          type == TimelineEventType.photo && photoSource == 'camera';
      if (!cameraPhoto &&
          (type != TimelineEventType.chapter || offsetOverride != 0)) {
        HapticFeedback.selectionClick();
        final label = type == TimelineEventType.highlight
            ? '已标记重点'
            : type == TimelineEventType.question
            ? '已记录疑问'
            : type == TimelineEventType.text
            ? '已保存备注'
            : type == TimelineEventType.chapter
            ? '已开始新章节'
            : type == TimelineEventType.interruption
            ? (title ?? '录音状态已记录')
            : '照片已加入时间轴';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label · ${formatDuration(event.offsetMs)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
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
      case PhotoSourceChoice.document:
        await _scanDocument();
      case PhotoSourceChoice.gallery:
        await _importGalleryPhoto();
    }
  }

  Future<void> _scanDocument() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PPT / 文档扫描'),
        content: const Text(
          '直接拍摄并裁边、矫正透视，无需手动导入。首次使用可能需要 Google Play 服务下载组件。\n\n扫描器只返回处理后的图片，不提供原始快门时间；节点按进入扫描的时间定位，备注保留操作时间范围，可在回顾页调整。需要精准同步或未处理原图时，请使用“相机拍照”。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始扫描'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    try {
      final scan = await DocumentScanner().scan(
        sessionId: _session.id,
        offsetMs: await _clock.offsetMs(),
        deviceTime: DateTime.now(),
      );
      if (scan != null) await _saveDocumentScan(scan);
    } catch (error) {
      _showPhotoError('扫描不可用，请改用相机拍照', error);
    }
  }

  Future<void> _saveDocumentScan(DocumentScan scan) async {
    final eventId = 'scan-${scan.id}';
    final events = await widget.repository.listTimelineEvents(_session.id);
    if (!events.any((e) => e.id == eventId)) {
      await _persistPhoto(
        sourcePath: scan.path,
        offsetMs: scan.offsetMs,
        source: 'documentScan',
        deviceTime: scan.startedAt,
        eventId: eventId,
        note:
            '文档扫描处理图；时间点为扫描入口时间，非精确快门时间。操作范围：${formatDeviceTimestamp(scan.startedAt)} 至 ${formatDeviceTimestamp(scan.completedAt)}。可在回顾页调整时间点。',
      );
    }
    await DocumentScanner().acknowledge(scan.id);
  }

  Future<void> _recoverDocumentScans() async {
    try {
      for (final scan in await DocumentScanner().pending(_session.id)) {
        await _saveDocumentScan(scan);
      }
    } on MissingPluginException {
      // Document scanning is Android-only; ordinary camera/gallery remain.
    } catch (error) {
      _showPhotoError('扫描图片仍保存在本机，下次进入会重试导入', error);
    }
  }

  Future<void> _takePhoto() async {
    var permission = await Permission.camera.status;
    if (!mounted) return;
    if (!permission.isGranted) {
      final proceed = await PermissionExplanationSheet.show(
        context,
        icon: Icons.camera_alt_outlined,
        title: '允许使用相机',
        message: '相机只用于把现场照片保存到这条本地记录；拍摄期间录音会继续。',
        actionLabel: '继续授权',
      );
      if (!proceed) return;
      permission = await Permission.camera.request();
    }
    if (!permission.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('相机权限未开启；录音仍在继续。可在系统设置中允许后重试。')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CameraCaptureScreen(
          offsetProvider: _clock.offsetMs,
          onCapture: (result) => _persistPhoto(
            sourcePath: result.temporaryPath,
            offsetMs: result.offsetMs,
            source: 'camera',
            deviceTime: result.capturedAt,
          ),
        ),
      ),
    );
  }

  Future<void> _importGalleryPhoto() async {
    final offsetMs = await _clock.offsetMs();
    final startedAt = DateTime.now();
    try {
      await widget.storage.writePendingGalleryImport(
        sessionId: _session.id,
        offsetMs: offsetMs,
        deviceTime: startedAt,
      );
      final sourcePath = await _galleryPicker.pickImage();
      if (sourcePath == null) return;
      await _persistPhoto(
        sourcePath: sourcePath,
        offsetMs: await _clock.offsetMs(),
        source: 'gallery',
        deviceTime: DateTime.now(),
      );
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
      final pendingDeviceTime = await widget.storage
          .readPendingGalleryImportDeviceTime(_session.id);
      final paths = await _galleryPicker.retrieveLostImages();
      if (paths.isEmpty) return;
      await _persistPhoto(
        sourcePath: paths.first,
        offsetMs: pendingOffset ?? await _clock.offsetMs(),
        source: 'gallery',
        deviceTime: pendingDeviceTime ?? DateTime.now(),
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
    required String source,
    required DateTime deviceTime,
    String? note,
    String? eventId,
  }) async {
    final stored = await widget.storage.storePhoto(
      sessionId: _session.id,
      sourcePath: sourcePath,
    );
    await _addEvent(
      TimelineEventType.photo,
      title: '照片 ${_photoCount + 1}',
      note: note,
      eventId: eventId,
      photoPath: stored.path,
      thumbnailPath: stored.thumbnailPath,
      photoSource: source,
      offsetOverride: offsetMs,
      deviceTime: deviceTime,
    );
    if (mounted) setState(() => _photoCount++);
  }

  void _showPhotoError(String title, Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title：${userFacingError(error)}')),
      );
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

  Future<void> _addTextNote() async {
    final text = await _optionalTextDialog(title: '添加备注', hint: '记录此刻的想法或讲解线索');
    if (text == null || text.trim().isEmpty) return;
    await _addEvent(TimelineEventType.text, title: '备注', note: text.trim());
  }

  Future<void> _togglePause() async {
    if (_paused) {
      final deviceTime = DateTime.now();
      widget.recording.resume();
      await _clock.resume();
      _session = _session.copyWith(status: SessionStatus.recording);
      await _addEvent(
        TimelineEventType.interruption,
        title: '继续录音',
        deviceTime: deviceTime,
      );
    } else {
      final deviceTime = DateTime.now();
      widget.recording.pause();
      final offset = await _clock.pause();
      _session = _session.copyWith(status: SessionStatus.paused);
      await _addEvent(
        TimelineEventType.interruption,
        title: '暂停录音',
        offsetOverride: offset,
        deviceTime: deviceTime,
      );
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
    try {
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
      Navigator.of(context).pop(_session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('结束保存未完全完成：$error。已落盘的音频和节点不会被删除，请稍后重试。'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  void _showEventDetails(TimelineEvent event) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title ?? event.type.label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('${formatDuration(event.offsetMs)} · 录音仍在继续'),
              if (event.note?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(event.note!),
              ],
            ],
          ),
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
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_session.title),
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            tooltip: '最小化，继续录音',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  _paused ? '已暂停' : '录音中',
                  style: TextStyle(
                    color: _paused ? Colors.orange : Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
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
                            ? Theme.of(context).colorScheme.tertiaryContainer
                            : Theme.of(context).colorScheme.errorContainer
                                  .withValues(alpha: 0.55),
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
                    RecordingWaveform(active: !_paused, phase: _offsetMs),
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
                      child: RecordingQuickActions(
                        onPhoto: _choosePhotoSource,
                        onHighlight: () =>
                            _addEvent(TimelineEventType.highlight, title: '重点'),
                        onQuestion: () =>
                            _addEvent(TimelineEventType.question, title: '没听懂'),
                        onChapter: _newChapter,
                        onNote: _addTextNote,
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
                          '最近事件',
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
                                onTap: () => _showEventDetails(
                                  _events.reversed.elementAt(index),
                                ),
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

class RecordingWaveform extends StatelessWidget {
  const RecordingWaveform({
    required this.active,
    required this.phase,
    super.key,
  });
  final bool active;
  final int phase;

  @override
  Widget build(BuildContext context) => Semantics(
    label: active ? '录音正在进行' : '录音已暂停',
    child: SizedBox(
      height: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(29, (index) {
          final seed = ((index * 13 + phase ~/ 160) % 17).abs();
          final height = active ? 7.0 + seed * 1.25 : 5.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active
                  ? Theme.of(context).colorScheme.error.withValues(alpha: 0.75)
                  : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    ),
  );
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
