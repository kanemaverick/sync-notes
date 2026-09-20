import 'package:flutter/material.dart';
import '../core/timeline_clock.dart';
import '../models/entities.dart';

/// Shows the current repository snapshot, including revised cloud sentences.
/// Does not turn uncertain ASR text into invented, apparently verified prose.
class LiveTranscriptPanel extends StatefulWidget {
  const LiveTranscriptPanel({
    super.key,
    required this.transcripts,
    required this.partialText,
    required this.status,
    this.error,
  });
  final List<TranscriptSegment> transcripts;
  final String partialText;
  final String status;
  final String? error;

  @override
  State<LiveTranscriptPanel> createState() => _LiveTranscriptPanelState();
}

class _LiveTranscriptPanelState extends State<LiveTranscriptPanel> {
  bool _expanded = false;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant LiveTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow only when already at the bottom; do not interrupt history review.
    if (_expanded && _scroll.hasClients && _scroll.position.extentAfter < 60) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = [...widget.transcripts]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final last = widget.partialText.isNotEmpty
        ? widget.partialText
        : rows.isEmpty
        ? '说话后字幕会显示在这里'
        : rows.last.text;
    final full = [
      for (final row in rows)
        '[${formatDuration(row.startMs)} · ${row.speakerLabel ?? '识别初稿'}] ${row.text}',
      if (widget.partialText.isNotEmpty) '[正在识别，可修订] ${widget.partialText}',
    ].join('\n\n');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  '实时转写 · ${widget.status}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(_expanded ? '收起全文' : '展开全文（${rows.length}段）'),
                ),
              ],
            ),
            if (widget.error != null)
              Text(
                widget.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_expanded) ...[
              const Text(
                '未校对初稿；云端句子可能修订。可滚动、选择并复制文字。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 300,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      full.isEmpty ? last : full,
                      style: const TextStyle(fontSize: 17, height: 1.5),
                    ),
                  ),
                ),
              ),
            ] else
              Text(
                last,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, height: 1.4),
              ),
          ],
        ),
      ),
    );
  }
}
