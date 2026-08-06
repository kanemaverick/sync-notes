import '../core/timeline_clock.dart';
import '../models/entities.dart';
import 'illustrated_note.dart';

enum EvidenceKind { teacherSaid, directlyObserved, inferred, needsVerification }

extension EvidenceKindLabel on EvidenceKind {
  String get label => switch (this) {
    EvidenceKind.teacherSaid => '老师明确讲过',
    EvidenceKind.directlyObserved => '照片直接可见',
    EvidenceKind.inferred => 'AI结合上下文推测',
    EvidenceKind.needsVerification => '需要人工核实',
  };
}

class PhotoAiContext {
  const PhotoAiContext({
    required this.filePath,
    required this.offsetMs,
    required this.ocrText,
    required this.nearbyTranscript,
    this.userNote,
    this.deviceTime,
  });
  final String filePath;
  final int offsetMs;
  final String ocrText;
  final String nearbyTranscript;
  final String? userNote;
  final DateTime? deviceTime;
}

class AiProcessingInput {
  const AiProcessingInput({
    required this.session,
    required this.transcripts,
    required this.photos,
    required this.events,
  });
  final Session session;
  final List<TranscriptSegment> transcripts;
  final List<PhotoAiContext> photos;
  final List<TimelineEvent> events;
}

abstract interface class AiProcessingService {
  Future<String> process(AiProcessingInput input);
}

class MockAiProcessingService implements AiProcessingService {
  const MockAiProcessingService();

  @override
  Future<String> process(AiProcessingInput input) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final highlights = input.events
        .where((event) => event.type == TimelineEventType.highlight)
        .length;
    final questions = input.events
        .where((event) => event.type == TimelineEventType.question)
        .length;
    final chapters = input.events
        .where((event) => event.type == TimelineEventType.chapter)
        .toList();
    final buffer = StringBuffer()
      ..writeln('# ${input.session.title} · 现场记录整理包')
      ..writeln()
      ..writeln('> 本应用只汇总现场记录，不在手机端生成最终结论。请导出图文 ZIP，并交给 Codex 继续整理和核验。')
      ..writeln()
      ..writeln('- 场景：${input.session.sceneType.label}')
      ..writeln(
        '- 章节：${chapters.length}；照片：${input.photos.length}；重点：$highlights；疑问：$questions',
      )
      ..writeln();
    _writeChronologicalIllustratedNotes(buffer, input);
    if (questions > 0) {
      buffer
        ..writeln('## 需要重点处理的疑问')
        ..writeln()
        ..writeln('记录到 $questions 个“没听懂”节点。Codex 整理时应优先结合每个节点前后约45秒的转写重新解释。')
        ..writeln();
    }
    buffer
      ..writeln('## 交给 Codex 的整理提示词')
      ..writeln()
      ..writeln('```text')
      ..writeln(buildCodexAnalysisPrompt(input.session))
      ..writeln('```')
      ..writeln()
      ..writeln('---')
      ..writeln('生成器：同步讲记记录整理器（无需API密钥）');
    return buffer.toString();
  }
}

String buildCodexAnalysisPrompt(Session session) {
  final expectedSections = switch (session.sceneType) {
    SceneType.classroom => [
      '课程知识框架',
      '概念、公式和例子',
      '老师强调的重点',
      '用户没听懂内容的重新解释',
      '复习问题和闪卡',
    ],
    SceneType.lecture => ['核心观点', '论证结构', '案例和引用', '现场问答', '延伸思考'],
    SceneType.fieldVisit => [
      '参观顺序',
      '装置、展品或现象',
      '结构、用途和工作原理',
      '每张照片对应的讲解',
      '图文实习记录',
      '需要补查的专业术语',
    ],
    SceneType.meeting => ['会议目标', '讨论要点', '决定事项', '待办与负责人', '分歧和待确认项'],
    SceneType.interview => ['访谈背景', '核心回答', '关键事实与案例', '有代表性的原话', '待追问与待核实项'],
    SceneType.custom => ['内容概览', '关键节点', '图片与讲解对应', '疑问与待核实项'],
  };
  final location = session.location?.trim();
  final speaker = session.speaker?.trim();
  final note = session.note?.trim();
  final activityName = session.activityName?.trim();
  final buffer = StringBuffer()
    ..writeln('请分析这个“同步讲记”ZIP，生成一份准确、可核查的中文图文笔记。')
    ..writeln()
    ..writeln('记录信息：')
    ..writeln('- 标题：${session.title}')
    ..writeln('- 场景：${session.sceneType.label}');
  if (activityName != null && activityName.isNotEmpty) {
    buffer.writeln('- 课程或活动：$activityName');
  }
  if (location != null && location.isNotEmpty) {
    buffer.writeln('- 地点：$location');
  }
  if (speaker != null && speaker.isNotEmpty) {
    buffer.writeln('- 老师或讲解人：$speaker');
  }
  if (note != null && note.isNotEmpty) {
    buffer.writeln('- 用户备注：$note');
  }
  if (session.tags.isNotEmpty) {
    buffer.writeln('- 标签：${session.tags.join('、')}');
  }
  buffer
    ..writeln()
    ..writeln('请先读取：')
    ..writeln('1. note.md：按时间整理的转写初稿、照片引用和用户标记。')
    ..writeln('2. manifest.json：场景信息、时间节点、照片偏移和文件对应关系。')
    ..writeln('3. images/：现场原始照片；请自行观察并在必要时做OCR。')
    ..writeln('4. audio/：原始WAV分片；当转写不确定时，可结合原始录音核对。')
    ..writeln()
    ..writeln('整理规则：')
    ..writeln('1. 以 offsetMs 和时间戳恢复讲解、照片、章节、重点和疑问之间的关系。')
    ..writeln('2. 转写是实时识别初稿，专有名词、数字、公式和引用必须结合上下文与照片校正。')
    ..writeln('3. 图片应插入最相关的正文位置，使用 ZIP 内相对路径，不要只放在文末。')
    ..writeln('4. 每项关键内容必须标记为“老师明确讲过”“照片直接可见”“AI结合上下文推测”或“需要人工核实”。')
    ..writeln('5. 不要把照片观察或AI推测改写成老师原话；证据不足时明确说明，不要编造。')
    ..writeln('6. 优先处理“重点”和“没听懂”节点；结合节点前后内容解释，仍不确定的列入待核实清单。')
    ..writeln('7. 输出一份结构清楚、可直接保存的 Markdown 文档，并保留重要时间戳。')
    ..writeln(
      '8. 节点同时提供 offsetMs（可播放位置）和 deviceTime（设备实际时间），暂停期间必须保留设备时间差，不要把它压缩掉。',
    )
    ..writeln()
    ..writeln('本场景建议输出结构：');
  for (final section in expectedSections) {
    buffer.writeln('- $section');
  }
  return buffer.toString().trimRight();
}

void _writeChronologicalIllustratedNotes(
  StringBuffer buffer,
  AiProcessingInput input,
) {
  buffer
    ..writeln('## 按时间整理的图文稿')
    ..writeln();

  final items = <({int offsetMs, int priority, String markdown})>[];
  for (final event in input.events) {
    if (event.type == TimelineEventType.chapter) {
      items.add((
        offsetMs: event.offsetMs,
        priority: 0,
        markdown: '### ${event.title ?? '未命名章节'} · ${_eventTime(event)}',
      ));
    } else if (event.type == TimelineEventType.highlight) {
      items.add((
        offsetMs: event.offsetMs,
        priority: 3,
        markdown:
            '- **[用户标记·重点]** ${_eventTime(event)} ${event.note ?? '此处需重点复习。'}',
      ));
    } else if (event.type == TimelineEventType.question) {
      items.add((
        offsetMs: event.offsetMs,
        priority: 3,
        markdown: '- **[用户标记·没听懂]** ${_eventTime(event)} 需结合前后转写重新解释。',
      ));
    } else if (event.type == TimelineEventType.text ||
        event.type == TimelineEventType.interruption) {
      final content = event.note ?? event.title;
      if (content != null && content.isNotEmpty) {
        items.add((
          offsetMs: event.offsetMs,
          priority: 3,
          markdown: '- **[记录]** ${_eventTime(event)} $content',
        ));
      }
    }
  }

  for (final transcript in input.transcripts) {
    if (transcript.text.trim().isEmpty) continue;
    items.add((
      offsetMs: transcript.startMs,
      priority: 1,
      markdown:
          '- **[${EvidenceKind.teacherSaid.label}]** ${_formatOffset(transcript.startMs)} ${transcript.text.trim()}',
    ));
  }

  final photos = [...input.photos]
    ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
  for (var index = 0; index < photos.length; index++) {
    final photo = photos[index];
    final assetPath = photoAssetRelativePath(index, photo.filePath);
    final caption = photo.userNote?.trim().isNotEmpty == true
        ? photo.userNote!.trim()
        : '照片 ${index + 1}';
    final nearby = photo.nearbyTranscript.trim();
    items.add((
      offsetMs: photo.offsetMs,
      priority: 2,
      markdown:
          '![${markdownEscapeAlt(caption)}]($assetPath)\n\n'
          '*[${EvidenceKind.directlyObserved.label}] ${_photoTime(photo)}：$caption*'
          '${nearby.isEmpty ? '' : '\n\n> 附近讲解：$nearby'}',
    ));
  }

  items.sort((a, b) {
    final byTime = a.offsetMs.compareTo(b.offsetMs);
    return byTime != 0 ? byTime : a.priority.compareTo(b.priority);
  });
  if (items.isEmpty) {
    buffer
      ..writeln('本次记录暂无可整理的转写、照片或时间节点。')
      ..writeln();
    return;
  }
  for (final item in items) {
    buffer
      ..writeln(item.markdown)
      ..writeln();
  }
}

String _formatOffset(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText'
      : '$minuteText:$secondText';
}

String _eventTime(TimelineEvent event) =>
    '${_formatOffset(event.offsetMs)} · 设备时间 ${formatDeviceTimestamp(event.createdAt)}';

String _photoTime(PhotoAiContext photo) =>
    '${_formatOffset(photo.offsetMs)} · 设备时间 ${photo.deviceTime == null ? '未知' : formatDeviceTimestamp(photo.deviceTime!)}';

List<PhotoAiContext> buildPhotoContexts({
  required List<TimelineEvent> events,
  required List<TranscriptSegment> transcripts,
}) {
  return events
      .where(
        (event) =>
            event.type == TimelineEventType.photo && event.photoPath != null,
      )
      .map((photo) {
        final from = photo.offsetMs - 45000;
        final to = photo.offsetMs + 45000;
        final nearby = transcripts
            .where((segment) => segment.endMs >= from && segment.startMs <= to)
            .map((segment) => segment.text)
            .join('\n');
        return PhotoAiContext(
          filePath: photo.photoPath!,
          offsetMs: photo.offsetMs,
          ocrText: '',
          nearbyTranscript: nearby,
          userNote: photo.note,
          deviceTime: photo.createdAt,
        );
      })
      .toList();
}
