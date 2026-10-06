import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../shared/ipc_protocol.dart';

class DesktopGatewayException implements Exception {
  const DesktopGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Pin Code Manager's view of the Desktop instance that launched it.
abstract interface class DesktopGateway {
  Future<void> send(PcmEvent event);

  void close();
}

/// Talks to Desktop's loopback [PinReceiverServer] over HTTP.
class HttpDesktopGateway implements DesktopGateway {
  HttpDesktopGateway(
    this.parameters, {
    HttpClient? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? HttpClient();

  final LaunchParameters parameters;
  final Duration timeout;
  final HttpClient _client;

  @override
  Future<void> send(PcmEvent event) async {
    try {
      final request = await _client
          .postUrl(parameters.uri(IpcProtocol.eventPath))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        '${IpcProtocol.bearerPrefix}${parameters.token}',
      );
      request.write(jsonEncode(event.toJson()));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw DesktopGatewayException(
          'YesEm Desktop rejected the event (HTTP ${response.statusCode}): '
          '$body',
        );
      }
    } on SocketException catch (error) {
      throw DesktopGatewayException(
        'Cannot reach YesEm Desktop at ${parameters.host}:${parameters.port}: '
        '${error.message}',
      );
    } on TimeoutException {
      throw const DesktopGatewayException(
        'YesEm Desktop did not answer in time.',
      );
    }
  }

  @override
  void close() => _client.close(force: true);
}
