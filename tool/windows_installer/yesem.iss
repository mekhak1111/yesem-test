; Inno Setup 6 script for the YesEm Windows installer: one setup.exe that
; installs both applications per machine, each in its own folder:
;
;   C:\Program Files\YesEm\desktop\yesem-desktop.exe
;   C:\Program Files\YesEm\pincode\yesem-pincode.exe
;
; Desktop finds the helper through the sibling pincode\ folder
; (PinCodeManagerLocator), exactly as in dist\windows\.
;
; Compile through tool\build_windows_installer.ps1, which passes:
;   /DAppVersion=<x.y.z>       from pubspec.yaml
;   /DArch=arm64|x64           from the built executables
;   /DSourceDir=<dist\windows> folder holding desktop\ and pincode\
;   /DOutputDir=<dist\windows> where YesEm-Setup-<version>.exe goes
;   /DSign /Syesem=<command>   only when signing (-SignCommand)

#ifndef AppVersion
  #error AppVersion is not defined; build with tool\build_windows_installer.ps1
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\windows"
#endif
#ifndef OutputDir
  #define OutputDir SourceDir
#endif

#if Arch == "arm64"
  #define ArchAllowed "arm64"
#else
  #define ArchAllowed "x64compatible"
#endif

[Setup]
; Never change AppId: upgrades and the single entry in Settings > Apps depend on it.
AppId={{D98ED91B-9264-45B8-991E-87A451F30A99}
AppName=YesEm
AppVersion={#AppVersion}
AppVerName=YesEm {#AppVersion}
AppPublisher=Volo
VersionInfoVersion={#AppVersion}
VersionInfoProductName=YesEm
VersionInfoCompany=Volo
DefaultDirName={autopf}\YesEm
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed={#ArchAllowed}
ArchitecturesInstallIn64BitMode={#ArchAllowed}
MinVersion=10.0
CloseApplications=yes
RestartApplications=no
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\desktop\yesem-desktop.exe
UninstallDisplayName=YesEm
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=YesEm-Setup-{#AppVersion}
#ifdef Sign
SignTool=yesem
SignedUninstaller=yes
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Flutter assets are re-copied in full on every build; drop stale ones on upgrade.
Type: filesandordirs; Name: "{app}\desktop\data\flutter_assets"
Type: filesandordirs; Name: "{app}\pincode\data\flutter_assets"

[Files]
Source: "{#SourceDir}\desktop\*"; DestDir: "{app}\desktop"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\pincode\*"; DestDir: "{app}\pincode"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Only Desktop gets shortcuts; the Pin Code Manager is started by Desktop.
Name: "{autoprograms}\YesEm Desktop"; Filename: "{app}\desktop\yesem-desktop.exe"; WorkingDir: "{app}\desktop"
Name: "{autodesktop}\YesEm Desktop"; Filename: "{app}\desktop\yesem-desktop.exe"; WorkingDir: "{app}\desktop"; Tasks: desktopicon

[Run]
Filename: "{app}\desktop\yesem-desktop.exe"; Description: "{cm:LaunchProgram,YesEm Desktop}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; CloseApplications only applies to Setup. Without this, a running app keeps
; its files locked and the uninstaller leaves the folder behind.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM yesem-desktop.exe /IM yesem-pincode.exe"; Flags: runhidden waituntilterminated; RunOnceId: "CloseYesEm"
