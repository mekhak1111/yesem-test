// End-to-end check against the real built Pin Code Manager. Kept out of
// `test/` because it opens a window; run it explicitly:
//
//   flutter build macos --debug --flavor pincode
//   flutter test test_e2e
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yesem/desktop/pin_code_manager_launcher.dart';
import 'package:yesem/desktop/signing_controller.dart';

const String desktopBinary =
    'build/macos/Build/Products/Debug-desktop/YesEm Desktop.app/Contents/MacOS/YesEm Desktop';

Future<void> waitUntil(
  SigningController controller,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out in phase ${controller.phase}: ${controller.errorMessage}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  test('Desktop launches the built Pin Code Manager and hears back from it', () async {
    final locator = PinCodeManagerLocator(
      currentExecutable: p.absolute(desktopBinary),
    );
    final appPath = locator.locate();
    if (appPath == null || !Platform.isMacOS) {
      markTestSkipped('Pin Code Manager not built; run flutter build macos --debug --flavor pincode');
      return;
    }

    final controller = SigningController(
      launcher: ProcessPinCodeManagerLauncher(locator: locator),
    );
    addTearDown(controller.dispose);
    addTearDown(() => Process.run('pkill', <String>['-f', 'YesEm Pin Code Manager.app/Contents/MacOS']));

    await controller.startSigning();
    expect(controller.phase, SigningPhase.launching);
    expect(controller.pinCodeManagerPath, appPath);

    // The helper parsed the arguments handed over by `open --args` and posted
    // its "opened" event to our server with the right token.
    await waitUntil(controller, () => controller.phase == SigningPhase.waitingForPin);

    // Closing the helper without a PIN is noticed by Desktop.
    await Process.run('pkill', <String>['-f', 'YesEm Pin Code Manager.app/Contents/MacOS']);
    await waitUntil(controller, () => !controller.isBusy);
    expect(controller.receivedPin, isNull);
    expect(
      controller.phase,
      anyOf(SigningPhase.closedWithoutPin, SigningPhase.failed),
    );
  }, timeout: const Timeout(Duration(minutes: 1)));
}
