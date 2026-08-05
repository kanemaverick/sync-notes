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
      FROM sessions s
      ORDER BY s.created_at DESC
    ''');
    return rows
        .map(
          (row) => SessionSummary(
            session: Session.fromMap(row),
            photoCount: row['photo_count']! as int,
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
}
