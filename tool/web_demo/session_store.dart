// Sessions of the demo web service (tool/web_demo/server.dart), kept free of
// I/O so test/web_demo_session_store_test.dart can exercise them.
//
// The JSON shapes mirror lib/shared/web_link.dart and the PcmEvent of
// lib/shared/ipc_protocol.dart; they are duplicated here because the server
// runs with plain `dart run`, which can't load Flutter libraries.
import 'dart:convert';
import 'dart:math';

enum SessionStatus { pending, opened, completed, cancelled, expired }

class DemoSession {
  DemoSession({
    required this.id,
    required this.service,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String service;
  final DateTime createdAt;
  final DateTime expiresAt;
  SessionStatus status = SessionStatus.pending;

  /// Test bed only: the page shows the PIN it got back. A real service never
  /// receives a PIN; the card performs the operation and the server gets the
  /// signature or authentication result.
  String? pin;
  DateTime? updatedAt;

  bool get isFinal =>
      status == SessionStatus.completed ||
      status == SessionStatus.cancelled ||
      status == SessionStatus.expired;

  Map<String, Object?> toJson(String link) => <String, Object?>{
    'id': id,
    'service': service,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    if (pin != null) 'pin': pin,
    'link': link,
  };
}

class SessionError implements Exception {
  const SessionError(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode: $message';
}

class SessionStore {
  SessionStore({
    this.service = 'Demo Web Service',
    this.lifetime = const Duration(minutes: 5),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final String service;
  final Duration lifetime;
  final DateTime Function() _clock;
  final Random _random;
  final Map<String, DemoSession> _sessions = <String, DemoSession>{};

  DemoSession create() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final id = base64Url.encode(bytes).replaceAll('=', '');
    final now = _clock();
    return _sessions[id] = DemoSession(
      id: id,
      service: service,
      createdAt: now,
      expiresAt: now.add(lifetime),
    );
  }

  /// The session, marked expired once its lifetime has passed; null if unknown.
  DemoSession? get(String id) {
    final session = _sessions[id];
    if (session != null && !session.isFinal && _clock().isAfter(session.expiresAt)) {
      session
        ..status = SessionStatus.expired
        ..updatedAt = _clock();
    }
    return session;
  }

  /// Applies a Pin Code Manager event: `{"requestId", "type", "pin"?}` with
  /// type `opened`, `pinEntered` or `cancelled`.
  DemoSession applyEvent(String id, Object? json) {
    final session = get(id);
    if (session == null) {
      throw const SessionError(404, 'unknown session');
    }
    if (session.status == SessionStatus.expired) {
      throw const SessionError(410, 'session expired');
    }
    if (session.isFinal) {
      throw SessionError(409, 'session already ${session.status.name}');
    }
    if (json is! Map<String, Object?> || json['requestId'] != id) {
      throw const SessionError(400, 'event needs "requestId" equal to the session id');
    }
    switch (json['type']) {
      case 'opened':
        session.status = SessionStatus.opened;
      case 'pinEntered':
        final pin = json['pin'];
        if (pin is! String || !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
          throw const SessionError(400, 'pinEntered needs a 4-8 digit "pin"');
        }
        session
          ..status = SessionStatus.completed
          ..pin = pin;
      case 'cancelled':
        session.status = SessionStatus.cancelled;
      default:
        throw SessionError(400, 'unknown event type ${json['type']}');
    }
    session.updatedAt = _clock();
    return session;
  }
}
