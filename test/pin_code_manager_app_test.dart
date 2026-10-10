import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import 'package:yesem/pincode/desktop_client.dart';
import 'package:yesem/pincode/link_source.dart';
import 'package:yesem/pincode/pin_code_manager_app.dart';
import 'package:yesem/pincode/web_client.dart';
import 'package:yesem/shared/ipc_protocol.dart';
import 'package:yesem/shared/web_link.dart';

class FakeGateway implements DesktopGateway {
  FakeGateway({this.failWith});

  final String? failWith;
  final List<PcmEvent> sent = <PcmEvent>[];

  @override
  Future<void> send(PcmEvent event) async {
    if (failWith case final message?) {
      throw DesktopGatewayException(message);
    }
    sent.add(event);
  }

  @override
  void close() {}
}

const launch = LaunchParameters(port: 4000, token: 'tok', requestId: 'req-1');

class FakeWebGateway extends FakeGateway implements WebSessionGateway {
  FakeWebGateway({super.failWith, this.service = 'Demo Web Service'});

  final String service;

  @override
  Future<WebSessionInfo> describe() async {
    if (failWith case final message?) {
      throw DesktopGatewayException(message);
    }
    return WebSessionInfo(service: service, status: 'pending');
  }
}

class FakeLinks implements LinkSource {
  FakeLinks([this.initial = const <String>[]]);

  final List<String> initial;
  final StreamController<String> controller = StreamController<String>.broadcast();

  @override
  Future<List<String>> takeInitial() async => initial;

  @override
  Stream<String> get incoming => controller.stream;
}

const sessionId = 'Ab3_kd93-xQ2mZ0pL7wR1t';
final webLink = WebPinRequest(server: Uri.parse('http://127.0.0.1:8787'), sessionId: sessionId).toLink();

void main() {
  testWidgets('announces itself, gates Confirm on a 4-digit PIN, delivers it, then quits',
      (tester) async {
    final gateway = FakeGateway();
    var finished = 0;
    await tester.pumpWidget(
      PinCodeManagerApp(
        launch: launch,
        gatewayFactory: (_) => gateway,
        onFinished: () => finished++,
      ),
    );
    await tester.pumpAndSettle();

    expect(gateway.sent, <PcmEvent>[
      const PcmEvent(requestId: 'req-1', type: PcmEventType.opened),
    ]);
    expect(find.text('Signing request from YesEm Desktop'), findsOneWidget);

    final confirm = find.byKey(const Key('confirm-button'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('pin-field')), '12a');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'letters are dropped');

    await tester.enterText(find.byKey(const Key('pin-field')), '1234');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pump();
    expect(gateway.sent.last, const PcmEvent(requestId: 'req-1', type: PcmEventType.pinEntered, pin: '1234'));
    expect(find.byKey(const Key('delivered-text')), findsOneWidget);
    expect(finished, 0);

    await tester.pump(PinCodeManagerPage.closeDelay);
    expect(finished, 1);
  });

  testWidgets('cancel reports to Desktop and quits', (tester) async {
    final gateway = FakeGateway();
    var finished = 0;
    await tester.pumpWidget(
      PinCodeManagerApp(launch: launch, gatewayFactory: (_) => gateway, onFinished: () => finished++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-button')));
    await tester.pump();
    expect(gateway.sent.last.type, PcmEventType.cancelled);
    expect(finished, 1);
  });

  testWidgets('shows the error and the manual form when Desktop is unreachable', (tester) async {
    await tester.pumpWidget(
      PinCodeManagerApp(
        launch: launch,
        gatewayFactory: (_) => FakeGateway(failWith: 'Cannot reach YesEm Desktop'),
        onFinished: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not reach YesEm Desktop'), findsOneWidget);
    expect(find.text('Cannot reach YesEm Desktop'), findsOneWidget);
    expect(find.text('Manual connection (development)'), findsOneWidget);
    expect(find.byKey(const Key('pin-field')), findsNothing);
  });

  testWidgets('started by hand: no request, manual form offered', (tester) async {
    await tester.pumpWidget(
      PinCodeManagerApp(gatewayFactory: (_) => FakeGateway(), onFinished: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('No active signing request'), findsOneWidget);
    expect(find.text('Manual connection (development)'), findsOneWidget);
  });

  group('opened from a browser link', () {
    testWidgets('shows the requesting service and sends the PIN to its server', (tester) async {
      final gateway = FakeWebGateway();
      WebPinRequest? requested;
      var finished = 0;
      await tester.pumpWidget(
        PinCodeManagerApp(
          links: FakeLinks(<String>[webLink]),
          webGatewayFactory: (request) {
            requested = request;
            return gateway;
          },
          onFinished: () => finished++,
        ),
      );
      await tester.pumpAndSettle();

      expect(requested?.server.origin, 'http://127.0.0.1:8787');
      expect(find.text('Signing request from Demo Web Service'), findsOneWidget);
      expect(find.text('Manual connection (development)'), findsNothing);
      expect(gateway.sent, <PcmEvent>[const PcmEvent(requestId: sessionId, type: PcmEventType.opened)]);

      await tester.enterText(find.byKey(const Key('pin-field')), '2468');
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-button')));
      await tester.pump();
      expect(gateway.sent.last, const PcmEvent(requestId: sessionId, type: PcmEventType.pinEntered, pin: '2468'));
      expect(find.text('PIN delivered to Demo Web Service. Closing…'), findsOneWidget);
      await tester.pump(PinCodeManagerPage.closeDelay);
      expect(finished, 1);
    });

    testWidgets('a link arriving while running starts the request', (tester) async {
      final links = FakeLinks();
      await tester.pumpWidget(
        PinCodeManagerApp(links: links, webGatewayFactory: (_) => FakeWebGateway(), onFinished: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('No active signing request'), findsOneWidget);
      links.controller.add(webLink);
      await tester.pumpAndSettle();
      expect(find.text('Signing request from Demo Web Service'), findsOneWidget);
    });

    testWidgets('rejects a link pointing at a server outside the allowlist', (tester) async {
      var created = 0;
      final evil = 'yesem-pcm://pin?session=$sessionId&server=${Uri.encodeComponent('https://evil.example')}';
      await tester.pumpWidget(
        PinCodeManagerApp(
          links: FakeLinks(<String>[evil]),
          webGatewayFactory: (_) {
            created++;
            return FakeWebGateway();
          },
          onFinished: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(created, 0, reason: 'never contacts a server it does not trust');
      expect(find.text("Could not process the website's request"), findsOneWidget);
      expect(find.byKey(const Key('pin-field')), findsNothing);
    });

    testWidgets('reports an expired request from the server', (tester) async {
      await tester.pumpWidget(
        PinCodeManagerApp(
          links: FakeLinks(<String>[webLink]),
          webGatewayFactory: (_) => FakeWebGateway(failWith: 'This request has expired. Start again from the website.'),
          onFinished: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This request has expired. Start again from the website.'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });
}
