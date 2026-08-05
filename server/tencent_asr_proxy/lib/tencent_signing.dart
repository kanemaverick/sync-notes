import 'dart:convert';

import 'package:crypto/crypto.dart';

const tencentAsrHost = 'asr.cloud.tencent.com';

String hmacSha1Base64(String value, List<int> key) =>
    base64Encode(Hmac(sha1, key).convert(utf8.encode(value)).bytes);

String sortedQuery(Map<String, String> parameters) {
  final keys = parameters.keys.toList()..sort();
  return keys
      .map(
        (key) =>
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(parameters[key]!)}',
      )
      .join('&');
}

String buildTencentAsrUrl({
  required String appId,
  required String secretId,
  required String secretKey,
  required String voiceId,
  required int timestamp,
  required int nonce,
}) {
  final path = '/asr/v2/$appId';
  final parameters = <String, String>{
    'convert_num_mode': '3',
    'engine_model_type': '16k_zh_en_2.0',
    'expired': '${timestamp + 3600}',
    'filter_dirty': '0',
    'filter_modal': '0',
    'filter_punc': '0',
    'needvad': '1',
    'nonce': '$nonce',
    'secretid': secretId,
    'sentence_strategy': '0',
    'timestamp': '$timestamp',
    'voice_format': '1',
    'voice_id': voiceId,
  };
  final query = sortedQuery(parameters);
  final source = '$tencentAsrHost$path?$query';
  final signature = hmacSha1Base64(source, utf8.encode(secretKey));
  return 'wss://$source&signature=${Uri.encodeQueryComponent(signature)}';
}
