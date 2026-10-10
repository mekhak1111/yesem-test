# Testing on the Windows 11 ARM VM with Claude Code

The Windows VM in VMware Fusion is encrypted, so nothing can be automated from
the Mac. Instead, Claude Code runs **inside** the VM and does the setup there.

## 1. Get the project into the VM

Either share the folder, in Fusion: Virtual Machine → Settings → Sharing →
enable, add `~/Desktop/testFlutterMObileDesktop`. Windows then sees it as
`\\vmware-host\Shared Folders\testFlutterMObileDesktop`.

Or drag `~/Desktop/yesem-project.zip` from the Mac onto the VM desktop
(needs VMware Tools in the guest, which Fusion Windows VMs normally have).

## 2. Install Claude Code, in PowerShell inside the VM

Copy `tool\vm\windows_bootstrap.ps1` next to the project or run it from the
share, then:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& "\\vmware-host\Shared Folders\testFlutterMObileDesktop\tool\vm\windows_bootstrap.ps1"
# or, from a zip on the desktop:
& "$env:USERPROFILE\Desktop\windows_bootstrap.ps1" -Source "$env:USERPROFILE\Desktop\yesem-project.zip"
```

The script installs Git for Windows and Claude Code (both via official
installers, no admin), copies the project to `%USERPROFILE%\yesem`, and starts
`claude` there. The first start opens a browser: log in with the same Claude
account you use on the Mac.

Manual equivalent of the install step:

```powershell
winget install --id Git.Git -e
irm https://claude.ai/install.ps1 | iex
claude --version
```

## 3. Prompt for the Windows Claude session

Paste this as the first message (the project `CLAUDE.md` gives it the rest):

> Read CLAUDE.md, README.md and tool/vm/WINDOWS_VM.md. Set this Windows machine
> up to build and run the two desktop flavors of this Flutter project, then run
> the full test plan in section 4 of WINDOWS_VM.md and fix anything in
> windows/runner or the CMake files that does not compile. Report what you
> changed. Ask before anything that needs administrator rights, then use an
> elevated PowerShell for it.

## 4. What the Windows Claude session should do

1. Prerequisites (administrator PowerShell):
   * Developer Mode, needed for plugin symlinks:
     `reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1`
   * Visual Studio 2022 Build Tools with the C++ desktop workload and ARM64
     tools (this VM is ARM64):
     `winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --includeRecommended"`
2. Flutter 3.47.4, the version pinned in `.fvmrc`. Simplest: plain clone, then
   drop the `fvm` prefix from every command in the README:
   `git clone -b 3.47.4 --depth 1 https://github.com/flutter/flutter.git C:\src\flutter`
   and add `C:\src\flutter\bin` to the user PATH. `flutter doctor -v` must show
   a green "Visual Studio" line. Android and Chrome may be red.
3. `flutter pub get`, `flutter analyze`, `flutter test` (65 tests expected).
4. First real compile of the Windows runner:
   `flutter build windows --debug --flavor pincode`
   Output: `build\windows\arm64\pincode\runner\Debug\yesem.exe`. Likely trouble
   spots if it fails: the `target_compile_definitions` line in
   `windows/runner/CMakeLists.txt` and `L"" YESEM_WINDOW_TITLE` in
   `windows/runner/main.cpp`.
5. `flutter run -d windows --flavor desktop`. Title "YesEm Desktop", chip
   "flavor: desktop". Click Sign → "YesEm Pin Code Manager" window → type a
   PIN → Confirm → the PIN shows in Desktop.
6. Fallback: `Rename-Item build\windows\arm64\pincode pincode.off`, click Sign
   again; Desktop must start its own executable in helper role (Connection
   details shows "this executable, helper role"). Rename back.
7. Cancel in the helper, and closing it without a PIN, are reported by Desktop.
8. `tool\build_desktop_bundles.ps1` then run `dist\windows\desktop\yesem-desktop.exe`;
   Sign must find `dist\windows\pincode\yesem-pincode.exe`.
9. Confirm no Windows Firewall prompt appeared (loopback is exempt).

Report back: compiler output of any failure, and which of steps 4 to 9 passed.

## 5. Windows installer (after section 4 passes)

Prompt for the Windows Claude session:

> Read CLAUDE.md, README.md (section "macOS installer") and section 5 of
> tool/vm/WINDOWS_VM.md. Create the Windows installer for YesEm with Inno Setup,
> following the decisions listed there. Build it, install it, test it, uninstall
> it, and report what you created. Ask before anything that needs administrator
> rights, then use an elevated PowerShell for it.

Decisions (agreed on the Mac side, mirror the macOS `.pkg`):

* **Tool**: Inno Setup 6 (`winget install --id JRSoftware.InnoSetup -e`). An MSI
  (WiX) may follow later for IT deployment; not now.
* **Files to create**: `tool/windows_installer/yesem.iss` and
  `tool/build_windows_installer.ps1`, in the style of `tool/build_macos_installer.sh`:
  build both flavors in release mode (reuse `tool\build_desktop_bundles.ps1`), then
  run `ISCC.exe`. Output `dist\windows\YesEm-Setup-<version>.exe`, version from
  `pubspec.yaml`. A `-SkipBuild` switch reuses existing builds.
* **One installer, both apps**, per machine (admin prompt):
  `C:\Program Files\YesEm\desktop\yesem-desktop.exe` and
  `C:\Program Files\YesEm\pincode\yesem-pincode.exe`. Each app keeps its own
  folder (each needs its own `data\`). Desktop finds the helper through the sibling
  `pincode\` folder, so no Dart changes should be needed. Check that it does.
* **Visual C++ runtime**: copy `msvcp140.dll`, `vcruntime140.dll`,
  `vcruntime140_1.dll` (from the VS Build Tools redist folder, matching the
  architecture) next to each `.exe`, so the app starts on a clean PC.
* **Architecture**: this VM is ARM64, so the build is arm64. Make the script and
  `.iss` take the architecture from the build output (`ArchitecturesAllowed` /
  `ArchitecturesInstallIn64BitMode` = `arm64` or `x64compatible`) so the same
  files produce an x64 installer on an x64 machine.
* **Installer contents**: AppName "YesEm", AppPublisher "Volo", a fixed `AppId`
  GUID (generate once, never change: upgrades depend on it), Start menu shortcut
  for YesEm Desktop only (optional desktop icon task), app icon from
  `windows\runner\resources\app_icon.ico`, `CloseApplications=yes` so running
  apps are closed before files are replaced, uninstaller registered in
  Settings → Apps, `MinVersion` Windows 10.
* **Signing**: unsigned for now, but ready: `SignTool=yesem` and
  `SignedUninstaller=yes` only when the script gets a `-SignCommand` parameter
  (passed to ISCC as `/Syesem=…`); the script then also signs both `.exe` files
  with `signtool sign /fd SHA256 /sha1 <thumbprint> /tr <timestamp-url> /td SHA256`.
* **Test**: install, start YesEm Desktop from the Start menu, click Sign, type a
  PIN in the Pin Code Manager, see it in Desktop. Install the same version again
  (repair) and a rebuilt one with a higher version (upgrade, no second entry in
  Settings → Apps). Uninstall: both folders and the Start menu entry are gone.
* **Docs**: a "Windows installer" section in README.md next to "macOS installer",
  and one line in CLAUDE.md under Layout.

When done, zip the changed and new files (not `build\` or `dist\`) to the
desktop so they can be copied back to the Mac.

## Browser → Pin Code Manager link (yesem-pcm://)

See README "Browser → Pin Code Manager". In the VM:

```powershell
git pull
tool\build_desktop_bundles.ps1
tool\web_demo\register_scheme.ps1
flutter dart run tool/web_demo/server.dart
```

Open http://127.0.0.1:8787 in the VM's browser, click **Sign with ID card**,
allow opening the Pin Code Manager, enter a PIN, Confirm: the page must show
"Done" and the PIN. Also check Cancel, and that a second click opens a new
Pin Code Manager window (no single-instance forwarding on Windows yet).
After installing the setup.exe, unregister the dev entry
(register_scheme.ps1 -Unregister) and repeat: the installed app must handle the link.

