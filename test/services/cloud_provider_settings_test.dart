import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/cloud_transcription_settings.dart';

void main() {
  test('旧腾讯地址无需迁移，新阿里地址正确显示来源', () {
    expect(
      CloudAsrProvider.fromUrl('wss://test/v1/asr/tencent/realtime'),
      CloudAsrProvider.tencent,
    );
    expect(
      CloudAsrProvider.fromUrl('wss://test/v1/asr/aliyun/realtime?q=1'),
      CloudAsrProvider.aliyun,
    );
    expect(
      CloudAsrProvider.fromUrl('wss://test/custom'),
      CloudAsrProvider.custom,
    );
    expect(CloudAsrProvider.fromUrl(''), CloudAsrProvider.custom);
  });
  test('服务切换保留服务器端口及参数，不修改自定义地址', () {
    const url = 'wss://test:8443/v1/asr/tencent/realtime?route=one';
    expect(
      cloudProviderUrl(url, CloudAsrProvider.aliyun),
      'wss://test:8443/v1/asr/aliyun/realtime?route=one',
    );
    expect(cloudProviderUrl(url, CloudAsrProvider.custom), url);
    expect(cloudProviderUrl('', CloudAsrProvider.aliyun), '');
  });
}
