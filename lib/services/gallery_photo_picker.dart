import 'package:image_picker/image_picker.dart';

abstract interface class GalleryPhotoPicker {
  Future<String?> pickImage();

  Future<List<String>> retrieveLostImages();
}

class ImagePickerGalleryPhotoPicker implements GalleryPhotoPicker {
  ImagePickerGalleryPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file?.path;
  }

  @override
  Future<List<String>> retrieveLostImages() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    return response.files?.map((file) => file.path).toList() ?? const [];
  }
}
