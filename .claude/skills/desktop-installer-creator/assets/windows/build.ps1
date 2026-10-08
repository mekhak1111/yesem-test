# Builds a Windows installer (Inno Setup 6.1+) from config.psd1: one setup.exe
# that installs the app(s) per machine and, optionally, a third-party
# prerequisite (bundled inside or downloaded during install).
#
#   installer\windows\build.ps1 [-SkipBuild] [-SignCommand '<signtool sign …>'] [-ProjectRoot <dir>]
#
# Without -SignCommand everything stays unsigned. With it, the command signs
# our executables, setup.exe and its uninstaller; the file name is appended:
#   -SignCommand 'signtool sign /fd SHA256 /sha1 <thumbprint> /tr http://timestamp.digicert.com /td SHA256'
param(
  [switch]$SkipBuild,
  [string]$SignCommand,
  [string]$ProjectRoot,
  [string]$Config = (Join-Path $PSScriptRoot 'config.psd1')
)
$ErrorActionPreference = 'Stop'
$cfg = Import-PowerShellDataFile $Config
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
Set-Location $ProjectRoot
$out = Join-Path $ProjectRoot $cfg.OutDir
$stage = Join-Path $out 'stage'
$work = Join-Path $out 'work'
$p = $cfg.Prereq

function Fail([string]$msg) { throw "error: $msg" }
function PasStr([string]$s) { "'" + ($s -replace "'", "''") + "'" }   # Pascal string literal

# --- version -----------------------------------------------------------------
$version = $cfg.Version
if ($cfg.VersionFromPubspec) {
  $m = Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
  if (-not $m) { Fail 'no version in pubspec.yaml' }
  $version = $m.Matches[0].Groups[1].Value
}

# --- 1. build ------------------------------------------------------------------
if (-not $SkipBuild -and $cfg.BuildCommand) {
  Write-Host "== $($cfg.BuildCommand) =="
  & cmd.exe /d /c $cfg.BuildCommand
  if ($LASTEXITCODE -ne 0) { Fail 'build failed' }
}

# --- 2. stage apps ---------------------------------------------------------------
Remove-Item $stage, $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage, $work | Out-Null
foreach ($a in $cfg.Apps) {
  $exe = Join-Path $a.Source $a.Exe
  if (-not (Test-Path $exe)) { Fail "missing $exe (build first, or fix Apps in config.psd1)" }
  $dest = if ($a.Subdir) { Join-Path $stage $a.Subdir } else { $stage }
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item -Path (Join-Path $a.Source '*') -Destination $dest -Recurse -Force
}

function Get-PeArch([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $pe = [BitConverter]::ToInt32($bytes, 0x3C)
  switch ([BitConverter]::ToUInt16($bytes, $pe + 4)) {
    0xAA64 { 'arm64' } 0x8664 { 'x64' } default { Fail "unsupported machine type in $Path" }
  }
}
$first = $cfg.Apps[0]
$mainRel = if ($first.Subdir) { "$($first.Subdir)\$($first.Exe)" } else { $first.Exe }
$arch = Get-PeArch (Join-Path $stage $mainRel)
Write-Host "== $($cfg.AppName) $version for $arch =="

if ($cfg.CopyVcRuntime) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path $vswhere)) { Fail 'vswhere.exe not found; install Visual Studio 2022 Build Tools' }
  $vs = & $vswhere -latest -products * -property installationPath
  $crt = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory | Where-Object { $_.Name -match '^\d' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Get-ChildItem (Join-Path $_.FullName $arch) -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue } |
    Select-Object -First 1
  if (-not $crt) { Fail "no Visual C++ $arch runtime in $vs" }
  foreach ($a in $cfg.Apps) {
    $dest = if ($a.Subdir) { Join-Path $stage $a.Subdir } else { $stage }
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
      Copy-Item (Join-Path $crt.FullName $dll) $dest -Force
    }
  }
}

function Invoke-Sign([string]$File) {
  $proc = Start-Process cmd.exe -ArgumentList "/d /s /c `"$SignCommand `"$File`"`"" -NoNewWindow -Wait -PassThru
  if ($proc.ExitCode -ne 0) { Fail "signing failed for $File" }
}
if ($SignCommand) {
  foreach ($a in $cfg.Apps) {
    $rel = if ($a.Subdir) { "$($a.Subdir)\$($a.Exe)" } else { $a.Exe }
    Write-Host "== signing $rel =="; Invoke-Sign (Join-Path $stage $rel)
  }
}

# --- 3. prerequisite ---------------------------------------------------------------
function Test-Vendor([string]$File, [string]$Sha) {
  if (-not (Test-Path $File)) { Fail "missing $File (see installer\prereqs\README.md)" }
  if (-not $Sha) { Fail "no SHA-256 configured for $File" }
  $got = (Get-FileHash $File -Algorithm SHA256).Hash
  if ($got -ne $Sha.ToUpper()) { Fail "SHA-256 of $File is $got, expected $Sha" }
  $sig = Get-AuthenticodeSignature $File
  Write-Host "   $File : signature $($sig.Status), $($sig.SignerCertificate.Subject)"
  if ($p.Signer -and ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike "*$($p.Signer)*")) {
    Fail "$File is not validly signed by '$($p.Signer)'"
  }
}
$ext = if ($p.Type -eq 'msi') { 'msi' } else { 'exe' }
$hasArm64 = $false
switch ($p.Mode) {
  'none' { }
  'bundle' {
    Test-Vendor $p.File $p.Sha256
    if ($p.FileArm64) { Test-Vendor $p.FileArm64 $p.Sha256Arm64; $hasArm64 = $true }
  }
  'link' {
    if (-not $p.Url -or -not $p.Sha256) { Fail 'link mode needs Prereq.Url and Prereq.Sha256' }
    if ($p.UrlArm64) { if (-not $p.Sha256Arm64) { Fail 'Prereq.UrlArm64 needs Sha256Arm64' }; $hasArm64 = $true }
  }
  default { Fail "unknown Prereq.Mode $($p.Mode)" }
}

# --- 4. generated Inno Setup includes -------------------------------------------------
$defines = @(
  "#pragma parseroption -p+",   # backslashes in strings are literal
  "#define Generated",
  "#define AppName `"$($cfg.AppName)`"",
  "#define AppPublisher `"$($cfg.Publisher)`"",
  "#define AppGuid `"$($cfg.AppGuid)`"",
  "#define AppVersion `"$version`"",
  "#define Arch `"$arch`"",
  "#define InstallDirName `"$($cfg.InstallDirName)`"",
  "#define MainExe `"$mainRel`"",
  "#define OutputDir `"$out`"",
  "#define OutputBase `"$($cfg.AppName -replace '\s','')-Setup-$version`""
)
if ($cfg.SetupIcon) { $defines += "#define SetupIcon `"$((Resolve-Path $cfg.SetupIcon).Path)`"" }
if ($SignCommand) { $defines += '#define Sign' }
Set-Content (Join-Path $work 'defines.iss') $defines -Encoding UTF8

$sections = @('[Files]')
foreach ($a in $cfg.Apps) {
  $src = if ($a.Subdir) { Join-Path $stage $a.Subdir } else { $stage }
  $dst = if ($a.Subdir) { "{app}\$($a.Subdir)" } else { '{app}' }
  $exclude = if ($a.Subdir) { '' } else { ($cfg.Apps | Where-Object { $_.Subdir } | ForEach-Object { "$($_.Subdir)\*" }) -join ',' }
  $line = "Source: `"$src\*`"; DestDir: `"$dst`"; Flags: ignoreversion recursesubdirs createallsubdirs"
  if ($exclude) { $line += "; Excludes: `"$exclude`"" }
  $sections += $line
}
if ($p.Mode -eq 'bundle') {
  $sections += "Source: `"$((Resolve-Path $p.File).Path)`"; DestName: `"vendor.$ext`"; Flags: dontcopy"
  if ($hasArm64) { $sections += "Source: `"$((Resolve-Path $p.FileArm64).Path)`"; DestName: `"vendor-arm64.$ext`"; Flags: dontcopy" }
}
$sections += '', '[Icons]'
$firstShortcut = $true
foreach ($a in $cfg.Apps | Where-Object { $_.Shortcut }) {
  $rel = if ($a.Subdir) { "$($a.Subdir)\$($a.Exe)" } else { $a.Exe }
  $wd = if ($a.Subdir) { "{app}\$($a.Subdir)" } else { '{app}' }
  $sections += "Name: `"{autoprograms}\$($a.Shortcut)`"; Filename: `"{app}\$rel`"; WorkingDir: `"$wd`""
  if ($firstShortcut) {
    $sections += "Name: `"{autodesktop}\$($a.Shortcut)`"; Filename: `"{app}\$rel`"; WorkingDir: `"$wd`"; Tasks: desktopicon"
    $firstShortcut = $false
  }
}
$exes = ($cfg.Apps | ForEach-Object { "/IM $($_.Exe)" }) -join ' '
$sections += '', '[UninstallRun]',
  "Filename: `"{sys}\taskkill.exe`"; Parameters: `"/F $exes`"; Flags: runhidden waituntilterminated; RunOnceId: `"CloseApps`""
$sections += '', '[Code]', 'const',
  "  PrereqMode = $(PasStr $p.Mode);",
  "  VendorName = $(PasStr $p.Name);",
  "  VendorDisplayName = $(PasStr $p.DisplayName);",
  "  VendorMinVersion = $(PasStr $p.MinVersion);",
  "  VendorType = $(PasStr $ext);",
  "  VendorArgs = $(PasStr $p.Args);",
  "  VendorUrl = $(PasStr $p.Url);",
  "  VendorSha256 = $(PasStr ([string]$p.Sha256).ToLower());",
  "  VendorUrlArm64 = $(PasStr $p.UrlArm64);",
  "  VendorSha256Arm64 = $(PasStr ([string]$p.Sha256Arm64).ToLower());",
  "  VendorHasArm64 = $(if ($hasArm64) { 'True' } else { 'False' });"
Set-Content (Join-Path $work 'sections.iss') $sections -Encoding UTF8

# --- 5. compile ------------------------------------------------------------------------
$iscc = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { Fail 'ISCC.exe not found; winget install --id JRSoftware.InnoSetup -e' }

$isccArgs = @("/DWorkDir=$work")
if ($SignCommand) { $isccArgs += ("/Ssigntool=" + $SignCommand.Replace('"', '$q') + ' $f') }
Write-Host "== ISCC =="
& $iscc @isccArgs (Join-Path $PSScriptRoot 'installer.iss')
if ($LASTEXITCODE -ne 0) { Fail 'ISCC failed' }
$setup = Join-Path $out "$($cfg.AppName -replace '\s','')-Setup-$version.exe"
Write-Host "Done: $setup"
if ($SignCommand) { Get-AuthenticodeSignature $setup | Format-List Status, SignerCertificate }
