import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_states.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';

class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({
    required this.repository,
    required this.onOpen,
    super.key,
  });
  final AppRepository repository;
  final Future<void> Function(Session session) onOpen;

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  late Future<List<SessionSummary>> _sessions;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _sessions = widget.repository.listSessionSummaries();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('资料包')),
    body: FutureBuilder<List<SessionSummary>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            title: '无法读取记录',
            message: '${snapshot.error}',
            onRetry: () => setState(_reload),
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final sessions = snapshot.data!
            .where(
              (item) =>
                  item.session.status == SessionStatus.completed ||
                  item.session.status == SessionStatus.interrupted,
            )
            .toList();
        if (sessions.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inventory_2_outlined,
            title: '还没有可导出的记录',
            message: '结束一条记录后，可在这里生成交给 Codex 的图文资料包。',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            8,
            AppSpacing.lg,
            24,
          ),
          children: [
            Card(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('资料包包含转写稿、原始照片、结构化时间轴和给 Codex 的整理提示词。'),
              ),
            ),
            const SizedBox(height: 16),
            ...sessions.map(
              (summary) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: CircleAvatar(
                      child: Icon(
                        summary.session.exportedAt != null
                            ? Icons.check_rounded
                            : Icons.inventory_2_outlined,
                      ),
                    ),
                    title: Text(
                      summary.session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      summary.session.exportedAt != null
                          ? '上次导出 ${DateFormat('MM月dd日 HH:mm').format(summary.session.exportedAt!)} · ${_formatBytes(summary.session.exportSizeBytes ?? 0)}'
                          : '${DateFormat('MM月dd日 HH:mm').format(summary.session.createdAt)} · 尚未导出',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await widget.onOpen(summary.session);
                      if (mounted) setState(_reload);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '大小未知';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
