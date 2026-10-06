# Builds the YesEm Windows installer: one setup.exe (Inno Setup 6) that puts
# both applications into C:\Program Files\YesEm\{desktop,pincode}, where
# Desktop finds the helper in the sibling pincode\ folder.
#
#   dist\windows\YesEm-Setup-<version>.exe
#
# Steps:
#   1. tool\build_desktop_bundles.ps1 (release): dist\windows\{desktop,pincode}
#   2. copy the Visual C++ runtime (msvcp140, vcruntime140, vcruntime140_1)
#      next to each .exe, so the apps start on a PC without the VC++ redist
#   3. optionally sign both .exe files
#   4. ISCC.exe tool\windows_installer\yesem.iss
#
# The architecture (arm64 or x64) is read from the built yesem-desktop.exe, so
# the same files give an arm64 installer on an ARM PC and an x64 one on x64.
#
# Signing: without -SignCommand the executables and the installer stay
# unsigned. With it, the command is used for the executables, the installer
# and its uninstaller (Inno Setup SignTool "yesem"); the file to sign is
# appended as the last argument. For example:
#
#   tool\build_windows_installer.ps1 -SignCommand 'signtool sign /fd SHA256 /sha1 <thumbprint> /tr http://timestamp.digicert.com /td SHA256'
#
# Usage: tool\build_windows_installer.ps1 [-SkipBuild] [-SignCommand '<signtool …>']
param(
  [switch]$SkipBuild,
  [string]$SignCommand
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
$out = Join-Path $root 'dist\windows'

# pubspec "version: 0.1.0+1" -> 0.1.0
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $versionLine) { throw 'No version in pubspec.yaml' }
$version = $versionLine.Matches[0].Groups[1].Value

if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'build_desktop_bundles.ps1') -Mode release
}

$apps = @(
  @{ Dir = Join-Path $out 'desktop'; Exe = 'yesem-desktop.exe' },
  @{ Dir = Join-Path $out 'pincode'; Exe = 'yesem-pincode.exe' }
)
foreach ($app in $apps) {
  $exe = Join-Path $app.Dir $app.Exe
  if (-not (Test-Path $exe)) { throw "Missing $exe (run without -SkipBuild)" }
}

# Machine type from the PE header of the built executable.
function Get-PeArch([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $pe = [BitConverter]::ToInt32($bytes, 0x3C)
  switch ([BitConverter]::ToUInt16($bytes, $pe + 4)) {
    0xAA64 { 'arm64' }
    0x8664 { 'x64' }
    default { throw "Unsupported machine type in $Path" }
  }
}
$arch = Get-PeArch (Join-Path $apps[0].Dir $apps[0].Exe)
Write-Host "== YesEm $version for $arch =="

# Visual C++ runtime from the Visual Studio (Build Tools) redist folder.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found; install Visual Studio 2022 Build Tools' }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { $vsPath = & $vswhere -latest -products * -property installationPath }
$crt = Get-ChildItem -Path (Join-Path $vsPath 'VC\Redist\MSVC') -Directory |
  Where-Object { $_.Name -match '^\d' } |
  Sort-Object { [version]$_.Name } -Descending |
  ForEach-Object { Get-ChildItem -Path (Join-Path $_.FullName $arch) -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue } |
  Select-Object -First 1
if (-not $crt) { throw "No Visual C++ $arch runtime under $vsPath\VC\Redist\MSVC" }
Write-Host "== Visual C++ runtime from $($crt.FullName) =="
foreach ($app in $apps) {
  foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item -Path (Join-Path $crt.FullName $dll) -Destination $app.Dir -Force
  }
}

function Invoke-Sign([string]$File) {
  # Start-Process passes the command line verbatim; /s keeps a quoted tool path
  # (e.g. "C:\Program Files (x86)\…\signtool.exe") intact.
  $p = Start-Process -FilePath cmd.exe -ArgumentList "/d /s /c `"$SignCommand `"$File`"`"" -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Signing failed for $File" }
}

$isccArgs = @(
  "/DAppVersion=$version",
  "/DArch=$arch",
  "/DSourceDir=$out",
  "/DOutputDir=$out"
)
if ($SignCommand) {
  foreach ($app in $apps) {
    Write-Host "== Signing $($app.Exe) =="
    Invoke-Sign (Join-Path $app.Dir $app.Exe)
  }
  # $f is Inno Setup's placeholder for the file to sign, $q a double quote
  # (literal quotes would break ISCC's own command-line parsing).
  $isccArgs += '/DSign', ("/Syesem=" + $SignCommand.Replace('"', '$q') + ' $f')
} else {
  Write-Host '== Executables and installer stay unsigned (-SignCommand not given) =='
}

$iscc = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source }
if (-not $iscc) { throw 'ISCC.exe not found; install Inno Setup 6 (winget install --id JRSoftware.InnoSetup -e)' }

$setup = Join-Path $out "YesEm-Setup-$version.exe"
if (Test-Path $setup) { Remove-Item $setup -Force }
Write-Host "== ISCC $setup =="
& $iscc @isccArgs (Join-Path $PSScriptRoot 'windows_installer\yesem.iss')
if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }
Write-Host "Done: $setup"
