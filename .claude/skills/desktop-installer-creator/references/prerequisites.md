# Third-party prerequisites in an installer

## Contents
1. Bundle vs link
2. What to find out about the vendor installer
3. Silent switches and exit codes (Windows)
4. Detecting an existing installation
5. Storing vendor files
6. Test plan
7. Updates

## 1. Bundle vs link

| | Bundle (inside our installer) | Link: download during install | Link shown to the user only |
|---|---|---|---|
| Installer size | ours + vendor's | small | small |
| Internet during install | not needed | required; proxies/TLS inspection can break it | user needs it separately |
| Vendor version installed | exactly the tested one | the one at the URL (pin a versioned URL + SHA-256) | whatever the user picks |
| Integrity | checked once at build time (hash + vendor signature), then covered by our signature | pinned SHA-256 checked on every install (the generated scripts do this); vendor signature additionally on macOS when `PREREQ_TEAM_ID` is set, optional on Windows (see windows.md); without a check a swapped file runs as admin | not checked by us |
| Failure modes | few | URL moved/404, server down, slow, hash mismatch after a silent vendor update | user skips it; app fails later |
| License | needs vendor's written permission to redistribute | usually fine | fine |
| Vendor fixes | rebuild + re-release | change URL + hash, re-release | user installs latest |
| Notarization / AV scan | vendor content scanned as part of ours | only our code | only our code |
| IT deployment (MDM/Intune/SCCM) | one file | often blocked: no outbound downloads during install | IT deploys vendor separately (common) |
| User experience | one flow | one flow + download step | two separate installs |

Recommend **bundle** when redistribution is allowed and users may be offline or
in regulated environments; **link** when redistribution isn't allowed, the file
is very large, or the vendor publishes stable versioned URLs; **user link only**
when automation isn't possible or IT installs the prerequisite separately.

In all modes: detect first, never downgrade, never uninstall the vendor's
software when ours is removed, never re-sign their files.

## 2. What to find out about the vendor installer

Ask the vendor (or read their docs):
- Redistribution permission (bundle mode), in writing.
- Files per platform and architecture (x64, arm64, Apple Silicon/Intel).
- Silent install options and exit codes; whether a reboot may be required.
- Whether it installs drivers, services, browser extensions, udev rules.
- How to detect an installed version (registry key/DisplayName, package id, path).
- Stable per-version download URLs and published checksums (link mode).
- Who signs it (Authenticode subject, Apple Team ID).

Check the file yourself:

```sh
shasum -a 256 VendorMiddleware.pkg                  # macOS
pkgutil --check-signature VendorMiddleware.pkg      # macOS: signer + notarization
sha256sum vendor-middleware_1.2.3_amd64.deb         # Linux
dpkg-deb -I vendor-middleware_1.2.3_amd64.deb       # Package, Version, Depends
```
```powershell
Get-FileHash .\VendorMiddleware-Setup.exe -Algorithm SHA256
Get-AuthenticodeSignature .\VendorMiddleware-Setup.exe | Format-List Status, SignerCertificate
```

## 3. Silent switches and exit codes (Windows)

Identify the technology from the vendor docs, file Properties → Details, or
running it with `/?`. Test the switches on a clean VM.

| Technology | Silent | Progress, no questions | Notes |
|---|---|---|---|
| MSI | `msiexec /i x.msi /qn /norestart` | `/passive` | `/l*v log.txt`; properties as `NAME=value` |
| NSIS | `/S` | — | case-sensitive; `/D=C:\Path` last, unquoted |
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` | `/SILENT` | `/LOG="file"` |
| InstallShield | `/s`; MSI-based `/s /v"/qn"` | — | old versions need a response file (`/r`, then `/s /f1"x.iss"`) |
| WiX Burn | `/quiet /norestart` | `/passive` | `/log file.txt` |

Exit codes: `0` success, `3010` success + restart required, `1641` success +
restart started, `1602` user cancelled (MSI), `1618` another install running.
Everything else is a failure.

macOS `.pkg` and Linux `.deb` are always installed non-interactively
(`installer -pkg`, `apt-get install -y`), so no switches are needed there.

## 4. Detecting an existing installation

| Platform | Check | Command / API |
|---|---|---|
| macOS | package receipt | `pkgutil --pkg-info com.vendor.middleware` |
| macOS | app bundle version | Distribution JS: `system.files.bundleAtPath(p).CFBundleShortVersionString`; shell: `defaults read "/Applications/X.app/Contents/Info" CFBundleShortVersionString` |
| Windows | Settings → Apps entry | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` (64- and 32-bit views) and `HKCU\…`: `DisplayName`, `DisplayVersion`, `UninstallString` |
| Windows | MSI product | `UpgradeCode` / `ProductCode` from the vendor |
| Linux | Debian package | `dpkg-query -W -f='${Version}' vendor-middleware`; compare with `dpkg --compare-versions A lt B` |

Treat a Windows entry as installed only if its uninstaller still exists:
folders deleted by hand leave stale registry entries behind.

## 5. Storing vendor files

- `installer/prereqs/` with the binaries **not in git** (`.gitignore`:
  `installer/prereqs/*` and `!installer/prereqs/README.md`).
- `installer/prereqs/README.md`: file name, vendor version, source URL, SHA-256,
  date obtained, permission reference.
- The build config pins the SHA-256; the build fails on mismatch.
- Keep the originals in artifact storage so old releases can be rebuilt.

## 6. Test plan

Run on a clean VM per platform (take a snapshot first):

| Case | Expected |
|---|---|
| Clean machine | vendor installed first, then the app; app works |
| Same vendor version installed | vendor step skipped |
| Older vendor version installed | upgraded to the required version |
| Newer vendor version installed | left alone, never downgraded |
| Vendor install fails / cancelled | clear message; app not half-installed (Windows) or failure reported |
| Link mode: offline, wrong hash, 404 | clear message naming the URL; nothing unverified runs |
| Silent / managed install | works without clicks |
| Vendor requests restart (Windows) | Setup offers restart at the end |
| Upgrade our app | replaced in place; vendor not reinstalled |
| Uninstall our app | our app gone; vendor still installed |
| Downloaded copy, another machine | signed: no warnings (`spctl` accepted / "Verified publisher") |

## 7. Updates

- Our app: raise the version everywhere; never change identifiers; keep every
  released installer and test upgrading from the previous one.
- Vendor: bundle → replace the file, update SHA-256 and required version,
  retest, release. Link → new versioned URL + hash. Raise the minimum vendor
  version only when our app needs it.
- In-app updates: Sparkle (macOS), WinSparkle (Windows), an APT repository (Linux).
  Managed fleets usually disable self-updates and let IT deploy.
