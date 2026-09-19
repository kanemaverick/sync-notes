import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/widgets/photo_source_sheet.dart';

void main() {
  testWidgets('照片入口可选择内置相机或相册', (tester) async {
    PhotoSourceChoice? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await showModalBottomSheet<PhotoSourceChoice>(
                  context: context,
                  builder: (_) => const PhotoSourceSheet(),
                );
              },
              child: const Text('照片'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('照片'));
    await tester.pumpAndSettle();
    expect(find.text('相机拍照'), findsOneWidget);
    expect(find.text('PPT / 文档扫描'), findsOneWidget);
    expect(find.text('从相册导入'), findsOneWidget);

    await tester.tap(find.text('从相册导入'));
    await tester.pumpAndSettle();
    expect(selected, PhotoSourceChoice.gallery);
    expect(tester.takeException(), isNull);
  });
}
