import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/pincode/desktop_client.dart';
import 'package:yesem/pincode/pin_code_manager_app.dart';
import 'package:yesem/shared/ipc_protocol.dart';

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
}
