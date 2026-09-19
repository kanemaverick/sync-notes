import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/local_transcription_settings.dart';

void main() {
  test('默认中英模型无需API密钥', () {
    expect(const LocalTranscriptionConfig().model, OfflineAsrModel.bilingual);
    expect(const LocalTranscriptionConfig().hotwords, isEmpty);
  });
  test('热词统一英文大小写、去重并支持中文分隔符', () {
    expect(normalizeHotwords('  GPT\ngpt,Transformer；神经网络， GPU  '), [
      'GPT',
      'TRANSFORMER',
      '神经网络',
      'GPU',
    ]);
  });
  test('剔除热词文件控制语法，限制长度和数量', () {
    expect(normalizeHotwords('GPU :10 #test'), ['GPU 10 TEST']);
    expect(normalizeHotwords('A' * 61), isEmpty);
    expect(
      normalizeHotwords(List.generate(100, (i) => 'TERM$i').join('\n')),
      hasLength(80),
    );
  });
}
