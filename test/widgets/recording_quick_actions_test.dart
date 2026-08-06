import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/widgets/recording_quick_actions.dart';

void main() {
  testWidgets('录音页五个快捷操作均可单击触发', (tester) async {
    final called = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingQuickActions(
            onPhoto: () => called.add('photo'),
            onHighlight: () => called.add('highlight'),
            onQuestion: () => called.add('question'),
            onChapter: () => called.add('chapter'),
            onNote: () => called.add('note'),
          ),
        ),
      ),
    );
    for (final label in ['拍照 / 相册', '重点', '没听懂', '章节', '备注']) {
      await tester.tap(find.text(label));
    }
    expect(called, ['photo', 'highlight', 'question', 'chapter', 'note']);
  });
}
