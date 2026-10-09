# Elospeed StemMaker 1.7

**by Elospeed**

🇩🇪 **Deutsche Anleitung:** [LIESMICH.md](LIESMICH.md)

Turns MP3s (also WAV, FLAC, AIFF, M4A, OGG) into **Traktor stem files (`*.stem.mp4`)** with 4 tracks: Drums, Bass, Other (melody) and Vox.
It works the same way as [Stemgen](https://github.com/axeldelafosse/stemgen), just **without Python** and without setting up a Python environment: a single Lazarus program that downloads everything it needs on first start. Available as an installer or as a portable ZIP.

**Why StemMaker**

- **Nothing to set up:** one 4 MB Windows exe. The separation engine is C++ ([demucs.cpp](https://github.com/sevagh/demucs.cpp)) instead of Python, so there is no Python environment, no PyTorch and no CUDA driver to install and nothing that can conflict with other software. It runs on the processor of any 64-bit Windows PC.
- **Traktor format, not four loose files:** master plus the four stems land in one `.stem.mp4` with the NI stem metadata, ready for a stem deck. No routing by hand, no extra software for the container, no Traktor licence to convert.
- **Built for whole collections:** add complete folders, see the expected time beforehand, let it run overnight. The list is saved after every file, so a crash or a power cut costs one track instead of the run, and subfolders are rebuilt in the output folder.
- **Check before you play:** `AddOns\StemPlayer.exe` plays a finished stem file with mute, solo, volume and level meters per stem and A/B against the original, so you don't have to import into Traktor just to listen.
- **Level and bass sorted out:** quiet files are raised to club level without a limiter, and low bass that the model leaves in the melody stem is moved into the bass stem.
- **Quality:** in a side-by-side test against a stem file made by Traktor Pro 4 from the same track, drums, kick, vocals and level came out practically the same.
- **Your music stays local:** no account, no cloud, no telemetry, nothing running in the background.

The German version of this guide is `LIESMICH.md`.

```
MP3 ──ffmpeg──► 44.1 kHz WAV ──demucs.cpp──► drums / bass / other / vocals
                                                     │
      Master + 4 stems ──ffmpeg (AAC/ALAC)──► MP4 with 5 tracks
                                                     │
                       StemMaker (Pascal) ──► NI "stem" metadata ──► *.stem.mp4
```

## Getting started

There are two downloads on the [release page](https://github.com/Elospeed/StemMaker/releases/latest), with the same program inside:
- **`StemMaker-<version>-Setup.exe`** (installer): installs for your Windows user only, without admin rights, to `%LOCALAPPDATA%\Programs\StemMaker`, with a Start menu entry and an uninstall entry under "Apps & features". When you uninstall by hand, it asks whether the downloaded models, ffmpeg and settings should be deleted too.
- **`StemMaker-<version>.zip`** (portable): unzip anywhere, e.g. to `C:\Tools\StemMaker` or a USB stick. Nothing is installed.

1. Run the installer, or unzip the archive.
2. Run `StemMaker.exe` (Start menu entry "StemMaker" after the installer). If Windows shows a blue warning window, see [Windows warning](#windows-warning-windows-protected-your-pc).

**On the first start on a PC** a window shows the disclaimer and the license notes. Tick the box and click **"I agree - start StemMaker"**. This is asked once per PC: if you copy the StemMaker folder to another PC, it asks again there (this is not copy protection, copying is allowed under the MIT License). `AddOns\StemCLI.exe` asks for the same confirmation once with `--accept`. You can read the text again any time under **Info → Licenses**.

Then the **startup check window** opens. It ticks off, one by one: processor, ffmpeg, demucs, model and temp folder.
- **All green:** The main window opens by itself after about a second.
- **On the very first start** ffmpeg (approx. 56 MB) and the separation model (81 MB) are missing. Click **"Download"** to fetch both with a progress bar. Every download is checked against the SHA-256 checksum from `update.json`; a damaged or swapped file is discarded. StemMaker then checks again and starts.
- **Something is red and can't be downloaded** (e.g. a demucs file is missing): Unzip the whole archive again. Hover over the red line to see the exact reason.

**Updates:** At startup StemMaker checks in the background (max. 5 seconds) whether a newer version exists. If so, it offers **Update now / Later / Skip this version**. The update is checked with its SHA-256 checksum; settings, list, logs, models and ffmpeg are kept. Never during a conversion. If copying fails halfway, StemMaker rolls everything back and stays on the old version. Check by hand: **Info → Check for updates** (also shows a skipped version again). Turn it off with the checkbox in the update or Info window or `AutoCheck=0` (see below).

If you pick a model in the main window that isn't installed yet (e.g. htdemucs_ft), StemMaker asks whether to download it now.

## Windows warning ("Windows protected your PC")

StemMaker is not digitally signed. Signing certificates cost money every year, which doesn't pay off for a free hobby project. That's why Windows shows a blue SmartScreen window ("Windows protected your PC", publisher "Unknown") the first time you start the installer `StemMaker-<version>-Setup.exe`, `StemMaker.exe`, `StemCLI.exe` or `AddOns\StemPlayer.exe`. Many small open-source tools do the same.

**To start it anyway:**
1. Click **"More info"** in the blue window.
2. Click **"Run anyway"**.

Windows remembers this, so the window only appears once per program.

**Tip:** Before unzipping, right-click the downloaded ZIP → **Properties** → tick **"Unblock"** at the bottom → OK. Then Windows treats the unzipped files as local and usually doesn't warn at all.

**If Windows blocks it completely** (no "Run anyway" button): Smart App Control is switched on (Windows 11). Then StemMaker can only be started after turning it off under *Windows Security → App & browser control → Smart App Control*. Only do this if you trust the source.

**Want to check the download?**
- Upload the ZIP or the exe to [VirusTotal](https://www.virustotal.com). Single hits from little-known scanners are common with unsigned programs and are usually false alarms.
- If the release notes list a SHA-256 checksum, compare it in PowerShell: `Get-FileHash .\StemMaker-1.7.zip` (adjust the file name).
- The full source code is in this repository. You can build StemMaker yourself (see [Build it yourself](#build-it-yourself)).

## Donations

StemMaker is free and open source. Before it starts, a small window asks for a voluntary donation via [Ko-fi](https://ko-fi.com/elospeed). "Start tool" simply carries on. Tick "Don't show at startup" to hide the window for good. You can still donate any time via **Info → Donate now**.

## Folder structure

```
StemMaker\
  StemMaker.exe          program (GUI)
  StemMaker.ini          settings (created when you first close the program)
  StemMaker_queue.txt    saved file list (queue)
  logs\                  logs of the last 20 program starts
    statistik.csv        one line per converted file (for analysis)
  AddOns\                extra programs for advanced users
    StemCLI.exe          command-line version (batch files, Task Scheduler)
    StemPlayer.exe       test player for .stem.mp4 files (mute/solo per stem)
  tools\
    demucs_mt.cpp.main.exe      separation, Demucs v4 (AVX2 build)
    demucs_ft_mt.cpp.main.exe   separation, Demucs v4 fine-tuned
    demucs_v3_mt.cpp.main.exe   separation, Demucs v3
    avx\...                     same, for CPUs with AVX but without AVX2 (approx. 2011-2013)
    generic\...                 same, for even older CPUs
    ffmpeg.exe                  ← downloaded on first start
  models\
    ggml-model-htdemucs-4s-f16.bin   ← downloaded on first start
  lang\                  language files (gettext .po)
  src\                   complete source code (Lazarus)
  demucs-build\          build instructions for the demucs programs
```

The demucs programs are fully statically linked; they need no DLLs and no installation. StemMaker detects which instructions your CPU supports and picks the fastest matching build: AVX2, AVX or generic. In testing, the AVX build was a good 30 % faster than generic.

## Usage

- **Drag** files or whole folders **into the window**, or use "Add files..." or "Folder...". You can also drop them straight onto `StemMaker.exe`.
- **Start** processes the list one file after another. "Cancel" stops immediately and cleans up the temp files.
- Below both progress bars you see **elapsed and estimated remaining time**: the top one for the current file, the bottom one for the whole list. The estimate uses the length of the waiting songs and the speed of this PC, and gets more accurate with every finished file. After each song the list shows how long it took, e.g. "OK (4:12)".
- The result is `Title.stem.mp4`, by default next to the original file. Alternatively, choose an output folder.
- Tags and the **cover art** are copied from the source file: title, artist, album, album artist, composer, genre, year, track and disc number, comment, grouping, lyrics – plus **BPM**, **key**, **label** and **ISRC**. Traktor shows title, artist, album, genre, label and cover right after the import; BPM and key are overwritten by Traktor's own analysis.
- **Check stem...** shows whether a file is a valid stem (5 tracks + stem metadata). This also works with purchased NI stems.
- A normal player only plays track 1, the master. You only hear the individual stems in Traktor.

- **Info** (top left) shows this guide, the version and the name of the current log. From there you can also open the logs folder or donate.
- **Copy log** puts the log on the clipboard, e.g. to pass it on when reporting a problem.

### Converting a whole collection

StemMaker is built for preparing an entire music collection in one go, e.g. overnight:

- **Time estimate before you start:** Below the lower progress bar you'll see e.g. "87 files pending, 6:12:40 of music - approx. 11:30:00". StemMaker reads the song lengths in the background and learns the speed of your PC with every finished track: "(this PC's speed)" means the estimate is based on your machine, "(rough estimate)" means it hasn't measured yet.
- **The list is remembered:** The file list and the status of every file is saved continuously (`StemMaker_queue.txt`). If StemMaker crashes, the power fails or you close the program, the list is back on the next start. Click **Start** to continue where it stopped. An interrupted file is redone. "Clear list" also deletes the saved list.
- **Recreate subfolders in the output folder:** If you add a whole folder, e.g. `D:\Music\House`, then `D:\Music\House\2024\track.mp3` ends up as `<output folder>\House\2024\track.stem.mp4`. Only applies with your own output folder.
- **Shut down the PC when finished:** When all files are done, a 60-second countdown with "Cancel" appears. Then StemMaker closes cleanly and Windows shuts down. The checkbox only applies to the next run. If you cancel the run, the PC does not shut down.
- **Keep the PC awake** (see Settings) stops Windows from going to sleep halfway through.
- Stem files that already exist are skipped (unless "overwrite existing stem files" is on).

### Logs and troubleshooting

Every program start writes a log to the `logs` folder. Each line is saved immediately, so even after a crash everything up to the last action is in it. The last 20 logs are kept.

| File name ends with | Meaning |
|---|---|
| `_LAEUFT.log` | StemMaker is currently running |
| `.log` | closed normally |
| `_FEHLER.log` | closed normally, but an error occurred along the way |
| `_ABSTURZ.log` | ended unexpectedly (crash, Task Manager, power failure); renamed like this on the next start |

For each file the log shows: file size, length, source (e.g. mp3 320 kbit/s), loudness of the master track (LUFS, range, true peak), conversion time and the speed in "seconds per minute of music". That number does not depend on the song length, so it is good for comparing models and PCs.

In addition, StemMaker adds one line per converted file to `logs\statistik.csv` (date, file, size, length, model, cores, conversion time, seconds per minute of music, RAM, loudness, CPU, result). If a new version changes the columns, the old file is renamed to `statistik_bis_<date>.csv`. The file is never cleaned up and opens with a double click in Excel or LibreOffice (separator `;`, decimal comma). If it is open in Excel at that moment, the line for that file is missing.

The log contains:
- system info: Windows version, processor, cores, RAM, graphics card
- every ffmpeg and demucs call with all parameters and the result
- progress in 10 % steps
- for errors, the call stack with file and line number in the source code
- at the end of a run, a summary: total time, average per track, cores used and the peak RAM usage of demucs

The graphics card is only listed. demucs.cpp computes on the CPU only.

### Settings

| Setting | Meaning |
|---|---|
| Separation model | **htdemucs**: default, good quality. **htdemucs_ft**: best quality, approx. 4× slower, 4 model files. **hdemucs_mmi (v3)**: faster, slightly worse. |
| Parts / Auto | How many parts of the song are separated in parallel. **Auto** (default) recalculates on every start: as many parts as the processor has physical cores, at most 4 – and only as many as the RAM can handle (each part needs a good 2 GB, so with 8 GB RAM at most 2). Each part also uses additional cores; this is distributed automatically. Without the tick, the number you set applies. |
| Audio format | **AAC automatic** (default): the stem file gets the bitrate of the source, e.g. MP3 256 → AAC 256, MP3 320 → AAC 320. Going higher gains nothing; it can never be better than the source. Sources below 192 kbit/s get 192, so nothing extra is lost when re-encoding. Lossless sources (WAV/FLAC) get 320. **AAC 256**: NI standard, fixed. **AAC 320**: fixed. **ALAC**: lossless, very large, only worthwhile for WAV/FLAC sources. The log shows per file e.g. "Source: mp3 320 kbit/s → stem file AAC 320 kbit/s". |
| Stem names/colors | How the stems appear in Traktor. The defaults use the same colors as Stemgen. |
| Normalize loudness (club level) | On by default. Quiet files are raised until the loudest point is just below 0 dB (about −1 dB). All 5 tracks get the same value, no limiter – the dynamics stay as in the original. Loud club tracks hardly change. Benefit: in Traktor the stem waveforms are big and easy to read (Autogain only raises playback, not the display). The log shows e.g. "Normalize loudness: +11.6 dB". |
| Bass fix | On by default. The low bass below 80 Hz that the separation leaves in the "Other" stem is moved to the Bass stem. The Bass stem sounds fuller, like Traktor's own stems; all stems together sound unchanged. Skipped for files over 20 minutes (DJ mixes), because it needs the whole track in memory. |
| Keep the PC awake during conversion | On by default. During conversion the PC won't go to sleep (the screen may turn off). If Windows is set to the **Power saver** plan (or, on Windows 11, the power mode is "Best power efficiency"), it switches to more performance for the duration of the conversion. Afterwards everything is back to how it was, even after a crash: in that case StemMaker restores the old power plan on the next start. "Balanced" is left untouched. |

### Command line (AddOns\StemCLI.exe)

The same without a window, e.g. for batch files or Task Scheduler:
```
AddOns\StemCLI.exe "D:\Music\New" -o "D:\Music\Stems" -m ht -t 4
AddOns\StemCLI.exe track.mp3 -f alac --overwrite
AddOns\StemCLI.exe --check "track.stem.mp4"
```
Options: `-o folder`, `-m ht|ft|v3`, `-t parts`, `-f aac|alac`, `-b auto|kbit` (default auto), `--overwrite`, `--keep` (keep temp folder), `--no-awake` (PC may go to sleep), `--no-normalize` (don't normalize loudness), `--no-bassfix` (no bass fix), `--ffmpeg exe`, `--demucs folder`, `--models folder`.
Most people won't need this: the main window handles whole folders, the queue and overnight runs. StemCLI is meant for automation (batch files, Windows Task Scheduler). It uses the same tools, models, language and settings (`StemMaker.ini`) as the main program and doesn't download anything itself; StemMaker.exe must have run once beforehand.

### Test player (AddOns\StemPlayer.exe)

Listen to a finished `.stem.mp4` without Traktor: mute, solo (also several at once) and volume per stem, level meters, A/B comparison with the original mix, and a "Rest" mode (original minus the sum of all stems) that shows what the separation lost. Start it from StemMaker with **Listen** (opens the file dialog in the folder of the last converted file) or double-click a finished file in the list, or open a file via the dialog, drag & drop or as a parameter: `AddOns\StemPlayer.exe "track.stem.mp4"`. It uses StemMaker's `tools\ffmpeg.exe`. The interface is German only for now. Source: `src/AddOns/StemPlayer/`.

## Processing time

Separation runs purely on the processor (CPU). Measured with a 12-minute track (extended mix), converted to a normal 4-minute track:

| Computer | htdemucs (default) | hdemucs_mmi (v3) |
|---|---|---|
| Intel i7-12700KF (12 cores, 2021) | 22 min → approx. **7–8 min** per 4-min track | 12.5 min → approx. **4 min** per 4-min track |
| Intel i5-2500 (4 cores, 2011) | 1 h 22 min → approx. **27 min** per 4-min track | – |

Rule of thumb: on a current PC, htdemucs takes about **twice as long as the song**, v3 about **as long as the song**. htdemucs_ft takes roughly four times as long as htdemucs. Time grows with song length. Larger batches are best run overnight.

Older processors without AVX2 (e.g. 2nd/3rd generation Intel Core i) are much slower: a 12-minute track can take over an hour there. Laptops on battery are also throttled; StemMaker shows a notice in that case. If the PC went to sleep in between, this is noted at the end of the log.

## How the stem file is built

Same as Stemgen with `ni-stem`/MP4Box:
- MP4 with 5 audio tracks: track 1 is the master and the only *enabled* one, tracks 2–5 are Drums/Bass/Other/Vox and *disabled*.
- `moov/udta/stem`: JSON with stem names, colors and mastering DSP (compressor/limiter off, same values as Stemgen).
- iTunes tags plus `TAUT = STEM`. BPM goes into the `tmpo` atom, the key into `----:com.apple.iTunes:initialkey`, the label into `©pub` and the ISRC into `----:com.apple.iTunes:ISRC` – ffmpeg cannot write those four for MP4, so StemMaker writes them itself (`uStemMP4`).

## Advanced: StemMaker.ini

```ini
[Tools]
FFmpeg=D:\Programs\ffmpeg\bin\ffmpeg.exe    ; use an existing ffmpeg
DemucsDir=...                                ; different folder for demucs
ModelsDir=D:\Models                          ; store models elsewhere

[Download]
FFmpegZipURL=https://...                     ; your own ffmpeg source (no checksum then)
ModelBaseURL=https://...                     ; your own model source

[Update]
AutoCheck=0                                  ; don't check for updates at startup
```

Normally the download addresses come from [`update.json`](update.json) in this repository (fixed ffmpeg version, checksums). If a file moves, only that file has to change on GitHub.

## Problems?

- **Download fails:** Check your internet connection, firewall or proxy. If necessary, download manually:
  - ffmpeg: <https://www.gyan.dev/ffmpeg/builds/> ("release essentials"). Copy `ffmpeg.exe` to `tools\`.
  - Models: <https://huggingface.co/datasets/Retrobear/demucs.cpp/tree/main>. Put the `.bin` files in `models\`.
- **demucs aborts:** The log at the bottom of the main window shows the last lines of output. If the path contains unusual characters (e.g. Japanese), move the StemMaker folder to a simple path. Umlauts are fine.

## Languages

On first start, StemMaker asks for the language; your Windows language is preselected. You can change it at any time in the Info window under "Language:". The new language applies from the next start.

The language files are in the `lang\` folder (gettext, `.po`). To add a language, copy `lang\StemMaker.pot` to e.g. `lang\fr.po` and translate it with [Poedit](https://poedit.net).

## Build it yourself

- **StemMaker/StemCLI:** Open `src\StemMaker.lpi` or `src\StemCLI.lpi` in Lazarus (≥ 2.2, FPC 3.2) and press F9. No extra packages are needed, only LCL and LazUtils, which ship with Lazarus. The code is extensively commented in German:

  | Unit | Purpose |
  |---|---|
  | `StemMaker.lpr` | main program: startup check window first, then main window |
  | `umain.pas/.lfm` | main window, file list, worker thread |
  | `uinit.pas` | startup check window with checks and download |
  | `ustemjob.pas` | converts one file (ffmpeg → demucs → ffmpeg → metadata) |
  | `ustemmp4.pas` | writes the Traktor stem info into the MP4 (pure Pascal) |
  | `udownload.pas` | download via WinINet + unzip |
  | `ulog.pas` | real-time log file, crash detection, system info |
  | `ulogui.pas` | catches unexpected errors and writes them to the log |
  | `udonate.pas` | donation window before startup |
  | `uinfo.pas` | Info window |
  | `upower.pas` | keep the PC awake, power plan, battery, sleep detection |
  | `ulang.pas` | multilingual support: `_()` function and `.po` reader |
  | `ulangui.pas` | language picker at first start, translates forms |
  | `uqueue.pas` | Remembers the queue, reads song lengths, learns the speed |
  | `stemcli.lpr` | command-line version |

- **Language files:** `lang-tools/i18n.py` collects all texts from the code (`_('...')` and `.lfm`) and generates `src/lang/StemMaker.pot` and `src/lang/en.po` (copied to `lang\` in the release) from `lang-tools/en.json`.
- **Icon:** `art/make_icon.py` (Python + Pillow) draws the program icon: four bars in the stem colors. The result `StemMaker.ico` goes into `src\`; Lazarus embeds it automatically.
- **demucs.cpp for Windows:** `demucs-build/build_demucs_windows.sh` (cross-build on Linux/WSL with mingw-w64). The patch changes only 3 things: `.string()` for Windows paths, selectable CPU architecture instead of `-march=native`, and the tests are not built.

## Development

- [Roadmap](ROADMAP.md) (German): what is being worked on and what is planned next
- [Changelog](CHANGELOG.md) (German): what is done, per version
- [TODO](TODO.md) (German): what needs to be tested, decided or built next
- [Development log](docs/ENTWICKLUNGSLOG.md) (German): problems found during development and how they were solved
- [Ideas for future versions](docs/IDEEN.md) (German)

## Licenses / Credits

- StemMaker: © 2026 Elospeed, MIT License (see `LICENSE`).
- [demucs.cpp](https://github.com/sevagh/demucs.cpp) by Sevag Hanssian (MIT) – the separation programs shipped in `tools\`.
- The [Demucs](https://github.com/facebookresearch/demucs) models are by Alexandre Défossez et al. / Meta AI. They are downloaded from their original location and not redistributed by StemMaker – see the licensing note in `THIRD-PARTY-NOTICES.md`.
- [FFmpeg](https://ffmpeg.org) (LGPL, downloaded separately on first start from this repository's releases; unmodified Windows build by BtbN, version pinned in `update.json`).
- Approach and metadata values based on [Stemgen](https://github.com/axeldelafosse/stemgen) by axeldelafosse (MIT).
- Traktor and STEMS are trademarks of Native Instruments; StemMaker is not affiliated with Native Instruments.
- Full list of all components, authors and licenses: **`THIRD-PARTY-NOTICES.md`**.
- Only use with material you have the rights to.
- **Disclaimer:** StemMaker is provided free of charge and without any warranty ("as is"); use at your own risk. The full text is shown on first start and under Info → Licenses.
