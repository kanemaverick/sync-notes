import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/services/transcript_documents.dart';

TranscriptSegment row(
  String id,
  int start,
  int end,
  String text, {
  String source = '本地初稿',
}) => TranscriptSegment(
  id: id,
  sessionId: 's',
  startMs: start,
  endMs: end,
  text: text,
  speakerLabel: source,
);

void main() {
  test(
    'grouping sorts without modifying source, retains even repeated words',
    () {
      final input = [row('b', 2000, 3000, '模型'), row('a', 0, 1000, '模型')];
      final groups = transcriptParagraphs(input);
      expect(groups.single.text, '模型 模型');
      expect(input.first.id, 'b');
      expect(
        buildTranscriptSrt(input),
        contains('00:00:00,000 --> 00:00:01,000'),
      );
      expect(buildTranscriptSrt(input), contains('2\n00:00:02,000'));
    },
  );
  test(
    'long gaps, source changes and thirty-second windows break paragraphs',
    () {
      expect(
        transcriptParagraphs([
          row('a', 0, 1000, '甲'),
          row('b', 9000, 10000, '乙'),
        ]),
        hasLength(2),
      );
      expect(
        transcriptParagraphs([
          row('a', 0, 1000, '甲'),
          row('b', 1000, 2000, '乙', source: '腾讯云'),
        ]),
        hasLength(2),
      );
      expect(
        transcriptParagraphs([
          row('a', 0, 29000, '甲'),
          row('b', 29000, 31000, '乙'),
        ]),
        hasLength(2),
      );
    },
  );
  test(
    'quality report distinguishes local-only, empty and mixed transcripts',
    () {
      expect(buildTranscriptQualityReport([]), contains('未保存转写'));
      expect(
        buildTranscriptQualityReport([row('a', 0, 1, '啊')]),
        contains('全部为本地识别'),
      );
      expect(
        buildTranscriptQualityReport([row('a', 0, 1, '你好', source: '腾讯云')]),
        isNot(contains('全部为本地识别')),
      );
    },
  );
}
