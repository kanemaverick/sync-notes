import 'package:shared_preferences/shared_preferences.dart';

enum CloudAsrProvider {
  tencent('腾讯云', '/v1/asr/tencent/realtime'),
  aliyun('阿里 Fun-ASR', '/v1/asr/aliyun/realtime'),
  doubao('豆包语音', '/v1/asr/doubao/realtime'),
  custom('自定义兼容代理', '');

  const CloudAsrProvider(this.label, this.path);
  final String label;
  final String path;

  static CloudAsrProvider fromUrl(String url) {
    final path = Uri.tryParse(url.trim())?.path;
    return values.firstWhere(
      (provider) => provider != custom && provider.path == path,
      orElse: () => custom,
    );
  }
}

/// Switching provider keeps the operator's server and routing query intact.
/// A custom path is never guessed; its owner must enter the correct endpoint.
String cloudProviderUrl(String current, CloudAsrProvider provider) {
  if (provider == CloudAsrProvider.custom) return current;
  final uri = Uri.tryParse(current.trim());
  if (uri == null || uri.host.isEmpty) return '';
  return uri.replace(path: provider.path).toString();
}

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
    this.preferences,
    this.bundledConfig = bundledCloudTranscriptionConfig,
  });

  static const _enabledKey = 'cloud_asr.enabled';
  static const _proxyUrlKey = 'cloud_asr.proxy_url';
  static const _accessTokenKey = 'cloud_asr.access_token';

  SharedPreferencesAsync? preferences;
  SharedPreferencesAsync get _prefs => preferences ??= SharedPreferencesAsync();
  final CloudTranscriptionConfig bundledConfig;

  bool get hasBundledConfig => bundledConfig.isConfigured;

  Future<CloudTranscriptionConfig> load() async {
    final savedEnabled = await _prefs.getBool(_enabledKey);
    final savedProxyUrl = await _prefs.getString(_proxyUrlKey);
    final savedAccessToken = await _prefs.getString(_accessTokenKey);
    return resolveCloudTranscriptionConfig(
      bundledConfig: bundledConfig,
      savedEnabled: savedEnabled,
      savedProxyUrl: savedProxyUrl,
      savedAccessToken: savedAccessToken,
    );
  }

  Future<void> save(CloudTranscriptionConfig config) async {
    await _prefs.setBool(_enabledKey, config.enabled);
    await _prefs.setString(_proxyUrlKey, config.proxyUrl.trim());
    await _prefs.setString(_accessTokenKey, config.accessToken.trim());
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
