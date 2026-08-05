import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

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
  final _speaker = TextEditingController();
  final _note = TextEditingController();
  SceneType _scene = SceneType.classroom;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _speaker.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final session = Session(
      id: const Uuid().v4(),
      title: _title.text.trim(),
      sceneType: _scene,
      location: _nullable(_location.text),
      speaker: _nullable(_speaker.text),
      note: _nullable(_note.text),
      createdAt: DateTime.now(),
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
      appBar: AppBar(title: const Text('创建记录')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined),
                    SizedBox(width: 12),
                    Expanded(child: Text('请确认你已经获得讲解人许可，并遵守所在地区和场所的录音规定。')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标题 *',
                hintText: '例如：材料力学第3讲',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入标题' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SceneType>(
              initialValue: _scene,
              decoration: const InputDecoration(labelText: '场景类型 *'),
              items: SceneType.values
                  .map(
                    (scene) => DropdownMenuItem(
                      value: scene,
                      child: Text(scene.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _scene = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: '地点（可选）'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _speaker,
              decoration: const InputDecoration(labelText: '老师或讲解人（可选）'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            const SizedBox(height: 24),
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
                child: Text('开始记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
