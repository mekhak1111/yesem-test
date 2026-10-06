import 'package:flutter_test/flutter_test.dart';
import 'package:yesem/app_role.dart';

void main() {
  test('mobile platforms always run YesEm Mobile', () {
    expect(
      resolveAppRole(isMobilePlatform: true, flavor: 'pincode'),
      AppRole.mobile,
    );
  });

  test('flavor decides on desktop', () {
    expect(resolveAppRole(isMobilePlatform: false, flavor: 'desktop'), AppRole.desktop);
    expect(resolveAppRole(isMobilePlatform: false, flavor: 'pincode'), AppRole.pinCodeManager);
    expect(resolveAppRole(isMobilePlatform: false, flavor: 'PinCode'), AppRole.pinCodeManager);
  });

  test('dart-define is the fallback and no flavor means Desktop', () {
    expect(
      resolveAppRole(isMobilePlatform: false, flavor: null, dartDefine: 'pincode'),
      AppRole.pinCodeManager,
    );
    expect(resolveAppRole(isMobilePlatform: false, flavor: null), AppRole.desktop);
    expect(resolveAppRole(isMobilePlatform: false, flavor: ''), AppRole.desktop);
  });

  test('the --yesem-role argument beats flavor and define', () {
    expect(
      resolveAppRole(
        isMobilePlatform: false,
        roleArgument: 'pincode',
        flavor: 'desktop',
        dartDefine: 'desktop',
      ),
      AppRole.pinCodeManager,
    );
    expect(
      resolveAppRole(isMobilePlatform: false, roleArgument: '', flavor: 'desktop'),
      AppRole.desktop,
      reason: 'an empty argument does not count',
    );
  });

  test('unknown roles fail loudly', () {
    expect(
      () => resolveAppRole(isMobilePlatform: false, flavor: 'tablet'),
      throwsArgumentError,
    );
  });

  test('window titles and role source descriptions', () {
    expect(AppRole.pinCodeManager.windowTitle, 'YesEm Pin Code Manager');
    expect(describeRoleSource(roleArgument: 'pincode', flavor: 'desktop'), 'argument: pincode');
    expect(describeRoleSource(flavor: 'desktop'), 'flavor: desktop');
    expect(describeRoleSource(dartDefine: 'pincode'), 'YESEM_APP: pincode');
    expect(describeRoleSource(), 'default');
  });
}
