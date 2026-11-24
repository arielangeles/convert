# Convert

Local file converter for macOS. Right-click a file or folder in Finder, choose **Convert…**, pick a format. Nothing is uploaded.

## Build

```bash
brew install ffmpeg          # needed for audio, video and WebP
./scripts/build.sh           # builds, signs ad-hoc, installs to ~/Applications
```

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed; the code avoids SwiftUI macros like `@State` because their plugin only ships with Xcode.

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
```

## Troubleshooting

If **Convert…** doesn't show in the right-click menu: System Settings › Keyboard › Keyboard Shortcuts › Services › Files and Folders, enable **Convert…**. Then run `/System/Library/CoreServices/pbs -update`.

## License

MIT. Inspired by [newtonstudios/convert](https://github.com/newtonstudios/convert); this is an independent implementation.
