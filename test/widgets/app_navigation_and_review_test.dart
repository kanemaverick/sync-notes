import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_notes/data/app_database.dart';
import 'package:sync_notes/data/app_repository.dart';
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/screens/home_screen.dart';
import 'package:sync_notes/screens/review_screen.dart';
import 'package:sync_notes/services/ai_processing_service.dart';
import 'package:sync_notes/services/background_recording_service.dart';
import 'package:sync_notes/services/cloud_transcription_settings.dart';
import 'package:sync_notes/services/media_storage.dart';

Session _session() => Session(
  id: 'ui-session',
  title: '流速仪现场讲解',
  sceneType: SceneType.fieldVisit,
  createdAt: DateTime(2026, 8, 6, 9, 30),
  durationMs: 90000,
  status: SessionStatus.completed,
  aiStatus: AiStatus.notStarted,
);

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('首页提供记录搜索资料包设置四个一级入口', (tester) async {
    late AppDatabase database;
    late Directory root;
    await tester.runAsync(() async {
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      root = await Directory.systemTemp.createTemp('sync_notes_home_ui_');
    });
    final repository = AppRepository(database);
    SharedPreferences.setMockInitialValues({});
    final storage = MediaStorage(rootDirectory: root);
    final recording = BackgroundRecordingService(
      repository: repository,
      storage: storage,
      cloudSettings: CloudTranscriptionSettingsStore(),
    );
    final summary = SessionSummary(session: _session(), photoCount: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: repository,
          storage: storage,
          recording: recording,
          cloudSettings: CloudTranscriptionSettingsStore(),
          aiService: const MockAiProcessingService(),
          sessionLoader: () async => [summary],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('流速仪现场讲解'), findsOneWidget);
    for (final destination in ['记录', '搜索', '资料包', '设置']) {
      expect(find.text(destination), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await database.close();
      await root.delete(recursive: true);
    });
  });

  testWidgets('记录详情包含回顾字幕时间轴资料包并可打开字幕', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late AppDatabase database;
    late Directory root;
    await tester.runAsync(() async {
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      root = await Directory.systemTemp.createTemp('sync_notes_review_ui_');
    });
    final session = _session();
    final event = TimelineEvent(
      id: 'highlight',
      sessionId: session.id,
      type: TimelineEventType.highlight,
      offsetMs: 12000,
      title: '重点',
      note: '注意测量方向',
      createdAt: DateTime(2026, 8, 6, 9, 31),
    );
    const transcript = TranscriptSegment(
      id: 'transcript',
      sessionId: 'ui-session',
      startMs: 10000,
      endMs: 16000,
      text: '设备根据多普勒频移计算流速',
      speakerLabel: '本地初稿',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          session: session,
          repository: AppRepository(database),
          storage: MediaStorage(rootDirectory: root),
          aiService: const MockAiProcessingService(),
          bootstrapData: ReviewBootstrapData(
            events: [event],
            transcripts: const [transcript],
          ),
        ),
      ),
    );
    await tester.pump();
    for (final tab in ['回顾', '字幕', '时间轴', '资料包']) {
      expect(find.text(tab), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(Tab, '字幕'));
    await tester.pumpAndSettle();
    expect(find.text('设备根据多普勒频移计算流速'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await database.close();
      await root.delete(recursive: true);
    });
  });
}
