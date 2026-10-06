# Windows VM bootstrap for the YesEm project.
#
# Installs Git for Windows and Claude Code, copies the project from a VMware
# shared folder (or a .zip) onto the local disk, and starts Claude Code there.
# No administrator rights needed. Run in PowerShell:
#
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\windows_bootstrap.ps1
#   .\windows_bootstrap.ps1 -Source "$env:USERPROFILE\Desktop\yesem-project.zip"
#
param(
  [string]$Source = "\\vmware-host\Shared Folders\testFlutterMObileDesktop",
  [string]$Dest = (Join-Path $env:USERPROFILE 'yesem')
)
$ErrorActionPreference = 'Stop'

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
              "$env:USERPROFILE\.local\bin"
}

# 1. Git for Windows: Flutter needs it, and it gives Claude Code its Bash tool.
if (Get-Command git -ErrorAction SilentlyContinue) {
  Write-Host "Git already installed: $(git --version)"
} else {
  Write-Host 'Installing Git for Windows…'
  winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
  Refresh-Path
}

# 2. Claude Code, native installer (Windows x64 and ARM64).
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host 'Installing Claude Code…'
  irm https://claude.ai/install.ps1 | iex
  Refresh-Path
}
Write-Host "Claude Code: $(claude --version)"

# 3. Project onto the local disk. Never build inside a shared folder.
if (Test-Path $Source -PathType Container) {
  Write-Host "Copying project from $Source to $Dest…"
  & robocopy $Source $Dest /E /XD build .dart_tool .fvm dist ephemeral .idea .claude /XF *.iml /NFL /NDL /NJH /NJS | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
} elseif ((Test-Path $Source -PathType Leaf) -and ($Source -like '*.zip')) {
  Write-Host "Extracting $Source to $Dest…"
  Expand-Archive -Path $Source -DestinationPath $Dest -Force
} else {
  Write-Warning "Project source '$Source' not found."
  Write-Warning "Share the project folder in VMware Fusion (Virtual Machine > Settings > Sharing) or copy yesem-project.zip into the VM, then rerun with -Source."
  exit 1
}
if (-not (Test-Path (Join-Path $Dest 'pubspec.yaml'))) { throw "No pubspec.yaml in $Dest; copy failed?" }

# 4. Start Claude Code in the project. The first run opens a browser to log in.
Set-Location $Dest
Write-Host ''
Write-Host "Project is at $Dest. Starting Claude Code; see tool\vm\WINDOWS_VM.md for the prompt to give it."
claude
