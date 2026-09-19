import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/cloud_transcription_settings.dart';
import '../services/local_transcription_settings.dart';
import '../services/asr_diagnostics.dart';

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
  final _hotwordsController = TextEditingController();
  final _localStore = LocalTranscriptionSettingsStore();
  OfflineAsrModel _localModel = OfflineAsrModel.bilingual;
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscureToken = true;
  bool _testing = false;
  CloudAsrProvider _provider = CloudAsrProvider.custom;

  Future<void> _checkModel() async {
    if (await FlutterForegroundTask.isRunningService) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先结束当前录音再做模型自检，避免争用计算资源')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _testing = true);
    try {
      final text = await checkOfflineRecognizer(
        LocalTranscriptionConfig(
          model: _localModel,
          hotwords: normalizeHotwords(_hotwordsController.text),
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('本机离线识别自检完成'),
          content: SingleChildScrollView(
            child: SelectableText(
              '测试音频：中文夹杂英文星期词。\n\n识别结果：\n$text\n\n本次仅处理安装包里的示例音频，不使用麦克风，也未上传。自检通过不代表会议现场准确率。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('离线模型自检失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await widget.store.load();
    final local = await _localStore.load();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _localModel = local.model;
      _hotwordsController.text = local.hotwords.join('\n');
      _urlController.text = config.proxyUrl;
      _provider = CloudAsrProvider.fromUrl(config.proxyUrl);
      _tokenController.text = config.accessToken;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_enabled && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _localStore.save(
        LocalTranscriptionConfig(
          model: _localModel,
          hotwords: normalizeHotwords(_hotwordsController.text),
        ),
      );
      await widget.store.save(
        CloudTranscriptionConfig(
          enabled: _enabled,
          proxyUrl: _urlController.text,
          accessToken: _tokenController.text,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _restoreBundledConfig() async {
    await widget.store.restoreBundledConfig();
    final config = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _urlController.text = config.proxyUrl;
      _provider = CloudAsrProvider.fromUrl(config.proxyUrl);
      _tokenController.text = config.accessToken;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _hotwordsController.dispose();
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
                  Text('本机离线识别', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<OfflineAsrModel>(
                    initialValue: _localModel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '离线模型'),
                    items: const [
                      DropdownMenuItem(
                        value: OfflineAsrModel.bilingual,
                        child: Text('中英双语 · 会议推荐'),
                      ),
                      DropdownMenuItem(
                        value: OfflineAsrModel.chinese,
                        child: Text('轻量中文 · 低负载'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _localModel = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _hotwordsController,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: '会议术语 / 人名 / 英文缩写',
                      hintText: 'Transformer\n神经网络\nPPT\nGPU',
                      helperText: '每行一个，最多 80 项、每项 60 字。仅影响下次录音；热词不能保证识别准确。',
                      helperMaxLines: 3,
                    ),
                  ),
                  const Text('模型随 App 安装，无需网络或电脑。热词会增加计算量；录音始终优先，字幕仅作为初稿。'),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _checkModel,
                    icon: _testing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_outlined),
                    label: Text(_testing ? '正在本机自检，请稍候…' : '验证当前离线模型（不录音、不联网）'),
                  ),
                  const Divider(height: 40),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用云端实时转写'),
                    subtitle: const Text(
                      '启用后，录音会经你的代理上传至所选服务商；断网不影响本地录音。新服务需先在服务器配置密钥。',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  DropdownButtonFormField<CloudAsrProvider>(
                    key: ValueKey(_provider),
                    initialValue: _provider,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '云端识别服务'),
                    items: CloudAsrProvider.values
                        .map(
                          (provider) => DropdownMenuItem(
                            value: provider,
                            child: Text(provider.label),
                          ),
                        )
                        .toList(),
                    onChanged: _enabled
                        ? (provider) {
                            if (provider == null) return;
                            setState(() {
                              _urlController.text = cloudProviderUrl(
                                _urlController.text,
                                provider,
                              );
                              _provider = provider;
                            });
                          }
                        : null,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '选择只修改代理路由，不会自动开通服务。阿里、豆包接口仍待真实云端验证。上方术语目前仅用于本机识别，云端热词需在服务器配置。',
                    ),
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
                    onChanged: (value) => setState(
                      () => _provider = CloudAsrProvider.fromUrl(value),
                    ),
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
                      helperText: '这是代理令牌，不是云厂商 API Key / SecretKey',
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
                              '云厂商 API Key、AppID、SecretID 和 SecretKey 只能配置在代理服务器。'
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
