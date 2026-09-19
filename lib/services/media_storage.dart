import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/entities.dart';
import 'ai_processing_service.dart';
import 'illustrated_note.dart';

class StoredPhoto {
  const StoredPhoto({required this.path, required this.thumbnailPath});
  final String path;
  final String thumbnailPath;
}

class MediaStorage {
  MediaStorage({this.rootDirectory});

  final Directory? rootDirectory;

  Future<Directory> sessionDirectory(String sessionId) async {
    final support = rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'sessions', sessionId));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> audioDirectory(String sessionId) async {
    final root = await sessionDirectory(sessionId);
    final directory = Directory(p.join(root.path, 'audio'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<StoredPhoto> storePhoto({
    required String sessionId,
    required String sourcePath,
  }) async {
    final root = await sessionDirectory(sessionId);
    final photos = Directory(p.join(root.path, 'photos'));
    final thumbnails = Directory(p.join(root.path, 'thumbnails'));
    await photos.create(recursive: true);
    await thumbnails.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final sourceBytes = await File(sourcePath).readAsBytes();
    final originalExtension = detectPhotoFileExtension(
      sourceBytes,
      sourcePath: sourcePath,
    );
    final originalPath = p.join(photos.path, 'photo_$stamp$originalExtension');
    final thumbnailPath = p.join(thumbnails.path, 'photo_$stamp.jpg');
    await File(originalPath).writeAsBytes(sourceBytes, flush: true);

    await writePhotoThumbnail(originalPath, thumbnailPath);
    return StoredPhoto(path: originalPath, thumbnailPath: thumbnailPath);
  }

  Future<void> writePendingGalleryImport({
    required String sessionId,
    required int offsetMs,
    DateTime? deviceTime,
  }) async {
    final root = await sessionDirectory(sessionId);
    final file = File(p.join(root.path, 'pending_gallery_import.json'));
    await file.writeAsString(
      jsonEncode({
        'offsetMs': offsetMs,
        'deviceTimeMs': (deviceTime ?? DateTime.now()).millisecondsSinceEpoch,
      }),
      flush: true,
    );
  }

  Future<int?> readPendingGalleryImportOffset(String sessionId) async {
    final root = await sessionDirectory(sessionId);
    final file = File(p.join(root.path, 'pending_gallery_import.json'));
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return data['offsetMs'] as int?;
  }

  Future<DateTime?> readPendingGalleryImportDeviceTime(String sessionId) async {
    final root = await sessionDirectory(sessionId);
    final file = File(p.join(root.path, 'pending_gallery_import.json'));
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final milliseconds = data['deviceTimeMs'] as int?;
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  Future<void> clearPendingGalleryImport(String sessionId) async {
    final root = await sessionDirectory(sessionId);
    final file = File(p.join(root.path, 'pending_gallery_import.json'));
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteEventMedia(TimelineEvent event) async {
    for (final path in [event.photoPath, event.thumbnailPath]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> deleteSessionMedia(String sessionId) async {
    final support = rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'sessions', sessionId));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<File> writeMarkdown({
    required String sessionId,
    required String markdown,
  }) async {
    final root = await sessionDirectory(sessionId);
    final file = File(p.join(root.path, 'ai_note.md'));
    await file.writeAsString(markdown, flush: true);
    return file;
  }

  Future<String?> readMarkdown(String sessionId) async {
    final root = await sessionDirectory(sessionId);
    final file = File(p.join(root.path, 'ai_note.md'));
    return await file.exists() ? file.readAsString() : null;
  }

  Future<File> exportIllustratedZip({
    required Session session,
    required String markdown,
    required List<TimelineEvent> events,
    List<AudioSegment> audioSegments = const [],
    List<TranscriptSegment> transcriptSegments = const [],
  }) async {
    final root = await sessionDirectory(session.id);
    final exports = Directory(p.join(root.path, 'exports'));
    await exports.create(recursive: true);
    final safeTitle = session.title
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final zipFile = File(
      p.join(
        exports.path,
        '${safeTitle.isEmpty ? '同步讲记' : safeTitle}_Codex整理包.zip',
      ),
    );
    final noteFile = await writeMarkdown(
      sessionId: session.id,
      markdown: markdown,
    );
    final photos =
        events
            .where(
              (event) =>
                  event.type == TimelineEventType.photo &&
                  event.photoPath != null,
            )
            .toList()
          ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
    final sortedEvents = [...events]
      ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
    final sortedAudioSegments = [...audioSegments]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final audioFiles = <String, String>{};
    for (final segment in sortedAudioSegments) {
      if (await File(segment.filePath).exists()) {
        audioFiles[segment.id] = audioAssetRelativePath(segment);
      }
    }
    final photoFiles = <String, String>{
      for (var index = 0; index < photos.length; index++)
        photos[index].id: photoAssetRelativePath(
          index,
          photos[index].photoPath!,
        ),
    };
    final promptFile = File(p.join(root.path, 'codex_prompt.md'));
    await promptFile.writeAsString(
      buildCodexAnalysisPrompt(session),
      flush: true,
    );
    final manifestFile = File(p.join(root.path, 'export_manifest.json'));
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 3,
        'session': {
          'id': session.id,
          'title': session.title,
          'sceneType': session.sceneType.name,
          'sceneTypeLabel': session.sceneType.label,
          'activityName': session.activityName,
          'location': session.location,
          'speaker': session.speaker,
          'note': session.note,
          'tags': session.tags,
          'createdAt': session.createdAt.toIso8601String(),
          'recordingStartedAt': session.recordingStartedAt?.toIso8601String(),
          'durationMs': session.durationMs,
        },
        'audioSegments': [
          for (final segment in sortedAudioSegments)
            {
              'id': segment.id,
              'sequence': segment.sequence,
              'timelineStartMs': segment.timelineStartMs,
              'durationMs': segment.durationMs,
              'fileName': p.basename(segment.filePath),
              'file': audioFiles[segment.id],
              'included': audioFiles.containsKey(segment.id),
            },
        ],
        'transcriptSegments': [
          for (final transcript in transcriptSegments)
            {
              'id': transcript.id,
              'startMs': transcript.startMs,
              'endMs': transcript.endMs,
              'text': transcript.text,
              'source': transcript.speakerLabel,
            },
        ],
        'events': [
          for (final event in sortedEvents)
            {
              'type': event.type.name,
              'typeLabel': event.type.label,
              'offsetMs': event.offsetMs,
              'timelineMs': event.offsetMs,
              'createdAt': event.createdAt.toIso8601String(),
              'deviceTime': event.createdAt.toIso8601String(),
              'title': event.title,
              'note': event.note,
              'photoSource': event.photoSource,
              'file': ?photoFiles[event.id],
            },
        ],
        'photos': [
          for (var index = 0; index < photos.length; index++)
            {
              'offsetMs': photos[index].offsetMs,
              'createdAt': photos[index].createdAt.toIso8601String(),
              'deviceTime': photos[index].createdAt.toIso8601String(),
              'note': photos[index].note,
              'source': photos[index].photoSource,
              'file': photoAssetRelativePath(index, photos[index].photoPath!),
            },
        ],
        'exportMetadata': {
          'generatedAt': DateTime.now().toIso8601String(),
          'format': 'sync-notes-codex-package',
          'includesOriginalAudio': audioFiles.isNotEmpty,
          'audioComplete': audioFiles.length == sortedAudioSegments.length,
        },
      }),
      flush: true,
    );

    final encoder = ZipFileEncoder()..create(zipFile.path);
    try {
      await encoder.addFile(promptFile, 'CODEX_PROMPT.md');
      await encoder.addFile(noteFile, 'note.md');
      await encoder.addFile(manifestFile, 'manifest.json');
      for (final segment in sortedAudioSegments) {
        final relativePath = audioFiles[segment.id];
        if (relativePath == null) continue;
        await encoder.addFile(File(segment.filePath), relativePath);
      }
      for (var index = 0; index < photos.length; index++) {
        final source = File(photos[index].photoPath!);
        if (await source.exists()) {
          await encoder.addFile(
            source,
            photoAssetRelativePath(index, source.path),
          );
        }
      }
    } finally {
      await encoder.close();
    }
    return zipFile;
  }
}

/// Android decodes a subsampled bitmap on a native worker thread. The portable
/// fallback keeps CPU-heavy full-image decoding off Flutter's UI isolate.
Future<void> writePhotoThumbnail(
  String source,
  String destination, {
  bool? useNative,
}) async {
  if (useNative ?? Platform.isAndroid) {
    try {
      await const MethodChannel('sync_notes/thumbnail').invokeMethod<void>(
        'create',
        {'source': source, 'destination': destination},
      );
      return;
    } on MissingPluginException {
      // Non-Android embeddings can continue using the portable implementation.
    }
  }
  await Isolate.run(() => createPhotoThumbnail(source, destination));
}

/// Full-resolution decoding must not freeze the live controls or camera UI.
Future<void> createPhotoThumbnail(
  String originalPath,
  String thumbnailPath,
) async {
  final bytes = await File(originalPath).readAsBytes();
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法读取照片');
  final oriented = image_lib.bakeOrientation(decoded);
  final thumbnail = image_lib.copyResize(oriented, width: 480);
  await File(
    thumbnailPath,
  ).writeAsBytes(image_lib.encodeJpg(thumbnail, quality: 78), flush: true);
}

/// Returns an extension that matches the encoded photo bytes.
///
/// Photo Picker paths are temporary and their suffix is not guaranteed to
/// describe the selected media, so byte signatures take precedence. The
/// source suffix is used only for formats whose signature is less specific.
String detectPhotoFileExtension(List<int> bytes, {String? sourcePath}) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  if (startsWith(const [0xff, 0xd8, 0xff])) return '.jpg';
  if (startsWith(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return '.png';
  }
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return '.gif';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return '.webp';
  }
  if (startsWith(const [0x42, 0x4d])) return '.bmp';
  if (startsWith(const [0x49, 0x49, 0x2a, 0x00]) ||
      startsWith(const [0x4d, 0x4d, 0x00, 0x2a])) {
    return '.tiff';
  }

  if (startsWith(const [0x66, 0x74, 0x79, 0x70], 4) && bytes.length >= 12) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand == 'avif' || brand == 'avis') return '.avif';
    if ({'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'}.contains(brand)) {
      return '.heic';
    }
  }

  final suffix = sourcePath == null
      ? ''
      : p.extension(sourcePath).toLowerCase();
  return switch (suffix) {
    '.jpeg' => '.jpg',
    '.jpg' ||
    '.png' ||
    '.gif' ||
    '.webp' ||
    '.bmp' ||
    '.tiff' ||
    '.heic' ||
    '.avif' => suffix,
    '.tif' => '.tiff',
    '.heif' => '.heic',
    _ => '.img',
  };
}
