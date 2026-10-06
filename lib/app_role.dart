/// The three applications that share this code base.
enum AppRole {
  /// YesEm Mobile (Android / iOS). Placeholder for now.
  mobile('YesEm Mobile'),

  /// YesEm Desktop: the document-signing application.
  desktop('YesEm Desktop'),

  /// YesEm Pin Code Manager: the helper that collects the card PIN.
  pinCodeManager('YesEm Pin Code Manager');

  const AppRole(this.windowTitle);

  final String windowTitle;
}

/// Decides which application this process is.
///
/// Mobile platforms always run YesEm Mobile. On desktop, in order of priority:
///
/// 1. [roleArgument]: a `--yesem-role=…` command-line argument. Desktop uses it
///    to run its own executable in helper role where no separate helper is
///    installed.
/// 2. [flavor]: the build flavor (`flutter run --flavor desktop|pincode`), which
///    the Flutter tool only supports on macOS among desktop platforms.
/// 3. [dartDefine]: `--dart-define=YESEM_APP=desktop|pincode`, the way to pick
///    the role when building for Windows and Linux.
///
/// Nothing at all means YesEm Desktop.
AppRole resolveAppRole({
  required bool isMobilePlatform,
  String? roleArgument,
  String? flavor,
  String dartDefine = '',
}) {
  if (isMobilePlatform) {
    return AppRole.mobile;
  }
  final key = <String?>[roleArgument, flavor, dartDefine]
      .firstWhere((value) => value != null && value.isNotEmpty, orElse: () => '')!
      .toLowerCase();
  return switch (key) {
    'pincode' || 'pin_code_manager' || 'pincodemanager' => AppRole.pinCodeManager,
    'desktop' || '' => AppRole.desktop,
    _ => throw ArgumentError.value(key, 'role', 'Unknown YesEm app role'),
  };
}

/// Human-readable origin of the role, for the debug chip in the UI.
String describeRoleSource({
  String? roleArgument,
  String? flavor,
  String dartDefine = '',
}) {
  if (roleArgument != null && roleArgument.isNotEmpty) {
    return 'argument: $roleArgument';
  }
  if (flavor != null && flavor.isNotEmpty) {
    return 'flavor: $flavor';
  }
  if (dartDefine.isNotEmpty) {
    return 'YESEM_APP: $dartDefine';
  }
  return 'default';
}
