import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/services/media_storage.dart';

void main() {
  group('detectPhotoFileExtension', () {
    test('uses encoded PNG signature instead of a misleading path suffix', () {
      expect(
        detectPhotoFileExtension(const [
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ], sourcePath: '/tmp/temporary.jpg'),
        '.png',
      );
    });

    test('recognizes JPEG and WebP signatures', () {
      expect(detectPhotoFileExtension(const [0xff, 0xd8, 0xff, 0xe0]), '.jpg');
      expect(
        detectPhotoFileExtension(const [
          0x52,
          0x49,
          0x46,
          0x46,
          0,
          0,
          0,
          0,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
        '.webp',
      );
    });

    test('normalizes supported source suffixes as a fallback', () {
      expect(
        detectPhotoFileExtension(const [1, 2, 3], sourcePath: '/tmp/a.jpeg'),
        '.jpg',
      );
      expect(
        detectPhotoFileExtension(const [1, 2, 3], sourcePath: '/tmp/a.heif'),
        '.heic',
      );
    });
  });
}
