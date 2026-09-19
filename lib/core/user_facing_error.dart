import 'package:flutter/services.dart';

/// Keep platform stack traces and arbitrary details out of transient banners.
String userFacingError(Object error) {
  final message = error is PlatformException
      ? (error.message ?? error.code)
      : error.toString();
  final firstLine = message.split('\n').first.trim();
  return firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine;
}
