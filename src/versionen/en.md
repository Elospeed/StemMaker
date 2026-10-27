# Version history

Short version for the "Versions" tab in the Info window, newest version on top.
Built into StemMaker.exe. For every release add a section "## <version> – <date>"
here, in de.md and in es.md (the release workflow checks this).
Only things users notice, short and without technical details.

## 2.0 – 26 October 2026
- New Turbo engine: stems are separated about 6 to 10 times faster on the CPU, same quality
- With a suitable graphics card (NVIDIA, AMD, Intel) it takes only seconds per song (beta)
- A short pre-test on first start measures CPU and graphics card and tells you how long a song will take
- The previous engine can still be selected and steps in automatically if Turbo fails on a file
- Long DJ mixes need much less memory

## 1.9 – 23 October 2026
- StemMaker is now also available in Spanish (thanks to David GJ for the translation)
- New "Thanks" tab under "Info" listing everyone who helped
- StemPlayer: loop A-B, a section repeats seamlessly
- StemPlayer: zoom view to set the loop precisely, with time grid and zoom
- StemPlayer: scrubbing, dragging the waveform plays the sound like a record
- StemPlayer now speaks German, English and Spanish (as set in StemMaker)

## 1.8.1 – 20 October 2026
- Title, artist, album and BPM from OGG and Opus files now end up in the stem file
- Window title says "from audio files" instead of "from MP3"

## 1.8 – 18 October 2026
- Main window with colour: progress bar in the list, check mark and stem colour dots for finished files
- StemPlayer 1.5: waveform per stem, solo like on a DJ mixer
- "Convert again" really converts again, cancelled songs no longer count as errors
- Existing stem file is no longer lost when overwriting
- Many small fixes

## 1.7.1 – 14 October 2026
- New "More settings" window (gear icon)
- Tray icon: progress and notification when everything is done
- "Traktor colours" button for the stem colours
- Installer (Setup.exe) next to the ZIP
- Send error report (only if you want, nothing is sent automatically)
- Clean stop on Windows shutdown, clear message for too long paths
- StemPlayer 1.4 and safer downloads

## 1.7 – 6 October 2026
- "Listen" in StemPlayer and "Open folder after conversion"
- Club level (normalize loudness) and bass fix
- BPM, key, label and ISRC are copied into the stem file
- Update check on start and "Check for updates" in the Info window
- StemPlayer 1.3 in the "Traktor Dark" design with mute, solo and fader per stem
- Many bug fixes

## 1.6 – 2 October 2026
- First public version on GitHub
- Convert whole collections, the list continues after a crash or restart
- Shut down the PC afterwards (with countdown)
- German and English
- Umlauts and accents in file names work everywhere

## 1.5
- PC stays awake during conversion, the power plan is set to performance for the time being
- New program icon and new name "Elospeed StemMaker"

## 1.4
- All processor cores are used, about twice as fast on older PCs

## 1.0 – 1.3
- Audio files become Traktor stem files with master, drums, bass, other and vox
- Start window checks everything and downloads ffmpeg and the separation model by itself
- StemCLI as command line version
