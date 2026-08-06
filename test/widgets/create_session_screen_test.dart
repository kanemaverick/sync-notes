import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/data/app_repository.dart';
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/screens/create_session_screen.dart';

class FakeSessionWriter implements SessionWriter {
  Session? inserted;

  @override
  Future<void> insertSession(Session session) async => inserted = session;
}

void main() {
  testWidgets('标题为空时自动命名并显示录音合规提示', (tester) async {
    final writer = FakeSessionWriter();
    await tester.pumpWidget(
      MaterialApp(home: CreateSessionScreen(repository: writer)),
    );
    expect(find.textContaining('获得讲解人许可'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始录音'));
    await tester.pump();
    expect(writer.inserted, isNotNull);
    expect(writer.inserted!.title, startsWith('课堂记录 ·'));
  });
}
