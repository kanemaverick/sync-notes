import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'data/app_repository.dart';
import 'screens/home_screen.dart';
import 'services/ai_processing_service.dart';
import 'services/background_recording_service.dart';
import 'services/cloud_transcription_settings.dart';
import 'services/media_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  final repository = AppRepository(database);
  final storage = MediaStorage();
  final cloudSettings = CloudTranscriptionSettingsStore();
  final recording = BackgroundRecordingService(
    repository: repository,
    storage: storage,
    cloudSettings: cloudSettings,
  )..initialize();
  await recording.recoverInterruptedSessions();
  runApp(
    SyncNotesApp(
      repository: repository,
      storage: storage,
      recording: recording,
      cloudSettings: cloudSettings,
      aiService: const MockAiProcessingService(),
    ),
  );
}

class SyncNotesApp extends StatelessWidget {
  const SyncNotesApp({
    required this.repository,
    required this.storage,
    required this.recording,
    required this.cloudSettings,
    required this.aiService,
    super.key,
  });

  final AppRepository repository;
  final MediaStorage storage;
  final BackgroundRecordingService recording;
  final CloudTranscriptionSettingsStore cloudSettings;
  final AiProcessingService aiService;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF426A5A);
    return MaterialApp(
      title: '同步讲记',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: HomeScreen(
        repository: repository,
        storage: storage,
        recording: recording,
        cloudSettings: cloudSettings,
        aiService: aiService,
      ),
    );
  }
}
