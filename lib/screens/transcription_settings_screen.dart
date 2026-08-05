import 'package:flutter/material.dart';

import '../services/cloud_transcription_settings.dart';

class TranscriptionSettingsScreen extends StatefulWidget {
  const TranscriptionSettingsScreen({required this.store, super.key});

  final CloudTranscriptionSettingsStore store;

  @override
  State<TranscriptionSettingsScreen> createState() =>
      _TranscriptionSettingsScreenState();
}

class _TranscriptionSettingsScreenState
    extends State<TranscriptionSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _urlController.text = config.proxyUrl;
      _tokenController.text = config.accessToken;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_enabled && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.store.save(
      CloudTranscriptionConfig(
        enabled: _enabled,
        proxyUrl: _urlController.text,
        accessToken: _tokenController.text,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _restoreBundledConfig() async {
    await widget.store.restoreBundledConfig();
    final config = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _urlController.text = config.proxyUrl;
      _tokenController.text = config.accessToken;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实时转写设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用腾讯云实时转写'),
                    subtitle: const Text(
                      '启用后，录音 PCM 会经你的代理发送给腾讯云；失败时自动保留本地字幕和录音',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  if (widget.store.hasBundledConfig) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text('已内置云端转写服务'),
                        subtitle: const Text('新设备安装后会自动使用内置配置，无需连接开发电脑。'),
                        trailing: TextButton(
                          onPressed: _restoreBundledConfig,
                          child: const Text('恢复内置设置'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _urlController,
                    enabled: _enabled,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '安全代理 WebSocket 地址',
                      hintText: 'wss://example.com/v1/asr/tencent/realtime',
                    ),
                    validator: _enabled ? validateCloudProxyUrl : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tokenController,
                    enabled: _enabled,
                    obscureText: _obscureToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '代理访问令牌',
                      helperText: '这是代理令牌，不是腾讯云 SecretKey',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        _enabled && (value?.trim().isEmpty ?? true)
                        ? '请输入代理访问令牌'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.security_outlined),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '腾讯云 AppID、SecretID 和 SecretKey 只能配置在代理服务器。'
                              'App 不保存云厂商密钥，也不会因为断网停止本地录音。',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('保存设置'),
                  ),
                ],
              ),
            ),
    );
  }
}
