import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yesem/desktop/pin_code_manager_launcher.dart';

void main() {
  group('macOS', () {
    const executable =
        '/repo/build/macos/Build/Products/Debug-desktop/YesEm Desktop.app/Contents/MacOS/YesEm Desktop';

    test('prefers the sibling pincode product of the same mode', () {
      final locator = PinCodeManagerLocator(
        currentExecutable: executable,
        environment: const <String, String>{},
        exists: (_) => false,
        os: DesktopOs.macos,
      );
      expect(locator.candidates(), <String>[
        '/repo/build/macos/Build/Products/Debug-desktop/YesEm Pin Code Manager.app',
        '/repo/build/macos/Build/Products/Debug-pincode/YesEm Pin Code Manager.app',
        '/repo/build/macos/Build/Products/Release-pincode/YesEm Pin Code Manager.app',
        '/repo/build/macos/Build/Products/Profile-pincode/YesEm Pin Code Manager.app',
        '/Applications/YesEm Pin Code Manager.app',
      ]);
    });

    test('an explicit override comes first and HOME adds ~/Applications', () {
      final locator = PinCodeManagerLocator(
        currentExecutable: executable,
        environment: const <String, String>{
          'YESEM_PCM_APP': '/custom/PCM.app',
          'HOME': '/Users/me',
        },
        exists: (_) => false,
        os: DesktopOs.macos,
      );
      final candidates = locator.candidates();
      expect(candidates.first, '/custom/PCM.app');
      expect(candidates.last, '/Users/me/Applications/YesEm Pin Code Manager.app');
    });

    test('locate returns the first existing candidate, or null', () {
      const wanted = '/repo/build/macos/Build/Products/Release-pincode/YesEm Pin Code Manager.app';
      final found = PinCodeManagerLocator(
        currentExecutable: executable,
        environment: const <String, String>{},
        exists: (path) => path == wanted,
        os: DesktopOs.macos,
      );
      expect(found.locate(), wanted);
      final missing = PinCodeManagerLocator(
        currentExecutable: executable,
        environment: const <String, String>{},
        exists: (_) => false,
        os: DesktopOs.macos,
      );
      expect(missing.locate(), isNull);
    });
  });

  group('Linux', () {
    test('sibling dist folder first, then system locations', () {
      final locator = PinCodeManagerLocator(
        currentExecutable: '/opt/yesem/desktop/yesem-desktop',
        environment: const <String, String>{'HOME': '/home/me'},
        exists: (_) => false,
        os: DesktopOs.linux,
        pathContext: p.posix,
      );
      expect(locator.candidates(), <String>[
        '/opt/yesem/pincode/yesem-pincode',
        '/opt/yesem/pincode/yesem-desktop',
        '/opt/yesem/YesEm Pin Code Manager/yesem-pincode',
        '/opt/yesem/YesEm Pin Code Manager/yesem-desktop',
        '/opt/yesem/desktop/yesem-pincode',
        '/usr/local/bin/yesem-pincode',
        '/home/me/.local/bin/yesem-pincode',
      ]);
    });

    test('bundles copied without renaming are found by the shared name', () {
      final locator = PinCodeManagerLocator(
        currentExecutable: '/srv/dist/desktop/yesem',
        environment: const <String, String>{},
        exists: (path) => path == '/srv/dist/pincode/yesem',
        os: DesktopOs.linux,
        pathContext: p.posix,
      );
      expect(locator.locate(), '/srv/dist/pincode/yesem');
    });
  });

  group('Flutter 3.47+ flavored build trees', () {
    test('Linux: flutter run of the desktop flavor finds the built pincode flavor', () {
      const helper = '/repo/build/linux/x64/pincode/debug/bundle/yesem';
      final locator = PinCodeManagerLocator(
        currentExecutable: '/repo/build/linux/x64/desktop/debug/bundle/yesem',
        environment: const <String, String>{},
        exists: (path) => path == helper,
        os: DesktopOs.linux,
        pathContext: p.posix,
      );
      expect(
        locator.candidates(),
        containsAllInOrder(<String>[
          helper,
          '/repo/build/linux/x64/pincode/release/bundle/yesem',
          '/repo/build/linux/x64/pincode/profile/bundle/yesem',
          '/repo/build/linux/x64/desktop/debug/bundle/yesem-pincode',
        ]),
      );
      expect(locator.locate(), helper);
    });

    test('Windows: same, with the runner/<Mode> layout', () {
      const helper = r'C:\repo\build\windows\x64\pincode\runner\Debug\yesem.exe';
      final locator = PinCodeManagerLocator(
        currentExecutable: r'C:\repo\build\windows\x64\desktop\runner\Debug\yesem.exe',
        environment: const <String, String>{},
        exists: (path) => path == helper,
        os: DesktopOs.windows,
        pathContext: p.windows,
      );
      expect(
        locator.candidates(),
        containsAllInOrder(<String>[
          helper,
          r'C:\repo\build\windows\x64\pincode\runner\Release\yesem.exe',
          r'C:\repo\build\windows\x64\pincode\runner\Profile\yesem.exe',
        ]),
      );
      expect(locator.locate(), helper);
    });

    test('plain install trees add no flavored candidates', () {
      final locator = PinCodeManagerLocator(
        currentExecutable: '/opt/yesem/desktop/yesem-desktop',
        environment: const <String, String>{},
        exists: (_) => false,
        os: DesktopOs.linux,
        pathContext: p.posix,
      );
      expect(locator.candidates().where((c) => c.contains('/bundle/')), isEmpty);
    });
  });

  group('Windows', () {
    test('sibling dist folder first, then per-user and Program Files', () {
      final locator = PinCodeManagerLocator(
        currentExecutable: r'C:\Apps\YesEm\desktop\yesem-desktop.exe',
        environment: const <String, String>{
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
          'ProgramFiles': r'C:\Program Files',
        },
        exists: (_) => false,
        os: DesktopOs.windows,
        pathContext: p.windows,
      );
      expect(locator.candidates(), <String>[
        r'C:\Apps\YesEm\pincode\yesem-pincode.exe',
        r'C:\Apps\YesEm\pincode\yesem-desktop.exe',
        r'C:\Apps\YesEm\YesEm Pin Code Manager\yesem-pincode.exe',
        r'C:\Apps\YesEm\YesEm Pin Code Manager\yesem-desktop.exe',
        r'C:\Apps\YesEm\desktop\yesem-pincode.exe',
        r'C:\Users\me\AppData\Local\Programs\YesEm Pin Code Manager\yesem-pincode.exe',
        r'C:\Program Files\YesEm Pin Code Manager\yesem-pincode.exe',
      ]);
    });
  });
}
