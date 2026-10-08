---
name: desktop-installer-creator
description: Creates installers for desktop applications on macOS (.pkg), Windows (Inno Setup setup.exe) and Ubuntu/Debian (.deb, optionally a self-extracting .run), including injecting a third-party prerequisite installer (driver, middleware, runtime) either bundled inside or downloaded from a link, and signing (Developer ID + notarization, Authenticode, APT repository GPG) or deliberately unsigned builds. Use this skill whenever the user wants to package, ship, distribute or release a desktop app, make a setup/installer/pkg/msi/deb, add a prerequisite or vendor installer to an installer, sign or notarize an installer, or asks how installers for Mac, Windows or Linux are built, even if they don't say "installer" explicitly (e.g. "how do users install my app", "bundle the middleware with our app", "make a release build people can download").
---

# Desktop installer creator

Builds a platform-native installer for an already-built desktop app, optionally
with a third-party prerequisite installed alongside it, signed or unsigned. The
work splits into four phases: **inspect → interview → generate → build & verify**.
The three decisions the interview captures (prerequisite, method, signing)
change which files get generated; guessing them produces an installer that
silently does the wrong thing, so don't skip it.

**A question isn't a build request.** If the user asks *how* installers work
or *how to* make one ("how do I make an installer people can download?"),
answer first in a few lines for their situation (formats per platform, the
steps, what signing involves, what you found in their repo) and offer to build
it. Start the interview only when they want it done.

## Phase 1: Inspect the project (before asking anything)

Answer as much as possible from the repository, so the interview only asks
what the code can't tell you:

- **Host OS** (`uname -s` / `$env:OS`). Each installer can only be built on its
  own OS: `.pkg` on macOS, `setup.exe` on Windows, `.deb` on Linux with the
  target's CPU architecture. Other platforms get generated files and a hand-off
  (Phase 4).
- **App type and build output**: Flutter (`pubspec.yaml`, `build/<os>/…`),
  Electron (`package.json` with electron-builder/forge: prefer their packagers
  unless the user wants this flow), Tauri, .NET, Qt/CMake, Xcode. Find the
  release build command and the output folder per platform.
- **Identity**: display name, version (+ build number), bundle/package ids,
  publisher, icons. Flutter: `pubspec.yaml` `version:`, `macos/Runner/Configs/*.xcconfig`,
  `windows/runner/Runner.rc`, `linux/CMakeLists.txt` `APPLICATION_ID`.
- **Several apps?** A main app plus helpers all go into one installer; note
  each one's build output and which gets the menu/Start shortcut.
- **Existing installers** (`tool/`, `installer/`, `packaging/`, CI, `*.iss`,
  `*.wxs`, `distribution.xml`, `DEBIAN/control`). If they exist, read their
  identity (bundle ids, Inno `AppId`, package name), prerequisite and signing
  hooks. **Reuse those identifiers**: changing a shipped `AppId`, bundle id or
  package name breaks upgrades. Then extend those scripts with the patterns
  from the references instead of adding the assets as a second set; use the
  assets only for platforms that have no installer yet, or when the user asks
  to replace the old scripts.
- **Release blockers**: read `CLAUDE.md`, `README.md` and release notes for
  test-only behavior (debug features, mock data, "never ship this") and raise
  it before building anything meant for real users.

## Phase 2: Interview

Use AskUserQuestion for choices (clickable options, recommended option first,
with a one-line consequence each). Collect free-form details (paths, URLs,
names, versions) in plain text as one checklist message, not as multiple-choice
questions. Ask in rounds, only what's still open. When existing installers
already answer something, show the current state and ask only what should change.

**Round 1: scope.**
- Confirm the identity you found (name, version, ids, publisher).
- Platforms: macOS, Windows, Ubuntu/Debian (multi-select). Architectures only if
  it matters (Windows/Linux x64 vs arm64; macOS builds are usually universal).
- **Who installs it and how they get it**: public download, customers' IT
  departments (MDM, Intune, SCCM), internal testers. This drives the
  recommendations below: a public download effectively needs signing; IT
  deployment favors bundling (or deploying the prerequisite separately) and
  silent installs; internal testing can stay unsigned.

**Round 2: prerequisite, per platform.** "Should the installer also install
another vendor's installer (driver, middleware, runtime)?" The answer and
method can differ per platform (vendors often ship different formats).
- **No** → Round 3.
- **Yes** → the **method** per platform, with these trade-offs:
  - *Bundle* (recommended when the vendor permits redistribution): their file
    ships inside our installer. Offline-capable, exactly the tested version;
    needs written permission, makes the installer bigger. On Linux, "bundle"
    means a self-extracting `.run` (or archive) containing both `.deb` files,
    because a `.deb` can't install another `.deb` (dpkg holds its lock).
  - *Link: download during install*: a pinned, versioned URL plus SHA-256.
    Small and license-friendly; needs internet, breaks if the URL changes,
    often blocked on managed PCs.
  - *Link shown to the user only*: no automation; the app or the installer's
    last page says where to get it.
  - Linux only: *repository*, when the prerequisite is in Ubuntu's or the
    vendor's APT repository: just `Depends:`.
- Then one plain-text checklist for the **vendor details**:
  - vendor and product name, minimum version to require;
  - the file per platform/architecture (local path for bundle, versioned URL for link);
  - bundle: confirmation that redistribution is allowed;
  - detection: macOS package id (`pkgutil --pkgs`) or app path; Windows name in
    Settings → Apps and installer type (exe/msi); Linux Debian package name;
  - silent switches and success exit codes if known (otherwise determine them:
    `references/prerequisites.md`).
  Compute SHA-256 values yourself from local files; for link mode ask where
  the vendor publishes checksums, or download once and hash it.
- The assets support **one** prerequisite per installer. With several, say so,
  and extend the generated config/code (duplicate the prerequisite block) or
  keep the existing project script that already handles them.

**Round 3: signing, per platform.** Signed or unsigned? Give the consequence
of unsigned in one line (macOS: blocked on other Macs; Windows: SmartScreen
warning, blocked on managed PCs; Linux: none for a .deb). If signed, collect
what's needed and verify it on the machine where possible:
- **macOS**: run `security find-identity -v`, let the user pick the
  `Developer ID Application: …` and `Developer ID Installer: …` identities, ask
  for the notarytool profile name and check it
  (`xcrun notarytool history --keychain-profile <name>`).
- **Windows**: how the certificate is held (cloud signing, USB token, Microsoft
  Trusted Signing), the thumbprint (or the provider's full signtool command),
  the CA's timestamp URL. Verify on the Windows build machine with
  `Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert`; from another OS, record
  the values and put that check into the hand-off.
- **Linux**: no signature for a .deb. Ask only whether they want an APT
  repository; if so, the GPG key id.

**No certificate yet?** (Common: e.g. only "Apple Development" identities, or
the Windows certificate still on order.) Don't stop. Build unsigned now with
signing left switchable (environment variables / `-SignCommand`), and point to
`references/signing.md` for obtaining it. On macOS only the team's Account
Holder can create Developer ID certificates.

Never ask the user to paste passwords, app-specific passwords, private keys or
`.p12`/`.pfx` files into the chat: they would end up in the transcript. Secrets
go into the keychain/certificate store, entered by the user (suggest
`! <command>` in Claude Code so the prompt runs in their terminal).

Before generating, summarize in a short table (platform × prerequisite method ×
signing × output file) and get a go-ahead.

## Phase 3: Generate the files

Read only the references for the chosen platforms. For platforms without an
installer, copy the assets (default `installer/<os>/`) and fill in the config;
leave the build scripts unchanged unless the project needs something they don't
support. For existing installers, edit those scripts instead (Phase 1).

| Platform | Read | Copy from `assets/` | You fill in |
|---|---|---|---|
| macOS | `references/macos.md` | `macos/build.sh`, `macos/config.sh`, `macos/resources/*.html` | `config.sh`, the two HTML pages |
| Windows | `references/windows.md` | `windows/build.ps1`, `windows/config.psd1`, `windows/installer.iss` | `config.psd1` (AppGuid: existing one, or a fresh `New-Guid` for a never-shipped app) |
| Ubuntu | `references/linux.md` | `linux/build.sh`, `linux/config.sh`, `linux/install.sh.in`, `linux/app.desktop` (rename to `<app-id>.desktop`) | `config.sh`, the launcher, a copyright file |
| Any prerequisite | `references/prerequisites.md` | — | `prereqs/README.md`, `.gitignore` entry |
| Signed builds | `references/signing.md` | — | — |

Vendor binaries go into a `prereqs/` folder next to the installer scripts (or
the project's existing one), gitignored, with a README naming file, version,
source URL and SHA-256. The build scripts refuse a file whose SHA-256 differs
from the configured one, so a changed vendor file can't slip into a release.

Rules that hold on every platform, because breaking them causes support
problems later:
- Identifiers (bundle ids, package ids, Inno `AppId`, Debian package name) are
  permanent once shipped.
- Don't re-sign or modify the vendor's files (flattening a macOS vendor
  product archive is the documented exception and needs their consent).
- Detect an existing vendor install, never downgrade it, never uninstall it
  when our app is removed.
- Signing identities and secrets come from environment variables or the
  keychain at build time, never from committed files.

## Phase 4: Build, verify, hand off

- **Current OS**: run the build script (unsigned first if signing isn't set up),
  then the verification commands from the platform reference. Report the output
  path and size, what was signed, warnings the script printed (unsigned vendor
  package, flattened product archive), and the verification results.
  Installing needs admin rights: give the user the exact command
  (`sudo installer -pkg …`, the setup.exe, `sh ….run` / `sudo apt install ./…`)
  rather than running sudo yourself.
- **Other OSes**: commit the generated files and write a hand-off for the user
  or a Claude session on that machine: tools to install, the build command, the
  checks (including the Windows certificate check), and the test plan.
- End with the **test plan** from `references/prerequisites.md` (clean
  machine, vendor already installed, newer vendor, vendor failure, offline for
  link mode, silent install, upgrade, uninstall), marking which cases you ran.

## Reference files

- `references/prerequisites.md`: bundle vs link, questions for the vendor,
  silent switches and exit codes, detection, storing vendor files, test plan, updates.
- `references/macos.md`: product archives, vendor package types, prerequisite
  modes, manual commands, verify, pitfalls.
- `references/windows.md`: Inno Setup layout, prerequisite handling in `[Code]`,
  MSI/arm64/download variants, signing hook, verify.
- `references/linux.md`: why a .deb can't contain a .deb, the delivery modes,
  `.run` with makeself, manual commands, APT repository.
- `references/signing.md`: obtaining and checking certificates per platform,
  unsigned behavior, timestamp servers, troubleshooting.
