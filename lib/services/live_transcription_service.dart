import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'local_transcription_settings.dart';

const asrSampleRate = 16000;
const _modelAssetDirectory = 'assets/asr';

class TranscriptionModelFiles {
  const TranscriptionModelFiles({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    this.bpeVocab = '',
    this.hotwordsFile = '',
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String bpeVocab;
  final String hotwordsFile;
}

/// Copies the bundled ASR model to a normal file path that sherpa-onnx can
/// memory-map. Existing files are reused after their size has been verified.
Future<TranscriptionModelFiles> prepareTranscriptionModel({
  LocalTranscriptionConfig config = const LocalTranscriptionConfig(),
}) async {
  final support = await getApplicationSupportDirectory();
  final bilingual = config.model == OfflineAsrModel.bilingual;
  final assetDirectory = bilingual
      ? 'assets/asr_bilingual'
      : _modelAssetDirectory;
  final modelDirectory = Directory(
    p.join(support.path, 'asr_models', '${config.model.name}-v1'),
  );
  await modelDirectory.create(recursive: true);
  final manifest =
      jsonDecode(await rootBundle.loadString('$assetDirectory/manifest.json'))
          as Map<String, dynamic>;

  Future<String> copy(String name) async {
    final target = File(p.join(modelDirectory.path, name));
    final expected = manifest[name] as Map<String, dynamic>;
    if (!await target.exists() ||
        await target.length() != expected['bytes'] ||
        (await sha256.bind(target.openRead()).first).toString() !=
            expected['sha256']) {
      final data = await rootBundle.load('$assetDirectory/$name');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (sha256.convert(bytes).toString() != expected['sha256']) {
        throw const FormatException('离线模型校验失败，请重新安装完整安装包');
      }
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    }
    return target.path;
  }

  final hotwords = normalizeHotwords(config.hotwords.join('\n'));
  final hotwordsFile = File(p.join(modelDirectory.path, 'hotwords.txt'));
  await hotwordsFile.writeAsString(hotwords.join('\n'), flush: true);
  return TranscriptionModelFiles(
    encoder: await copy('encoder.int8.onnx'),
    decoder: await copy('decoder.onnx'),
    joiner: await copy('joiner.int8.onnx'),
    tokens: await copy('tokens.txt'),
    bpeVocab: bilingual ? await copy('bpe.vocab') : '',
    hotwordsFile: hotwords.isEmpty ? '' : hotwordsFile.path,
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
        modelingUnit: files.bpeVocab.isEmpty ? 'cjkchar' : 'cjkchar+bpe',
        bpeVocab: files.bpeVocab,
      ),
      enableEndpoint: true,
      decodingMethod: files.hotwordsFile.isEmpty && files.bpeVocab.isEmpty
          ? 'greedy_search'
          : 'modified_beam_search',
      hotwordsFile: files.hotwordsFile,
      hotwordsScore: 1.5,
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
