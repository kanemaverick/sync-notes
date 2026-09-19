import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Only call while this session has no active audio writer. The disk, not a
/// possibly stale completion manifest, is authoritative after process death.
Future<Map<String, dynamic>> reconcileRecordingFiles({
  required Directory directory,
  required String sessionId,
  Future<int> Function(File)? legacyDuration,
}) async {
  final manifest = File(p.join(directory.path, 'recording_manifest.json'));
  var data = <String, dynamic>{};
  if (await manifest.exists()) {
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('清单不是对象');
      }
      data = decoded;
    } on FormatException {
      await manifest.copy(
        '${manifest.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
  }
  if (data['segments'] is! List) data['segments'] = [];
  final known = <String, Map>{
    for (final item in data['segments'] as List? ?? [])
      if (item is Map && item['filePath'] is String)
        item['filePath'] as String: item,
  };
  final audio = Directory(p.join(directory.path, 'audio'));
  await audio.create(recursive: true);
  final files = await audio
      .list()
      .where((f) => f is File && {'.wav', '.m4a'}.contains(p.extension(f.path)))
      .cast<File>()
      .toList();
  int? sequenceOf(File f) => int.tryParse(
    RegExp(
          r'^segment_(\d+)\.(wav|m4a)$',
        ).firstMatch(p.basename(f.path))?.group(1) ??
        '',
  );
  int? priorSequence(File f) => (known[f.path]?['sequence'] as num?)?.toInt();
  var next = 0;
  for (final file in files) {
    for (final sequence in [sequenceOf(file), priorSequence(file)]) {
      if (sequence != null && sequence >= next) next = sequence + 1;
    }
  }
  files.sort((a, b) {
    final order = (priorSequence(a) ?? sequenceOf(a) ?? next).compareTo(
      priorSequence(b) ?? sequenceOf(b) ?? next,
    );
    return order == 0 ? a.path.compareTo(b.path) : order;
  });
  final usedSequences = <int>{};
  var position = 0;
  final segments = <Map<String, dynamic>>[];
  for (final file in files) {
    var sequence = priorSequence(file) ?? sequenceOf(file);
    if (sequence == null || sequence < 0 || usedSequences.contains(sequence)) {
      sequence = next++;
    }
    usedSequences.add(sequence);
    // Recompute WAV duration even if a stale DB/manifest claims it is known.
    final wavDuration = await repairOwnedWav(file);
    final duration =
        wavDuration ??
        (known[file.path]?['durationMs'] as num?)?.toInt() ??
        (legacyDuration == null ? 0 : await legacyDuration(file));
    if (duration <= 0) {
      continue; // Keep the file and reserve its sequence anyway.
    }
    segments.add({
      'id': '$sessionId-segment-$sequence',
      'filePath': file.path,
      'timelineStartMs': position,
      'durationMs': duration,
      'sequence': sequence,
    });
    position += duration;
  }
  data['segments'] = segments;
  data['nextSequence'] = next;
  data.putIfAbsent('events', () => []);
  data.putIfAbsent('transcripts', () => []);
  final temp = File('${manifest.path}.tmp');
  await temp.writeAsString(jsonEncode(data), flush: true);
  await temp.rename(manifest.path);
  return data;
}

/// Repairs only the exact 44-byte PCM WAV layout produced by this application.
/// Payload bytes are never truncated or rewritten, including after a stale header.
Future<int?> repairOwnedWav(File file) async {
  if (p.extension(file.path) != '.wav' || await file.length() < 44) return null;
  final reader = await file.open();
  late Uint8List header;
  try {
    header = await reader.read(44);
  } finally {
    await reader.close();
  }
  String tag(int start) =>
      String.fromCharCodes(header.sublist(start, start + 4));
  final view = ByteData.sublistView(header);
  if (tag(0) != 'RIFF' ||
      tag(8) != 'WAVE' ||
      tag(12) != 'fmt ' ||
      tag(36) != 'data' ||
      view.getUint32(16, Endian.little) != 16 ||
      view.getUint16(20, Endian.little) != 1) {
    return null;
  }
  final bytesPerSecond = view.getUint32(28, Endian.little);
  final blockAlign = view.getUint16(32, Endian.little);
  if (bytesPerSecond == 0 || blockAlign == 0) return null;
  final payload = (await file.length() - 44) ~/ blockAlign * blockAlign;
  if (view.getUint32(40, Endian.little) != payload ||
      view.getUint32(4, Endian.little) != 36 + payload) {
    view.setUint32(4, 36 + payload, Endian.little);
    view.setUint32(40, payload, Endian.little);
    final writer = await file.open(mode: FileMode.append);
    try {
      await writer.setPosition(0);
      await writer.writeFrom(header);
      await writer.flush();
    } finally {
      await writer.close();
    }
  }
  return payload * 1000 ~/ bytesPerSecond;
}

/// Exclusive creation is the final safety net, even if a manifest is corrupt.
Future<({File file, int sequence})> reserveAudioFile(
  Directory audio,
  int sequence,
) async {
  while (true) {
    final file = File(
      p.join(audio.path, 'segment_${sequence.toString().padLeft(4, '0')}.wav'),
    );
    try {
      await file.create(exclusive: true);
      return (file: file, sequence: sequence);
    } on FileSystemException {
      if (!await file.exists()) rethrow;
      sequence++;
    }
  }
}
