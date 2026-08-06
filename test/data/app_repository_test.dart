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

  test('SQLite v1升级到v3后保留旧记录并补充新字段', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sync_notes_migration_',
    );
    final path = '${directory.path}/migration.sqlite';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY, title TEXT NOT NULL, scene_type TEXT NOT NULL,
              location TEXT, speaker TEXT, note TEXT, created_at INTEGER NOT NULL,
              recording_started_at INTEGER, duration_ms INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL, ai_status TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE timeline_events (
              id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              type TEXT NOT NULL, offset_ms INTEGER NOT NULL, title TEXT, note TEXT,
              photo_path TEXT, thumbnail_path TEXT, created_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE audio_segments (
              id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              file_path TEXT NOT NULL, timeline_start_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
              sequence INTEGER NOT NULL, UNIQUE(session_id, sequence)
            )
          ''');
          await database.execute('''
            CREATE TABLE transcript_segments (
              id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, text TEXT NOT NULL, speaker_label TEXT
            )
          ''');
        },
      ),
    );
    await legacy.insert(
      'sessions',
      buildSession().toMap()
        ..remove('activity_name')
        ..remove('tags')
        ..remove('exported_at')
        ..remove('export_path')
        ..remove('export_size_bytes'),
    );
    await legacy.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final repository = AppRepository(upgraded);
    final session = await repository.getSession('session-1');
    expect(session?.title, '测试课堂');
    expect(session?.activityName, isNull);
    expect(session?.tags, isEmpty);
    final columns = await upgraded.db.rawQuery(
      'PRAGMA table_info(timeline_events)',
    );
    expect(columns.map((row) => row['name']), contains('photo_source'));
    await upgraded.close();
    await directory.delete(recursive: true);
  });

  test('全文搜索可命中字幕并返回连续时间点', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = AppRepository(database);
    await repository.insertSession(buildSession());
    await repository.insertTranscript(
      const TranscriptSegment(
        id: 'search-text',
        sessionId: 'session-1',
        startMs: 42000,
        endMs: 46000,
        text: '多普勒频移用于计算流速',
      ),
    );
    final results = await repository.search(query: '多普勒');
    expect(results.single.kind, '字幕');
    expect(results.single.offsetMs, 42000);
    await database.close();
  });

  test('SQLite v2升级到v3后补充导出历史字段', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sync_notes_v3_migration_',
    );
    final path = '${directory.path}/migration.sqlite';
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, _) => database.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, scene_type TEXT NOT NULL,
            location TEXT, speaker TEXT, note TEXT, activity_name TEXT,
            tags TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
            recording_started_at INTEGER, duration_ms INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL, ai_status TEXT NOT NULL
          )
        '''),
      ),
    );
    await v2.close();
    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final columns = await upgraded.db.rawQuery('PRAGMA table_info(sessions)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll(['exported_at', 'export_path', 'export_size_bytes']),
    );
    await upgraded.close();
    await directory.delete(recursive: true);
  });

  test('SQLite v2已提前存在导出字段时升级仍可安全完成', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sync_notes_dirty_v2_',
    );
    final path = '${directory.path}/migration.sqlite';
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, _) => database.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, scene_type TEXT NOT NULL,
            location TEXT, speaker TEXT, note TEXT, activity_name TEXT,
            tags TEXT NOT NULL DEFAULT '', exported_at INTEGER, export_path TEXT,
            export_size_bytes INTEGER, created_at INTEGER NOT NULL,
            recording_started_at INTEGER, duration_ms INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL, ai_status TEXT NOT NULL
          )
        '''),
      ),
    );
    await v2.insert('sessions', buildSession().toMap());
    await v2.close();
    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final session = await AppRepository(upgraded).getSession('session-1');
    expect(session?.title, '测试课堂');
    final columns = await upgraded.db.rawQuery('PRAGMA table_info(sessions)');
    expect(columns.where((row) => row['name'] == 'exported_at'), hasLength(1));
    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
