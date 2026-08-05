import 'package:path/path.dart' as p;

String photoAssetRelativePath(int zeroBasedIndex, String sourcePath) {
  final number = (zeroBasedIndex + 1).toString().padLeft(3, '0');
  final extension = p.extension(sourcePath).toLowerCase();
  return 'images/photo_$number${extension.isEmpty ? '.img' : extension}';
}

String markdownEscapeAlt(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]');
