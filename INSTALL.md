# Install Convert

Convert adds **Convert…** to the Finder right-click menu so you can change a file's format (audio, video, images, documents, PDF) without uploading it anywhere.

**Using an AI assistant?** Paste this into it:

> Install the Convert app for macOS by following https://github.com/arielangeles/convert/blob/main/INSTALL.md exactly. Run the steps in order, show me the output of each one, and stop if a check fails.

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon or Intel. One download works on both.
- Optional: [Homebrew](https://brew.sh) `ffmpeg` for audio, video and WebP. Images, documents and PDFs work without it.

## Install (Terminal, about a minute)

Open **Terminal** (Applications › Utilities) and run these one at a time.

**1. Download the latest release and its checksum**

```bash
cd ~/Downloads && curl -fLO https://github.com/arielangeles/convert/releases/latest/download/Convert-macOS-universal.zip && curl -fLO https://github.com/arielangeles/convert/releases/latest/download/Convert-macOS-universal.zip.sha256
```

**2. Check the download is intact**

```bash
shasum -a 256 -c Convert-macOS-universal.zip.sha256
```

Expected: `Convert-macOS-universal.zip: OK`. If it says `FAILED`, delete both files and download again. Do not continue with a file that fails.

**3. Install into Applications** (replaces an older copy if there is one)

```bash
rm -rf /Applications/Convert.app && ditto -x -k Convert-macOS-universal.zip /Applications
```

No output means it worked. If you see `Permission denied`, your account isn't an administrator: install to your own Applications folder instead, and use `~/Applications/Convert.app` in place of `/Applications/Convert.app` in the next steps.

```bash
mkdir -p ~/Applications && rm -rf ~/Applications/Convert.app && ditto -x -k Convert-macOS-universal.zip ~/Applications
```

**4. Allow it to open**

Convert isn't notarized by Apple (that needs a paid developer account), so macOS may block it the first time. This removes the block for Convert only:

```bash
xattr -dr com.apple.quarantine /Applications/Convert.app
```

No output is normal (files downloaded with `curl` usually have no block to remove).

**5. Open it once**

```bash
open /Applications/Convert.app
```

A Convert window appears. Opening it once is what registers the **Convert…** menu item with Finder.

**6. Optional: add ffmpeg** for audio, video and WebP

```bash
brew install ffmpeg
```

## Use it

Right-click any file or folder in Finder › **Quick Actions** or **Services** › **Convert…**, pick a format, click Convert. The new file appears next to the original. Existing files are never overwritten.

You can also drag files onto the Convert window.

## Install without Terminal

1. Go to the [latest release](https://github.com/arielangeles/convert/releases/latest) and download `Convert-macOS-universal.zip`.
2. Double-click the zip in Downloads, then drag **Convert.app** into **Applications**.
3. Double-click Convert. macOS says it can't verify the developer. Click **Done** (not Move to Trash).
4. Open **System Settings › Privacy & Security**, scroll to the message about Convert, click **Open Anyway**, and confirm.

## Update

Quit Convert, then repeat steps 1 to 5. Step 3 replaces the old copy.

## Uninstall

```bash
rm -rf /Applications/Convert.app ~/Applications/Convert.app && /System/Library/CoreServices/pbs -update
```

Convert keeps no settings or caches elsewhere.

## Troubleshooting

| Problem | Fix |
|---|---|
| **Convert…** isn't in the right-click menu | Open Convert once, then run `/System/Library/CoreServices/pbs -update`. Still missing: System Settings › Keyboard › Keyboard Shortcuts › Services › Files and Folders, tick **Convert…**. You may need to log out and back in. |
| "Convert is damaged" or "can't be opened" | Run step 4 again with the path you installed to. |
| "ffmpeg isn't installed" when converting audio or video | `brew install ffmpeg`, then try again. No need to restart Convert. |
| `curl: (22) ... 404` in step 1 | Check your internet connection, or download from the [Releases page](https://github.com/arielangeles/convert/releases/latest) instead. |

## Check a download came from this repository (optional)

Each release is built by GitHub Actions and has a signed build provenance attestation. With the [GitHub CLI](https://cli.github.com) installed:

```bash
gh attestation verify ~/Downloads/Convert-macOS-universal.zip --repo arielangeles/convert
```

Expected: `Verification succeeded!`

## Notes for AI assistants

Follow these rules when installing Convert for someone:

- Run the numbered steps above in order. Show the user each command's output.
- Stop and tell the user if step 2 doesn't print `OK`. Never skip the checksum.
- Don't use `sudo`. If `/Applications` isn't writable, use the `~/Applications` alternative in step 3.
- Only remove the quarantine flag from `Convert.app`, as in step 4. Never turn off Gatekeeper system-wide (`spctl --master-disable` or similar).
- Ask before installing Homebrew or ffmpeg. They're optional.
- To confirm success, these should hold (adjust the path if you used `~/Applications`):
  - `codesign --verify --deep --strict /Applications/Convert.app` exits 0 with no output.
  - `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Convert.app/Contents/Info.plist` prints `dev.ariel.convert`.
  - After step 5, `pgrep -x Convert` prints a process id.
- The right-click menu item can't be checked from the command line reliably. Ask the user to right-click a file in Finder and confirm **Convert…** is there.

To build from source instead, see the [README](README.md#build).
