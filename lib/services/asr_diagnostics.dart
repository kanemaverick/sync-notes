import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'live_transcription_service.dart';
import 'local_asr_worker.dart';
import 'local_transcription_settings.dart';

/// Uses an official, bundled sample, never a user's microphone or network.
Future<String> checkOfflineRecognizer(LocalTranscriptionConfig config) async {
  final files = await prepareTranscriptionModel(config: config);
  final data = await rootBundle.load('test/fixtures/asr/0.wav');
  final wav = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final view = ByteData.sublistView(wav);
  Uint8List? pcm;
  for (var offset = 12; offset + 8 <= wav.length;) {
    final size = view.getUint32(offset + 4, Endian.little);
    if (offset + 8 + size > wav.length) throw const FormatException('测试音频损坏');
    if (String.fromCharCodes(wav.sublist(offset, offset + 4)) == 'data') {
      pcm = Uint8List.sublistView(wav, offset + 8, offset + 8 + size);
      break;
    }
    offset += 8 + size + (size % 2);
  }
  if (pcm == null) throw const FormatException('测试音频缺少 PCM');
  final ready = Completer<void>();
  final texts = <String>[];
  String? failure;
  final worker = LocalAsrWorker(
    onEvent: (event) {
      if (event['type'] == 'ready' && !ready.isCompleted) ready.complete();
      if (event['type'] == 'error') {
        failure = event['error'] as String?;
        if (!ready.isCompleted) ready.complete();
      }
      if (event['type'] == 'final') texts.add(event['text']! as String);
    },
  );
  try {
    await worker.start(files);
    await ready.future.timeout(const Duration(seconds: 10));
    if (failure != null) throw StateError(failure!);
    for (var offset = 0; offset < pcm.length; offset += 3200) {
      final end = (offset + 3200).clamp(0, pcm.length);
      worker.addPcm(
        Uint8List.sublistView(pcm, offset, end),
        startMs: offset * 1000 ~/ 32000,
        endMs: end * 1000 ~/ 32000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (failure != null) throw StateError(failure!);
    }
    // A small silence tail releases delayed decoder frames.
    final endMs = pcm.length * 1000 ~/ 32000;
    worker.addPcm(Uint8List(25600), startMs: endMs, endMs: endMs + 800);
    await worker.flush();
    if (failure != null) throw StateError(failure!);
    if (texts.isEmpty) throw StateError('模型没有返回文字');
    return texts.join(' ');
  } finally {
    worker.close();
  }
}
