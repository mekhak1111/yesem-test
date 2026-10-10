// Demo "web service" for the browser → Pin Code Manager flow. Serves a page
// with a "Sign with ID card" button and the session API both sides use:
//
//   POST /api/sessions               page: new session -> {id, link, ...}
//   GET  /api/sessions/<id>          page polls; Pin Code Manager reads service
//   POST /api/sessions/<id>/events   Pin Code Manager: opened / pinEntered / cancelled
//
// Run: fvm dart run tool/web_demo/server.dart [--port 8787]
// then open http://127.0.0.1:8787 in a browser. Loopback only.
import 'dart:convert';
import 'dart:io';

import 'session_store.dart';

const String linkScheme = 'yesem-pcm'; // lib/shared/web_link.dart WebLink.scheme

Future<void> main(List<String> args) async {
  final portIndex = args.indexOf('--port');
  final port = portIndex >= 0 && portIndex + 1 < args.length
      ? int.parse(args[portIndex + 1])
      : 8787;
  final store = SessionStore();
  final page = File.fromUri(Platform.script.resolve('index.html'));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final origin = 'http://127.0.0.1:${server.port}';
  stdout.writeln('Demo web service on $origin  (Ctrl+C to stop)');

  String linkFor(DemoSession s) => Uri(
    scheme: linkScheme,
    host: 'pin',
    queryParameters: <String, String>{'session': s.id, 'server': origin},
  ).toString();

  await for (final request in server) {
    final response = request.response;
    final segments = request.uri.pathSegments;
    try {
      if (request.method == 'GET' && (segments.isEmpty || segments.first == 'index.html')) {
        response.headers.contentType = ContentType.html;
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        await response.addStream(page.openRead());
      } else if (segments.length >= 2 && segments[0] == 'api' && segments[1] == 'sessions') {
        if (request.method == 'POST' && segments.length == 2) {
          final session = store.create();
          stdout.writeln('session ${session.id} created');
          _json(response, 201, session.toJson(linkFor(session)));
        } else if (request.method == 'GET' && segments.length == 3) {
          final session = store.get(segments[2]);
          if (session == null) {
            throw const SessionError(404, 'unknown session');
          }
          _json(response, 200, session.toJson(linkFor(session)));
        } else if (request.method == 'POST' && segments.length == 4 && segments[3] == 'events') {
          final body = await utf8.decoder.bind(request).join();
          final session = store.applyEvent(segments[2], body.isEmpty ? null : jsonDecode(body));
          // Never log the PIN itself, not even in the test bed.
          stdout.writeln(
            'session ${session.id}: ${session.status.name}'
            '${session.pin != null ? ' (PIN with ${session.pin!.length} digits)' : ''}',
          );
          _json(response, 200, session.toJson(linkFor(session)));
        } else {
          throw const SessionError(405, 'method not allowed');
        }
      } else {
        throw const SessionError(404, 'not found');
      }
    } on SessionError catch (error) {
      _json(response, error.statusCode, <String, Object?>{'error': error.message});
    } on FormatException {
      _json(response, 400, <String, Object?>{'error': 'invalid JSON'});
    }
    await response.close();
  }
}

void _json(HttpResponse response, int status, Map<String, Object?> body) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
    ..write(jsonEncode(body));
}
