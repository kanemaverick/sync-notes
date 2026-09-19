import 'package:shared_preferences/shared_preferences.dart';

enum OfflineAsrModel { bilingual, chinese }

class LocalTranscriptionConfig {
  const LocalTranscriptionConfig({
    this.model = OfflineAsrModel.bilingual,
    this.hotwords = const [],
  });
  final OfflineAsrModel model;
  final List<String> hotwords;
}

/// No decoder syntax/weights from user input are passed through to native code.
List<String> normalizeHotwords(String input) => input
    .split(RegExp(r'[\n,，;；]'))
    .map(
      (s) => s
          .trim()
          .toUpperCase()
          .replaceAll(RegExp(r'[^\u3400-\u9fffA-Z0-9\s\x27-]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    )
    .where((s) => s.isNotEmpty && s.length <= 60)
    .toSet()
    .take(80)
    .toList();

class LocalTranscriptionSettingsStore {
  LocalTranscriptionSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;

  Future<LocalTranscriptionConfig> load() async => LocalTranscriptionConfig(
    model: await _preferences.getString('local_asr.model') == 'chinese'
        ? OfflineAsrModel.chinese
        : OfflineAsrModel.bilingual,
    hotwords: normalizeHotwords(
      await _preferences.getString('local_asr.hotwords') ?? '',
    ),
  );

  Future<void> save(LocalTranscriptionConfig config) async {
    await _preferences.setString('local_asr.model', config.model.name);
    await _preferences.setString(
      'local_asr.hotwords',
      normalizeHotwords(config.hotwords.join('\n')).join('\n'),
    );
  }
}
