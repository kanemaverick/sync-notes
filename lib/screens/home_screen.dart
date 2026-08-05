import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/timeline_clock.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';
import '../services/ai_processing_service.dart';
import '../services/background_recording_service.dart';
import '../services/cloud_transcription_settings.dart';
import '../services/media_storage.dart';
import 'create_session_screen.dart';
import 'live_record_screen.dart';
import 'review_screen.dart';
import 'transcription_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.repository,
    required this.storage,
    required this.recording,
    required this.cloudSettings,
    required this.aiService,
    super.key,
  });
  final AppRepository repository;
  final MediaStorage storage;
  final BackgroundRecordingService recording;
  final CloudTranscriptionSettingsStore cloudSettings;
  final AiProcessingService aiService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<SessionSummary>> _sessions;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _sessions = widget.repository.listSessionSummaries();
  }

  Future<void> _create() async {
    final session = await Navigator.of(context).push<Session>(
      MaterialPageRoute(
        builder: (_) => CreateSessionScreen(repository: widget.repository),
      ),
    );
    if (!mounted || session == null) return;
    await Navigator.of(context).push(
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
    setState(_reload);
  }

  Future<void> _open(Session session) async {
    final active =
        session.status == SessionStatus.recording ||
        session.status == SessionStatus.paused;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => active
            ? LiveRecordScreen(
                session: session,
                repository: widget.repository,
                storage: widget.storage,
                recording: widget.recording,
                aiService: widget.aiService,
                autoStart: false,
              )
            : ReviewScreen(
                session: session,
                repository: widget.repository,
                storage: widget.storage,
                aiService: widget.aiService,
              ),
      ),
    );
    setState(_reload);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TranscriptionSettingsScreen(store: widget.cloudSettings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步讲记'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '实时转写设置',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('开始新记录'),
      ),
      body: FutureBuilder<List<SessionSummary>>(
        future: _sessions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _CenteredMessage(
              icon: Icons.error_outline,
              title: '记录加载失败',
              detail: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const _CenteredMessage(
              icon: Icons.auto_stories_outlined,
              title: '还没有记录',
              detail: '开始录音后，可以低干扰地拍照和标记重点。',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _sessions;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final summary = sessions[index];
                final session = summary.session;
                final active =
                    session.status == SessionStatus.recording ||
                    session.status == SessionStatus.paused;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    onTap: () => _open(session),
                    leading: CircleAvatar(
                      backgroundColor: active ? Colors.red.shade100 : null,
                      child: Icon(active ? Icons.graphic_eq : Icons.notes),
                    ),
                    title: Text(
                      session.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${session.sceneType.label} · ${DateFormat('MM月dd日 HH:mm').format(session.createdAt)}\n'
                        '${formatDuration(session.durationMs)} · ${summary.photoCount}张照片 · ${session.aiStatus == AiStatus.completed ? '已生成整理包' : '未生成整理包'}',
                      ),
                    ),
                    trailing: active
                        ? const Chip(label: Text('进行中'))
                        : const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
