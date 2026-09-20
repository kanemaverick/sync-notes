import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sync_notes/services/gallery_photo_picker.dart';

class FakeImagePicker extends ImagePicker {
  List<XFile> files = [];
  bool? metadataRequested;
  LostDataResponse lost = LostDataResponse.empty();

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    metadataRequested = requestFullMetadata;
    return files;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => lost;
}

void main() {
  test(
    'multi-selection returns every path in order without metadata permission',
    () async {
      final native = FakeImagePicker()
        ..files = [XFile('/a.jpg'), XFile('/b.jpg'), XFile('/c.jpg')];
      final picker = ImagePickerGalleryPhotoPicker(picker: native);
      expect(await picker.pickImages(), ['/a.jpg', '/b.jpg', '/c.jpg']);
      expect(native.metadataRequested, isFalse);
    },
  );

  test('cancelled selection is empty', () async {
    final picker = ImagePickerGalleryPhotoPicker(picker: FakeImagePicker());
    expect(await picker.pickImages(), isEmpty);
  });

  test('recovery returns all photos, not only the first', () async {
    final native = FakeImagePicker()
      ..lost = LostDataResponse(
        files: [XFile('/a.jpg'), XFile('/b.jpg')],
        type: RetrieveType.image,
      );
    expect(
      await ImagePickerGalleryPhotoPicker(picker: native).retrieveLostImages(),
      ['/a.jpg', '/b.jpg'],
    );
  });

  test('recovery errors propagate to the UI', () async {
    final native = FakeImagePicker()
      ..lost = LostDataResponse(
        exception: PlatformException(code: 'unavailable'),
      );
    await expectLater(
      ImagePickerGalleryPhotoPicker(picker: native).retrieveLostImages(),
      throwsA(isA<PlatformException>()),
    );
  });
}
