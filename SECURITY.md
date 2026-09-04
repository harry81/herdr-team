# Security Policy

## Supported versions

Only the latest `main` commit and the latest GitHub Release are supported.
Please upgrade before reporting.

## Reporting a vulnerability

**Do not open a public issue.** Email the maintainer privately
(see the GitHub profile of `harry81`) with:

- Affected commit/tag and platform (Linux / macOS / Windows WSL / Git-Bash)
- Steps to reproduce and impact assessment

You will get a first response within 7 days. Once fixed, a release will credit
you unless you ask to stay anonymous.

## Scope notes

- `install.sh` writes symlinks and appends one PATH block to shell rc files —
  review `install.sh` before piping it to `bash`.
- The Windows `.bat` launchers never auto-install anything; dependency setup is
  always manual (`winget` / `wsl --install`) by design.
