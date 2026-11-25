# Security policy

## Reporting a vulnerability

Please report security vulnerabilities privately using GitHub's private vulnerability reporting:

**https://github.com/arielangeles/convert/security/advisories/new**

Do not open a public issue for a vulnerability. Include what you found, how to reproduce it, and the version you tested (`Convert.app` › Get Info, or the release tag).

## Disclosure process

- You get an acknowledgement within 7 days.
- Confirmed issues are fixed in a new release, normally within 30 days, and published as a GitHub security advisory that credits you unless you prefer otherwise.
- Please keep the details private until the fix is released or 90 days have passed, whichever comes first.

## Supported versions

Only the latest release gets security fixes.

## How releases are built

- Every release is built by GitHub Actions from a tagged commit (`.github/workflows/release.yml`), never on a personal machine.
- Each release has SHA-256 checksum files and a signed build provenance attestation. The attestation is also attached to the release as `Convert-vX.Y.Z-provenance.sigstore.json`. To check that a download came from this repository's workflow:
  ```bash
  gh attestation verify Convert-macOS-universal.zip --repo arielangeles/convert
  ```
  Or offline, with the bundle from the release:
  ```bash
  gh attestation verify Convert-macOS-universal.zip --repo arielangeles/convert --bundle Convert-v1.0.0-provenance.sigstore.json
  ```
- The app is ad-hoc signed, not notarized by Apple. See [INSTALL.md](INSTALL.md) for what that means when you first open it.
- Convert works entirely on your Mac. It makes no network requests and never uploads files. Audio, video and WebP conversions run your own Homebrew `ffmpeg`.

## Automated checks

CodeQL (Swift and Actions), zizmor, actionlint, shellcheck and OpenSSF Scorecard run on every change and weekly. Dependabot keeps the pinned Actions current.
