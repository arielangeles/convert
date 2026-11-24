# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Do not open a public issue.

Include what you found, how to reproduce it, and the version you tested (`Convert.app` › Get Info, or the release tag). You can expect a first reply within a week.

## Supported versions

Only the latest release gets fixes.

## How releases are built

- Every release is built by GitHub Actions from a tagged commit (`.github/workflows/release.yml`), never on a personal machine.
- Each release zip has a SHA-256 checksum file and a signed build provenance attestation. To check that a download came from this repository's workflow:
  ```bash
  gh attestation verify Convert-macOS-universal.zip --repo arielangeles/convert
  ```
- The app is ad-hoc signed, not notarized by Apple. See [INSTALL.md](INSTALL.md) for what that means when you first open it.
- Convert works entirely on your Mac. It makes no network requests and never uploads files. Audio, video and WebP conversions run your own Homebrew `ffmpeg`.

## Automated checks

CodeQL (Swift and Actions), zizmor, actionlint, shellcheck and OpenSSF Scorecard run on every change and weekly. Dependabot keeps the pinned Actions current.
