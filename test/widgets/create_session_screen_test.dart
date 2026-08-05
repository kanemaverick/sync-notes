import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/data/app_repository.dart';
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/screens/create_session_screen.dart';

class FakeSessionWriter implements SessionWriter {
  @override
  Future<void> insertSession(Session session) async {}
}

void main() {
  testWidgets('标题必填并显示录音合规提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CreateSessionScreen(repository: FakeSessionWriter())),
    );
    expect(find.textContaining('获得讲解人许可'), findsOneWidget);
    await tester.tap(find.text('开始记录'));
    await tester.pump();
    expect(find.text('请输入标题'), findsOneWidget);
  });
}
