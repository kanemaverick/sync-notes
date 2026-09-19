import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sync_notes/models/entities.dart';
import 'package:sync_notes/services/media_storage.dart';

void main() {
  test('照片原件字节不变，独立线程生成缩略图', () async {
    final root = await Directory.systemTemp.createTemp('sync_notes_photo_');
    addTearDown(() => root.delete(recursive: true));
    final bytes = img.encodeJpg(img.Image(width: 800, height: 400));
    final source = File('${root.path}/source.jpg');
    await source.writeAsBytes(bytes);
    final stored = await MediaStorage(
      rootDirectory: root,
    ).storePhoto(sessionId: 's', sourcePath: source.path);
    expect(await File(stored.path).readAsBytes(), bytes);
    final thumbnail = img.decodeJpg(
      await File(stored.thumbnailPath).readAsBytes(),
    )!;
    expect(thumbnail.width, 480);
    expect(thumbnail.height, 240);
  });
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

  test('Codex ZIP包含提示词、笔记、结构化manifest和原始照片', () async {
    final root = await Directory.systemTemp.createTemp('sync_notes_export_');
    final photo = File('${root.path}/source.jpg');
    await photo.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
    final audio = File('${root.path}/segment_source.wav');
    await audio.writeAsBytes(List<int>.filled(64, 7));
    final session = Session(
      id: 'export-session',
      title: '现场记录',
      sceneType: SceneType.fieldVisit,
      activityName: '水文仪器参观',
      tags: const ['实习', '仪器'],
      createdAt: DateTime(2026, 8, 6),
      durationMs: 120000,
      status: SessionStatus.completed,
      aiStatus: AiStatus.completed,
    );
    final event = TimelineEvent(
      id: 'photo-1',
      sessionId: session.id,
      type: TimelineEventType.photo,
      offsetMs: 65000,
      title: '设备正面',
      photoPath: photo.path,
      photoSource: 'gallery',
      createdAt: DateTime(2026, 8, 6),
    );
    final storage = MediaStorage(rootDirectory: root);
    final zip = await storage.exportIllustratedZip(
      session: session,
      markdown: '# 现场记录\n\n## 01:05\n\n![设备](images/photo_001.jpg)',
      events: [event],
      audioSegments: [
        AudioSegment(
          id: 'audio-1',
          sessionId: 'export-session',
          filePath: audio.path,
          timelineStartMs: 0,
          durationMs: 120000,
          sequence: 0,
        ),
      ],
      transcriptSegments: const [
        TranscriptSegment(
          id: 'text-1',
          sessionId: 'export-session',
          startMs: 60000,
          endMs: 70000,
          text: '这是流速测量设备',
          speakerLabel: '本地初稿',
        ),
      ],
    );
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final names = archive.files.map((file) => file.name).toSet();
    expect(
      names,
      containsAll([
        'CODEX_PROMPT.md',
        'note.md',
        'manifest.json',
        'images/photo_001.jpg',
        'audio/segment_0000.wav',
      ]),
    );
    final manifestFile = archive.files.singleWhere(
      (file) => file.name == 'manifest.json',
    );
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>;
    expect(manifest['schemaVersion'], 3);
    expect((manifest['audioSegments'] as List), hasLength(1));
    expect(
      (manifest['audioSegments'] as List).single['file'],
      'audio/segment_0000.wav',
    );
    expect(manifest['exportMetadata']['includesOriginalAudio'], isTrue);
    final audioEntry = archive.files.singleWhere(
      (file) => file.name == 'audio/segment_0000.wav',
    );
    expect(audioEntry.content, List<int>.filled(64, 7));
    expect((manifest['transcriptSegments'] as List).single['text'], '这是流速测量设备');
    expect((manifest['photos'] as List).single['source'], 'gallery');
    expect(
      (manifest['events'] as List).single['deviceTime'],
      '2026-08-06T00:00:00.000',
    );
    await root.delete(recursive: true);
  });
}
