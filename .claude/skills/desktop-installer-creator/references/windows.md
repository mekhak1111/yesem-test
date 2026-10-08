# Windows installer (Inno Setup setup.exe)

## Contents
1. Tools and layout
2. Using assets/windows/build.ps1
3. How the prerequisite is handled
4. Manual equivalent (no script)
5. Verify and install
6. Alternatives and pitfalls

## 1. Tools and layout

- Windows 10/11, the app's toolchain (Flutter: Visual Studio 2022 Build Tools
  with the C++ workload; ARM64 tools on ARM machines).
- Inno Setup 6.1 or newer: `winget install --id JRSoftware.InnoSetup -e`
  (6.1 added `DownloadTemporaryFile`, `StrToVersion`, `ComparePackedVersion`).
- Signing: `signtool.exe` from the Windows SDK (Visual Studio Installer →
  Individual components → Windows SDK).
- The build machine's architecture decides the app's: Flutter builds only the
  host architecture, so an x64 installer needs an x64 machine.

Copy `assets/windows/{build.ps1,config.psd1,installer.iss}` to
`installer\windows\`. Prerequisite binaries go in `installer\prereqs\` (gitignored).

## 2. Using assets/windows/build.ps1

Fill in `config.psd1`: name, publisher, a fresh `AppGuid` (`New-Guid`, never
change it), version (or `VersionFromPubspec`), build command, app folders
(`Apps`: one entry per app; several apps need their own `Subdir`), and `Prereq`.

```powershell
installer\windows\build.ps1                    # build + package, unsigned
installer\windows\build.ps1 -SkipBuild
installer\windows\build.ps1 -SignCommand 'signtool sign /fd SHA256 /sha1 <thumbprint> /tr http://timestamp.digicert.com /td SHA256'
```

Steps: run the build, stage the app folders into `dist\windows\stage`, read
the architecture from the main exe's PE header (arm64 / x64), copy the Visual
C++ runtime next to each exe (`CopyVcRuntime`), sign our exes, verify the
prerequisite (SHA-256 + Authenticode, optionally the expected signer), write
`work\defines.iss` and `work\sections.iss`, compile `installer.iss` with ISCC
(passing the sign tool when signing). Output: `dist\windows\<AppName>-Setup-<version>.exe`.

If the signtool path contains spaces, quote it inside the command:
`-SignCommand '"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" sign …'`
(the script converts quotes for ISCC).

## 3. How the prerequisite is handled

All in `installer.iss` `[Code]`:

- `VendorNeeded`: searches Settings → Apps (`Uninstall` keys in HKLM 64-bit,
  HKLM 32-bit, HKCU) for an entry whose `DisplayName` contains
  `Prereq.DisplayName`; ignores exe entries whose uninstaller no longer exists;
  compares `DisplayVersion` with `MinVersion` (`StrToVersion`/`ComparePackedVersion`).
  Missing or older → install. Same/newer or unknown version → skip.
- `PrepareToInstall` (runs before any of our files are copied; a returned
  message stops Setup, so nothing is half-installed):
  - bundle: `ExtractTemporaryFile` (vendor files are `[Files]` entries with
    `Flags: dontcopy`, named `vendor.<ext>` / `vendor-arm64.<ext>`);
  - link: `DownloadTemporaryFile(url, name, sha256, nil)`, which verifies the
    hash and raises on mismatch; works in silent installs too;
  - runs exe with `Args`, or `msiexec /i … Args /l*v {tmp}\vendor-install.log`;
  - exit 0 → continue; 3010/1641 → continue and `NeedRestart` asks for a
    restart at the end; anything else → stop with the exit code in the message.
- On ARM64 Windows the arm64 vendor file/URL is used when configured;
  otherwise the x64 one (runs under emulation; drivers usually don't, so ask
  the vendor for an ARM64 build if it installs drivers).
- Uninstall never touches the vendor (no `[UninstallRun]` for it).

The link mode checks the pinned SHA-256 only. To also require the vendor's
signature, run before `RunVendor`:
`Exec('powershell.exe', '-NoProfile -Command "if ((Get-AuthenticodeSignature ''' + Path + ''').Status -ne ''Valid'') { exit 1 }"', '', SW_HIDE, ewWaitUntilTerminated, Code)`
and stop when `Code <> 0`.

For a progress page during download, replace `DownloadTemporaryFile` with
`CreateDownloadPage` (see Inno Setup's `CodeDownloadFiles.iss` example); note
that wizard-page events don't run in `/VERYSILENT` installs.

## 4. Manual equivalent (no script)

```ini
[Setup]
AppId={{00000000-0000-0000-0000-000000000000}
AppName=MyApp
AppVersion=1.0.0
AppPublisher=Example Ltd
DefaultDirName={autopf}\MyApp
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
OutputDir=dist
OutputBaseFilename=MyApp-Setup-1.0.0

[Files]
Source: "build\MyApp\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "prereqs\VendorMiddleware-Setup.exe"; DestName: "vendor.exe"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\MyApp"; Filename: "{app}\myapp.exe"

[Code]
const
  PrereqMode = 'bundle'; VendorName = 'Vendor Middleware';
  VendorDisplayName = 'Vendor Middleware'; VendorMinVersion = '1.2.3';
  VendorType = 'exe'; VendorArgs = '/quiet /norestart';
  VendorUrl = ''; VendorSha256 = ''; VendorUrlArm64 = ''; VendorSha256Arm64 = '';
  VendorHasArm64 = False;
{ …then the [Code] body of assets/windows/installer.iss }
```

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" myapp.iss
# signed:
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" `
  "/Ssigntool=signtool sign /fd SHA256 /sha1 <thumbprint> /tr http://timestamp.digicert.com /td SHA256 `$f" myapp.iss
# with SignTool=signtool and SignedUninstaller=yes in [Setup]
```

## 5. Verify and install

```powershell
signtool verify /pa /v dist\windows\MyApp-Setup-1.0.0.exe
Get-AuthenticodeSignature dist\windows\MyApp-Setup-1.0.0.exe | Format-List Status, SignerCertificate
# admin PowerShell (the user runs these):
dist\windows\MyApp-Setup-1.0.0.exe /VERYSILENT /SUPPRESSMSGBOXES /LOG="$env:TEMP\myapp-setup.log"
Get-Content "$env:TEMP\myapp-setup.log" | Select-String 'PrepareToInstall|Exec|exit code'
& "C:\Program Files\MyApp\unins000.exe" /VERYSILENT
```

## 6. Alternatives and pitfalls

- MSI needed (Intune/Group Policy): WiX Toolset; a Burn bundle (`<Chain>` with
  `<ExePackage>`/`<MsiPackage>`, `DetectCondition`) chains the vendor installer.
  Many IT departments instead deploy the prerequisite as its own package; our
  detection then skips it.
- `CloseApplications` only covers Setup; the generated `[UninstallRun]` closes
  our exes before uninstalling so their folders aren't left behind.
- Flutter Windows apps need the VC++ runtime; without it a clean PC fails with
  "VCRUNTIME140_1.dll was not found".
- Unsigned: SmartScreen "Windows protected your PC" → More info → Run anyway;
  Smart App Control and AppLocker/WDAC block it.
