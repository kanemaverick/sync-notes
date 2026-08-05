import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/background_recording_service.dart';
import 'package:sync_notes/services/live_transcription_service.dart';

void main() {
  test('PCM16 样本正确转为浮点波形', () {
    final bytes = Uint8List.fromList([0x00, 0x80, 0x00, 0x00, 0xff, 0x7f]);
    final samples = pcm16BytesToFloat32(bytes);
    expect(samples, hasLength(3));
    expect(samples[0], -1.0);
    expect(samples[1], 0.0);
    expect(samples[2], closeTo(0.99997, 0.00001));
  });

  test('WAV 头包含16kHz单声道和已落盘数据长度', () {
    final header = createWavHeader(dataLength: 32000);
    final view = ByteData.sublistView(header);
    expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
    expect(view.getUint16(22, Endian.little), 1);
    expect(view.getUint32(24, Endian.little), asrSampleRate);
    expect(view.getUint16(34, Endian.little), 16);
    expect(view.getUint32(40, Endian.little), 32000);
    expect(view.getUint32(4, Endian.little), 32036);
  });
}
