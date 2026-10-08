; Inno Setup 6.1+ template. Compiled by build.ps1, which writes
; <WorkDir>\defines.iss (identity, version, architecture) and
; <WorkDir>\sections.iss ([Files], [Icons], [UninstallRun], prerequisite constants).
; Edit config.psd1 rather than this file; change this file only for behavior
; the config doesn't cover.

#ifndef WorkDir
  #error Build with installer\windows\build.ps1
#endif
#include AddBackslash(WorkDir) + "defines.iss"

#if Arch == "arm64"
  #define ArchAllowed "arm64"
#else
  #define ArchAllowed "x64compatible"
#endif

[Setup]
AppId={{{#AppGuid}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#InstallDirName}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed={#ArchAllowed}
ArchitecturesInstallIn64BitMode={#ArchAllowed}
MinVersion=10.0
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MainExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBase}
#ifdef SetupIcon
SetupIconFile={#SetupIcon}
#endif
#ifdef Sign
SignTool=signtool
SignedUninstaller=yes
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

#include AddBackslash(WorkDir) + "sections.iss"

[Run]
Filename: "{app}\{#MainExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  UninstallKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

var
  VendorRestart: Boolean;

{ Outside {tmp}, which Setup deletes on exit, so a failed MSI can be diagnosed. }
function VendorLog: String;
begin
  Result := ExpandConstant('{%TEMP}\') + 'vendor-install.log';
end;

{ Executable part of an UninstallString such as "C:\x\uninst.exe" /S }
function UninstallerPath(S: String): String;
var
  P: Integer;
begin
  Result := Trim(S);
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

{ Finds the vendor in Settings > Apps. An MSI entry counts as installed;
  an exe entry only while its uninstaller still exists (stale entries are
  left behind when folders are deleted by hand). }
function FindVendor(RootKey: Integer; var Version: String): Boolean;
var
  Names: TArrayOfString;
  I: Integer;
  Key, Name, Uninst: String;
begin
  Result := False;
  if not RegGetSubkeyNames(RootKey, UninstallKey, Names) then
    Exit;
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    Key := UninstallKey + '\' + Names[I];
    if RegQueryStringValue(RootKey, Key, 'DisplayName', Name) and
       (Pos(Lowercase(VendorDisplayName), Lowercase(Name)) > 0) then
    begin
      if RegQueryStringValue(RootKey, Key, 'UninstallString', Uninst) and
         (Pos('msiexec', Lowercase(Uninst)) = 0) and
         not FileExists(UninstallerPath(Uninst)) then
        Continue;
      if not RegQueryStringValue(RootKey, Key, 'DisplayVersion', Version) then
        Version := '';
      Result := True;
      Exit;
    end;
  end;
end;

function VendorNeeded: Boolean;
var
  Version: String;
  Found: Boolean;
  Installed, Required: Int64;
begin
  Result := False;
  if PrereqMode = 'none' then
    Exit;
  Found := False;
  if IsWin64 then
    Found := FindVendor(HKLM64, Version);
  if not Found then
    Found := FindVendor(HKLM32, Version);
  if not Found then
    Found := FindVendor(HKCU, Version);
  if not Found then
  begin
    Result := True;
    Exit;
  end;
  { Installed: only reinstall when older than required; unknown version: leave it. }
  if StrToVersion(Version, Installed) and StrToVersion(VendorMinVersion, Required) then
    Result := ComparePackedVersion(Installed, Required) < 0;
end;

function UseArm64Vendor: Boolean;
begin
  Result := IsArm64 and VendorHasArm64;
end;

function RunVendor(const Path: String; var Code: Integer): Boolean;
begin
  if VendorType = 'msi' then
    Result := Exec(ExpandConstant('{sys}\msiexec.exe'),
      '/i "' + Path + '" ' + VendorArgs + ' /l*v "' + VendorLog + '"',
      '', SW_SHOW, ewWaitUntilTerminated, Code)
  else
    Result := Exec(Path, VendorArgs, '', SW_SHOW, ewWaitUntilTerminated, Code);
end;

{ Runs before any of our files are copied; a non-empty result stops Setup,
  so a failed prerequisite never leaves the app half-installed. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
  Name, Url, Sha: String;
begin
  Result := '';
  if not VendorNeeded then
    Exit;
  if UseArm64Vendor then
  begin
    Name := 'vendor-arm64.' + VendorType; Url := VendorUrlArm64; Sha := VendorSha256Arm64;
  end
  else
  begin
    Name := 'vendor.' + VendorType; Url := VendorUrl; Sha := VendorSha256;
  end;

  if PrereqMode = 'bundle' then
    ExtractTemporaryFile(Name)
  else
  begin
    try
      DownloadTemporaryFile(Url, Name, Sha, nil);   { verifies the SHA-256 }
    except
      Result := VendorName + ' could not be downloaded: ' + GetExceptionMessage + #13#10 +
                'Check the internet connection, or install it from ' + Url + ' and run Setup again.';
      Exit;
    end;
  end;

  if not RunVendor(ExpandConstant('{tmp}\' + Name), Code) then
    Result := VendorName + ' could not be started: ' + SysErrorMessage(Code)
  else if (Code = 3010) or (Code = 1641) then
    VendorRestart := True
  else if Code <> 0 then
  begin
    Result := VendorName + ' was not installed (exit code ' + IntToStr(Code) + '). ' +
              '{#AppName} needs it. Fix the problem and run Setup again.';
    if VendorType = 'msi' then
      Result := Result + #13#10 + 'Installer log: ' + VendorLog;
  end;
end;

function NeedRestart: Boolean;
begin
  Result := VendorRestart;
end;
