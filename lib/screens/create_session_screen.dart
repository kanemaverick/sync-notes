import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/app_theme.dart';
import '../data/app_repository.dart';
import '../models/entities.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({required this.repository, super.key});
  final SessionWriter repository;

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _activityName = TextEditingController();
  final _note = TextEditingController();
  SceneType _scene = SceneType.classroom;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _activityName.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final title = _title.text.trim().isEmpty
        ? '${_scene.defaultTitlePrefix}记录 · ${DateFormat('yyyy-MM-dd HH:mm').format(now)}'
        : _title.text.trim();
    final session = Session(
      id: const Uuid().v4(),
      title: title,
      sceneType: _scene,
      location: _nullable(_location.text),
      note: _nullable(_note.text),
      activityName: _nullable(_activityName.text),
      createdAt: now,
      durationMs: 0,
      status: SessionStatus.draft,
      aiStatus: AiStatus.notStarted,
    );
    await widget.repository.insertSession(session);
    if (mounted) Navigator.pop(context, session);
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建记录')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            8,
            AppSpacing.lg,
            32,
          ),
          children: [
            Text('准备记录什么？', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '只需选择场景即可开始，其余内容稍后也能补充。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标题（可选）',
                hintText: '留空将按场景和时间自动命名',
              ),
            ),
            const SizedBox(height: 16),
            Text('场景', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SceneType.values
                  .map(
                    (scene) => ChoiceChip(
                      label: Text(scene.label),
                      selected: _scene == scene,
                      onSelected: (_) => setState(() => _scene = scene),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _activityName,
              decoration: const InputDecoration(
                labelText: '课程或活动名称（可选）',
                prefixIcon: Icon(Icons.event_note_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: '地点（可选）',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '简短说明（可选）'),
            ),
            const SizedBox(height: 20),
            Card(
              color: Theme.of(
                context,
              ).colorScheme.tertiaryContainer.withValues(alpha: 0.55),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('开始即表示你已获得讲解人许可，并会遵守所在地区和场所的录音规定。')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mic),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('开始录音'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
