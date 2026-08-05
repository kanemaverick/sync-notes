import 'dart:io';

import 'package:flutter/material.dart';

import '../core/timeline_clock.dart';
import '../models/entities.dart';

class TimelineEventTile extends StatelessWidget {
  const TimelineEventTile({
    required this.event,
    required this.onTap,
    this.highlighted = false,
    this.onEdit,
    this.onDelete,
    super.key,
  });
  final TimelineEvent event;
  final VoidCallback onTap;
  final bool highlighted;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  IconData get _icon => switch (event.type) {
    TimelineEventType.photo => Icons.photo_outlined,
    TimelineEventType.highlight => Icons.star_rounded,
    TimelineEventType.question => Icons.help_outline,
    TimelineEventType.chapter => Icons.bookmark_outline,
    TimelineEventType.text => Icons.notes,
    TimelineEventType.interruption => Icons.warning_amber_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlighted
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.thumbnailPath != null &&
                  File(event.thumbnailPath!).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(event.thumbnailPath!),
                    width: 78,
                    height: 62,
                    fit: BoxFit.cover,
                  ),
                )
              else
                CircleAvatar(child: Icon(_icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title ?? event.type.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (event.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(event.note!),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      formatDuration(event.offsetMs),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'edit' ? onEdit?.call() : onDelete?.call(),
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (onDelete != null)
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
