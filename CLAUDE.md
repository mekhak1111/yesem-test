# YesEm test project — notes for Claude Code sessions

One Flutter code base (package `yesem`) producing three apps:

- **YesEm Mobile** (Android/iOS): a single placeholder page. Mobile work is postponed; leave it alone.
- **YesEm Desktop** (macOS/Windows/Linux): flavor `desktop`. Has a Sign button.
- **YesEm Pin Code Manager** (macOS/Windows/Linux): flavor `pincode`. Collects the signature PIN.

Clicking Sign in Desktop launches the Pin Code Manager as a separate process, the user
types a PIN there, and the PIN is sent back to Desktop over loopback HTTP with a
one-time bearer token. **This is a test bed**: Desktop deliberately displays the PIN.
The real product (see the PRDs summarised in README.md) must never display, store or
log a PIN.

## Layout

- `lib/main.dart` picks the role: `--yesem-role=` argument > build flavor (`appFlavor`)
  > `--dart-define=YESEM_APP=` > Desktop by default. Every build contains all roles.
- `lib/desktop/` Desktop UI, `PinReceiverServer` (loopback HTTP), `SigningController`,
  `PinCodeManagerLauncher` + `PinCodeManagerLocator` (how Desktop finds/starts the helper
  per OS). `lib/pincode/` the helper UI and its HTTP client. `lib/shared/ipc_protocol.dart`
  the wire protocol and command-line argument names.
- `macos/` flavors are Xcode configurations/schemes (`tool/add_macos_flavors.py`).
  `windows/runner` and `linux/runner` read `FLUTTER_APP_FLAVOR` in CMake for the window
  title. The Windows runner is verified on Windows 11 ARM64; the Linux one is not compiled yet.
- `tool/build_desktop_bundles.sh|.ps1` build both roles into `dist/<os>/{desktop,pincode}`.
- `tool/build_macos_installer.sh` + `tool/macos_installer/` build the signed/notarizable
  `.pkg` into `dist/macos/` (unsigned without `APP_SIGN_IDENTITY`/`PKG_SIGN_IDENTITY`).
- `tool/build_windows_installer.ps1` + `tool/windows_installer/yesem.iss` build the Inno Setup
  installer `dist\windows\YesEm-Setup-<version>.exe` (unsigned without `-SignCommand`).
- `tool/vm/` scripts and checklists for testing in the Ubuntu and Windows VMs.

## Toolchain

- Flutter **3.47.4** is pinned in `.fvmrc` (FVM). Windows/Linux flavors need ≥ 3.47.
  With FVM: `fvm flutter …`; with a plain 3.47.x install: `flutter …`.
- Never build inside a VMware shared folder; copy the project to the local disk.

## Commands

```sh
fvm flutter test                                  # 49 hermetic tests must pass
fvm flutter analyze                               # must be clean
fvm flutter build <os> --debug --flavor pincode   # build the helper first
fvm flutter run -d <os> --flavor desktop          # then run Desktop and click Sign
```

Details, per-platform notes and the test plan: `README.md`, `tool/vm/UBUNTU_VM.md`,
`tool/vm/WINDOWS_VM.md`.

## Conventions

- Keep the hermetic test suite free of real processes and sockets except loopback in
  `test/pin_receiver_server_test.dart` and `test/signing_controller_test.dart`.
- Don't add `default-flavor` to `pubspec.yaml`: in 3.47 it applies to Android too and
  there are no Android flavors.
- Bundle ids / product names: `global.volo.yesem.desktop` "YesEm Desktop",
  `global.volo.yesem.pincode` "YesEm Pin Code Manager". Executables on Windows/Linux stay
  `yesem[.exe]` in build output; the bundle scripts rename them to `yesem-desktop` /
  `yesem-pincode`.
