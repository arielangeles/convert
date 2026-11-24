## Install

Full step-by-step guide (works with an AI assistant too): [INSTALL.md](https://github.com/arielangeles/convert/blob/main/INSTALL.md)

Quick version, in Terminal:

```bash
cd ~/Downloads && curl -fLO https://github.com/arielangeles/convert/releases/latest/download/Convert-macOS-universal.zip && curl -fLO https://github.com/arielangeles/convert/releases/latest/download/Convert-macOS-universal.zip.sha256
shasum -a 256 -c Convert-macOS-universal.zip.sha256
rm -rf /Applications/Convert.app && ditto -x -k Convert-macOS-universal.zip /Applications
xattr -dr com.apple.quarantine /Applications/Convert.app
open /Applications/Convert.app
```

Then right-click any file in Finder › **Convert…**. Audio, video and WebP need ffmpeg: `brew install ffmpeg`.

The app is ad-hoc signed, not notarized, which is why the `xattr` step is there. `Convert-macOS-universal.zip` and the versioned zip are the same file. Both have a SHA-256 checksum and a build provenance attestation (`gh attestation verify Convert-macOS-universal.zip --repo arielangeles/convert`).
