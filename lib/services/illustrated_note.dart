import 'package:path/path.dart' as p;

import '../models/entities.dart';

String photoAssetRelativePath(int zeroBasedIndex, String sourcePath) {
  final number = (zeroBasedIndex + 1).toString().padLeft(3, '0');
  final extension = p.extension(sourcePath).toLowerCase();
  return 'images/photo_$number${extension.isEmpty ? '.img' : extension}';
}

String audioAssetRelativePath(AudioSegment segment) {
  final extension = p.extension(segment.filePath).toLowerCase();
  final sequence = segment.sequence.toString().padLeft(4, '0');
  return 'audio/segment_$sequence${extension.isEmpty ? '.wav' : extension}';
}

String markdownEscapeAlt(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]');
