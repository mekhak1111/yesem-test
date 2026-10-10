import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../shared/ipc_protocol.dart';
import '../shared/web_link.dart';
import 'desktop_client.dart';

/// What the requesting server says about a session.
class WebSessionInfo {
  const WebSessionInfo({required this.service, required this.status});

  /// Shown to the user, who must recognize the requesting service.
  final String service;
  final String status;
}

/// The Pin Code Manager's view of a web session started from a browser link.
/// Speaks the same [PcmEvent]s as the Desktop handshake, to the server that
/// owns the session instead of to Desktop.
abstract interface class WebSessionGateway implements DesktopGateway {
  Future<WebSessionInfo> describe();
}

class HttpWebSessionGateway implements WebSessionGateway {
  HttpWebSessionGateway(
    this.request, {
    HttpClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? HttpClient();

  final WebPinRequest request;
  final Duration timeout;
  final HttpClient _client;

  @override
  Future<WebSessionInfo> describe() async {
    final json = await _call('GET', WebLink.sessionPath(request.sessionId));
    final service = json['service'];
    final status = json['status'];
    if (service is! String || status is! String) {
      throw const DesktopGatewayException('The server sent an invalid session.');
    }
    // "opened": the same link was opened before (e.g. clicked twice).
    if (status != 'pending' && status != 'opened') {
      throw DesktopGatewayException(
        status == 'expired'
            ? 'This request has expired. Start again from the website.'
            : 'This request is no longer active ($status). Start again from '
                  'the website.',
      );
    }
    return WebSessionInfo(service: service, status: status);
  }

  @override
  Future<void> send(PcmEvent event) =>
      _call('POST', WebLink.eventsPath(request.sessionId), event.toJson());

  Future<Map<String, Object?>> _call(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final where = request.server.origin;
    try {
      final http = await _client.openUrl(method, request.uri(path)).timeout(timeout);
      if (body != null) {
        http.headers.contentType = ContentType.json;
        http.write(jsonEncode(body));
      }
      final response = await http.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.notFound) {
        throw const DesktopGatewayException(
          'The website does not know this request. Start again from the website.',
        );
      }
      if (response.statusCode == HttpStatus.gone) {
        throw const DesktopGatewayException(
          'This request has expired. Start again from the website.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw DesktopGatewayException(
          'The website rejected the request (HTTP ${response.statusCode}): $text',
        );
      }
      final decoded = text.isEmpty ? null : jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : const <String, Object?>{};
    } on SocketException catch (error) {
      throw DesktopGatewayException('Cannot reach $where: ${error.message}');
    } on TimeoutException {
      throw DesktopGatewayException('$where did not answer in time.');
    } on FormatException {
      throw DesktopGatewayException('$where sent an invalid answer.');
    }
  }

  @override
  void close() => _client.close(force: true);
}
