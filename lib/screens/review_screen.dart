import 'dart:io';

import 'package:flutter/material.dart';

import '../core/timeline_clock.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';
import '../services/ai_processing_service.dart';
import '../services/media_storage.dart';
import '../services/session_player.dart';
import '../widgets/text_input_dialog.dart';
import '../widgets/timeline_event_tile.dart';
import 'ai_note_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    required this.session,
    required this.repository,
    required this.storage,
    required this.aiService,
    super.key,
  });
  final Session session;
  final AppRepository repository;
  final MediaStorage storage;
  final AiProcessingService aiService;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final SessionPlayer _player = SessionPlayer();
  late Session _session;
  List<TimelineEvent> _events = [];
  int _positionMs = 0;
  bool _loading = true;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  Future<void> _load() async {
    try {
      final segments = await widget.repository.listAudioSegments(_session.id);
      _events = await widget.repository.listTimelineEvents(_session.id);
      if (segments.isNotEmpty) await _player.load(segments);
      _player.globalPositionStream.listen((position) {
        if (mounted) setState(() => _positionMs = position);
      });
      _player.playerStateStream.listen((state) {
        if (mounted) setState(() => _playing = state.playing);
      });
      setState(() => _loading = false);
    } catch (error) {
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _edit(TimelineEvent event) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => TextInputDialog(
        title: event.type == TimelineEventType.chapter ? '修改章节名称' : '修改照片备注',
        initialValue: event.type == TimelineEventType.chapter
            ? event.title
            : event.note,
        cancelLabel: '取消',
        submitLabel: '保存',
      ),
    );
    if (value == null) return;
    final updated = event.type == TimelineEventType.chapter
        ? event.copyWith(title: value)
        : event.copyWith(note: value);
    await widget.repository.updateTimelineEvent(updated);
    setState(
      () => _events = _events
          .map((item) => item.id == updated.id ? updated : item)
          .toList(),
    );
  }

  Future<void> _delete(TimelineEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个时间节点？'),
        content: Text(
          event.type == TimelineEventType.photo
              ? '照片文件和缩略图会被删除，原始录音不会受到影响。'
              : '只删除这个标记，原始录音不会受到影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteTimelineEvent(event.id);
    for (final path in [event.photoPath, event.thumbnailPath]) {
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    setState(() => _events.removeWhere((item) => item.id == event.id));
  }

  void _viewPhoto(TimelineEvent event) {
    if (event.photoPath == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            child: Center(child: Image.file(File(event.photoPath!))),
          ),
        ),
      ),
    );
  }

  Future<void> _openAi() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiNoteScreen(
          session: _session,
          repository: widget.repository,
          storage: widget.storage,
          aiService: widget.aiService,
        ),
      ),
    );
    final latest = await widget.repository.getSession(_session.id);
    if (latest != null && mounted) setState(() => _session = latest);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_session.title),
        actions: [
          IconButton(
            onPressed: _openAi,
            tooltip: 'AI整理',
            icon: const Icon(Icons.auto_awesome),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('加载失败\n$_error', textAlign: TextAlign.center))
          : Column(
              children: [
                Material(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  _player.skipBy(-10000, _positionMs),
                              tooltip: '后退10秒',
                              icon: const Icon(Icons.replay_10),
                              iconSize: 30,
                            ),
                            const SizedBox(width: 12),
                            IconButton.filled(
                              onPressed: _playing
                                  ? _player.pause
                                  : _player.play,
                              icon: Icon(
                                _playing ? Icons.pause : Icons.play_arrow,
                              ),
                              iconSize: 34,
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: () =>
                                  _player.skipBy(10000, _positionMs),
                              tooltip: '快进10秒',
                              icon: const Icon(Icons.forward_10),
                              iconSize: 30,
                            ),
                          ],
                        ),
                        Slider(
                          value: _positionMs
                              .clamp(0, _player.totalDurationMs)
                              .toDouble(),
                          max: _player.totalDurationMs > 0
                              ? _player.totalDurationMs.toDouble()
                              : 1,
                          onChanged: (value) =>
                              setState(() => _positionMs = value.round()),
                          onChangeEnd: (value) =>
                              _player.seekGlobal(value.round()),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(formatDuration(_positionMs)),
                            Text(formatDuration(_player.totalDurationMs)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '图文时间轴',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openAi,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(
                          _session.aiStatus == AiStatus.completed
                              ? '查看整理包'
                              : '整理与导出',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _events.isEmpty
                      ? const Center(child: Text('本次记录没有时间节点'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final event = _events[index];
                            return TimelineEventTile(
                              event: event,
                              highlighted:
                                  (event.offsetMs - _positionMs).abs() <= 2000,
                              onTap: () {
                                _player.seekGlobal(event.offsetMs);
                                if (event.type == TimelineEventType.photo) {
                                  _viewPhoto(event);
                                }
                              },
                              onEdit:
                                  event.type == TimelineEventType.photo ||
                                      event.type == TimelineEventType.chapter
                                  ? () => _edit(event)
                                  : null,
                              onDelete:
                                  event.type == TimelineEventType.photo ||
                                      event.type ==
                                          TimelineEventType.highlight ||
                                      event.type == TimelineEventType.question
                                  ? () => _delete(event)
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
