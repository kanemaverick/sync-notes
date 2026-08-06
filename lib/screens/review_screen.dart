import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../core/timeline_clock.dart';
import '../core/widgets/app_states.dart';
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
    this.initialPositionMs,
    this.bootstrapData,
    super.key,
  });
  final Session session;
  final AppRepository repository;
  final MediaStorage storage;
  final AiProcessingService aiService;
  final int? initialPositionMs;
  final ReviewBootstrapData? bootstrapData;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final SessionPlayer _player = SessionPlayer();
  late Session _session;
  List<TimelineEvent> _events = [];
  List<TranscriptSegment> _transcripts = [];
  StreamSubscription<int>? _positionSubscription;
  StreamSubscription<Object>? _playerSubscription;
  int _positionMs = 0;
  bool _loading = true;
  bool _playing = false;
  double _speed = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  Future<void> _load() async {
    try {
      final segments =
          widget.bootstrapData?.audioSegments ??
          await widget.repository.listAudioSegments(_session.id);
      _events =
          widget.bootstrapData?.events ??
          await widget.repository.listTimelineEvents(_session.id);
      _transcripts =
          widget.bootstrapData?.transcripts ??
          await widget.repository.listTranscripts(_session.id);
      if (segments.isNotEmpty) {
        await _player.load(segments);
        if (widget.initialPositionMs != null) {
          _positionMs = widget.initialPositionMs!.clamp(
            0,
            _player.totalDurationMs,
          );
          await _player.seekGlobal(_positionMs);
        }
      }
      _positionSubscription = _player.globalPositionStream.listen((position) {
        if (mounted) setState(() => _positionMs = position);
      });
      _playerSubscription = _player.playerStateStream.listen((state) {
        if (mounted) setState(() => _playing = _player.isPlaying);
      });
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _editEvent(TimelineEvent event) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => TextInputDialog(
        title: event.type == TimelineEventType.chapter ? '修改章节名称' : '修改节点内容',
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
    if (mounted) setState(() => _replaceEvent(updated));
  }

  Future<void> _editEventTime(TimelineEvent event) async {
    var value = event.offsetMs.toDouble();
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('调整照片时间点', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('当前 ${formatDuration(value.round())}，相册导入照片默认绑定导入时刻。'),
                Slider(
                  value: value.clamp(0, _player.totalDurationMs.toDouble()),
                  max: _player.totalDurationMs > 0
                      ? _player.totalDurationMs.toDouble()
                      : 1,
                  onChanged: (next) => setSheetState(() => value = next),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, value.round()),
                    child: const Text('保存时间点'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    final updated = event.copyWith(offsetMs: result);
    await widget.repository.updateTimelineEvent(updated);
    if (mounted) {
      setState(() {
        _replaceEvent(updated);
        _events.sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
      });
    }
  }

  void _replaceEvent(TimelineEvent updated) {
    _events = _events
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
  }

  Future<void> _editTranscript(TranscriptSegment segment) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: '修改字幕',
        initialValue: segment.text,
        cancelLabel: '取消',
        submitLabel: '保存',
        maxLength: 500,
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    final updated = TranscriptSegment(
      id: segment.id,
      sessionId: segment.sessionId,
      startMs: segment.startMs,
      endMs: segment.endMs,
      text: value.trim(),
      speakerLabel: segment.speakerLabel,
    );
    await widget.repository.updateTranscript(updated);
    if (mounted) {
      setState(
        () => _transcripts = _transcripts
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      );
    }
  }

  Future<void> _delete(TimelineEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个时间节点？'),
        content: Text(
          event.type == TimelineEventType.photo
              ? '照片文件和缩略图会被删除；原始录音不会受到影响。'
              : '只会删除这个节点；原始录音不会受到影响。',
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
    await widget.storage.deleteEventMedia(event);
    if (mounted) {
      setState(() => _events.removeWhere((item) => item.id == event.id));
    }
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

  Future<void> _openExport() async {
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

  Future<void> _editSession() async {
    final title = TextEditingController(text: _session.title);
    final location = TextEditingController(text: _session.location ?? '');
    final note = TextEditingController(text: _session.note ?? '');
    final tags = TextEditingController(text: _session.tags.join('，'));
    var scene = _session.sceneType;
    final updated = await showModalBottomSheet<Session>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('编辑记录信息', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SceneType>(
                  initialValue: scene,
                  decoration: const InputDecoration(labelText: '场景'),
                  items: SceneType.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setSheetState(() => scene = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: '地点'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '简介'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(labelText: '标签（用逗号分隔）'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _session.copyWith(
                        title: title.text.trim().isEmpty
                            ? _session.title
                            : title.text.trim(),
                        sceneType: scene,
                        location: location.text.trim(),
                        note: note.text.trim(),
                        tags: tags.text
                            .split(RegExp('[,，]'))
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList(),
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    title.dispose();
    location.dispose();
    note.dispose();
    tags.dispose();
    if (updated == null) return;
    await widget.repository.updateSession(updated);
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _deleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除整条记录？'),
        content: const Text('将永久删除音频分片、图片、字幕、标记和已生成资料包。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteSession(_session.id);
    await widget.storage.deleteSessionMedia(_session.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _editSession,
            tooltip: '编辑记录信息',
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _openExport();
              if (value == 'delete') _deleteSession();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('资料包'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除记录'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingState()
          : _error != null
          ? AppErrorState(
              title: '记录加载失败',
              message: '部分音频或时间轴可能暂时不可用。\n$_error',
              onRetry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerScrolled) => [
                SliverToBoxAdapter(
                  child: _SessionHeader(
                    session: _session,
                    events: _events,
                    transcriptCount: _transcripts.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PlayerCard(
                    playing: _playing,
                    positionMs: _positionMs,
                    totalMs: _player.totalDurationMs,
                    speed: _speed,
                    onToggle: _playing ? _player.pause : _player.play,
                    onSkip: (delta) => _player.skipBy(delta, _positionMs),
                    onSeek: _player.seekGlobal,
                    onSpeed: (speed) async {
                      await _player.setSpeed(speed);
                      if (mounted) setState(() => _speed = speed);
                    },
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabHeaderDelegate(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: '回顾'),
                        Tab(text: '字幕'),
                        Tab(text: '时间轴'),
                        Tab(text: '资料包'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _ReviewTab(
                    events: _events,
                    positionMs: _positionMs,
                    onSeek: _seekEvent,
                    onEdit: _editEvent,
                    onEditTime: _editEventTime,
                    onDelete: _delete,
                  ),
                  _TranscriptTab(
                    transcripts: _transcripts,
                    positionMs: _positionMs,
                    onSeek: (segment) => _player.seekGlobal(segment.startMs),
                    onEdit: _editTranscript,
                  ),
                  _TimelineTab(
                    events: _events,
                    transcripts: _transcripts,
                    positionMs: _positionMs,
                    onSeekEvent: _seekEvent,
                    onSeekTranscript: (segment) =>
                        _player.seekGlobal(segment.startMs),
                  ),
                  _PackageTab(session: _session, onOpen: _openExport),
                ],
              ),
            ),
    ),
  );

  void _seekEvent(TimelineEvent event) {
    _player.seekGlobal(event.offsetMs);
    if (event.type == TimelineEventType.photo) _viewPhoto(event);
  }
}

class ReviewBootstrapData {
  const ReviewBootstrapData({
    this.audioSegments = const [],
    this.events = const [],
    this.transcripts = const [],
  });

  final List<AudioSegment> audioSegments;
  final List<TimelineEvent> events;
  final List<TranscriptSegment> transcripts;
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.session,
    required this.events,
    required this.transcriptCount,
  });
  final Session session;
  final List<TimelineEvent> events;
  final int transcriptCount;

  @override
  Widget build(BuildContext context) {
    final photos = events
        .where((item) => item.type == TimelineEventType.photo)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text(session.sceneType.label)),
          Chip(
            avatar: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(DateFormat('MM月dd日').format(session.createdAt)),
          ),
          Chip(
            avatar: const Icon(Icons.photo_outlined, size: 16),
            label: Text('$photos 张'),
          ),
          Chip(
            avatar: const Icon(Icons.bookmark_outline, size: 16),
            label: Text('${events.length} 个节点'),
          ),
          Chip(
            avatar: const Icon(Icons.subtitles_outlined, size: 16),
            label: Text('$transcriptCount 段字幕'),
          ),
        ],
      ),
    );
  }
}

class _PlayerCard extends StatefulWidget {
  const _PlayerCard({
    required this.playing,
    required this.positionMs,
    required this.totalMs,
    required this.speed,
    required this.onToggle,
    required this.onSkip,
    required this.onSeek,
    required this.onSpeed,
  });
  final bool playing;
  final int positionMs;
  final int totalMs;
  final double speed;
  final VoidCallback onToggle;
  final ValueChanged<int> onSkip;
  final ValueChanged<int> onSeek;
  final ValueChanged<double> onSpeed;

  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.positionMs.toDouble())
        .clamp(0, widget.totalMs.toDouble())
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => widget.onSkip(-10000),
                    tooltip: '后退10秒',
                    icon: const Icon(Icons.replay_10_rounded),
                    iconSize: 30,
                  ),
                  const SizedBox(width: 14),
                  IconButton.filled(
                    onPressed: widget.onToggle,
                    icon: Icon(
                      widget.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    iconSize: 32,
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    onPressed: () => widget.onSkip(10000),
                    tooltip: '快进10秒',
                    icon: const Icon(Icons.forward_10_rounded),
                    iconSize: 30,
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<double>(
                    initialValue: widget.speed,
                    onSelected: widget.onSpeed,
                    itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                        .map(
                          (speed) => PopupMenuItem(
                            value: speed,
                            child: Text('${speed}x'),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${widget.speed}x',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: widget.totalMs > 0 ? value : 0.0,
                max: widget.totalMs > 0 ? widget.totalMs.toDouble() : 1,
                onChanged: widget.totalMs > 0
                    ? (next) => setState(() => _dragValue = next)
                    : null,
                onChangeEnd: (next) {
                  widget.onSeek(next.round());
                  setState(() => _dragValue = null);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(value.round())),
                  Text(formatDuration(widget.totalMs)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTab extends StatelessWidget {
  const _ReviewTab({
    required this.events,
    required this.positionMs,
    required this.onSeek,
    required this.onEdit,
    required this.onEditTime,
    required this.onDelete,
  });
  final List<TimelineEvent> events;
  final int positionMs;
  final ValueChanged<TimelineEvent> onSeek;
  final ValueChanged<TimelineEvent> onEdit;
  final ValueChanged<TimelineEvent> onEditTime;
  final ValueChanged<TimelineEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final visible = events
        .where((item) => item.type != TimelineEventType.interruption)
        .toList();
    if (visible.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bookmarks_outlined,
        title: '还没有回顾节点',
        message: '照片、重点、疑问、章节和备注会按时间显示在这里。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (_, index) {
        final event = visible[index];
        return TimelineEventTile(
          event: event,
          highlighted: (event.offsetMs - positionMs).abs() <= 2000,
          onTap: () => onSeek(event),
          onEdit: () => onEdit(event),
          onDelete: () => onDelete(event),
          onEditTime: event.type == TimelineEventType.photo
              ? () => onEditTime(event)
              : null,
        );
      },
    );
  }
}

class _TranscriptTab extends StatefulWidget {
  const _TranscriptTab({
    required this.transcripts,
    required this.positionMs,
    required this.onSeek,
    required this.onEdit,
  });
  final List<TranscriptSegment> transcripts;
  final int positionMs;
  final ValueChanged<TranscriptSegment> onSeek;
  final ValueChanged<TranscriptSegment> onEdit;

  @override
  State<_TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends State<_TranscriptTab> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = widget.transcripts
        .where(
          (item) => query.isEmpty || item.text.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '在本条字幕中搜索',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: widget.transcripts.isEmpty
              ? const AppEmptyState(
                  icon: Icons.subtitles_off_outlined,
                  title: '没有可用字幕',
                  message: '原始录音仍然完整保留，可稍后重新转写。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 20),
                  itemBuilder: (_, index) {
                    final item = visible[index];
                    final active =
                        widget.positionMs >= item.startMs &&
                        widget.positionMs <= item.endMs + 1000;
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => widget.onSeek(item),
                      onLongPress: () => widget.onEdit(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 62,
                              child: Text(
                                formatDuration(item.startMs),
                                style: TextStyle(
                                  color: active
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outline,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.55,
                                  color: active
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => widget.onEdit(item),
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              tooltip: '编辑字幕',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({
    required this.events,
    required this.transcripts,
    required this.positionMs,
    required this.onSeekEvent,
    required this.onSeekTranscript,
  });
  final List<TimelineEvent> events;
  final List<TranscriptSegment> transcripts;
  final int positionMs;
  final ValueChanged<TimelineEvent> onSeekEvent;
  final ValueChanged<TranscriptSegment> onSeekTranscript;

  @override
  Widget build(BuildContext context) {
    final items =
        <({int ms, TimelineEvent? event, TranscriptSegment? transcript})>[
          ...events.map(
            (event) => (ms: event.offsetMs, event: event, transcript: null),
          ),
          ...transcripts.map(
            (transcript) =>
                (ms: transcript.startMs, event: null, transcript: transcript),
          ),
        ]..sort((a, b) => a.ms.compareTo(b.ms));
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.timeline_rounded,
        title: '时间轴为空',
        message: '完成录音或添加节点后，连续时间轴会显示在这里。',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        final event = item.event;
        final active = (item.ms - positionMs).abs() <= 2000;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 92,
                child: event == null
                    ? Text(
                        formatDuration(item.ms),
                        style: TextStyle(
                          fontSize: 12,
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatDeviceTimestamp(event.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: active
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatDuration(event.offsetMs),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
              ),
              Column(
                children: [
                  Container(
                    width: 2,
                    height: 8,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Container(
                    width: active ? 12 : 9,
                    height: active ? 12 : 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => event != null
                      ? onSeekEvent(event)
                      : onSeekTranscript(item.transcript!),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      event != null
                          ? '${event.type.label} · ${event.note ?? event.title ?? ''}'
                          : item.transcript!.text,
                      maxLines: event == null ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PackageTab extends StatelessWidget {
  const _PackageTab({required this.session, required this.onOpen});
  final Session session;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                session.exportedAt != null
                    ? Icons.check_circle_rounded
                    : Icons.inventory_2_outlined,
                size: 38,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                session.exportedAt != null ? '资料包已经导出' : '尚未导出资料包',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('资料包包含原始音频、转写稿、照片、双时间轴和给 Codex 的整理提示词。'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(session.exportedAt != null ? '查看或重新导出' : '生成资料包'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabHeaderDelegate({required this.child, required this.color});
  final Widget child;
  final Color color;
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: color, child: child);
  @override
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) =>
      oldDelegate.color != color || oldDelegate.child != child;
}
