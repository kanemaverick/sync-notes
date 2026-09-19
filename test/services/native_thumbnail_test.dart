import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sync_notes/services/media_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sync_notes/thumbnail');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Android缩略图仅传递文件路径，不跨通道复制整张照片', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    await writePhotoThumbnail(
      '/private/original.jpg',
      '/private/thumb.jpg',
      useNative: true,
    );
    expect(received!.method, 'create');
    expect(received!.arguments, {
      'source': '/private/original.jpg',
      'destination': '/private/thumb.jpg',
    });
  });

  test('未注册原生通道时仍能生成缩略图，原图不变', () async {
    final root = await Directory.systemTemp.createTemp('thumbnail_fallback_');
    addTearDown(() => root.delete(recursive: true));
    final original = File('${root.path}/original.jpg');
    final destination = File('${root.path}/thumbnail.jpg');
    final bytes = image.encodeJpg(image.Image(width: 800, height: 400));
    await original.writeAsBytes(bytes);
    await writePhotoThumbnail(original.path, destination.path, useNative: true);
    expect(await original.readAsBytes(), bytes);
    expect(image.decodeJpg(await destination.readAsBytes())!.width, 480);
  });

  test('原生存储错误必须向上传递，不能误报照片已保存', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'thumbnail_failed', message: '磁盘已满');
    });
    await expectLater(
      writePhotoThumbnail('source', 'dest', useNative: true),
      throwsA(isA<PlatformException>()),
    );
  });
}
