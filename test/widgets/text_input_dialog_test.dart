import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/widgets/text_input_dialog.dart';

void main() {
  testWidgets('输入弹窗在退出动画完成后安全释放输入控制器', (tester) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const TextInputDialog(
                    title: '添加照片备注',
                    hintText: '一句话即可，也可以跳过',
                    cancelLabel: '跳过',
                    submitLabel: '保存',
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '板书中的关键公式');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, '板书中的关键公式');
    expect(find.byType(TextInputDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
