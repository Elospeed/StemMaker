# Version history

Short version for the "Versions" tab in the Info window, newest version on top.
Built into StemMaker.exe. For every release add a section "## <version> – <date>"
here, in de.md and in es.md (the release workflow checks this).
Below it "### New", "### Improved", "### Fixed" (only those that apply), one short
keyword line per item. Only things users notice, no technical details.

## 2.1.1 – not released yet
### Fixed
- At 150 % and 200 % display scaling windows were taller than the screen (main window, settings, StemDecks)
- Language choice, update window and shutdown question too small with display scaling
- Ko-fi button too wide at 150 %
- StemTagger 1.0.1: list columns too narrow with display scaling

## 2.1 – 29 October 2026
### New
- StemTagger 1.0: set title, artist, album, genre and cover in stem files, also for many files at once
- AddOn bar next to the file list: StemPlayer and StemTagger in one click
- StemPlayer 1.8: new CD player view with jog wheel and stem pads
- "Versions" tab in the Info window
- Right-click menu in the file list: Listen, Edit tags, Remove from list (also Del key)
### Improved
- "Listen" plays the finished file directly
- No Explorer window after conversion any more (can be switched on)
### Fixed
- Main window grew on every start with display scaling above 100 %
- StemPlayer: zoom view cut off at 150 % and 200 % display scaling

## 2.0 – 26 October 2026
### New
- Turbo engine: stems about 6 to 10 times faster on the CPU, same quality
- Graphics card (NVIDIA, AMD, Intel): only seconds per song (beta)
- Pre-test on first start: measures CPU and graphics card, predicts the time per song
### Improved
- Previous engine still selectable, steps in automatically if Turbo fails
- Long DJ mixes need much less memory
- Log shows the engine used for each file

## 1.9 – 23 October 2026
### New
- Spanish (translation: David GJ)
- "Thanks" tab in the Info window
- StemPlayer: loop A-B, seamless
- StemPlayer: zoom view with time grid and zoom to set the loop precisely
- StemPlayer: scrubbing like on a record
### Improved
- StemPlayer in German, English and Spanish (as set in StemMaker)

## 1.8.1 – 20 October 2026
### Fixed
- Tags (title, artist, album, BPM) from OGG and Opus were missing in the stem file
- Window title: "from audio files" instead of "from MP3"

## 1.8 – 18 October 2026
### New
- Main window with colour: progress bar in the list, check mark and stem colour dots
- StemPlayer 1.5: waveform per stem, compact/waveform view
### Improved
- StemPlayer: solo like on a DJ mixer
### Fixed
- "Convert again" skipped all files
- Cancelled songs counted as errors
- Existing stem file could be lost when overwriting
- File list survives a power cut while saving
- Various small fixes

## 1.7.1 – 14 October 2026
### New
- "More settings" window (gear icon)
- Tray icon with progress and done notification
- "Traktor colours" button
- Installer (Setup.exe) next to the ZIP
- Send error report (only by hand, nothing automatic)
### Improved
- Safer downloads (checksums built in)
- Clear message for paths over 260 characters
- StemPlayer 1.4: rejects wrong files with a clear message
### Fixed
- Windows shutdown during a conversion: now a clean stop
- Wrong version number under "Apps & features" after an update

## 1.7 – 6 October 2026
### New
- "Listen" in StemPlayer
- "Open folder after conversion"
- Club level (normalize loudness) and bass fix
- Update check on start and "Check for updates"
- StemPlayer 1.3: "Traktor Dark" design, mute, solo and fader per stem
### Improved
- Tags: also BPM, key, label and ISRC
- Fixed ffmpeg version with checksum
- Log with loudness and speed, statistik.csv file
### Fixed
- StemMaker sometimes could not be closed
- Same file names from different folders got lost
- demucs kept running in the background after a crash

## 1.6 – 2 October 2026
### New
- First public version on GitHub
- Convert whole collections, the list continues after a crash or restart
- Shut down the PC afterwards (with countdown)
- German and English
### Fixed
- Umlauts and accents in file names (e.g. "Tiësto")
- StemCLI did not read StemMaker.ini

## 1.5
### New
- PC stays awake during conversion
- New program icon, new name "Elospeed StemMaker"
### Improved
- Power plan set to performance during conversion (about 8 % faster)
- AAC bitrate follows the source

## 1.4
### Improved
- All processor cores used, about twice as fast on older PCs
- Better remaining time estimate

## 1.0 – 1.3
### New
- Audio files to Traktor stem files (master, drums, bass, other, vox)
- Start window downloads ffmpeg and the separation model by itself
- StemCLI for the command line
