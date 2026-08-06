import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_states.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';
import '../services/ai_processing_service.dart';
import '../services/background_recording_service.dart';
import '../services/cloud_transcription_settings.dart';
import '../services/media_storage.dart';
import '../widgets/record_session_card.dart';
import 'ai_note_screen.dart';
import 'create_session_screen.dart';
import 'export_center_screen.dart';
import 'live_record_screen.dart';
import 'review_screen.dart';
import 'search_screen.dart';
import 'settings_hub_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.repository,
    required this.storage,
    required this.recording,
    required this.cloudSettings,
    required this.aiService,
    this.sessionLoader,
    super.key,
  });
  final AppRepository repository;
  final MediaStorage storage;
  final BackgroundRecordingService recording;
  final CloudTranscriptionSettingsStore cloudSettings;
  final AiProcessingService aiService;
  final Future<List<SessionSummary>> Function()? sessionLoader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  int _recordsRevision = 0;

  Future<void> _review(Session session, [int? offsetMs]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          session: session,
          repository: widget.repository,
          storage: widget.storage,
          aiService: widget.aiService,
          initialPositionMs: offsetMs,
        ),
      ),
    );
    if (mounted) setState(() => _recordsRevision++);
  }

  Future<void> _create() async {
    final session = await Navigator.of(context).push<Session>(
      MaterialPageRoute(
        builder: (_) => CreateSessionScreen(repository: widget.repository),
      ),
    );
    if (!mounted || session == null) return;
    final completed = await Navigator.of(context).push<Session>(
      MaterialPageRoute(
        builder: (_) => LiveRecordScreen(
          session: session,
          repository: widget.repository,
          storage: widget.storage,
          recording: widget.recording,
          aiService: widget.aiService,
          autoStart: true,
        ),
      ),
    );
    if (!mounted) return;
    if (completed != null) {
      await _review(completed);
    } else {
      setState(() => _recordsRevision++);
    }
  }

  Future<void> _open(Session session, [int? offsetMs]) async {
    final active =
        session.status == SessionStatus.recording ||
        session.status == SessionStatus.paused;
    if (!active) {
      await _review(session, offsetMs);
      return;
    }
    final completed = await Navigator.of(context).push<Session>(
      MaterialPageRoute(
        builder: (_) => LiveRecordScreen(
          session: session,
          repository: widget.repository,
          storage: widget.storage,
          recording: widget.recording,
          aiService: widget.aiService,
          autoStart: false,
        ),
      ),
    );
    if (!mounted) return;
    if (completed != null) {
      await _review(completed);
    } else {
      setState(() => _recordsRevision++);
    }
  }

  Future<void> _resumeRecovered(Session session) async {
    final completed = await Navigator.of(context).push<Session>(
      MaterialPageRoute(
        builder: (_) => LiveRecordScreen(
          session: session,
          repository: widget.repository,
          storage: widget.storage,
          recording: widget.recording,
          aiService: widget.aiService,
          autoStart: true,
          resumeOffsetMs: session.durationMs,
        ),
      ),
    );
    if (!mounted) return;
    if (completed != null) {
      await _review(completed);
    } else {
      setState(() => _recordsRevision++);
    }
  }

  Future<void> _finalizeRecovered(Session session) async {
    await widget.repository.updateSession(
      session.copyWith(status: SessionStatus.completed),
    );
    if (mounted) {
      setState(() => _recordsRevision++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已将恢复数据保存为已结束记录')));
    }
  }

  Future<void> _openExport(Session session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiNoteScreen(
          session: session,
          repository: widget.repository,
          storage: widget.storage,
          aiService: widget.aiService,
        ),
      ),
    );
    if (mounted) setState(() => _recordsRevision++);
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_index) {
      0 => _RecordsPage(
        key: ValueKey(_recordsRevision),
        repository: widget.repository,
        sessionLoader: widget.sessionLoader,
        onCreate: _create,
        onOpen: _open,
        onSearch: () => setState(() => _index = 1),
        onResumeRecovered: _resumeRecovered,
        onFinalizeRecovered: _finalizeRecovered,
      ),
      1 => SearchScreen(repository: widget.repository, onOpen: _open),
      2 => ExportCenterScreen(
        repository: widget.repository,
        onOpen: _openExport,
      ),
      _ => SettingsHubScreen(cloudSettings: widget.cloudSettings),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: '记录',
          ),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: '搜索'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: '资料包',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _RecordsPage extends StatefulWidget {
  const _RecordsPage({
    required this.repository,
    required this.onCreate,
    required this.onOpen,
    required this.onSearch,
    required this.onResumeRecovered,
    required this.onFinalizeRecovered,
    this.sessionLoader,
    super.key,
  });
  final AppRepository repository;
  final VoidCallback onCreate;
  final Future<void> Function(Session session, [int? offsetMs]) onOpen;
  final VoidCallback onSearch;
  final Future<void> Function(Session session) onResumeRecovered;
  final Future<void> Function(Session session) onFinalizeRecovered;
  final Future<List<SessionSummary>> Function()? sessionLoader;

  @override
  State<_RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<_RecordsPage> {
  late Future<List<SessionSummary>> _sessions;
  SceneType? _scene;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _sessions =
      widget.sessionLoader?.call() ?? widget.repository.listSessionSummaries();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('同步讲记'),
          Text(
            '让讲解、照片与思考保持同步',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: widget.onSearch,
          icon: const Icon(Icons.search_rounded),
          tooltip: '搜索',
        ),
        const SizedBox(width: 4),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: widget.onCreate,
      icon: const Icon(Icons.mic_rounded),
      label: const Text('新建记录'),
    ),
    body: FutureBuilder<List<SessionSummary>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            title: '记录加载失败',
            message: '${snapshot.error}',
            onRetry: () => setState(_reload),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState(label: '正在读取本地记录');
        final all = snapshot.data!;
        final active = all
            .where(
              (item) =>
                  item.session.status == SessionStatus.recording ||
                  item.session.status == SessionStatus.paused,
            )
            .toList();
        final recovered = all
            .where((item) => item.session.status == SessionStatus.interrupted)
            .toList();
        final filtered = all
            .where((item) => _scene == null || item.session.sceneType == _scene)
            .toList();
        if (all.isEmpty) {
          return AppEmptyState(
            icon: Icons.auto_stories_outlined,
            title: '从第一条讲记开始',
            message: '持续录音时拍照、标重点和记疑问，结束后所有内容会自动对齐。',
            actionLabel: '新建记录',
            onAction: widget.onCreate,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _sessions;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              4,
              AppSpacing.lg,
              104,
            ),
            children: [
              if (active.isNotEmpty) ...[
                Text('正在进行', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...active.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RecordSessionCard(
                      summary: item,
                      onTap: () => widget.onOpen(item.session),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (recovered.isNotEmpty) ...[
                Text('已恢复的记录', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...recovered.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.tertiaryContainer.withValues(alpha: 0.45),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.restore_rounded),
                                SizedBox(width: 8),
                                Text(
                                  '发现一条未正常结束的记录',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${item.session.title}\n已保存 ${item.session.durationMs ~/ 60000} 分钟音频和 ${item.photoCount} 张照片',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        widget.onOpen(item.session),
                                    child: const Text('查看详情'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () =>
                                        widget.onResumeRecovered(item.session),
                                    child: const Text('继续记录'),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () =>
                                    widget.onFinalizeRecovered(item.session),
                                child: const Text('结束并保存现有数据'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '最近记录',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  PopupMenuButton<SceneType?>(
                    initialValue: _scene,
                    tooltip: '按场景筛选',
                    onSelected: (value) => setState(() => _scene = value),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: null, child: Text('全部场景')),
                      ...SceneType.values.map(
                        (scene) => PopupMenuItem(
                          value: scene,
                          child: Text(scene.label),
                        ),
                      ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.tune_rounded, size: 17),
                      label: Text(_scene?.label ?? '全部'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: AppEmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: '这个场景还没有记录',
                    message: '切换筛选条件查看其他记录。',
                  ),
                )
              else
                ...filtered
                    .where(
                      (item) =>
                          !active.contains(item) && !recovered.contains(item),
                    )
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RecordSessionCard(
                          summary: item,
                          onTap: () => widget.onOpen(item.session),
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    ),
  );
}
