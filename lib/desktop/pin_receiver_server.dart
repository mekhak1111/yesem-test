import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../shared/ipc_protocol.dart';

/// Loopback HTTP server through which the Pin Code Manager reports back to
/// YesEm Desktop.
///
/// The server is armed for one signing request at a time with [expect]. Only
/// requests carrying the matching bearer token and request id are accepted,
/// and the token is invalidated as soon as a terminal event (PIN entered or
/// cancelled) arrives, so a token can never be replayed.
class PinReceiverServer {
  PinReceiverServer({InternetAddress? address})
    : _address = address ?? InternetAddress.loopbackIPv4;

  static const int _maxBodyBytes = 64 * 1024;

  final InternetAddress _address;
  final StreamController<PcmEvent> _events =
      StreamController<PcmEvent>.broadcast();

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  String? _expectedToken;
  String? _expectedRequestId;

  /// Accepted events, in arrival order.
  Stream<PcmEvent> get events => _events.stream;

  /// The bound port, or null while stopped.
  int? get port => _server?.port;

  bool get isRunning => _server != null;

  /// Binds an ephemeral loopback port (idempotent) and returns it.
  Future<int> start() async {
    if (_server case final server?) {
      return server.port;
    }
    final server = await HttpServer.bind(_address, 0);
    _server = server;
    _subscription = server.listen(_handle);
    return server.port;
  }

  /// Accepts events for exactly one signing request from now on.
  void expect({required String token, required String requestId}) {
    _expectedToken = token;
    _expectedRequestId = requestId;
  }

  /// Rejects every event until the next [expect].
  void disarm() {
    _expectedToken = null;
    _expectedRequestId = null;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
    disarm();
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<void> _handle(HttpRequest request) async {
    // Every branch is awaited here so that failures stay inside this try and
    // the client always gets an answer instead of hanging.
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == IpcProtocol.healthPath) {
        await _reply(request.response, HttpStatus.ok, <String, Object?>{
          'app': 'yesem-desktop',
          'status': 'ok',
        });
      } else if (request.method == 'POST' && path == IpcProtocol.eventPath) {
        await _handleEvent(request);
      } else {
        await _reply(request.response, HttpStatus.notFound, <String, Object?>{
          'error': 'not found',
        });
      }
    } on FormatException catch (error) {
      await _reply(request.response, HttpStatus.badRequest, <String, Object?>{
        'error': error.message,
      });
    } on Object catch (error) {
      await _reply(
        request.response,
        HttpStatus.internalServerError,
        <String, Object?>{'error': '$error'},
      );
    }
  }

  Future<void> _handleEvent(HttpRequest request) async {
    final token = _expectedToken;
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (token == null ||
        authorization != '${IpcProtocol.bearerPrefix}$token') {
      return _reply(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{'error': 'invalid or expired token'},
      );
    }
    if (request.contentLength > _maxBodyBytes) {
      return _reply(
        request.response,
        HttpStatus.requestEntityTooLarge,
        <String, Object?>{'error': 'body too large'},
      );
    }
    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Event body must be a JSON object');
    }
    final event = PcmEvent.fromJson(decoded);
    if (event.requestId != _expectedRequestId) {
      return _reply(request.response, HttpStatus.conflict, <String, Object?>{
        'error': 'unknown request id',
      });
    }
    if (event.type != PcmEventType.opened) {
      disarm(); // Terminal event: the token is single use.
    }
    _events.add(event);
    return _reply(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
    });
  }

  static Future<void> _reply(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
