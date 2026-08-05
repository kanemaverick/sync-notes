import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_repository.dart';
import '../models/entities.dart';
import '../services/ai_processing_service.dart';
import '../services/media_storage.dart';

class AiNoteScreen extends StatefulWidget {
  const AiNoteScreen({
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
  State<AiNoteScreen> createState() => _AiNoteScreenState();
}

class _AiNoteScreenState extends State<AiNoteScreen> {
  String? _markdown;
  List<TimelineEvent> _events = [];
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final markdown = await widget.storage.readMarkdown(widget.session.id);
    final isLegacyNote =
        markdown != null && !markdown.contains('## 交给 Codex 的整理提示词');
    if (isLegacyNote) {
      await widget.repository.updateSession(
        widget.session.copyWith(aiStatus: AiStatus.notStarted),
      );
    }
    final events = await widget.repository.listTimelineEvents(
      widget.session.id,
    );
    if (mounted) {
      setState(() {
        _markdown = isLegacyNote ? null : markdown;
        _events = events;
      });
    }
  }

  Future<void> _generate() async {
    setState(() {
      _processing = true;
      _error = null;
    });
    var session = widget.session.copyWith(aiStatus: AiStatus.processing);
    await widget.repository.updateSession(session);
    try {
      final events = await widget.repository.listTimelineEvents(session.id);
      final transcripts = await widget.repository.listTranscripts(session.id);
      final markdown = await widget.aiService.process(
        AiProcessingInput(
          session: session,
          transcripts: transcripts,
          photos: buildPhotoContexts(events: events, transcripts: transcripts),
          events: events,
        ),
      );
      await widget.storage.writeMarkdown(
        sessionId: session.id,
        markdown: markdown,
      );
      session = session.copyWith(aiStatus: AiStatus.completed);
      await widget.repository.updateSession(session);
      if (mounted) {
        setState(() {
          _markdown = markdown;
          _events = events;
          _processing = false;
        });
      }
    } catch (error) {
      await widget.repository.updateSession(
        session.copyWith(aiStatus: AiStatus.failed),
      );
      if (mounted) {
        setState(() {
          _processing = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _markdown ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制全文')));
    }
  }

  Future<void> _exportMarkdown() async {
    final file = await widget.storage.writeMarkdown(
      sessionId: widget.session.id,
      markdown: _markdown ?? '',
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '${widget.session.title}.md',
      ),
    );
  }

  Future<void> _exportZip() async {
    final file = await widget.storage.exportIllustratedZip(
      session: widget.session,
      markdown: _markdown ?? '',
      events: _events,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '${widget.session.title}·Codex整理包.zip',
      ),
    );
  }

  Widget _buildMarkdownImage(Uri uri, String? title, String? alt) {
    final match = RegExp(r'photo_(\d{3})').firstMatch(uri.path);
    final index = match == null ? -1 : int.parse(match.group(1)!) - 1;
    final photos =
        _events
            .where(
              (event) =>
                  event.type == TimelineEventType.photo &&
                  event.photoPath != null,
            )
            .toList()
          ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
    if (index < 0 || index >= photos.length) {
      return Text(alt ?? '照片不可用');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(photos[index].photoPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Text('无法显示这张照片'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('整理与导出'),
        actions: [
          if (_markdown != null)
            IconButton(
              onPressed: _copy,
              tooltip: '复制全文',
              icon: const Icon(Icons.copy),
            ),
          if (_markdown != null)
            IconButton(
              onPressed: _exportMarkdown,
              tooltip: '导出Markdown',
              icon: const Icon(Icons.ios_share),
            ),
          if (_markdown != null)
            IconButton(
              onPressed: _exportZip,
              tooltip: '导出图文ZIP',
              icon: const Icon(Icons.folder_zip_outlined),
            ),
        ],
      ),
      body: _processing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在准备记录整理包…'),
                ],
              ),
            )
          : _markdown == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 58),
                    const SizedBox(height: 16),
                    const Text(
                      '准备 Codex 整理包',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '应用只汇总现场记录并生成整理提示词，不在手机端生成最终结论。导出 ZIP 后交给 Codex 分析。',
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('生成整理包说明'),
                    ),
                  ],
                ),
              ),
            )
          : Markdown(
              data: _markdown!,
              selectable: true,
              padding: const EdgeInsets.all(20),
              imageBuilder: _buildMarkdownImage,
            ),
    );
  }
}
