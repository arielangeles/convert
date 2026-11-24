# Convert

Local file converter for macOS. Right-click a file or folder in Finder, choose **Convert…**, pick a format. Nothing is uploaded.

[![CI](https://github.com/arielangeles/convert/actions/workflows/ci.yml/badge.svg)](https://github.com/arielangeles/convert/actions/workflows/ci.yml)
[![Security](https://github.com/arielangeles/convert/actions/workflows/security.yml/badge.svg)](https://github.com/arielangeles/convert/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/arielangeles/convert/badge)](https://scorecard.dev/viewer/?uri=github.com/arielangeles/convert)

## Install

**[Step-by-step install guide](INSTALL.md)**, written so you can follow it yourself or hand it to your AI assistant. Short version: download `Convert-macOS-universal.zip` from the [latest release](https://github.com/arielangeles/convert/releases/latest), unzip it into Applications, clear the quarantine flag once, open it.

## Build

```bash
brew install ffmpeg          # needed for audio, video and WebP
./scripts/build.sh           # builds, signs ad-hoc, installs to ~/Applications
```

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed; the code avoids SwiftUI macros like `@State` because their plugin only ships with Xcode.

## Tests

```bash
./scripts/test.sh                    # all unit tests (Swift Testing)
./scripts/test.sh --filter Markdown  # one suite
```

Tests cover the format catalog, input classification and folder expansion, the never-overwrite and atomic-write rules, ffmpeg arguments, the Markdown renderer, the process runner (including cancellation), and real image, PDF and document conversions in a temp folder. None need ffmpeg.

## Releases

Each release has one universal build (Apple Silicon + Intel), published twice under two names: `Convert-vX.Y.Z-macOS-universal.zip`, and `Convert-macOS-universal.zip` so that `releases/latest/download/...` links keep working.

Releases are built by GitHub Actions on a macOS runner. To cut one:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

`.github/workflows/release.yml` runs the tests, builds a universal binary, stamps the tag's version into `Info.plist`, verifies the bundle, zips it with `ditto`, attests build provenance and publishes the zips plus SHA-256 checksums. `ci.yml` tests and builds every push to `main` and every PR.

The app is ad-hoc signed, not notarized; [INSTALL.md](INSTALL.md) covers the one-time Gatekeeper step.

## Security

All Actions are pinned to commit SHAs with least-privilege tokens. `security.yml` runs CodeQL (Swift and Actions), zizmor, actionlint and shellcheck on every PR and weekly; `scorecard.yml` runs OpenSSF Scorecard; Dependabot updates the pinned Actions. See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Engines

| Input | Engine | Outputs |
|---|---|---|
| Audio | ffmpeg | MP3, M4A, WAV, AIFF, FLAC, ALAC, OGG, Opus, WMA, AC3 |
| Video | ffmpeg (HEVC via VideoToolbox) | MP4, MP4 HEVC, MOV, M4V, MKV, WebM, AVI, WMV, GIF, plus any audio format |
| Images | ImageIO (in-process, keeps metadata) | JPEG, PNG, HEIC, TIFF, GIF, BMP, JPEG 2000, TGA, PSD, ICO, PDF; WebP via ffmpeg |
| Documents (DOCX, DOC, ODT, RTF, HTML, TXT, Markdown) | AppKit text system | DOCX, DOC, ODT, RTF, HTML, TXT, Web Archive, PDF |
| PDF | PDFKit | PNG/JPEG per page, multi-page TIFF, TXT |

## Behaviour

- Folders are expanded recursively; files that can't become the chosen format are skipped and counted.
- Output goes next to the original. Existing files are never overwritten (`name 2.ext`).
- Writes go to a hidden temp file first, so a failed or stopped job leaves nothing half-written.
- "Move original to Trash" only trashes after a successful conversion.
- Quality presets (High / Balanced / Small) map to CRF, bitrate or JPEG quality per engine.

## Layout

```
Sources/Convert/
  App.swift              app lifecycle, Finder service handler, windows
  ConvertView.swift      SwiftUI panel
  ConversionModel.swift  batch state, bounded concurrency, progress
  Converter.swift        engines (ffmpeg, ImageIO, AppKit text, PDFKit)
  Formats.swift          format catalog and input classification
  ProcessRunner.swift    async subprocess runner with cancellation
Resources/Info.plist     NSServices entry that adds "Convert…" to Finder
Tests/ConvertTests/      unit and engine tests (Swift Testing)
```

## Troubleshooting

See [INSTALL.md › Troubleshooting](INSTALL.md#troubleshooting).

## License

MIT. Inspired by [newtonstudios/convert](https://github.com/newtonstudios/convert); this is an independent implementation.
