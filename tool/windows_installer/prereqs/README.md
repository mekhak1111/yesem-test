# Prerequisite installers (not in git)

`tool\build_windows_installer.ps1` bundles these into `YesEm-Setup-<version>.exe`.
They are third-party binaries, so they are kept out of git: put them here by hand.

| File | What | SHA-256 |
| --- | --- | --- |
| `Crypto_Suite_Manager_64.exe` | Crypto Suite Manager 2.0.0.0 (EKENG), NSIS installer, required by YesEm Desktop | `506C66F6FD372532A165DABB42ABF3552E8952C9EC77A92738DFDA6D6B960336` |

The build script checks the hash. When EKENG ships a new version, update
`$CryptoSuiteSha256` in `tool\build_windows_installer.ps1` and the table above.
Another location can be given with `-CryptoSuiteInstaller <path>`.
