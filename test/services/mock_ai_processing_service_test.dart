import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/services/ai_processing_service.dart';

void main() {
  test('无API密钥时生成可交给Codex的场景提示词', () async {
    const service = MockAiProcessingService();
    final markdown = await service.process(
      AiProcessingInput(
        session: Session(
          id: 's',
          title: '参观记录',
          sceneType: SceneType.fieldVisit,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          durationMs: 1000,
          status: SessionStatus.completed,
          aiStatus: AiStatus.notStarted,
        ),
        transcripts: const [],
        photos: const [],
        events: const [],
      ),
    );
    expect(markdown, contains('## 交给 Codex 的整理提示词'));
    expect(markdown, contains('本场景建议输出结构：'));
    expect(markdown, contains('- 参观顺序'));
    expect(markdown, contains('- 装置、展品或现象'));
    expect(markdown, isNot(contains('演示占位')));
    expect(markdown, contains('老师明确讲过'));
    expect(markdown, contains('照片直接可见'));
    expect(markdown, contains('AI结合上下文推测'));
    expect(markdown, contains('需要人工核实'));
  });

  test('Codex提示词要求读取ZIP并把图片插入正文对应位置', () {
    final prompt = buildCodexAnalysisPrompt(
      Session(
        id: 'prompt',
        title: '专题讲座',
        sceneType: SceneType.lecture,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        durationMs: 1000,
        status: SessionStatus.completed,
        aiStatus: AiStatus.notStarted,
      ),
    );
    expect(prompt, contains('note.md'));
    expect(prompt, contains('manifest.json'));
    expect(prompt, contains('images/'));
    expect(prompt, contains('图片应插入最相关的正文位置'));
    expect(prompt, contains('不要编造'));
    expect(prompt, contains('- 核心观点'));
  });

  test('转写与照片按时间插入图文整理稿', () async {
    const service = MockAiProcessingService();
    final markdown = await service.process(
      AiProcessingInput(
        session: Session(
          id: 's2',
          title: '图文课堂',
          sceneType: SceneType.classroom,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          durationMs: 30000,
          status: SessionStatus.completed,
          aiStatus: AiStatus.notStarted,
        ),
        transcripts: const [
          TranscriptSegment(
            id: 't1',
            sessionId: 's2',
            startMs: 8000,
            endMs: 12000,
            text: '这是老师讲解的公式',
          ),
        ],
        photos: const [
          PhotoAiContext(
            filePath: '/private/photo.png',
            offsetMs: 10000,
            ocrText: '',
            nearbyTranscript: '这是老师讲解的公式',
            userNote: '板书公式',
          ),
        ],
        events: [
          TimelineEvent(
            id: 'c1',
            sessionId: 's2',
            type: TimelineEventType.chapter,
            offsetMs: 0,
            title: '章节1',
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
      ),
    );
    expect(markdown, contains('### 章节1 · 00:00'));
    expect(markdown, contains('这是老师讲解的公式'));
    expect('这是老师讲解的公式'.allMatches(markdown).length, 1);
    expect(markdown, isNot(contains('**[老师明确讲过]**')));
    expect(markdown, contains('![板书公式](images/photo_001.png)'));
    expect(
      markdown.indexOf('这是老师讲解的公式'),
      lessThan(markdown.indexOf('![板书公式]')),
    );
  });
}
