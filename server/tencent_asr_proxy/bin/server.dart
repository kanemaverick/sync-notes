import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sync_notes_tencent_asr_proxy/tencent_signing.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final isScf = environment['TENCENTCLOUD_RUNENV'] == 'SCF';
  final port = int.tryParse(environment['PORT'] ?? '') ?? (isScf ? 9000 : 8080);
  final appId = environment['TENCENT_APP_ID']?.trim() ?? '';
  final secretId = environment['TENCENT_SECRET_ID']?.trim() ?? '';
  final secretKey = environment['TENCENT_SECRET_KEY']?.trim() ?? '';
  final proxyToken = environment['PROXY_AUTH_TOKEN']?.trim() ?? '';
  final configured =
      appId.isNotEmpty &&
      secretId.isNotEmpty &&
      secretKey.isNotEmpty &&
      proxyToken.isNotEmpty;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Tencent ASR proxy listening on :$port');
  stdout.writeln('Provider configured: $configured');

  ProcessSignal.sigterm.watch().listen((_) => unawaited(server.close()));
  await for (final request in server) {
    unawaited(
      _handleRequest(
        request,
        configured: configured,
        appId: appId,
        secretId: secretId,
        secretKey: secretKey,
        proxyToken: proxyToken,
      ),
    );
  }
}

Future<void> _handleRequest(
  HttpRequest request, {
  required bool configured,
  required String appId,
  required String secretId,
  required String secretKey,
  required String proxyToken,
}) async {
  if (request.method == 'GET' && request.uri.path == '/health') {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'ok': true, 'providerConfigured': configured}));
    await request.response.close();
    return;
  }
  if (request.uri.path != '/v1/asr/tencent/realtime' ||
      !WebSocketTransformer.isUpgradeRequest(request)) {
    await _respond(request, HttpStatus.notFound, 'Not found');
    return;
  }
  if (!configured) {
    await _respond(
      request,
      HttpStatus.serviceUnavailable,
      'Tencent ASR is not configured',
    );
    return;
  }
  final authorization = request.headers.value(HttpHeaders.authorizationHeader);
  if (!_constantTimeEquals(authorization ?? '', 'Bearer $proxyToken')) {
    await _respond(request, HttpStatus.unauthorized, 'Unauthorized');
    return;
  }

  WebSocket? upstream;
  WebSocket? client;
  try {
    final sessionId = _safeId(
      request.uri.queryParameters['session_id'] ?? 'session',
    );
    final random = Random.secure();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final voiceId = '${sessionId}_${_randomHex(random, 8)}';
    final upstreamUrl = buildTencentAsrUrl(
      appId: appId,
      secretId: secretId,
      secretKey: secretKey,
      voiceId: voiceId,
      timestamp: now,
      nonce: random.nextInt(2000000000) + 1,
    );
    upstream = await WebSocket.connect(
      upstreamUrl,
    ).timeout(const Duration(seconds: 8));
    upstream.pingInterval = const Duration(seconds: 5);
    client = await WebSocketTransformer.upgrade(request);
    client.pingInterval = const Duration(seconds: 5);
    client.add(jsonEncode({'type': 'proxy.ready'}));

    late final StreamSubscription<dynamic> clientSubscription;
    late final StreamSubscription<dynamic> upstreamSubscription;
    clientSubscription = client.listen(
      (message) {
        if (upstream!.readyState == WebSocket.open) upstream.add(message);
      },
      onError: (_) => unawaited(upstream!.close()),
      onDone: () {
        if (upstream!.readyState == WebSocket.open) {
          upstream.add(jsonEncode({'type': 'end'}));
        }
        unawaited(upstream.close());
      },
    );
    upstreamSubscription = upstream.listen(
      (message) {
        if (client!.readyState == WebSocket.open) client.add(message);
      },
      onError: (Object error) {
        if (client!.readyState == WebSocket.open) {
          client.add(jsonEncode({'type': 'proxy.error', 'message': '$error'}));
        }
      },
      onDone: () => unawaited(client!.close()),
    );
    await Future.wait([
      clientSubscription.asFuture<void>(),
      upstreamSubscription.asFuture<void>(),
    ]);
  } catch (error) {
    if (client != null && client.readyState == WebSocket.open) {
      client.add(jsonEncode({'type': 'proxy.error', 'message': '$error'}));
      await client.close(WebSocketStatus.internalServerError);
    } else {
      try {
        await _respond(request, HttpStatus.badGateway, 'Upstream unavailable');
      } catch (_) {
        // The WebSocket upgrade may already have committed the response.
      }
    }
    await upstream?.close();
  }
}

Future<void> _respond(HttpRequest request, int status, String message) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.text
    ..write(message);
  await request.response.close();
}

bool _constantTimeEquals(String left, String right) {
  var difference = left.length ^ right.length;
  final length = min(left.length, right.length);
  for (var index = 0; index < length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}

String _safeId(String value) {
  final sanitized = value.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
  return sanitized.substring(0, min(80, sanitized.length));
}

String _randomHex(Random random, int bytes) => List.generate(
  bytes,
  (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
