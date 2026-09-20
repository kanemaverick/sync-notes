import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/widgets/live_transcript_panel.dart';

void main() {
  testWidgets(
    'expand history, replace revised sentence and keep partial separate',
    (tester) async {
      Widget view(String first) => MaterialApp(
        home: Scaffold(
          body: LiveTranscriptPanel(
            transcripts: [
              TranscriptSegment(
                id: '1',
                sessionId: 's',
                startMs: 0,
                endMs: 1000,
                text: first,
                speakerLabel: '腾讯云',
              ),
              const TranscriptSegment(
                id: '2',
                sessionId: 's',
                startMs: 1000,
                endMs: 2000,
                text: '第二句',
              ),
            ],
            partialText: '正在说的第三句',
            status: '云端识别',
          ),
        ),
      );
      await tester.pumpWidget(view('旧词'));
      await tester.tap(find.text('展开全文（2段）'));
      await tester.pump();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('旧词'),
      );
      await tester.pumpWidget(view('修正后的词'));
      await tester.pump();
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(text, contains('修正后的词'));
      expect(text, isNot(contains('旧词')));
      expect(text, contains('[正在识别，可修订]'));
      await tester.tap(find.text('收起全文'));
      await tester.pump();
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
