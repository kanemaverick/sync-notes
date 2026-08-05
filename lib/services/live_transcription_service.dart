import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const asrSampleRate = 16000;
const _modelAssetDirectory = 'assets/asr';

class TranscriptionModelFiles {
  const TranscriptionModelFiles({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
}

/// Copies the bundled ASR model to a normal file path that sherpa-onnx can
/// memory-map. Existing files are reused after their size has been verified.
Future<TranscriptionModelFiles> prepareTranscriptionModel() async {
  final support = await getApplicationSupportDirectory();
  final modelDirectory = Directory(p.join(support.path, 'asr_model'));
  await modelDirectory.create(recursive: true);

  Future<String> copy(String name) async {
    final data = await rootBundle.load('$_modelAssetDirectory/$name');
    final target = File(p.join(modelDirectory.path, name));
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await target.writeAsBytes(bytes, flush: true);
    }
    return target.path;
  }

  return TranscriptionModelFiles(
    encoder: await copy('encoder.int8.onnx'),
    decoder: await copy('decoder.onnx'),
    joiner: await copy('joiner.int8.onnx'),
    tokens: await copy('tokens.txt'),
  );
}

sherpa.OnlineRecognizer createOnlineRecognizer(TranscriptionModelFiles files) {
  sherpa.initBindings();
  return sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: files.encoder,
          decoder: files.decoder,
          joiner: files.joiner,
        ),
        tokens: files.tokens,
        modelType: 'zipformer',
        numThreads: 2,
      ),
      enableEndpoint: true,
      decodingMethod: 'greedy_search',
    ),
  );
}

Float32List pcm16BytesToFloat32(Uint8List bytes) {
  final sampleCount = bytes.length ~/ 2;
  final samples = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes, 0, sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    samples[index] = view.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return samples;
}
