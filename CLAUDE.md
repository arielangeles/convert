# Convert

Local file converter for macOS. Adds **Convert…** to Finder's right-click menu (NSServices), converts on-device, never uploads. Inspired by newtonstudios/convert, independent implementation. MIT.

Repo: github.com/arielangeles/convert. Local: `~/code/personal/convert`.

## Build and run

```bash
./scripts/build.sh               # build, ad-hoc sign, install to ~/Applications, register Finder service
./scripts/build.sh --no-install  # build only, output in build/Convert.app
UNIVERSAL=1 VERSION=1.2.0 BUILD_NUMBER=7 ./scripts/build.sh --no-install   # what CI does
./scripts/test.sh                # unit tests; extra args go to swift test (--filter X)
```

- SwiftPM executable target, macOS 13+, Swift 5 language mode. The script assembles the .app bundle by hand (no Xcode project).
- The owner's Mac has **Command Line Tools only, no full Xcode**. That shapes the code:
  - **Do not use SwiftUI macros** (`@State`, `@Observable`, `#Preview`, `@Entry`). Their plugin (`SwiftUIMacros`) ships only with Xcode, so the build fails with "external macro implementation type could not be found". Keep view state in `ConversionModel` as `@Published` properties instead.
  - `UNIVERSAL=1` (arm64 + x86_64) needs full Xcode; it works in CI, not on the owner's Mac.
  - Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest: XCTest ships only with Xcode. Run them through `scripts/test.sh`, which passes `-plugin-path .../host/plugins/testing` on CLT. Without it the default build system can fail with "plugin for module 'TestingMacros' not found" (it did on 2026-11-24 after first working). `--build-system native` is worse: "no such module 'Testing'".
- The two `ld: warning: search path ... not found` lines on local builds are harmless CLT noise.
- `build.sh` runs under macOS `/bin/bash` 3.2 locally: no associative arrays, guard empty-array expansion under `set -u` with `${arr[@]+"${arr[@]}"}`, and wrap a variable in braces when non-ASCII text follows it (`${INSTALL_DIR}…`; the owner's shell is not UTF-8, and `$INSTALL_DIR…` broke once).
- ffmpeg (Homebrew) is required at runtime for audio, video and WebP. `ToolLocator` checks `/opt/homebrew/bin`, `/usr/local/bin`, `~/.homebrew/bin`, then a login shell, because GUI apps don't inherit PATH.
- Homebrew's ffmpeg (9.x) is built **without libvorbis and libwebp**. OGG falls back to ffmpeg's native `vorbis` encoder (experimental, stereo only) via `FFmpeg.encoders()`. WebP output currently has no working encoder on such a Mac (ImageIO can't write WebP on macOS 27 either).

## Layout

| File | Role |
|---|---|
| `Sources/Convert/App.swift` | Manual `NSApplication` entry (`@main enum`), `AppDelegate` (`@MainActor`), NSServices handler `convertFiles(_:userData:error:)`, Open With, AppKit windows hosting SwiftUI |
| `Sources/Convert/ConvertView.swift` | SwiftUI panel: drop zone, format picker, Advanced (quality), Move to Trash, progress, results |
| `Sources/Convert/ConversionModel.swift` | Batch state, folder expansion, TaskGroup with bounded concurrency (2 for audio/video, 4 otherwise), aggregated progress, cancel |
| `Sources/Convert/Converter.swift` | Engines: `FFmpeg` (audio/video, progress via `-progress pipe:1` and ffprobe duration), `ImageConverter` (ImageIO in-process, WebP via ffmpeg), `DocumentConverter` (`@MainActor`, NSAttributedString, PDF via NSPrintOperation), `Markdown` (small block renderer), `PDFConverter` (PDFKit) |
| `Sources/Convert/Formats.swift` | Output format catalog, input classification by extension then UTType, folder expansion |
| `Sources/Convert/ProcessRunner.swift` | Async `Process` wrapper: reads both pipes to EOF with `read(2)` on background threads (live progress lines, no lost output), stderr tail for errors, Stop = own cancel flag (ffmpeg exits non-zero on SIGTERM instead of dying from it) |
| `Resources/Info.plist` | Bundle id `dev.ariel.convert`, `NSServices` (menu item "Convert…", `NSRequiredContext` so it's on by default), document types at `Alternate` rank |
| `scripts/build.sh` | Build, assemble, sign, install, register (`lsregister`, `pbs -update`) |
| `scripts/test.sh` | `swift test` with the CLT plugin-path workaround |
| `Tests/ConvertTests/` | Swift Testing suites. `TestSupport.swift` has `TempDir` (self-deleting), `png()` fixture, `format(id)` lookup |
| `.github/workflows/ci.yml` | Tests, universal build + bundle checks on push to main and PRs (macos-15) |
| `.github/workflows/release.yml` | On `vX.Y.Z` tags or manual dispatch: test, build universal, stamp version, verify, `ditto` zip (versioned + fixed `Convert-macOS-universal.zip`), provenance attestation, `gh release` with SHA-256 |
| `.github/workflows/security.yml` | actionlint + shellcheck, zizmor, CodeQL (Swift on macos-15, Actions on ubuntu) on PRs, main and weekly. On PRs, CodeQL Swift only runs when `Sources/`, `Tests/`, `Package.*` or `security.yml` change (skipped jobs still satisfy the required check); it takes ~13 min, almost all extractor time in `swift build` |
| `.github/workflows/scorecard.yml` | OpenSSF Scorecard, results to code scanning |
| `INSTALL.md` | End-user install guide, also written for AI assistants to follow. Keep its commands in sync with `release.yml` asset names |

## Invariants (keep these)

- Never overwrite: outputs go next to the input as `name.ext`, then `name 2.ext`, etc. (`Converter.uniqueOutputURL`).
- Atomic writes: write to a hidden `.convert-<uuid>.ext` temp beside the destination, then move. Failure or cancel removes the temp.
- Trash the original only after a successful conversion, and only when the user ticked the option.
- AppKit text/printing work stays on the main actor (`DocumentConverter`). Use `atomicWriteSync` there, not the async closure version.
- New output format: add it to `FormatCatalog`, then handle its `id` in the right engine (`FFmpeg.codecArgs`, `ImageConverter.utTypes`, etc.). Add the input UTI to `NSSendFileTypes` in Info.plist if it's a new input type.

## Verifying changes

Run `./scripts/test.sh`. New logic gets a test; engine tests write into a `TempDir`. Tests that need ffmpeg go in a suite marked `.enabled(if: ToolLocator.find("ffmpeg") != nil)` (see `VideoConversionTests`), because CI has no ffmpeg; run them locally before merging engine changes. For UI and Finder behaviour, check by hand: build, put sample files in `build/verify/` (git-ignored), right-click › Convert… in Finder, then check the outputs (`file`, `ffprobe`, open the PDF). If the menu item is missing, run `/System/Library/CoreServices/pbs -update` or enable it under System Settings › Keyboard › Keyboard Shortcuts › Services.

## Conventions

- Commits: imperative subject, short body explaining why.
- Branch for changes and open a PR; CI must be green before merging to main.
- Workflows: pin every action to a full commit SHA with a `# vX.Y.Z` comment, `permissions: {}` at the top and per-job grants, `persist-credentials: false` on checkout, and pass `${{ }}` values to `run:` through `env:`. zizmor and actionlint enforce most of this.
- No em dashes in docs or release notes (owner preference).
