import 'dart:convert';
import 'package:flutter/services.dart';

class DocumentScan {
  DocumentScan.fromJson(String value)
    : data = jsonDecode(value) as Map<String, dynamic>;
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get path => data['path'] as String;
  int get offsetMs => data['offsetMs'] as int;
  DateTime get startedAt =>
      DateTime.fromMillisecondsSinceEpoch(data['deviceTimeMs'] as int);
  DateTime get completedAt =>
      DateTime.fromMillisecondsSinceEpoch(data['completedAtMs'] as int);
}

class DocumentScanner {
  static const _channel = MethodChannel('sync_notes/document_scanner');

  Future<DocumentScan?> scan({
    required String sessionId,
    required int offsetMs,
    required DateTime deviceTime,
  }) async {
    final result = await _channel.invokeMethod<String>('scan', {
      'sessionId': sessionId,
      'offsetMs': offsetMs,
      'deviceTimeMs': deviceTime.millisecondsSinceEpoch,
    });
    return result == null ? null : DocumentScan.fromJson(result);
  }

  Future<List<DocumentScan>> pending(String sessionId) async {
    final results =
        await _channel.invokeListMethod<String>('pending', {
          'sessionId': sessionId,
        }) ??
        [];
    return results.map(DocumentScan.fromJson).toList();
  }

  Future<void> acknowledge(String id) =>
      _channel.invokeMethod('acknowledge', {'id': id});
}
