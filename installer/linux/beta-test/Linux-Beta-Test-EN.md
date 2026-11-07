# StemMaker for Linux (beta) – test guide

Thanks for trying the Linux version of StemMaker! It is a **beta**: the regular Windows version, running from a single file (AppImage) with a built-in Wine. You don't need to install anything, not even Wine.

Time needed: about 20–30 minutes.

## What you need
- A 64-bit Linux (tested: Ubuntu 24.04, Debian 12, Fedora, Arch)
- About 1 GB of free space (program + model downloaded on first start)
- Internet on first start
- One or two songs of your own (MP3, FLAC or WAV)

## 1. Download and start
1. Unzip **StemMaker-2.2.1-beta1-Linux-Test.zip** (download: https://github.com/Elospeed/StemMaker/releases/tag/v2.2.1-linux-beta1). It contains the AppImage, this guide (DE/EN) and `SHA256SUMS.txt` for checking (`sha256sum -c SHA256SUMS.txt`).
2. Make it executable: right-click → Properties → allow "Run as program". Or in a terminal:
   ```
   chmod +x StemMaker-2.2.1-beta1-x86_64.AppImage
   ./StemMaker-2.2.1-beta1-x86_64.AppImage
   ```
3. If it doesn't start and mentions **FUSE**: on Ubuntu 24.04 run `sudo apt install libfuse2t64`, on older Ubuntu/Debian `sudo apt install libfuse2`.

The first start takes longer (Wine sets itself up, about 30 s). Your data is stored in `~/.local/share/StemMaker-Wine/`.

## 2. What to check

| # | Test | What to look for |
|---|---|---|
| 1 | **First start** | Language choice, license note, model download all complete? |
| 2 | **Window** | Everything readable, nothing cut off? Can you **minimize**, maximize and resize the window? Does the dock/taskbar show the StemMaker icon? |
| 3 | **Conversion** | Add a song ("Add files" or drag it into the window) and convert it. Does it finish? How long did it take (shown in the log)? |
| 4 | **Drag & drop** | Drag a file from your file manager into StemMaker. Does it work? |
| 5 | **StemPlayer** | Click the StemPlayer tile on the right, open the finished .stem.mp4 and play it. Do you get **sound**? Does it crackle or stutter? Try muting tracks and loop A-B. |
| 6 | **StemTagger** | Click the StemTagger tile, open the .stem.mp4, change e.g. the genre, save, open again: is the change still there? |
| 7 | **Turbo (optional)** | Switch on Turbo in the settings and convert again. On Linux Turbo currently runs on the CPU only. |
| 8 | **DJ software (optional)** | Open the .stem.mp4 in Traktor (if you have it) or Mixxx 2.6. Are the 4 tracks recognised? |

## 3. Please send back
Ideally as a post in the [GitHub Discussions](https://github.com/Elospeed/StemMaker/discussions) or by mail to elospeed.dev@gmail.com:

- Your **distribution and version** (e.g. "Ubuntu 24.04, GNOME, Wayland") and desktop (GNOME, KDE, …)
- CPU and RAM (roughly is fine)
- For each test above: **works / doesn't work / odd**, with a short note
- **Screenshots** are welcome, especially if something looks wrong
- On errors the log: the "Send error report..." button in the Info window, or the newest file in `~/.local/share/StemMaker-Wine/prefix/drive_c/StemMaker/logs/`
- If the AppImage doesn't start at all: start it from a terminal and copy the text it prints

## Known issues (no need to report)
- **Turbo** doesn't use the **graphics card** on Linux yet, only the CPU.
- **"Open folder"** shows Wine's simple file manager instead of yours.
- **Dialogs** (open, save) look like Windows; your Linux folders are on drive **Z:**.
- **Japanese file names**: install the Noto CJK fonts (Ubuntu/Debian: `fonts-noto-cjk`).
- Inside a **virtual machine** sound may stutter; on a real PC it shouldn't. If it does, please tell me.
- **"Unexpectedly closed"** on the next start: appears if the PC was shut down while StemMaker was still open (on Linux StemMaker isn't told about it). Close StemMaker first.
- **Dock icon**: the proper StemMaker icon is only guaranteed once the AppImage is integrated into the system (e.g. with "Gear Lever" or "AppImageLauncher"). Started directly, a generic icon may appear.

Thanks! Speedy · Elospeed
StemMaker: https://elospeed.github.io/StemMaker/ · All tools: https://elospeed.github.io/
