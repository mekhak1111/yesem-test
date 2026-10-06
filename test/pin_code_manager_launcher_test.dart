import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yesem/desktop/pin_code_manager_launcher.dart';
import 'package:yesem/shared/ipc_protocol.dart';

class FakeProcess implements Process {
  final Completer<int> _exit = Completer<int>();

  void finish(int code) => _exit.complete(code);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => throw UnsupportedError('no stdin');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) {
      _exit.complete(-1);
    }
    return true;
  }
}

class RecordingStarter {
  String? executable;
  List<String>? arguments;
  Map<String, String>? environment;
  final FakeProcess process = FakeProcess();

  Future<Process> call(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.environment = environment;
    return process;
  }
}

PinCodeManagerLocator locatorFinding(String? path, DesktopOs os) =>
    PinCodeManagerLocator(
      currentExecutable: '/apps/desktop/yesem',
      environment: const <String, String>{},
      exists: (candidate) => candidate == path,
      os: os,
      // The fake paths are posix; keep them so on a Windows host too.
      pathContext: p.posix,
    );

const parameters = LaunchParameters(port: 5000, token: 'tok', requestId: 'req');

void main() {
  test('Linux: an installed helper is spawned directly with role and parameters', () async {
    final starter = RecordingStarter();
    final launcher = ProcessPinCodeManagerLauncher(
      locator: locatorFinding('/apps/pincode/yesem-pincode', DesktopOs.linux),
      startProcess: starter.call,
      os: DesktopOs.linux,
      selfExecutable: '/apps/desktop/yesem',
    );

    final launched = await launcher.launch(parameters);

    expect(launched.appPath, '/apps/pincode/yesem-pincode');
    expect(launched.isSameExecutable, isFalse);
    expect(starter.executable, '/apps/pincode/yesem-pincode');
    expect(starter.arguments, <String>[
      '--yesem-role=pincode',
      '--yesem-port=5000',
      '--yesem-token=tok',
      '--yesem-request=req',
    ]);
    expect(starter.environment, parameters.toEnvironment());

    starter.process.finish(0);
    expect((await launched.exited).code, 0);
  });

  test('Linux and Windows: without an installed helper, Desktop runs itself in helper role', () async {
    for (final os in <DesktopOs>[DesktopOs.linux, DesktopOs.windows]) {
      final starter = RecordingStarter();
      final launcher = ProcessPinCodeManagerLauncher(
        locator: locatorFinding(null, os),
        startProcess: starter.call,
        os: os,
        selfExecutable: '/apps/desktop/yesem',
      );

      final launched = await launcher.launch(parameters);

      expect(launched.isSameExecutable, isTrue, reason: '$os');
      expect(starter.executable, '/apps/desktop/yesem');
      expect(starter.arguments?.first, '--yesem-role=pincode');
      expect(readArgument(starter.arguments!, IpcProtocol.argPort), '5000');
    }
  });

  test('macOS: the helper bundle is started through open -W', () async {
    final starter = RecordingStarter();
    final launcher = ProcessPinCodeManagerLauncher(
      locator: locatorFinding('/Applications/YesEm Pin Code Manager.app', DesktopOs.macos),
      startProcess: starter.call,
      os: DesktopOs.macos,
      selfExecutable: '/apps/desktop/yesem',
    );

    await launcher.launch(parameters);

    expect(starter.executable, '/usr/bin/open');
    expect(starter.arguments, <String>[
      '-n',
      '-W',
      '-a',
      '/Applications/YesEm Pin Code Manager.app',
      '--args',
      '--yesem-role=pincode',
      '--yesem-port=5000',
      '--yesem-token=tok',
      '--yesem-request=req',
    ]);
    expect(starter.environment, isNull, reason: 'open does not forward the environment');
  });

  test('macOS: without the helper bundle the launch fails with the searched paths', () async {
    final starter = RecordingStarter();
    final launcher = ProcessPinCodeManagerLauncher(
      locator: locatorFinding(null, DesktopOs.macos),
      startProcess: starter.call,
      os: DesktopOs.macos,
      selfExecutable: '/apps/desktop/yesem',
    );

    await expectLater(
      launcher.launch(parameters),
      throwsA(isA<PinCodeManagerNotFound>().having(
        (error) => error.searched,
        'searched',
        contains('/Applications/YesEm Pin Code Manager.app'),
      )),
    );
    expect(starter.executable, isNull);
  });
}
