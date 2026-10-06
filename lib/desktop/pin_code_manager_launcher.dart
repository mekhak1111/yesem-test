import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../shared/ipc_protocol.dart';

/// Desktop operating systems this project runs on.
enum DesktopOs {
  macos,
  windows,
  linux,
  other;

  static DesktopOs get current {
    if (Platform.isMacOS) return DesktopOs.macos;
    if (Platform.isWindows) return DesktopOs.windows;
    if (Platform.isLinux) return DesktopOs.linux;
    return DesktopOs.other;
  }
}

/// Outcome of a finished Pin Code Manager process.
class ProcessExit {
  const ProcessExit({required this.code, this.stderr = ''});

  final int code;
  final String stderr;
}

/// Handle on a running Pin Code Manager.
class LaunchedPinCodeManager {
  const LaunchedPinCodeManager({
    required this.appPath,
    required this.exited,
    this.isSameExecutable = false,
  });

  /// Where the helper was found.
  final String appPath;

  /// Completes once the helper quits.
  final Future<ProcessExit> exited;

  /// True when Desktop started its own executable in helper role because no
  /// separate Pin Code Manager is installed (Windows and Linux development).
  final bool isSameExecutable;
}

class PinCodeManagerNotFound implements Exception {
  const PinCodeManagerNotFound(this.searched);

  final List<String> searched;

  @override
  String toString() =>
      'YesEm Pin Code Manager is not installed or not built yet. Looked in:\n'
      '${searched.map((path) => '  • $path').join('\n')}\n'
      'Build it with: flutter build macos --debug --flavor pincode, or set '
      '${PinCodeManagerLocator.envOverride} to its .app path.';
}

abstract interface class PinCodeManagerLauncher {
  Future<LaunchedPinCodeManager> launch(LaunchParameters parameters);
}

/// Finds a separately installed Pin Code Manager relative to the running
/// Desktop build, without any configuration in the common case.
class PinCodeManagerLocator {
  PinCodeManagerLocator({
    String? currentExecutable,
    Map<String, String>? environment,
    bool Function(String path)? exists,
    DesktopOs? os,
    p.Context? pathContext,
  }) : currentExecutable = currentExecutable ?? Platform.resolvedExecutable,
       environment = environment ?? Platform.environment,
       os = os ?? DesktopOs.current,
       _exists = exists ?? _pathExists,
       _paths = pathContext ?? p.context;

  static const String appName = 'YesEm Pin Code Manager';
  static const String flavorName = 'pincode';

  /// Executable name produced by tool/build_desktop_bundles.* on Windows and
  /// Linux (plus `.exe` on Windows).
  static const String helperExecutableName = 'yesem-pincode';

  /// Explicit override: full path to the Pin Code Manager .app or executable.
  static const String envOverride = 'YESEM_PCM_APP';

  static const List<String> _macModes = <String>['Debug', 'Release', 'Profile'];

  final String currentExecutable;
  final Map<String, String> environment;
  final DesktopOs os;
  final bool Function(String path) _exists;
  final p.Context _paths;

  static bool _pathExists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// Candidate locations, most specific first.
  ///
  /// macOS, for a Desktop binary at
  /// `…/Build/Products/Debug-desktop/YesEm Desktop.app/Contents/MacOS/…`:
  /// the sibling `Debug-pincode` product, the other modes, then
  /// `/Applications`.
  ///
  /// Windows and Linux, for `…/<dist>/desktop/yesem-desktop[.exe]`: the sibling
  /// `<dist>/pincode/` folder as laid out by tool/build_desktop_bundles.*,
  /// then the usual per-user and system install locations.
  List<String> candidates() {
    final result = <String>[];
    void add(String? path) {
      if (path == null || path.isEmpty) {
        return;
      }
      // Launchers need absolute paths; an override may be given relative.
      final absolute = _paths.normalize(_paths.absolute(path));
      if (!result.contains(absolute)) {
        result.add(absolute);
      }
    }

    add(environment[envOverride]);
    switch (os) {
      case DesktopOs.macos:
        final bundle = _paths.dirname(
          _paths.dirname(_paths.dirname(currentExecutable)),
        );
        final configurationDir = _paths.dirname(bundle);
        final productsDir = _paths.dirname(configurationDir);
        final currentMode = _paths.basename(configurationDir).split('-').first;
        add(_paths.join(configurationDir, '$appName.app'));
        for (final mode in <String>[currentMode, ..._macModes]) {
          add(_paths.join(productsDir, '$mode-$flavorName', '$appName.app'));
        }
        add('/Applications/$appName.app');
        final home = environment['HOME'];
        if (home != null && home.isNotEmpty) {
          add(_paths.join(home, 'Applications', '$appName.app'));
        }
      case DesktopOs.windows:
      case DesktopOs.linux:
      case DesktopOs.other:
        final exeDir = _paths.dirname(currentExecutable);
        final exeName = _paths.basename(currentExecutable);
        final extension = os == DesktopOs.windows ? '.exe' : '';
        final helperExe = '$helperExecutableName$extension';
        final distRoot = _paths.dirname(exeDir);
        for (final folder in <String>[
          _paths.join(distRoot, flavorName),
          _paths.join(distRoot, appName),
        ]) {
          add(_paths.join(folder, helperExe));
          add(_paths.join(folder, exeName)); // Bundles copied without renaming.
        }
        for (final path in _flavoredBuildSiblings(exeDir, exeName)) {
          add(path);
        }
        add(_paths.join(exeDir, helperExe));
        if (os == DesktopOs.windows) {
          final localAppData = environment['LOCALAPPDATA'];
          if (localAppData != null && localAppData.isNotEmpty) {
            add(_paths.join(localAppData, 'Programs', appName, helperExe));
          }
          final programFiles = environment['ProgramFiles'];
          if (programFiles != null && programFiles.isNotEmpty) {
            add(_paths.join(programFiles, appName, helperExe));
          }
        } else {
          add('/opt/yesem/$flavorName/$helperExe');
          add('/usr/local/bin/$helperExe');
          final home = environment['HOME'];
          if (home != null && home.isNotEmpty) {
            add(_paths.join(home, '.local', 'bin', helperExe));
          }
        }
    }
    return result;
  }

  /// Flutter 3.47+ builds each flavor into its own directory:
  ///
  /// * Windows: `build/windows/<arch>/<flavor>/runner/<Mode>/yesem.exe`
  /// * Linux: `build/linux/<arch>/<flavor>/<mode>/bundle/yesem`
  ///
  /// For an executable inside such a tree this returns the same executable in
  /// the sibling `pincode` flavor, current mode first, so `flutter run` of the
  /// Desktop flavor finds a previously built helper flavor.
  List<String> _flavoredBuildSiblings(String exeDir, String exeName) {
    if (os == DesktopOs.windows) {
      final runnerDir = _paths.dirname(exeDir);
      if (_paths.basename(runnerDir) != 'runner') {
        return const <String>[];
      }
      final archDir = _paths.dirname(_paths.dirname(runnerDir));
      final currentMode = _paths.basename(exeDir);
      return <String>[
        for (final mode in <String>[currentMode, 'Debug', 'Release', 'Profile'])
          _paths.join(archDir, flavorName, 'runner', mode, exeName),
      ];
    }
    if (_paths.basename(exeDir) != 'bundle') {
      return const <String>[];
    }
    final modeDir = _paths.dirname(exeDir);
    final archDir = _paths.dirname(_paths.dirname(modeDir));
    final currentMode = _paths.basename(modeDir);
    return <String>[
      for (final mode in <String>[currentMode, 'debug', 'release', 'profile'])
        _paths.join(archDir, flavorName, mode, 'bundle', exeName),
    ];
  }

  /// First existing candidate, or null.
  String? locate() {
    for (final candidate in candidates()) {
      if (_exists(candidate)) {
        return candidate;
      }
    }
    return null;
  }
}

/// Signature of [Process.start] as used here; injectable for tests.
typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

/// Starts the Pin Code Manager as a separate process.
///
/// macOS: the helper is a separate app bundle started through LaunchServices
/// (`open -W`), which brings its window to the front and keeps `open` alive
/// until the helper quits, so Desktop notices when the user closes it.
///
/// Windows and Linux: a separately installed helper executable is spawned
/// directly. Without one, Desktop spawns its own executable with
/// `--yesem-role=pincode`; every build of this project contains all roles.
class ProcessPinCodeManagerLauncher implements PinCodeManagerLauncher {
  ProcessPinCodeManagerLauncher({
    PinCodeManagerLocator? locator,
    ProcessStarter? startProcess,
    DesktopOs? os,
    String? selfExecutable,
  }) : locator = locator ?? PinCodeManagerLocator(),
       _startProcess = startProcess ?? Process.start,
       os = os ?? DesktopOs.current,
       selfExecutable = selfExecutable ?? Platform.resolvedExecutable;

  final PinCodeManagerLocator locator;
  final DesktopOs os;
  final String selfExecutable;
  final ProcessStarter _startProcess;

  @override
  Future<LaunchedPinCodeManager> launch(LaunchParameters parameters) async {
    final installed = locator.locate();
    if (installed != null) {
      return _start(installed, parameters);
    }
    if (os == DesktopOs.macos) {
      throw PinCodeManagerNotFound(locator.candidates());
    }
    return _start(selfExecutable, parameters, isSameExecutable: true);
  }

  Future<LaunchedPinCodeManager> _start(
    String path,
    LaunchParameters parameters, {
    bool isSameExecutable = false,
  }) async {
    // The role argument is redundant for a dedicated helper build and
    // decisive for a shared executable; always passing it keeps one code path.
    final helperArguments = <String>[
      '${IpcProtocol.argRole}=${PinCodeManagerLocator.flavorName}',
      ...parameters.toArgs(),
    ];
    final Process process;
    if (os == DesktopOs.macos) {
      process = await _startProcess('/usr/bin/open', <String>[
        '-n', // Always a fresh instance, so the arguments are delivered.
        '-W', // Stay alive until the helper quits.
        '-a',
        path,
        '--args',
        ...helperArguments,
      ]);
    } else {
      process = await _startProcess(
        path,
        helperArguments,
        environment: parameters.toEnvironment(),
      );
    }
    process.stdout.drain<void>();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exited = process.exitCode.then(
      (code) async => ProcessExit(code: code, stderr: (await stderr).trim()),
    );
    return LaunchedPinCodeManager(
      appPath: path,
      exited: exited,
      isSameExecutable: isSameExecutable,
    );
  }
}
