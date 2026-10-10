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
;   /DCryptoSuite=<path>       Crypto Suite Manager installer to bundle
;
; Crypto Suite Manager (EKENG) is a prerequisite of YesEm Desktop. Setup
; offers it as a pre-checked task (hidden when it is already installed) and
; runs its own wizard after YesEm's files are in place; silent YesEm installs
; run it with /S (NSIS). Uninstalling YesEm leaves it alone: it is shared.

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
#ifdef CryptoSuite
Name: "cryptosuite"; Description: "Install Crypto Suite Manager (required by YesEm Desktop)"; GroupDescription: "Prerequisites:"; Check: not IsCryptoSuiteInstalled
#endif
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Flutter assets are re-copied in full on every build; drop stale ones on upgrade.
Type: filesandordirs; Name: "{app}\desktop\data\flutter_assets"
Type: filesandordirs; Name: "{app}\pincode\data\flutter_assets"

[Files]
Source: "{#SourceDir}\desktop\*"; DestDir: "{app}\desktop"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\pincode\*"; DestDir: "{app}\pincode"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef CryptoSuite
; Extracted to {tmp} only when the task is selected (see [Code]).
Source: "{#CryptoSuite}"; DestName: "Crypto_Suite_Manager_64.exe"; Flags: dontcopy
#endif

[Icons]
; Only Desktop gets shortcuts; the Pin Code Manager is started by Desktop.
Name: "{autoprograms}\YesEm Desktop"; Filename: "{app}\desktop\yesem-desktop.exe"; WorkingDir: "{app}\desktop"
Name: "{autodesktop}\YesEm Desktop"; Filename: "{app}\desktop\yesem-desktop.exe"; WorkingDir: "{app}\desktop"; Tasks: desktopicon

[Registry]
; Browser links yesem-pcm://pin?session=…&server=… open the Pin Code Manager
; (lib/shared/web_link.dart). HKA = HKLM for this per-machine install;
; uninsdeletekey removes the scheme on uninstall.
Root: HKA; Subkey: "Software\Classes\yesem-pcm"; ValueType: string; ValueName: ""; ValueData: "URL:YesEm Pin Code Manager"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\yesem-pcm"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\yesem-pcm\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\pincode\yesem-pincode.exe,0"
Root: HKA; Subkey: "Software\Classes\yesem-pcm\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pincode\yesem-pincode.exe"" ""%1"""

[Run]
Filename: "{app}\desktop\yesem-desktop.exe"; Description: "{cm:LaunchProgram,YesEm Desktop}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; CloseApplications only applies to Setup. Without this, a running app keeps
; its files locked and the uninstaller leaves the folder behind.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM yesem-desktop.exe /IM yesem-pincode.exe"; Flags: runhidden waituntilterminated; RunOnceId: "CloseYesEm"

#ifdef CryptoSuite
[Code]
const
  CryptoSuiteName = 'Crypto Suite';  { matched against DisplayName in Settings > Apps }
  UninstallKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

{ Executable of an UninstallString such as "C:\…\uninst.exe" /S or C:\…\uninst.exe }
function UninstallerPath(UninstallString: String): String;
var
  P: Integer;
begin
  Result := Trim(UninstallString);
  if Copy(Result, 1, 1) = '"' then
  begin
    Delete(Result, 1, 1);
    P := Pos('"', Result);
    if P > 0 then
      Result := Copy(Result, 1, P - 1);
  end
  else
  begin
    P := Pos('.exe', Lowercase(Result));
    if P > 0 then
      Result := Copy(Result, 1, P + 3);
  end;
end;

{ An entry counts only while its uninstaller exists: a folder deleted by hand
  leaves the registry entry behind, and CSM must then be offered again. }
function HasUninstallEntry(RootKey: Integer): Boolean;
var
  Names: TArrayOfString;
  I: Integer;
  Key, DisplayName, UninstallString: String;
begin
  Result := False;
  if RegGetSubkeyNames(RootKey, UninstallKey, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      Key := UninstallKey + '\' + Names[I];
      if RegQueryStringValue(RootKey, Key, 'DisplayName', DisplayName) and
         (Pos(Lowercase(CryptoSuiteName), Lowercase(DisplayName)) > 0) and
         RegQueryStringValue(RootKey, Key, 'UninstallString', UninstallString) and
         FileExists(UninstallerPath(UninstallString)) then
      begin
        Result := True;
        Exit;
      end;
    end;
end;

function IsCryptoSuiteInstalled: Boolean;
begin
  Result := HasUninstallEntry(HKLM32) or HasUninstallEntry(HKCU);
  if not Result and IsWin64 then
    Result := HasUninstallEntry(HKLM64);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Params: String;
  ResultCode: Integer;
begin
  if (CurStep <> ssPostInstall) or not WizardIsTaskSelected('cryptosuite') then
    Exit;
  WizardForm.StatusLabel.Caption := 'Installing Crypto Suite Manager...';
  ExtractTemporaryFile('Crypto_Suite_Manager_64.exe');
  { The user clicks through its own wizard, unless YesEm itself runs silently. }
  if WizardSilent then
    Params := '/S'
  else
    Params := '';
  if not Exec(ExpandConstant('{tmp}\Crypto_Suite_Manager_64.exe'), Params, '',
              SW_SHOW, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    SuppressibleMsgBox('Crypto Suite Manager was not installed (exit code ' + IntToStr(ResultCode) + '). ' +
      'YesEm Desktop needs it; run this setup again to install it.', mbError, MB_OK, IDOK);
end;
#endif
