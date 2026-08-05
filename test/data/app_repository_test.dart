import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sync_notes/data/app_database.dart';
import 'package:sync_notes/data/app_repository.dart';
import 'package:sync_notes/models/entities.dart';

Session buildSession({SessionStatus status = SessionStatus.recording}) =>
    Session(
      id: 'session-1',
      title: '测试课堂',
      sceneType: SceneType.classroom,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      recordingStartedAt: DateTime.fromMillisecondsSinceEpoch(1100),
      durationMs: 0,
      status: status,
      aiStatus: AiStatus.notStarted,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  test('Session和TimelineEvent可写入并读回，时间轴按offset排序', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = AppRepository(database);
    await repository.insertSession(buildSession());
    await repository.insertTimelineEvent(
      TimelineEvent(
        id: 'later',
        sessionId: 'session-1',
        type: TimelineEventType.highlight,
        offsetMs: 9000,
        createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
      ),
    );
    await repository.insertTimelineEvent(
      TimelineEvent(
        id: 'earlier',
        sessionId: 'session-1',
        type: TimelineEventType.question,
        offsetMs: 2000,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );

    final session = await repository.getSession('session-1');
    final events = await repository.listTimelineEvents('session-1');
    expect(session?.title, '测试课堂');
    expect(events.map((event) => event.id), ['earlier', 'later']);
    await database.close();
  });

  test('App重启后仍能发现未完成记录并恢复结构化数据', () async {
    final directory = await Directory.systemTemp.createTemp('sync_notes_test_');
    final path = '${directory.path}/recovery.sqlite';
    var database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    var repository = AppRepository(database);
    await repository.insertSession(buildSession(status: SessionStatus.paused));
    await database.close();

    database = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    repository = AppRepository(database);
    final incomplete = await repository.listIncompleteSessions();
    expect(incomplete.single.id, 'session-1');
    expect(incomplete.single.status, SessionStatus.paused);
    await database.close();
    await directory.delete(recursive: true);
  });

  test('实时转写片段按开始时间持久化', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = AppRepository(database);
    await repository.insertSession(buildSession());
    await repository.insertTranscript(
      const TranscriptSegment(
        id: 'later-transcript',
        sessionId: 'session-1',
        startMs: 5000,
        endMs: 8000,
        text: '后一句',
      ),
    );
    await repository.insertTranscript(
      const TranscriptSegment(
        id: 'early-transcript',
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 3000,
        text: '前一句',
      ),
    );
    final transcripts = await repository.listTranscripts('session-1');
    expect(transcripts.map((item) => item.text), ['前一句', '后一句']);
    await database.close();
  });

  test('云端稳定句替换重叠的本地字幕初稿', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = AppRepository(database);
    await repository.insertSession(buildSession());
    await repository.insertTranscript(
      const TranscriptSegment(
        id: 'local',
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 5000,
        text: '本地错误初稿',
        speakerLabel: '本地初稿',
      ),
    );
    await repository.deleteLocalTranscriptsOverlapping(
      sessionId: 'session-1',
      startMs: 1200,
      endMs: 4800,
    );
    await repository.insertTranscript(
      const TranscriptSegment(
        id: 'cloud',
        sessionId: 'session-1',
        startMs: 1200,
        endMs: 4800,
        text: '云端稳定结果',
        speakerLabel: '腾讯云',
      ),
    );
    final transcripts = await repository.listTranscripts('session-1');
    expect(transcripts.map((item) => item.text), ['云端稳定结果']);
    await database.close();
  });
}
