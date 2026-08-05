import 'package:shared_preferences/shared_preferences.dart';

const bundledCloudTranscriptionConfig = CloudTranscriptionConfig(
  enabled: bool.fromEnvironment('CLOUD_ASR_ENABLED'),
  proxyUrl: String.fromEnvironment('CLOUD_ASR_PROXY_URL'),
  accessToken: String.fromEnvironment('CLOUD_ASR_PROXY_TOKEN'),
);

class CloudTranscriptionConfig {
  const CloudTranscriptionConfig({
    required this.enabled,
    required this.proxyUrl,
    required this.accessToken,
  });

  const CloudTranscriptionConfig.disabled()
    : enabled = false,
      proxyUrl = '',
      accessToken = '';

  final bool enabled;
  final String proxyUrl;
  final String accessToken;

  bool get isConfigured {
    if (!enabled || accessToken.trim().isEmpty) return false;
    final uri = Uri.tryParse(proxyUrl.trim());
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'wss' || uri.scheme == 'ws');
  }
}

class CloudTranscriptionSettingsStore {
  CloudTranscriptionSettingsStore({
    SharedPreferencesAsync? preferences,
    this.bundledConfig = bundledCloudTranscriptionConfig,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _enabledKey = 'cloud_asr.enabled';
  static const _proxyUrlKey = 'cloud_asr.proxy_url';
  static const _accessTokenKey = 'cloud_asr.access_token';

  final SharedPreferencesAsync _preferences;
  final CloudTranscriptionConfig bundledConfig;

  bool get hasBundledConfig => bundledConfig.isConfigured;

  Future<CloudTranscriptionConfig> load() async {
    final savedEnabled = await _preferences.getBool(_enabledKey);
    final savedProxyUrl = await _preferences.getString(_proxyUrlKey);
    final savedAccessToken = await _preferences.getString(_accessTokenKey);
    return resolveCloudTranscriptionConfig(
      bundledConfig: bundledConfig,
      savedEnabled: savedEnabled,
      savedProxyUrl: savedProxyUrl,
      savedAccessToken: savedAccessToken,
    );
  }

  Future<void> save(CloudTranscriptionConfig config) async {
    await _preferences.setBool(_enabledKey, config.enabled);
    await _preferences.setString(_proxyUrlKey, config.proxyUrl.trim());
    await _preferences.setString(_accessTokenKey, config.accessToken.trim());
  }

  Future<void> restoreBundledConfig() async {
    await save(bundledConfig);
  }
}

CloudTranscriptionConfig resolveCloudTranscriptionConfig({
  required CloudTranscriptionConfig bundledConfig,
  bool? savedEnabled,
  String? savedProxyUrl,
  String? savedAccessToken,
}) => CloudTranscriptionConfig(
  enabled: savedEnabled ?? bundledConfig.enabled,
  proxyUrl: savedProxyUrl ?? bundledConfig.proxyUrl,
  accessToken: savedAccessToken ?? bundledConfig.accessToken,
);

String? validateCloudProxyUrl(String? value) {
  final text = value?.trim() ?? '';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return '请输入完整的代理地址';
  if (uri.scheme != 'wss' && uri.scheme != 'ws') {
    return '地址必须以 wss:// 或 ws:// 开头';
  }
  return null;
}
