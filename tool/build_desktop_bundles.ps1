# Builds YesEm Desktop and the YesEm Pin Code Manager for Windows and lays them
# out as two sibling applications:
#
#   dist\windows\desktop\yesem-desktop.exe
#   dist\windows\pincode\yesem-pincode.exe
#
# Desktop looks for the helper in the sibling pincode\ folder, so ship the two
# folders together. Run in PowerShell on Windows with Visual Studio's
# "Desktop development with C++" workload installed.
#
# With Flutter 3.47 or newer the roles are real flavors (--flavor); older SDKs
# get the same result through --dart-define=YESEM_APP=<role>.
#
# Usage: tool\build_desktop_bundles.ps1 [-Mode release|debug|profile]
param(
  [ValidateSet('release', 'debug', 'profile')]
  [string]$Mode = 'release'
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$out = 'dist\windows'
$modeDir = (Get-Culture).TextInfo.ToTitleCase($Mode)  # Release / Debug / Profile
# Flutter names the output folder after the host architecture: x64 or arm64.
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }

# Use the SDK pinned in .fvmrc when FVM is installed; otherwise `flutter` on PATH.
$useFvm = (Get-Command fvm -ErrorAction SilentlyContinue) -and (Test-Path '.fvmrc')
function Invoke-Flutter {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
  if ($useFvm) { & fvm flutter @FlutterArgs } else { & flutter @FlutterArgs }
}

# Flavors on Windows need Flutter >= 3.47.
$versionLine = (Invoke-Flutter --version | Select-String -Pattern 'Flutter (\d+)\.(\d+)' | Select-Object -First 1)
$major = [int]$versionLine.Matches[0].Groups[1].Value
$minor = [int]$versionLine.Matches[0].Groups[2].Value
$useFlavors = ($major -gt 3) -or ($major -eq 3 -and $minor -ge 47)
if ($useFlavors) { Write-Host "Flutter ${major}.${minor}: building with --flavor" }
else { Write-Host "Flutter ${major}.${minor}: no Windows flavors before 3.47, using --dart-define=YESEM_APP" }

function Build-Role([string]$Role, [string]$Exe) {
  Write-Host "== Building $Role ($Mode) =="
  if ($useFlavors) {
    Invoke-Flutter build windows "--$Mode" --flavor $Role
    $bundle = "build\windows\$arch\$Role\runner\$modeDir"
  } else {
    Invoke-Flutter build windows "--$Mode" "--dart-define=YESEM_APP=$Role"
    $bundle = "build\windows\$arch\runner\$modeDir"
  }
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed for $Role" }
  $dest = Join-Path $out $Role
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Path $dest | Out-Null
  Copy-Item -Path "$bundle\*" -Destination $dest -Recurse
  Rename-Item -Path (Join-Path $dest 'yesem.exe') -NewName $Exe
}

Build-Role -Role desktop -Exe yesem-desktop.exe
Build-Role -Role pincode -Exe yesem-pincode.exe
Write-Host "Done: $out\desktop\yesem-desktop.exe and $out\pincode\yesem-pincode.exe"
