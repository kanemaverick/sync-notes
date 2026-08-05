import 'dart:convert';

import 'package:sync_notes_tencent_asr_proxy/tencent_signing.dart';
import 'package:test/test.dart';

void main() {
  test('HMAC-SHA1 matches RFC 2202 test vector', () {
    final key = List<int>.filled(20, 0x0b);
    expect(
      hmacSha1Base64('Hi There', key),
      base64Encode([
        0xb6,
        0x17,
        0x31,
        0x86,
        0x55,
        0x05,
        0x72,
        0x64,
        0xe2,
        0x8b,
        0xc0,
        0xb6,
        0xfb,
        0x37,
        0x8c,
        0x8e,
        0xf1,
        0x46,
        0xbe,
        0x00,
      ]),
    );
  });

  test('Tencent query parameters are sorted and secrets stay server-side', () {
    final url = buildTencentAsrUrl(
      appId: '12345',
      secretId: 'secret-id',
      secretKey: 'do-not-expose',
      voiceId: 'session_1',
      timestamp: 1000,
      nonce: 42,
    );
    expect(url, startsWith('wss://asr.cloud.tencent.com/asr/v2/12345?'));
    expect(url, contains('engine_model_type=16k_zh_en_2.0'));
    expect(url, contains('signature='));
    expect(url, isNot(contains('do-not-expose')));
    expect(
      url.indexOf('convert_num_mode'),
      lessThan(url.indexOf('engine_model_type')),
    );
  });
}
