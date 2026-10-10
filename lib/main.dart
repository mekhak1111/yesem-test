import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:window_manager/window_manager.dart';

import 'app_role.dart';
import 'desktop/desktop_app.dart';
import 'mobile/mobile_app.dart';
import 'pincode/link_source.dart';
import 'pincode/pin_code_manager_app.dart';
import 'shared/ipc_protocol.dart';

/// `--dart-define=YESEM_APP=…`; the role selector for Windows and Linux builds.
const String yesemAppDefine = String.fromEnvironment('YESEM_APP');

Future<void> main(List<String> args) async {
  final isMobile = Platform.isAndroid || Platform.isIOS;
  final roleArgument = readArgument(args, IpcProtocol.argRole);
  final role = resolveAppRole(
    isMobilePlatform: isMobile,
    roleArgument: roleArgument,
    flavor: appFlavor,
    dartDefine: yesemAppDefine,
  );
  if (!isMobile) {
    await _configureWindow(role);
  }
  final roleSource = describeRoleSource(
    roleArgument: roleArgument,
    flavor: appFlavor,
    dartDefine: yesemAppDefine,
  );
  switch (role) {
    case AppRole.mobile:
      runApp(const MobileApp());
    case AppRole.desktop:
      runApp(DesktopApp(roleSource: roleSource));
    case AppRole.pinCodeManager:
      final launch = LaunchParameters.parse(args, Platform.environment);
      runApp(
        PinCodeManagerApp(
          launch: launch,
          // Not started by Desktop: maybe by a browser link (yesem-pcm://…).
          links: launch == null ? platformLinkSource(args) : null,
        ),
      );
  }
}

/// The native runners only know the project name; the role, and therefore the
/// window title, is decided here in Dart.
Future<void> _configureWindow(AppRole role) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle(role.windowTitle);
  // macOS sizes the helper natively before the window appears
  // (MainFlutterWindow.swift); elsewhere it is done here.
  if (role == AppRole.pinCodeManager && !Platform.isMacOS) {
    await windowManager.setSize(const Size(520, 640));
    await windowManager.center();
  }
}
