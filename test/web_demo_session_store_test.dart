import 'package:flutter_test/flutter_test.dart';

import '../tool/web_demo/session_store.dart';

void main() {
  var now = DateTime.utc(2026, 10, 10, 12);
  SessionStore store() => SessionStore(clock: () => now, lifetime: const Duration(minutes: 5));

  setUp(() => now = DateTime.utc(2026, 10, 10, 12));

  test('new sessions have link-safe, unique ids', () {
    final s = store();
    final ids = <String>{for (var i = 0; i < 50; i++) s.create().id};
    expect(ids, hasLength(50));
    expect(ids.every(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch), isTrue);
  });

  test('opened, then pinEntered completes the session with the PIN', () {
    final s = store();
    final id = s.create().id;
    expect(s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'opened'}).status, SessionStatus.opened);
    final done = s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'pinEntered', 'pin': '2468'});
    expect(done.status, SessionStatus.completed);
    expect(done.toJson('link')['pin'], '2468');
  });

  test('cancelled is final; later events conflict', () {
    final s = store();
    final id = s.create().id;
    s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'cancelled'});
    expect(
      () => s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'pinEntered', 'pin': '1234'}),
      throwsA(isA<SessionError>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('expires after its lifetime', () {
    final s = store();
    final id = s.create().id;
    now = now.add(const Duration(minutes: 6));
    expect(s.get(id)!.status, SessionStatus.expired);
    expect(
      () => s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'opened'}),
      throwsA(isA<SessionError>().having((e) => e.statusCode, 'status', 410)),
    );
  });

  test('rejects unknown sessions, mismatched ids and bad PINs', () {
    final s = store();
    final id = s.create().id;
    Matcher status(int code) => throwsA(isA<SessionError>().having((e) => e.statusCode, 'status', code));
    expect(() => s.applyEvent('nope', <String, Object?>{}), status(404));
    expect(() => s.applyEvent(id, <String, Object?>{'requestId': 'other', 'type': 'opened'}), status(400));
    expect(() => s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'pinEntered', 'pin': '12'}), status(400));
    expect(() => s.applyEvent(id, <String, Object?>{'requestId': id, 'type': 'hack'}), status(400));
  });
}
