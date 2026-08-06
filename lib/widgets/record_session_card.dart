import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../core/timeline_clock.dart';
import '../models/entities.dart';
import '../core/widgets/app_states.dart';

class RecordSessionCard extends StatelessWidget {
  const RecordSessionCard({
    required this.summary,
    required this.onTap,
    super.key,
  });

  final SessionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final active =
        session.status == SessionStatus.recording ||
        session.status == SessionStatus.paused;
    final cover = summary.coverPath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(path: cover, active: active),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('yyyy年MM月dd日 HH:mm').format(session.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusBadge(label: session.sceneType.label),
                        if (active)
                          StatusBadge(
                            label: session.status == SessionStatus.paused
                                ? '已暂停'
                                : '录音中',
                            icon: active ? Icons.graphic_eq_rounded : null,
                            color: AppColors.recording,
                          ),
                        if (summary.hasCloudTranscript)
                          const StatusBadge(
                            label: '云端字幕',
                            icon: Icons.cloud_done_outlined,
                          ),
                        if (summary.hasOfflineTranscript)
                          const StatusBadge(
                            label: '离线字幕',
                            icon: Icons.offline_bolt_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _Metric(
                          icon: Icons.schedule_rounded,
                          text: formatDuration(session.durationMs),
                        ),
                        const SizedBox(width: 14),
                        _Metric(
                          icon: Icons.photo_outlined,
                          text: '${summary.photoCount}',
                        ),
                        const SizedBox(width: 14),
                        _Metric(
                          icon: Icons.bookmark_border_rounded,
                          text: '${summary.eventCount}',
                        ),
                        const Spacer(),
                        Icon(
                          session.exportedAt != null
                              ? Icons.inventory_2_outlined
                              : Icons.inventory_2_rounded,
                          size: 18,
                          color: session.exportedAt != null
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path, required this.active});
  final String? path;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    return Container(
      width: 84,
      height: 104,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: active
            ? AppColors.recording.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: file != null && file.existsSync()
          ? Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Icon(
    active ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
    size: 34,
    color: active ? AppColors.recording : null,
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
      const SizedBox(width: 4),
      Text(text, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}
