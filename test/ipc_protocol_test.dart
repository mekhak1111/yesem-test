import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/shared/ipc_protocol.dart';

void main() {
  group('LaunchParameters.parse', () {
    test('reads --key=value arguments', () {
      final parameters = LaunchParameters.parse(<String>[
        '--yesem-port=4321',
        '--yesem-token=abc',
        '--yesem-request=r1',
      ]);
      expect(
        parameters,
        const LaunchParameters(port: 4321, token: 'abc', requestId: 'r1'),
      );
    });

    test('reads --key value arguments', () {
      final parameters = LaunchParameters.parse(<String>[
        '--yesem-port', '4321',
        '--yesem-token', 'abc',
        '--yesem-request', 'r1',
      ]);
      expect(parameters?.port, 4321);
      expect(parameters?.token, 'abc');
      expect(parameters?.requestId, 'r1');
    });

    test('falls back to the environment', () {
      final parameters = LaunchParameters.parse(
        const <String>[],
        <String, String>{
          'YESEM_DESKTOP_PORT': '80',
          'YESEM_DESKTOP_TOKEN': 't',
          'YESEM_DESKTOP_REQUEST': 'r',
        },
      );
      expect(parameters, const LaunchParameters(port: 80, token: 't', requestId: 'r'));
    });

    test('returns null when anything is missing or malformed', () {
      expect(LaunchParameters.parse(const <String>[]), isNull);
      expect(
        LaunchParameters.parse(<String>['--yesem-port=x', '--yesem-token=t', '--yesem-request=r']),
        isNull,
      );
      expect(
        LaunchParameters.parse(<String>['--yesem-port=1', '--yesem-token=', '--yesem-request=r']),
        isNull,
      );
    });

    test('round-trips through toArgs and toEnvironment', () {
      const original = LaunchParameters(port: 5000, token: 'tok', requestId: 'req');
      expect(LaunchParameters.parse(original.toArgs()), original);
      expect(LaunchParameters.parse(const <String>[], original.toEnvironment()), original);
    });

    test('builds loopback URIs', () {
      const parameters = LaunchParameters(port: 5000, token: 'tok', requestId: 'req');
      expect(parameters.uri('/pcm/event').toString(), 'http://127.0.0.1:5000/pcm/event');
    });
  });

  group('readArgument', () {
    test('supports both spellings and ignores unrelated arguments', () {
      expect(readArgument(<String>['--x=1', '--yesem-role=pincode'], '--yesem-role'), 'pincode');
      expect(readArgument(<String>['--yesem-role', 'desktop'], '--yesem-role'), 'desktop');
      expect(readArgument(<String>['--yesem-role'], '--yesem-role'), isNull);
      expect(readArgument(const <String>[], '--yesem-role'), isNull);
    });
  });

  group('PcmEvent', () {
    test('round-trips through JSON', () {
      const event = PcmEvent(requestId: 'r', type: PcmEventType.pinEntered, pin: '1234');
      expect(PcmEvent.fromJson(event.toJson()), event);
    });

    test('omits pin when absent', () {
      const event = PcmEvent(requestId: 'r', type: PcmEventType.opened);
      expect(event.toJson(), <String, Object?>{'requestId': 'r', 'type': 'opened'});
    });

    test('rejects unknown types and missing fields', () {
      expect(
        () => PcmEvent.fromJson(<String, Object?>{'requestId': 'r', 'type': 'nope'}),
        throwsFormatException,
      );
      expect(
        () => PcmEvent.fromJson(<String, Object?>{'type': 'opened'}),
        throwsFormatException,
      );
    });
  });
}
