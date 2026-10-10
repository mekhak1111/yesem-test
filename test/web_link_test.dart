import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/shared/web_link.dart';

void main() {
  const session = 'Ab3_kd93-xQ2mZ0pL7wR1t';
  final server = Uri.encodeComponent('http://127.0.0.1:8787');

  test('parses a link from the demo server', () {
    final request = WebLink.parse('yesem-pcm://pin?session=$session&server=$server');
    expect(request.sessionId, session);
    expect(request.server.origin, 'http://127.0.0.1:8787');
    expect(request.uri(WebLink.eventsPath(session)).toString(),
        'http://127.0.0.1:8787/api/sessions/$session/events');
  });

  test('toLink round-trips', () {
    final request = WebPinRequest(server: Uri.parse('http://localhost:9000'), sessionId: session);
    expect(WebLink.parse(request.toLink()), request);
  });

  test('finds the link among command-line arguments', () {
    expect(WebLink.findInArgs(<String>['--x', 'YESEM-PCM://pin?session=1']), 'YESEM-PCM://pin?session=1');
    expect(WebLink.findInArgs(<String>['--yesem-role=pincode']), isNull);
  });

  group('rejects', () {
    void rejects(String link, String reason) => expect(
      () => WebLink.parse(link),
      throwsA(isA<WebLinkException>()),
      reason: reason,
    );

    test('other schemes and actions', () {
      rejects('https://pin?session=$session&server=$server', 'scheme');
      rejects('yesem-pcm://sign?session=$session&server=$server', 'action');
    });

    test('bad session ids', () {
      rejects('yesem-pcm://pin?server=$server', 'missing');
      rejects('yesem-pcm://pin?session=short&server=$server', 'too short');
      rejects('yesem-pcm://pin?session=${Uri.encodeComponent('a/../b c d e f')}&server=$server', 'characters');
    });

    test('servers outside the allowlist', () {
      String withServer(String s) => 'yesem-pcm://pin?session=$session&server=${Uri.encodeComponent(s)}';
      rejects(withServer('https://evil.example'), 'unknown https host');
      rejects(withServer('http://192.168.1.10:8787'), 'LAN http');
      rejects(withServer('http://user@127.0.0.1:8787'), 'credentials');
      rejects(withServer('http://127.0.0.1:8787/api'), 'path');
      rejects(withServer('file:///etc/passwd'), 'scheme');
    });
  });

  test('a product policy accepts only its pinned HTTPS hosts', () {
    const policy = WebLinkPolicy(httpsHosts: <String>{'nag.example.am'});
    final ok = 'yesem-pcm://pin?session=$session&server=${Uri.encodeComponent('https://nag.example.am')}';
    expect(WebLink.parse(ok, policy: policy).server.host, 'nag.example.am');
    expect(() => WebLink.parse('yesem-pcm://pin?session=$session&server=$server', policy: policy),
        throwsA(isA<WebLinkException>()), reason: 'loopback off in product policy');
  });
}
