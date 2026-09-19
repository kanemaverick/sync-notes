import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/screens/transcription_settings_screen.dart';
import 'package:sync_notes/services/cloud_transcription_settings.dart';
import 'package:sync_notes/services/local_transcription_settings.dart';

class FakeCloudStore extends CloudTranscriptionSettingsStore {
  bool fail = false;
  CloudTranscriptionConfig? saved;
  @override
  bool get hasBundledConfig => false;
  @override
  Future<CloudTranscriptionConfig> load() async {
    if (fail) throw StateError('private-error-not-for-ui');
    return const CloudTranscriptionConfig(
      enabled: true,
      proxyUrl: 'wss://proxy.example/v1/asr/tencent/realtime',
      accessToken: 'test-only-token',
    );
  }

  @override
  Future<void> save(CloudTranscriptionConfig config) async => saved = config;
}

class FakeLocalStore implements LocalTranscriptionSettingsStore {
  LocalTranscriptionConfig? saved;
  @override
  Future<LocalTranscriptionConfig> load() async =>
      const LocalTranscriptionConfig();
  @override
  Future<void> save(LocalTranscriptionConfig config) async => saved = config;
}

void main() {
  testWidgets('设置读取失败可重试且不写入空配置', (tester) async {
    final cloud = FakeCloudStore()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: TranscriptionSettingsScreen(
          store: cloud,
          localStore: FakeLocalStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('读取转写设置失败，原有配置未修改'), findsOneWidget);
    expect(cloud.saved, isNull);
    cloud.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('本机离线识别'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大字号可选择豆包并保存代理路由，不写入厂商密钥', (tester) async {
    final cloud = FakeCloudStore();
    final local = FakeLocalStore();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TranscriptionSettingsScreen(
                    store: cloud,
                    localStore: local,
                  ),
                ),
              ),
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    final selector = find.byType(DropdownButtonFormField<CloudAsrProvider>);
    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(selector, 300, scrollable: list);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('豆包语音').last);
    await tester.pumpAndSettle();
    expect(cloud.saved, isNull);
    final save = find.text('保存设置');
    await tester.scrollUntilVisible(save, 300, scrollable: list);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(cloud.saved!.proxyUrl, 'wss://proxy.example/v1/asr/doubao/realtime');
    expect(cloud.saved!.accessToken, 'test-only-token');
    expect(local.saved, isNotNull);
    expect(find.text('打开设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
