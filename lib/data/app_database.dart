import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final resolvedFactory = factory ?? databaseFactory;
    final databasePath =
        path ?? p.join(await getDatabasesPath(), 'sync_notes.sqlite');
    final db = await resolvedFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              scene_type TEXT NOT NULL,
              location TEXT,
              speaker TEXT,
              note TEXT,
              created_at INTEGER NOT NULL,
              recording_started_at INTEGER,
              duration_ms INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL,
              ai_status TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE audio_segments (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              file_path TEXT NOT NULL,
              timeline_start_ms INTEGER NOT NULL,
              duration_ms INTEGER NOT NULL,
              sequence INTEGER NOT NULL,
              UNIQUE(session_id, sequence)
            )
          ''');
          await database.execute('''
            CREATE TABLE timeline_events (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              type TEXT NOT NULL,
              offset_ms INTEGER NOT NULL,
              title TEXT,
              note TEXT,
              photo_path TEXT,
              thumbnail_path TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE transcript_segments (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
              start_ms INTEGER NOT NULL,
              end_ms INTEGER NOT NULL,
              text TEXT NOT NULL,
              speaker_label TEXT
            )
          ''');
          await database.execute(
            'CREATE INDEX timeline_session_offset ON timeline_events(session_id, offset_ms, created_at)',
          );
          await database.execute(
            'CREATE INDEX audio_session_sequence ON audio_segments(session_id, sequence)',
          );
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();
}
