## Install

1. Download `Convert-*-macOS-universal.zip`, unzip it, and move **Convert.app** to `/Applications`.
2. The app is ad-hoc signed, not notarized, so macOS will block the first launch. Clear the quarantine flag once:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Convert.app
   ```
3. Open Convert once so macOS registers the Finder menu item, then right-click any file › **Convert…**
4. Audio, video and WebP need ffmpeg: `brew install ffmpeg`

Optional: verify the download with the `.sha256` file (`shasum -a 256 -c Convert-*.zip.sha256`).
