import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/desktop/pin_receiver_server.dart';
import 'package:yesem/shared/ipc_protocol.dart';

Future<(int, String)> post(
  int port,
  String path, {
  String? token,
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path),
    );
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.contentType = ContentType.json;
    request.write(body is String ? body : jsonEncode(body));
    final response = await request.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  } finally {
    client.close(force: true);
  }
}

void main() {
  late PinReceiverServer server;
  late int port;
  late List<PcmEvent> received;

  setUp(() async {
    server = PinReceiverServer();
    received = <PcmEvent>[];
    server.events.listen(received.add);
    port = await server.start();
  });

  tearDown(() => server.dispose());

  test('binds an ephemeral loopback port once', () async {
    expect(port, greaterThan(0));
    expect(await server.start(), port);
    expect(server.isRunning, isTrue);
  });

  test('health endpoint needs no token', () async {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/health'),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    expect(
      jsonDecode(await utf8.decoder.bind(response).join()),
      <String, Object?>{'app': 'yesem-desktop', 'status': 'ok'},
    );
    client.close(force: true);
  });

  test('rejects events while disarmed or with a wrong token', () async {
    final event = const PcmEvent(requestId: 'r', type: PcmEventType.opened).toJson();
    var (status, _) = await post(port, '/pcm/event', token: 'anything', body: event);
    expect(status, HttpStatus.unauthorized);

    server.expect(token: 'secret', requestId: 'r');
    (status, _) = await post(port, '/pcm/event', token: 'wrong', body: event);
    expect(status, HttpStatus.unauthorized);
    (status, _) = await post(port, '/pcm/event', body: event);
    expect(status, HttpStatus.unauthorized);
    expect(received, isEmpty);
  });

  test('accepts matching events and emits them', () async {
    server.expect(token: 'secret', requestId: 'r');
    final opened = const PcmEvent(requestId: 'r', type: PcmEventType.opened);
    final (status, body) = await post(port, '/pcm/event', token: 'secret', body: opened.toJson());
    expect(status, HttpStatus.ok);
    expect(jsonDecode(body), <String, Object?>{'ok': true});
    await pumpEventQueue();
    expect(received, <PcmEvent>[opened]);
  });

  test('rejects a foreign request id', () async {
    server.expect(token: 'secret', requestId: 'r');
    final (status, _) = await post(
      port,
      '/pcm/event',
      token: 'secret',
      body: const PcmEvent(requestId: 'other', type: PcmEventType.opened).toJson(),
    );
    expect(status, HttpStatus.conflict);
    expect(received, isEmpty);
  });

  test('the token is single use once a PIN arrives', () async {
    server.expect(token: 'secret', requestId: 'r');
    final pin = const PcmEvent(requestId: 'r', type: PcmEventType.pinEntered, pin: '1234');
    var (status, _) = await post(port, '/pcm/event', token: 'secret', body: pin.toJson());
    expect(status, HttpStatus.ok);
    (status, _) = await post(port, '/pcm/event', token: 'secret', body: pin.toJson());
    expect(status, HttpStatus.unauthorized);
    await pumpEventQueue();
    expect(received, <PcmEvent>[pin]);
  });

  test('malformed bodies are a 400, unknown paths a 404', () async {
    server.expect(token: 'secret', requestId: 'r');
    var (status, _) = await post(port, '/pcm/event', token: 'secret', body: '{"type":"opened"}');
    expect(status, HttpStatus.badRequest);
    (status, _) = await post(port, '/nope', token: 'secret', body: '{}');
    expect(status, HttpStatus.notFound);
  });
}
