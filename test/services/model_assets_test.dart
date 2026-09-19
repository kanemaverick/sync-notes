import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final directory in ['assets/asr', 'assets/asr_bilingual']) {
    test('$directory 模型文件齐全且SHA256与发布清单相符', () async {
      final manifest =
          jsonDecode(await File('$directory/manifest.json').readAsString())
              as Map<String, dynamic>;
      expect(
        manifest.keys,
        containsAll([
          'encoder.int8.onnx',
          'decoder.onnx',
          'joiner.int8.onnx',
          'tokens.txt',
        ]),
      );
      for (final entry in manifest.entries) {
        final file = File('$directory/${entry.key}');
        expect(await file.length(), entry.value['bytes']);
        expect(
          (await sha256.bind(file.openRead()).first).toString(),
          entry.value['sha256'],
        );
      }
    });
  }
}
