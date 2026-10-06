import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../shared/ipc_protocol.dart';
import 'pin_code_manager_launcher.dart';
import 'pin_receiver_server.dart';

enum SigningPhase {
  idle,

  /// Server is up and the Pin Code Manager process is being started.
  launching,

  /// The Pin Code Manager reported that it is showing the PIN prompt.
  waitingForPin,
  pinReceived,
  cancelled,

  /// The Pin Code Manager quit without sending a PIN or a cancel.
  closedWithoutPin,
  failed,
}

/// Drives one card-reader signing attempt on the Desktop side:
/// start the loopback server, launch the Pin Code Manager, wait for its events.
class SigningController extends ChangeNotifier {
  SigningController({
    PinReceiverServer? server,
    PinCodeManagerLauncher? launcher,
    Random? random,
  }) : _server = server ?? PinReceiverServer(),
       _launcher = launcher ?? ProcessPinCodeManagerLauncher(),
       _random = random ?? Random.secure() {
    _subscription = _server.events.listen(_onEvent);
  }

  final PinReceiverServer _server;
  final PinCodeManagerLauncher _launcher;
  final Random _random;
  late final StreamSubscription<PcmEvent> _subscription;

  SigningPhase _phase = SigningPhase.idle;
  String? _receivedPin;
  String? _errorMessage;
  String? _requestId;
  String? _token;
  String? _pinCodeManagerPath;

  SigningPhase get phase => _phase;
  String? get receivedPin => _receivedPin;
  String? get errorMessage => _errorMessage;
  String? get requestId => _requestId;
  String? get token => _token;
  int? get port => _server.port;
  String? get pinCodeManagerPath => _pinCodeManagerPath;

  bool get isBusy =>
      _phase == SigningPhase.launching || _phase == SigningPhase.waitingForPin;

  Future<void> startSigning() async {
    if (isBusy) {
      return;
    }
    _receivedPin = null;
    _errorMessage = null;
    _pinCodeManagerPath = null;
    _setPhase(SigningPhase.launching);
    try {
      final port = await _server.start();
      final requestId = _randomHex(8);
      final token = _randomHex(32);
      _requestId = requestId;
      _token = token;
      _server.expect(token: token, requestId: requestId);
      final launched = await _launcher.launch(
        LaunchParameters(port: port, token: token, requestId: requestId),
      );
      _pinCodeManagerPath = launched.isSameExecutable
          ? '${launched.appPath} (this executable, helper role)'
          : launched.appPath;
      notifyListeners();
      unawaited(
        launched.exited.then((exit) => _onPinCodeManagerExited(requestId, exit)),
      );
    } on PinCodeManagerNotFound catch (error) {
      _fail('$error');
    } on Exception catch (error) {
      _fail('Could not start the Pin Code Manager: $error');
    }
  }

  /// Back to [SigningPhase.idle]; forgets the PIN and invalidates the token.
  void reset() {
    _server.disarm();
    _requestId = null;
    _token = null;
    _receivedPin = null;
    _errorMessage = null;
    _pinCodeManagerPath = null;
    _setPhase(SigningPhase.idle);
  }

  void _onEvent(PcmEvent event) {
    if (event.requestId != _requestId) {
      return;
    }
    switch (event.type) {
      case PcmEventType.opened:
        if (_phase == SigningPhase.launching) {
          _setPhase(SigningPhase.waitingForPin);
        }
      case PcmEventType.pinEntered:
        _receivedPin = event.pin;
        _setPhase(SigningPhase.pinReceived);
      case PcmEventType.cancelled:
        _setPhase(SigningPhase.cancelled);
    }
  }

  void _onPinCodeManagerExited(String requestId, ProcessExit exit) {
    if (requestId != _requestId || !isBusy) {
      return; // A newer request took over, or this one already finished.
    }
    _server.disarm();
    if (exit.code != 0) {
      final detail = exit.stderr.isEmpty ? '' : ': ${exit.stderr}';
      _fail('The Pin Code Manager exited with code ${exit.code}$detail');
    } else {
      _setPhase(SigningPhase.closedWithoutPin);
    }
  }

  void _fail(String message) {
    _server.disarm();
    _errorMessage = message;
    _setPhase(SigningPhase.failed);
  }

  void _setPhase(SigningPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  String _randomHex(int length) => List<String>.generate(
    length,
    (_) => _random.nextInt(16).toRadixString(16),
  ).join();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_server.dispose());
    super.dispose();
  }
}
