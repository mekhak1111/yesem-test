import 'package:flutter/foundation.dart';

/// Wire protocol shared by YesEm Desktop (server side) and the YesEm Pin Code
/// Manager (client side).
///
/// Transport is plain HTTP on the IPv4 loopback interface. Desktop binds an
/// ephemeral port, launches the Pin Code Manager and hands it the port, a
/// one-time bearer token and a request id on the command line. The Pin Code
/// Manager reports back by POSTing [PcmEvent]s to [eventPath].
abstract final class IpcProtocol {
  /// Both apps always run on the same machine, so only loopback is used.
  static const String loopbackHost = '127.0.0.1';

  static const String argPort = '--yesem-port';
  static const String argToken = '--yesem-token';
  static const String argRequestId = '--yesem-request';

  /// Runtime role override, e.g. `--yesem-role=pincode`. Lets one build act
  /// as the helper on platforms without build flavors (Windows, Linux).
  static const String argRole = '--yesem-role';

  /// Environment fallbacks for platforms where the helper is spawned directly
  /// instead of through a launcher service.
  static const String envPort = 'YESEM_DESKTOP_PORT';
  static const String envToken = 'YESEM_DESKTOP_TOKEN';
  static const String envRequestId = 'YESEM_DESKTOP_REQUEST';

  static const String healthPath = '/health';
  static const String eventPath = '/pcm/event';

  static const String bearerPrefix = 'Bearer ';
}

/// Reads `--name=value` or `--name value` from [args]; null when absent.
String? readArgument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}

/// What the Pin Code Manager tells Desktop about the current signing request.
enum PcmEventType {
  /// The Pin Code Manager started and is showing the PIN prompt.
  opened,

  /// The user confirmed a PIN. [PcmEvent.pin] carries it.
  pinEntered,

  /// The user cancelled inside the Pin Code Manager.
  cancelled;

  static PcmEventType parse(String value) => PcmEventType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => throw FormatException('Unknown event type: $value'),
  );
}

@immutable
class PcmEvent {
  const PcmEvent({required this.requestId, required this.type, this.pin});

  factory PcmEvent.fromJson(Map<String, Object?> json) {
    final requestId = json['requestId'];
    final type = json['type'];
    final pin = json['pin'];
    if (requestId is! String || type is! String) {
      throw const FormatException('Event needs string "requestId" and "type"');
    }
    return PcmEvent(
      requestId: requestId,
      type: PcmEventType.parse(type),
      pin: pin is String ? pin : null,
    );
  }

  final String requestId;
  final PcmEventType type;
  final String? pin;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'type': type.name,
    if (pin != null) 'pin': pin,
  };

  @override
  bool operator ==(Object other) =>
      other is PcmEvent &&
      other.requestId == requestId &&
      other.type == type &&
      other.pin == pin;

  @override
  int get hashCode => Object.hash(requestId, type, pin);

  @override
  String toString() => 'PcmEvent($type, request $requestId)';
}

/// Everything the Pin Code Manager needs to reach the Desktop instance that
/// launched it.
@immutable
class LaunchParameters {
  const LaunchParameters({
    required this.port,
    required this.token,
    required this.requestId,
    this.host = IpcProtocol.loopbackHost,
  });

  final String host;
  final int port;
  final String token;
  final String requestId;

  /// Reads parameters from command-line [args] (`--key=value` or `--key value`),
  /// falling back to [environment]. Returns null when any part is missing.
  static LaunchParameters? parse(
    List<String> args, [
    Map<String, String> environment = const <String, String>{},
  ]) {
    final portText =
        readArgument(args, IpcProtocol.argPort) ?? environment[IpcProtocol.envPort];
    final token =
        readArgument(args, IpcProtocol.argToken) ??
        environment[IpcProtocol.envToken];
    final requestId =
        readArgument(args, IpcProtocol.argRequestId) ??
        environment[IpcProtocol.envRequestId];
    final port = portText == null ? null : int.tryParse(portText);
    if (port == null ||
        token == null ||
        token.isEmpty ||
        requestId == null ||
        requestId.isEmpty) {
      return null;
    }
    return LaunchParameters(port: port, token: token, requestId: requestId);
  }

  List<String> toArgs() => <String>[
    '${IpcProtocol.argPort}=$port',
    '${IpcProtocol.argToken}=$token',
    '${IpcProtocol.argRequestId}=$requestId',
  ];

  Map<String, String> toEnvironment() => <String, String>{
    IpcProtocol.envPort: '$port',
    IpcProtocol.envToken: token,
    IpcProtocol.envRequestId: requestId,
  };

  Uri uri(String path) => Uri(scheme: 'http', host: host, port: port, path: path);

  @override
  bool operator ==(Object other) =>
      other is LaunchParameters &&
      other.host == host &&
      other.port == port &&
      other.token == token &&
      other.requestId == requestId;

  @override
  int get hashCode => Object.hash(host, port, token, requestId);
}
