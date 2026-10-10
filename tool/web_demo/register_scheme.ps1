# Registers the yesem-pcm:// scheme for a development build of the Pin Code
# Manager (current user only, no admin), so the browser demo (tool\web_demo)
# works without installing. The installer (tool\windows_installer\yesem.iss)
# registers it per machine itself.
#
#   tool\web_demo\register_scheme.ps1 [-Exe <path\to\yesem-pincode.exe>]
#   tool\web_demo\register_scheme.ps1 -Unregister
param(
  [string]$Exe,
  [switch]$Unregister
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')
$key = 'HKCU:\Software\Classes\yesem-pcm'

if ($Unregister) {
  Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Removed yesem-pcm:// for the current user.'
  return
}
if (-not $Exe) {
  $Exe = @('dist\windows\pincode\yesem-pincode.exe') +
    (Get-ChildItem 'build\windows\*\pincode\runner\*\yesem.exe' -ErrorAction SilentlyContinue | ForEach-Object FullName) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Exe -or -not (Test-Path $Exe)) {
  throw 'Build it first: tool\build_desktop_bundles.ps1 (or pass -Exe)'
}
$Exe = (Resolve-Path $Exe).Path

New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $key -Name '(default)' -Value 'URL:YesEm Pin Code Manager (dev)'
Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
# --yesem-role keeps a renamed or unflavored build in helper role.
Set-ItemProperty -Path "$key\shell\open\command" -Name '(default)' -Value "`"$Exe`" --yesem-role=pincode `"%1`""
Write-Host "Registered yesem-pcm:// for $Exe"
Write-Host 'Test: start "yesem-pcm://pin?session=test1234&server=http%3A%2F%2F127.0.0.1%3A8787"'
