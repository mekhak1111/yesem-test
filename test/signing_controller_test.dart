import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/desktop/pin_code_manager_launcher.dart';
import 'package:yesem/desktop/signing_controller.dart';
import 'package:yesem/pincode/desktop_client.dart';
import 'package:yesem/shared/ipc_protocol.dart';

/// Stands in for the Pin Code Manager process; the test drives the "helper"
/// itself through the real HTTP gateway.
class FakeLauncher implements PinCodeManagerLauncher {
  FakeLauncher({this.notFound = false});

  final bool notFound;
  final Completer<ProcessExit> exit = Completer<ProcessExit>();
  LaunchParameters? lastParameters;

  @override
  Future<LaunchedPinCodeManager> launch(LaunchParameters parameters) async {
    if (notFound) {
      throw const PinCodeManagerNotFound(<String>['/nowhere/PCM.app']);
    }
    lastParameters = parameters;
    return LaunchedPinCodeManager(appPath: '/fake/PCM.app', exited: exit.future);
  }
}

Future<void> waitForPhase(SigningController controller, SigningPhase phase) {
  if (controller.phase == phase) {
    return Future<void>.value();
  }
  final completer = Completer<void>();
  void listener() {
    if (controller.phase == phase && !completer.isCompleted) {
      completer.complete();
    }
  }
  controller.addListener(listener);
  return completer.future
      .timeout(const Duration(seconds: 5), onTimeout: () {
        throw TimeoutException('Never reached $phase (now ${controller.phase})');
      })
      .whenComplete(() => controller.removeListener(listener));
}

void main() {
  test('happy path: launch, helper opens, PIN arrives', () async {
    final launcher = FakeLauncher();
    final controller = SigningController(launcher: launcher);
    addTearDown(controller.dispose);

    await controller.startSigning();
    expect(controller.phase, SigningPhase.launching);
    expect(controller.port, isNotNull);
    expect(controller.pinCodeManagerPath, '/fake/PCM.app');

    final parameters = launcher.lastParameters!;
    expect(parameters.port, controller.port);
    expect(parameters.token, controller.token);
    expect(parameters.requestId, controller.requestId);

    final helper = HttpDesktopGateway(parameters);
    addTearDown(helper.close);
    await helper.send(PcmEvent(requestId: parameters.requestId, type: PcmEventType.opened));
    await waitForPhase(controller, SigningPhase.waitingForPin);

    await helper.send(
      PcmEvent(requestId: parameters.requestId, type: PcmEventType.pinEntered, pin: '2580'),
    );
    await waitForPhase(controller, SigningPhase.pinReceived);
    expect(controller.receivedPin, '2580');

    // A late exit of the helper must not disturb the finished session.
    launcher.exit.complete(const ProcessExit(code: 0));
    await pumpEventQueue();
    expect(controller.phase, SigningPhase.pinReceived);

    // The token died with the PIN.
    expect(
      () => helper.send(PcmEvent(requestId: parameters.requestId, type: PcmEventType.opened)),
      throwsA(isA<DesktopGatewayException>()),
    );
  });

  test('cancel from the helper', () async {
    final launcher = FakeLauncher();
    final controller = SigningController(launcher: launcher);
    addTearDown(controller.dispose);
    await controller.startSigning();
    final parameters = launcher.lastParameters!;
    final helper = HttpDesktopGateway(parameters);
    addTearDown(helper.close);

    await helper.send(PcmEvent(requestId: parameters.requestId, type: PcmEventType.cancelled));
    await waitForPhase(controller, SigningPhase.cancelled);
    expect(controller.receivedPin, isNull);
  });

  test('helper closed without a PIN', () async {
    final launcher = FakeLauncher();
    final controller = SigningController(launcher: launcher);
    addTearDown(controller.dispose);
    await controller.startSigning();

    launcher.exit.complete(const ProcessExit(code: 0));
    await waitForPhase(controller, SigningPhase.closedWithoutPin);
  });

  test('helper crashed', () async {
    final launcher = FakeLauncher();
    final controller = SigningController(launcher: launcher);
    addTearDown(controller.dispose);
    await controller.startSigning();

    launcher.exit.complete(const ProcessExit(code: 1, stderr: 'boom'));
    await waitForPhase(controller, SigningPhase.failed);
    expect(controller.errorMessage, contains('boom'));
  });

  test('helper not installed', () async {
    final controller = SigningController(launcher: FakeLauncher(notFound: true));
    addTearDown(controller.dispose);
    await controller.startSigning();
    expect(controller.phase, SigningPhase.failed);
    expect(controller.errorMessage, contains('/nowhere/PCM.app'));
  });

  test('reset clears the session and every new attempt gets a new token', () async {
    final launcher = FakeLauncher();
    final controller = SigningController(launcher: launcher);
    addTearDown(controller.dispose);

    await controller.startSigning();
    final first = launcher.lastParameters!;
    controller.reset();
    expect(controller.phase, SigningPhase.idle);
    expect(controller.token, isNull);

    await controller.startSigning();
    final second = launcher.lastParameters!;
    expect(second.token, isNot(first.token));
    expect(second.requestId, isNot(first.requestId));
    expect(second.port, first.port, reason: 'the server stays up between attempts');
  });
}
