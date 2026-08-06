import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';
import 'app_database.dart';

abstract interface class SessionWriter {
  Future<void> insertSession(Session session);
}

class AppRepository implements SessionWriter {
  AppRepository(this.database);

  final AppDatabase database;
  Database get _db => database.db;

  @override
  Future<void> insertSession(Session session) =>
      _db.insert('sessions', session.toMap());

  Future<void> updateSession(Session session) => _db.update(
    'sessions',
    session.toMap(),
    where: 'id = ?',
    whereArgs: [session.id],
  );

  Future<void> deleteSession(String sessionId) =>
      _db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);

  Future<Session?> getSession(String id) async {
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Session.fromMap(rows.first);
  }

  Future<List<SessionSummary>> listSessionSummaries() async {
    final rows = await _db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM timeline_events e
         WHERE e.session_id = s.id AND e.type = 'photo') AS photo_count
        ,(SELECT COUNT(*) FROM timeline_events e
          WHERE e.session_id = s.id) AS event_count
        ,(SELECT COUNT(*) FROM transcript_segments t
          WHERE t.session_id = s.id) AS transcript_count
        ,(SELECT COALESCE(e.thumbnail_path, e.photo_path)
          FROM timeline_events e WHERE e.session_id = s.id AND e.type = 'photo'
          ORDER BY e.offset_ms LIMIT 1) AS cover_path
        ,EXISTS(SELECT 1 FROM transcript_segments t
          WHERE t.session_id = s.id AND COALESCE(t.speaker_label, '') != '腾讯云') AS has_offline
        ,EXISTS(SELECT 1 FROM transcript_segments t
          WHERE t.session_id = s.id AND t.speaker_label = '腾讯云') AS has_cloud
      FROM sessions s
      ORDER BY s.created_at DESC
    ''');
    return rows
        .map(
          (row) => SessionSummary(
            session: Session.fromMap(row),
            photoCount: row['photo_count']! as int,
            eventCount: row['event_count']! as int,
            transcriptCount: row['transcript_count']! as int,
            coverPath: row['cover_path'] as String?,
            hasOfflineTranscript: row['has_offline'] == 1,
            hasCloudTranscript: row['has_cloud'] == 1,
          ),
        )
        .toList();
  }

  Future<List<Session>> listIncompleteSessions() async {
    final rows = await _db.query(
      'sessions',
      where: 'status IN (?, ?)',
      whereArgs: [SessionStatus.recording.name, SessionStatus.paused.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(Session.fromMap).toList();
  }

  Future<void> upsertAudioSegment(AudioSegment segment) => _db.insert(
    'audio_segments',
    segment.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<List<AudioSegment>> listAudioSegments(String sessionId) async {
    final rows = await _db.query(
      'audio_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'sequence ASC',
    );
    return rows.map(AudioSegment.fromMap).toList();
  }

  Future<void> insertTimelineEvent(TimelineEvent event) => _db.insert(
    'timeline_events',
    event.toMap(),
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );

  Future<void> updateTimelineEvent(TimelineEvent event) => _db.update(
    'timeline_events',
    event.toMap(),
    where: 'id = ?',
    whereArgs: [event.id],
  );

  Future<void> deleteTimelineEvent(String id) =>
      _db.delete('timeline_events', where: 'id = ?', whereArgs: [id]);

  Future<List<TimelineEvent>> listTimelineEvents(String sessionId) async {
    final rows = await _db.query(
      'timeline_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'offset_ms ASC, created_at ASC',
    );
    return rows.map(TimelineEvent.fromMap).toList();
  }

  Future<void> insertTranscript(TranscriptSegment segment) => _db.insert(
    'transcript_segments',
    segment.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> replaceTranscripts(
    String sessionId,
    List<TranscriptSegment> segments,
  ) => _db.transaction((transaction) async {
    await transaction.delete(
      'transcript_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    for (final segment in segments) {
      await transaction.insert(
        'transcript_segments',
        segment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });

  Future<void> deleteLocalTranscriptsOverlapping({
    required String sessionId,
    required int startMs,
    required int endMs,
  }) => _db.delete(
    'transcript_segments',
    where:
        'session_id = ? AND speaker_label = ? AND start_ms < ? AND end_ms > ?',
    whereArgs: [sessionId, '本地初稿', endMs, startMs],
  );

  Future<List<TranscriptSegment>> listTranscripts(String sessionId) async {
    final rows = await _db.query(
      'transcript_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'start_ms ASC',
    );
    return rows.map(TranscriptSegment.fromMap).toList();
  }

  Future<void> updateTranscript(TranscriptSegment segment) => _db.update(
    'transcript_segments',
    segment.toMap(),
    where: 'id = ?',
    whereArgs: [segment.id],
  );

  Future<List<SessionSearchResult>> search({
    required String query,
    SceneType? sceneType,
    bool photosOnly = false,
    bool highlightsOnly = false,
    bool questionsOnly = false,
    bool exportedOnly = false,
    String? transcriptSource,
    DateTime? createdAfter,
  }) async {
    final normalized = query.trim();
    final like = '%$normalized%';
    final rows = await _db.rawQuery(
      '''
      SELECT s.*, m.match_kind, m.context_text, m.match_offset
      FROM sessions s
      JOIN (
        SELECT id AS session_id, '记录' AS match_kind, title AS context_text,
               NULL AS match_offset
        FROM sessions
        WHERE (? = '' OR title LIKE ? OR scene_type LIKE ? OR
               COALESCE(location, '') LIKE ? OR COALESCE(speaker, '') LIKE ? OR
               COALESCE(note, '') LIKE ? OR COALESCE(activity_name, '') LIKE ? OR
               COALESCE(tags, '') LIKE ?)
        UNION ALL
        SELECT session_id, type AS match_kind, COALESCE(note, title, '') AS context_text,
               offset_ms AS match_offset
        FROM timeline_events
        WHERE ? <> '' AND (COALESCE(title, '') LIKE ? OR COALESCE(note, '') LIKE ?)
        UNION ALL
        SELECT session_id, '字幕' AS match_kind, text AS context_text,
               start_ms AS match_offset
        FROM transcript_segments
        WHERE ? <> '' AND text LIKE ?
      ) m ON m.session_id = s.id
      WHERE (? IS NULL OR s.scene_type = ?)
        AND (? = 0 OR EXISTS (SELECT 1 FROM timeline_events p WHERE p.session_id=s.id AND p.type='photo'))
        AND (? = 0 OR EXISTS (SELECT 1 FROM timeline_events h WHERE h.session_id=s.id AND h.type='highlight'))
        AND (? = 0 OR EXISTS (SELECT 1 FROM timeline_events q WHERE q.session_id=s.id AND q.type='question'))
        AND (? = 0 OR s.exported_at IS NOT NULL)
        AND (? IS NULL OR EXISTS (
          SELECT 1 FROM transcript_segments ts
          WHERE ts.session_id=s.id AND (
            (? = 'cloud' AND ts.speaker_label = '腾讯云') OR
            (? = 'offline' AND COALESCE(ts.speaker_label, '') != '腾讯云')
          )
        ))
        AND (? IS NULL OR s.created_at >= ?)
      ORDER BY s.created_at DESC, m.match_offset ASC
      LIMIT 100
      ''',
      [
        normalized,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        normalized,
        like,
        like,
        normalized,
        like,
        sceneType?.name,
        sceneType?.name,
        photosOnly ? 1 : 0,
        highlightsOnly ? 1 : 0,
        questionsOnly ? 1 : 0,
        exportedOnly ? 1 : 0,
        transcriptSource,
        transcriptSource,
        transcriptSource,
        createdAfter?.millisecondsSinceEpoch,
        createdAfter?.millisecondsSinceEpoch,
      ],
    );
    final seen = <String>{};
    return rows
        .map((row) {
          final session = Session.fromMap(row);
          final offset = row['match_offset'] as int?;
          final key = '${session.id}:${offset ?? -1}:${row['match_kind']}';
          if (!seen.add(key)) return null;
          return SessionSearchResult(
            session: session,
            contextText:
                (row['context_text'] as String?)?.trim().isNotEmpty == true
                ? row['context_text']! as String
                : session.title,
            offsetMs: offset,
            kind: row['match_kind']! as String,
          );
        })
        .whereType<SessionSearchResult>()
        .toList();
  }
}
