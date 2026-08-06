import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/cloud_transcription_settings.dart';
import 'transcription_settings_screen.dart';

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({required this.cloudSettings, super.key});
  final CloudTranscriptionSettingsStore cloudSettings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 32),
      children: [
        Text('记录与字幕', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: const Text('实时字幕'),
                subtitle: const Text('离线识别与腾讯云模式'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TranscriptionSettingsScreen(store: cloudSettings),
                  ),
                ),
              ),
              const Divider(indent: 56),
              const ListTile(
                leading: Icon(Icons.cut_rounded),
                title: Text('录音分片'),
                subtitle: Text('约每 5 分钟保存一个 WAV 分片'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('存储与隐私', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.phone_android_rounded),
                title: Text('本地优先'),
                subtitle: Text('录音、照片与字幕默认保存在本机'),
              ),
              Divider(indent: 56),
              ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('无账号与云同步'),
                subtitle: Text('只有启用云字幕时，实时音频帧会发送到安全代理'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('同步讲记'),
            subtitle: Text('本地优先多模态学习记录工具\n版本 1.1.1'),
            isThreeLine: true,
          ),
        ),
      ],
    ),
  );
}
