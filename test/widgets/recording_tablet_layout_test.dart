import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/widgets/live_transcript_panel.dart';
import 'package:sync_notes/widgets/recording_page_layout.dart';
import 'package:sync_notes/widgets/recording_quick_actions.dart';

void main() {
  for (final size in [
    const Size(1280, 800),
    const Size(800, 1280),
    const Size(1024, 600),
    const Size(600, 360),
    const Size(360, 640),
  ]) {
    testWidgets('录音整页可从按钮区域滚动到底部：$size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var stopped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('平板录音测试')),
            body: RecordingPageLayout(
              children: [
                const SizedBox(height: 140, child: Text('正在录音 00:30')),
                const LiveTranscriptPanel(
                  transcripts: [],
                  partialText: '实时字幕测试',
                  status: '云端识别',
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: RecordingQuickActions(
                    onPhoto: () {},
                    onHighlight: () {},
                    onQuestion: () {},
                    onChapter: () {},
                    onNote: () {},
                  ),
                ),
                FilledButton(
                  onPressed: () => stopped = true,
                  child: const Text('结束'),
                ),
                for (var i = 0; i < 5; i++)
                  SizedBox(height: 100, child: Text('最近事件 $i')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('展开全文（0段）'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final list = find.byKey(const PageStorageKey('recording-page-scroll'));
      await tester.scrollUntilVisible(
        find.text('结束'),
        180,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束'));
      expect(stopped, isTrue);
      await tester.drag(find.text('结束'), const Offset(0, -280));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('最近事件 4'),
        200,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('最近事件 4').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('平板按钮保持紧凑，旋转后无溢出，大字号仍可操作', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(800, 1280), const Size(1280, 800)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: RecordingPageLayout(
              children: [
                RecordingQuickActions(
                  onPhoto: () {},
                  onHighlight: () {},
                  onQuestion: () {},
                  onChapter: () {},
                  onNote: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(FilledButton).first).height,
        lessThanOrEqualTo(100),
      );
      for (final label in ['拍照 / 相册', '重点', '没听懂', '章节', '备注']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
}
