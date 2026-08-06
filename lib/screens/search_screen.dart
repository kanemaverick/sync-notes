import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/timeline_clock.dart';
import '../core/widgets/app_states.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.repository,
    required this.onOpen,
    super.key,
  });
  final AppRepository repository;
  final Future<void> Function(Session session, int? offsetMs) onOpen;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Future<List<SessionSearchResult>>? _results;
  SceneType? _scene;
  bool _photos = false;
  bool _highlights = false;
  bool _questions = false;
  bool _exported = false;
  int? _dateDays;
  String? _transcriptSource;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() => setState(() {
    _results = widget.repository.search(
      query: _controller.text,
      sceneType: _scene,
      photosOnly: _photos,
      highlightsOnly: _highlights,
      questionsOnly: _questions,
      exportedOnly: _exported,
      transcriptSource: _transcriptSource,
      createdAfter: _dateDays == null
          ? null
          : DateTime.now().subtract(Duration(days: _dateDays!)),
    );
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            10,
          ),
          child: SearchBar(
            controller: _controller,
            hintText: '搜索标题、字幕、备注或章节',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _controller.clear();
                    _search();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
            onChanged: (_) => _search(),
            onSubmitted: (_) => _search(),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              FilterChip(
                label: Text(_scene?.label ?? '全部场景'),
                selected: _scene != null,
                onSelected: (_) => _pickScene(),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(
                  _dateDays == null
                      ? '全部日期'
                      : _dateDays == 1
                      ? '今天'
                      : '近 $_dateDays 天',
                ),
                selected: _dateDays != null,
                onSelected: (_) => _pickDate(),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('有照片'),
                selected: _photos,
                onSelected: (v) {
                  _photos = v;
                  _search();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('有重点'),
                selected: _highlights,
                onSelected: (v) {
                  _highlights = v;
                  _search();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('有疑问'),
                selected: _questions,
                onSelected: (v) {
                  _questions = v;
                  _search();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('已导出'),
                selected: _exported,
                onSelected: (value) {
                  _exported = value;
                  _search();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(
                  _transcriptSource == 'cloud'
                      ? '云端字幕'
                      : _transcriptSource == 'offline'
                      ? '离线字幕'
                      : '字幕来源',
                ),
                selected: _transcriptSource != null,
                onSelected: (_) => _pickTranscriptSource(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<SessionSearchResult>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppErrorState(
                  title: '搜索失败',
                  message: '${snapshot.error}',
                  onRetry: _search,
                );
              }
              if (!snapshot.hasData) {
                return const AppLoadingState(label: '正在搜索');
              }
              if (snapshot.data!.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.manage_search_rounded,
                  title: '没有找到相关内容',
                  message: '试试更短的关键词，或减少筛选条件。',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final result = snapshot.data![index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(child: Icon(_iconFor(result.kind))),
                      title: Text(
                        result.session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${result.kind}${result.offsetMs == null ? '' : ' · ${formatDuration(result.offsetMs!)}'}\n${result.contextText}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          widget.onOpen(result.session, result.offsetMs),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  IconData _iconFor(String kind) => switch (kind) {
    'photo' => Icons.photo_outlined,
    'highlight' => Icons.star_outline_rounded,
    'question' => Icons.help_outline_rounded,
    'chapter' => Icons.bookmark_outline_rounded,
    '字幕' => Icons.subtitles_outlined,
    _ => Icons.mic_none_rounded,
  };

  Future<void> _pickScene() async {
    final selected = await showModalBottomSheet<SceneType?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('全部场景'),
              onTap: () => Navigator.pop(context),
            ),
            ...SceneType.values.map(
              (scene) => ListTile(
                title: Text(scene.label),
                trailing: _scene == scene
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, scene),
              ),
            ),
          ],
        ),
      ),
    );
    _scene = selected;
    _search();
  }

  Future<void> _pickDate() async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('全部日期'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('今天'),
              onTap: () => Navigator.pop(context, 1),
            ),
            ListTile(
              title: const Text('近 7 天'),
              onTap: () => Navigator.pop(context, 7),
            ),
            ListTile(
              title: const Text('近 30 天'),
              onTap: () => Navigator.pop(context, 30),
            ),
          ],
        ),
      ),
    );
    _dateDays = selected;
    _search();
  }

  Future<void> _pickTranscriptSource() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('全部字幕'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('离线字幕'),
              onTap: () => Navigator.pop(context, 'offline'),
            ),
            ListTile(
              title: const Text('云端字幕'),
              onTap: () => Navigator.pop(context, 'cloud'),
            ),
          ],
        ),
      ),
    );
    _transcriptSource = selected;
    _search();
  }
}
