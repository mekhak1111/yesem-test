# Windows installer configuration, read by build.ps1.
# Paths are relative to the project root (default: two levels above this file).
@{
  AppName        = 'MyApp'
  Publisher      = 'Example Ltd'
  # Generate once with New-Guid and never change it: upgrades and the single
  # Settings > Apps entry depend on it.
  AppGuid        = '00000000-0000-0000-0000-000000000000'
  Version        = '1.0.0'          # ignored when VersionFromPubspec is $true
  VersionFromPubspec = $false       # read "version: x.y.z+n" from pubspec.yaml
  BuildCommand   = 'flutter build windows --release'   # '' for none
  OutDir         = 'dist\windows'
  InstallDirName = 'MyApp'          # C:\Program Files\<InstallDirName>
  SetupIcon      = 'windows\runner\resources\app_icon.ico'   # '' for Inno's default
  CopyVcRuntime  = $true            # msvcp140/vcruntime140/vcruntime140_1 next to each exe

  # One entry per app. Subdir '' installs into the main folder; several apps
  # need their own Subdir. Shortcut '' means no Start menu entry.
  Apps = @(
    @{ Source = 'build\windows\x64\runner\Release'; Subdir = ''; Exe = 'myapp.exe'; Shortcut = 'MyApp' }
  )

  Prereq = @{
    Mode        = 'none'            # none | bundle | link
    Name        = 'Vendor Middleware'
    DisplayName = 'Vendor Middleware'   # substring of its Settings > Apps name (detection)
    MinVersion  = '1.2.3'           # older or missing: install; same or newer: skip
    Type        = 'exe'             # exe | msi
    Args        = '/quiet /norestart'   # silent switches (msi: msiexec adds /i and a log)
    # bundle: local files (x64 required, arm64 optional)
    File        = 'installer\prereqs\VendorMiddleware-Setup-x64.exe'
    Sha256      = ''
    FileArm64   = ''
    Sha256Arm64 = ''
    # link: versioned URLs + their SHA-256 (Sha256 / Sha256Arm64 above)
    Url         = ''
    UrlArm64    = ''
    Signer      = ''                # optional: substring of the vendor's certificate subject, e.g. 'O=Vendor Ltd'
  }
}
