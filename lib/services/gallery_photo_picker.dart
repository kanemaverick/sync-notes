import 'package:image_picker/image_picker.dart';

abstract interface class GalleryPhotoPicker {
  Future<List<String>> pickImages();

  Future<List<String>> retrieveLostImages();
}

class ImagePickerGalleryPhotoPicker implements GalleryPhotoPicker {
  ImagePickerGalleryPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<String>> pickImages() async {
    final files = await _picker.pickMultiImage(requestFullMetadata: false);
    return files.map((file) => file.path).toList();
  }

  @override
  Future<List<String>> retrieveLostImages() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    return response.files?.map((file) => file.path).toList() ?? const [];
  }
}
