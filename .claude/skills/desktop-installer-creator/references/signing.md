# Signing

## Contents
1. Summary per platform
2. macOS: Developer ID and notarization
3. Windows: Authenticode
4. Linux: APT repository GPG
5. Troubleshooting

Sign our own files and installers only; the vendor's files keep their
signatures. Never ask the user to paste passwords, private keys or
`.p12`/`.pfx` files into chat; secrets go into the keychain / certificate
store, typed by the user in their own terminal.

## 1. Summary per platform

| | macOS | Windows | Ubuntu |
|---|---|---|---|
| Certificate | Developer ID Application (apps) + Developer ID Installer (.pkg) | OV code signing (Authenticode) | none for a .deb; GPG key for an APT repo |
| Issued by | Apple (Developer Program, $99/yr); **only the Account Holder** can create Developer ID certs | a CA: DigiCert, Sectigo, SSL.com, GlobalSign (~$200–400/yr); key on USB token or cloud HSM (required since 2023) | yourself |
| Extra step | notarization + stapling | none; SmartScreen reputation builds over time (EV no longer skips it) | none |
| Unsigned build | works only on the building Mac; downloaded copies blocked by Gatekeeper | "Windows protected your PC" → More info → Run anyway; blocked by Smart App Control, AppLocker/WDAC, some AV | installs normally |
| Validity | 5 years; timestamped releases keep working | ~15 months max (renew yearly); timestamped releases keep working | key expiry you choose |

## 2. macOS: Developer ID and notarization

Obtain (once, on the Mac that will sign):
1. Keychain Access → Certificate Assistant → *Request a Certificate From a
   Certificate Authority* → email + common name, CA email empty, *Saved to disk*.
2. Account Holder: developer.apple.com → Certificates → **+** → *Developer ID
   Application* (G2 Sub-CA) with the request → download; repeat with *Developer
   ID Installer*. (Xcode → Settings → Accounts → Manage Certificates also works
   for the Account Holder.)
3. Double-click both `.cer` files (login keychain), then check:
   `security find-identity -v | grep "Developer ID"` — both must be listed; a
   certificate missing here has no private key (requested on another Mac).
4. Back up: Keychain Access → My Certificates → select both → Export → `.p12`.
5. Notarization credentials: app-specific password at account.apple.com, then
   the user runs `xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID>`.
   Check: `xcrun notarytool history --keychain-profile <profile>`.

Use: `APP_SIGN_IDENTITY`, `PKG_SIGN_IDENTITY`, `NOTARY_PROFILE` for
`assets/macos/build.sh`. First codesign use prompts for keychain access →
*Always Allow*.

Verify: `spctl -a -vv -t install x.pkg` → `accepted, source=Notarized Developer ID`;
`xcrun stapler validate x.pkg`; `codesign -dv --verbose=2 X.app` shows the
Developer ID authority, `flags=0x10000(runtime)` and a timestamp.

## 3. Windows: Authenticode

Obtain: an **OV** code signing certificate in the company's legal name; the
CA verifies the company (business register, phone; days to weeks). Prefer
**cloud signing** (DigiCert KeyLocker, SSL.com eSigner, Sectigo) for VMs and
CI; USB tokens need passthrough. Alternative: Microsoft Trusted Signing
(Azure, ~$10/month) for organizations in eligible countries (US, Canada, EU, UK
at the time of writing); signtool then uses `/dlib Azure.CodeSigning.Dlib.dll /dmdf metadata.json`.

Set up: install the provider's client or token driver; install the Windows SDK;
find the certificate:

```powershell
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject, Thumbprint, NotAfter
```

Sign command for `assets/windows/build.ps1 -SignCommand`:
`signtool sign /fd SHA256 /sha1 <thumbprint> /tr <timestamp URL> /td SHA256`
Timestamp URLs: DigiCert `http://timestamp.digicert.com`, Sectigo
`http://timestamp.sectigo.com`, SSL.com `http://ts.ssl.com`, GlobalSign
`http://timestamp.globalsign.com/tsa/r6advanced1`.

Verify: `signtool verify /pa /v file.exe`; Properties → Digital Signatures
shows the company and a timestamp; the UAC prompt shows "Verified publisher".

## 4. Linux: APT repository GPG

Only for an APT repository (a downloaded .deb needs no signature; publish its
SHA-256 next to it).

```sh
gpg --full-generate-key                                   # RSA 4096 or ECC, with expiry
gpg --list-secret-keys --keyid-format long                # key id
gpg --armor --export-secret-keys <KEYID> > repo-private.asc   # backup, keep secret
gpg --armor --export <KEYID> > repo.asc                   # publish
```

`repo/conf/distributions`:
```
Origin: Example
Label: Example
Codename: stable
Architectures: amd64 arm64
Components: main
SignWith: <KEYID>
```
`reprepro -b repo includedeb stable dist/linux/myapp_1.0.0-1_amd64.deb`, then
host `repo/dists`, `repo/pool`, `repo.asc` over HTTPS. Users add it with a
`signed-by=` keyring as shown in `linux.md`.

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| macOS: "This operation can only be performed by the Account Holder" | Developer ID needs the Account Holder; send them the certificate request |
| macOS: identity in Keychain Access but not in `find-identity` | no private key on this Mac; request again from this Mac or import the `.p12` |
| macOS: `errSecInternalComponent` | keychain locked / access denied: `security unlock-keychain ~/Library/Keychains/login.keychain-db`, Always Allow |
| macOS: notarization "Invalid" | `xcrun notarytool log <id> --keychain-profile <p>`: unsigned nested code, missing hardened runtime or timestamp, vendor binaries not Developer ID signed |
| macOS: "timestamp service is not available" | needs internet; retry; check proxy |
| Windows: "No certificates were found that met all the given criteria" | wrong thumbprint, provider client not logged in, token not plugged in |
| Windows: timestamp error | timestamp URL unreachable (proxy/firewall); use `http://` as documented |
| Windows: still SmartScreen warning when signed | new certificate has no reputation yet; it fades with installs |
| Linux: `NO_PUBKEY` / repository not signed | user's keyring missing or wrong `signed-by=` path |
