enum SceneType { classroom, lecture, fieldVisit, meeting, interview, custom }

extension SceneTypeLabel on SceneType {
  String get label => switch (this) {
    SceneType.classroom => '课堂',
    SceneType.lecture => '讲座',
    SceneType.fieldVisit => '实地参观',
    SceneType.meeting => '会议',
    SceneType.interview => '访谈',
    SceneType.custom => '其他',
  };

  String get defaultTitlePrefix => switch (this) {
    SceneType.classroom => '课堂',
    SceneType.lecture => '讲座',
    SceneType.fieldVisit => '参观',
    SceneType.meeting => '会议',
    SceneType.interview => '访谈',
    SceneType.custom => '记录',
  };
}

enum SessionStatus { draft, recording, paused, completed, interrupted, failed }

enum AiStatus { notStarted, processing, completed, failed }

enum TimelineEventType {
  photo,
  highlight,
  question,
  chapter,
  text,
  interruption,
}

extension TimelineEventTypeLabel on TimelineEventType {
  String get label => switch (this) {
    TimelineEventType.photo => '照片',
    TimelineEventType.highlight => '重点',
    TimelineEventType.question => '没听懂',
    TimelineEventType.chapter => '章节',
    TimelineEventType.text => '备注',
    TimelineEventType.interruption => '录音状态',
  };
}

class Session {
  const Session({
    required this.id,
    required this.title,
    required this.sceneType,
    required this.createdAt,
    required this.durationMs,
    required this.status,
    required this.aiStatus,
    this.location,
    this.speaker,
    this.note,
    this.activityName,
    this.tags = const [],
    this.exportedAt,
    this.exportPath,
    this.exportSizeBytes,
    this.recordingStartedAt,
  });

  final String id;
  final String title;
  final SceneType sceneType;
  final String? location;
  final String? speaker;
  final String? note;
  final String? activityName;
  final List<String> tags;
  final DateTime? exportedAt;
  final String? exportPath;
  final int? exportSizeBytes;
  final DateTime createdAt;
  final DateTime? recordingStartedAt;
  final int durationMs;
  final SessionStatus status;
  final AiStatus aiStatus;

  Session copyWith({
    String? title,
    SceneType? sceneType,
    String? location,
    String? speaker,
    String? note,
    String? activityName,
    List<String>? tags,
    DateTime? exportedAt,
    String? exportPath,
    int? exportSizeBytes,
    DateTime? recordingStartedAt,
    int? durationMs,
    SessionStatus? status,
    AiStatus? aiStatus,
  }) => Session(
    id: id,
    title: title ?? this.title,
    sceneType: sceneType ?? this.sceneType,
    location: location ?? this.location,
    speaker: speaker ?? this.speaker,
    note: note ?? this.note,
    activityName: activityName ?? this.activityName,
    tags: tags ?? this.tags,
    exportedAt: exportedAt ?? this.exportedAt,
    exportPath: exportPath ?? this.exportPath,
    exportSizeBytes: exportSizeBytes ?? this.exportSizeBytes,
    createdAt: createdAt,
    recordingStartedAt: recordingStartedAt ?? this.recordingStartedAt,
    durationMs: durationMs ?? this.durationMs,
    status: status ?? this.status,
    aiStatus: aiStatus ?? this.aiStatus,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'scene_type': sceneType.name,
    'location': location,
    'speaker': speaker,
    'note': note,
    'activity_name': activityName,
    'tags': tags.join(','),
    'exported_at': exportedAt?.millisecondsSinceEpoch,
    'export_path': exportPath,
    'export_size_bytes': exportSizeBytes,
    'created_at': createdAt.millisecondsSinceEpoch,
    'recording_started_at': recordingStartedAt?.millisecondsSinceEpoch,
    'duration_ms': durationMs,
    'status': status.name,
    'ai_status': aiStatus.name,
  };

  factory Session.fromMap(Map<String, Object?> map) => Session(
    id: map['id']! as String,
    title: map['title']! as String,
    sceneType: SceneType.values.byName(map['scene_type']! as String),
    location: map['location'] as String?,
    speaker: map['speaker'] as String?,
    note: map['note'] as String?,
    activityName: map['activity_name'] as String?,
    tags: ((map['tags'] as String?) ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(),
    exportedAt: map['exported_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['exported_at']! as int),
    exportPath: map['export_path'] as String?,
    exportSizeBytes: map['export_size_bytes'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    recordingStartedAt: map['recording_started_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            map['recording_started_at']! as int,
          ),
    durationMs: map['duration_ms']! as int,
    status: SessionStatus.values.byName(map['status']! as String),
    aiStatus: AiStatus.values.byName(map['ai_status']! as String),
  );
}

class SessionSummary {
  const SessionSummary({
    required this.session,
    required this.photoCount,
    this.eventCount = 0,
    this.transcriptCount = 0,
    this.coverPath,
    this.hasOfflineTranscript = false,
    this.hasCloudTranscript = false,
  });
  final Session session;
  final int photoCount;
  final int eventCount;
  final int transcriptCount;
  final String? coverPath;
  final bool hasOfflineTranscript;
  final bool hasCloudTranscript;
}

class AudioSegment {
  const AudioSegment({
    required this.id,
    required this.sessionId,
    required this.filePath,
    required this.timelineStartMs,
    required this.durationMs,
    required this.sequence,
  });
  final String id;
  final String sessionId;
  final String filePath;
  final int timelineStartMs;
  final int durationMs;
  final int sequence;

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'file_path': filePath,
    'timeline_start_ms': timelineStartMs,
    'duration_ms': durationMs,
    'sequence': sequence,
  };

  factory AudioSegment.fromMap(Map<String, Object?> map) => AudioSegment(
    id: map['id']! as String,
    sessionId: map['session_id']! as String,
    filePath: map['file_path']! as String,
    timelineStartMs: map['timeline_start_ms']! as int,
    durationMs: map['duration_ms']! as int,
    sequence: map['sequence']! as int,
  );
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.offsetMs,
    required this.createdAt,
    this.title,
    this.note,
    this.photoPath,
    this.thumbnailPath,
    this.photoSource,
  });
  final String id;
  final String sessionId;
  final TimelineEventType type;
  final int offsetMs;
  final String? title;
  final String? note;
  final String? photoPath;
  final String? thumbnailPath;
  final String? photoSource;
  final DateTime createdAt;

  TimelineEvent copyWith({
    String? title,
    String? note,
    int? offsetMs,
    String? photoSource,
  }) => TimelineEvent(
    id: id,
    sessionId: sessionId,
    type: type,
    offsetMs: offsetMs ?? this.offsetMs,
    title: title ?? this.title,
    note: note ?? this.note,
    photoPath: photoPath,
    thumbnailPath: thumbnailPath,
    photoSource: photoSource ?? this.photoSource,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'type': type.name,
    'offset_ms': offsetMs,
    'title': title,
    'note': note,
    'photo_path': photoPath,
    'thumbnail_path': thumbnailPath,
    'photo_source': photoSource,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory TimelineEvent.fromMap(Map<String, Object?> map) => TimelineEvent(
    id: map['id']! as String,
    sessionId: map['session_id']! as String,
    type: TimelineEventType.values.byName(map['type']! as String),
    offsetMs: map['offset_ms']! as int,
    title: map['title'] as String?,
    note: map['note'] as String?,
    photoPath: map['photo_path'] as String?,
    thumbnailPath: map['thumbnail_path'] as String?,
    photoSource: map['photo_source'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
  );
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.sessionId,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.speakerLabel,
  });
  final String id;
  final String sessionId;
  final int startMs;
  final int endMs;
  final String text;
  final String? speakerLabel;

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'start_ms': startMs,
    'end_ms': endMs,
    'text': text,
    'speaker_label': speakerLabel,
  };

  factory TranscriptSegment.fromMap(Map<String, Object?> map) =>
      TranscriptSegment(
        id: map['id']! as String,
        sessionId: map['session_id']! as String,
        startMs: map['start_ms']! as int,
        endMs: map['end_ms']! as int,
        text: map['text']! as String,
        speakerLabel: map['speaker_label'] as String?,
      );
}

class SessionSearchResult {
  const SessionSearchResult({
    required this.session,
    required this.contextText,
    this.offsetMs,
    this.kind = '记录',
  });

  final Session session;
  final String contextText;
  final int? offsetMs;
  final String kind;
}
