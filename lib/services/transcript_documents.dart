import '../models/entities.dart';

String transcriptTime(int ms, {bool srt = false}) {
  final value = ms < 0 ? 0 : ms;
  final h = (value ~/ 3600000).toString().padLeft(2, '0');
  final m = (value ~/ 60000 % 60).toString().padLeft(2, '0');
  final s = (value ~/ 1000 % 60).toString().padLeft(2, '0');
  return '$h:$m:$s${srt ? ',${(value % 1000).toString().padLeft(3, '0')}' : ''}';
}

List<TranscriptSegment> sortedTranscripts(List<TranscriptSegment> input) =>
    [...input]..sort((a, b) {
      final time = a.startMs.compareTo(b.startMs);
      return time != 0 ? time : a.id.compareTo(b.id);
    });

/// Layout-only grouping: no deletion, correction or invented punctuation.
List<({int startMs, int endMs, String source, String text})>
transcriptParagraphs(List<TranscriptSegment> input) {
  final result = <({int startMs, int endMs, String source, String text})>[];
  for (final row in sortedTranscripts(input)) {
    final source = row.speakerLabel ?? '来源未记录';
    if (result.isNotEmpty &&
        result.last.source == source &&
        row.startMs - result.last.endMs <= 5000 &&
        row.endMs - result.last.startMs <= 30000 &&
        result.last.text.length < 350) {
      final last = result.removeLast();
      result.add((
        startMs: last.startMs,
        endMs: row.endMs > last.endMs ? row.endMs : last.endMs,
        source: source,
        text: '${last.text} ${row.text.trim()}',
      ));
    } else {
      result.add((
        startMs: row.startMs,
        endMs: row.endMs,
        source: source,
        text: row.text.trim(),
      ));
    }
  }
  return result;
}

String buildTranscriptSrt(List<TranscriptSegment> input) {
  final rows = sortedTranscripts(input);
  return [
    for (var i = 0; i < rows.length; i++)
      '${i + 1}\n${transcriptTime(rows[i].startMs, srt: true)} --> '
          '${transcriptTime(rows[i].endMs, srt: true)}\n${rows[i].text}\n',
  ].join('\n');
}

String buildReadableTranscript(List<TranscriptSegment> rows) =>
    '# 实时转写初稿（未校对）\n\n'
    '> 仅按时间合段，未修正内容；来源是识别引擎标签，不是可靠的说话人身份。请优先用 audio/ 重转写。\n\n'
    '${transcriptParagraphs(rows).map((r) => '[${transcriptTime(r.startMs)}–${transcriptTime(r.endMs)} · ${r.source}]\n\n${r.text}').join('\n\n')}\n';

String buildTranscriptQualityReport(List<TranscriptSegment> rows) {
  final local = rows.where((r) => r.speakerLabel == '本地初稿').length;
  final short = rows.where((r) => r.text.trim().runes.length <= 4).length;
  return '# 转写质量提示\n\n'
      '- 片段数：${rows.length}；本地初稿：$local；不超过4字的短片段：$short。\n'
      '- 这些是结构统计，不是识别准确率或置信度。\n'
      '${rows.isEmpty ? '- 未保存转写，请从原始音频重新识别。\n' : ''}'
      '${local == rows.length && rows.isNotEmpty ? '- 全部为本地识别：包内没有云端识别结果，请检查云端开关、连接和额度。\n' : ''}'
      '${short * 3 > rows.length && rows.isNotEmpty ? '- 短片段较多，可能存在碎片化或识别困难；不要把合段后的流畅度当成准确性。\n' : ''}'
      '- 人名、英文缩写、数字和专业词必须结合原始音频与照片核对。\n'
      '- 原始片段在 manifest.json 和 transcripts/raw.srt；可读合段在 transcripts/draft.md。\n';
}
