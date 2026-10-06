import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/desktop/desktop_app.dart';
import 'package:yesem/desktop/pin_code_manager_launcher.dart';
import 'package:yesem/desktop/pin_receiver_server.dart';
import 'package:yesem/desktop/signing_controller.dart';
import 'package:yesem/shared/ipc_protocol.dart';

class NeverExitingLauncher implements PinCodeManagerLauncher {
  @override
  Future<LaunchedPinCodeManager> launch(LaunchParameters parameters) async =>
      LaunchedPinCodeManager(appPath: '/fake/PCM.app', exited: Completer<ProcessExit>().future);
}

/// No real socket: widget tests run under FakeAsync, where a live HttpServer
/// would leave its idle timer pending.
class FakeServer extends PinReceiverServer {
  @override
  Future<int> start() async => 4242;

  @override
  int? get port => 4242;

  @override
  Future<void> stop() async {}
}

SigningController buildController() =>
    SigningController(server: FakeServer(), launcher: NeverExitingLauncher());

void main() {
  testWidgets('idle Desktop shows a Sign button and no PIN', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(DesktopApp(controller: controller));

    expect(find.text('YesEm Desktop'), findsOneWidget);
    expect(find.byKey(const Key('sign-button')), findsOneWidget);
    expect(find.byKey(const Key('received-pin')), findsNothing);
    expect(find.byKey(const Key('reset-button')), findsNothing);
  });

  testWidgets('Sign disables itself while the helper is open', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(DesktopApp(controller: controller));

    await tester.tap(find.byKey(const Key('sign-button')));
    await tester.pump();
    await tester.pump();

    expect(controller.phase, SigningPhase.launching);
    expect(tester.widget<FilledButton>(find.byKey(const Key('sign-button'))).onPressed, isNull);
    expect(find.textContaining('Opening the YesEm Pin Code Manager'), findsOneWidget);
    expect(find.byKey(const Key('reset-button')), findsOneWidget);
  });
}
