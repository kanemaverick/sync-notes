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
        version: 3,
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
              activity_name TEXT,
              tags TEXT NOT NULL DEFAULT '',
              exported_at INTEGER,
              export_path TEXT,
              export_size_bytes INTEGER,
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
              photo_source TEXT,
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
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _addColumnIfMissing(
              database,
              'sessions',
              'activity_name',
              'TEXT',
            );
            await _addColumnIfMissing(
              database,
              'sessions',
              'tags',
              "TEXT NOT NULL DEFAULT ''",
            );
            await _addColumnIfMissing(
              database,
              'timeline_events',
              'photo_source',
              'TEXT',
            );
          }
          if (oldVersion < 3) {
            await _addColumnIfMissing(
              database,
              'sessions',
              'exported_at',
              'INTEGER',
            );
            await _addColumnIfMissing(
              database,
              'sessions',
              'export_path',
              'TEXT',
            );
            await _addColumnIfMissing(
              database,
              'sessions',
              'export_size_bytes',
              'INTEGER',
            );
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();
}

Future<void> _addColumnIfMissing(
  Database database,
  String table,
  String column,
  String definition,
) async {
  final columns = await database.rawQuery('PRAGMA table_info($table)');
  if (columns.any((item) => item['name'] == column)) return;
  await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}
