Elospeed 5.1 -> Stem  0.1 (test build)  -  by Elospeed  (ko-fi.com/elospeed)
============================================================================

Turns the 5.1 sound of a DVD (or any 5.1 file) into ONE Traktor stem file.
No AI and no installation needed: the four 5.1 parts go straight into
the four stem slots.

    Stem 1 = FRONT L/R      front left/right (stereo)
    Stem 2 = LFE (SUB)      subwoofer (mono on both sides, raised to 0 dB peak)
    Stem 3 = CENTER         center (mono on both sides)
    Stem 4 = SURROUND L/R   surround/back left/right (stereo)
    Master = same as stem 1 (or silent, see Settings)

You can change this order under "Settings ...".


HOW TO USE
----------
1. Unzip the whole folder somewhere (e.g. Desktop). Keep the "tools"
   folder next to Stem51.exe, it contains ffmpeg.exe.
2. Start Stem51.exe.
   Windows may show "Windows protected your PC" (the program is not
   signed): click "More info" -> "Run anyway".
3. Drag your 5.1 file onto the window (or click "Open file ...").
   Works with: VOB, MKV, MP4, M4V, MOV, TS, M2TS, DTS, AC3, EAC3, THD,
   WAV, FLAC and more.
4. If the file has several 5.1 audio tracks (DVDs often have AC3 and
   DTS), pick the one you want.
5. Done: <name>.stem.mp4 appears next to your file and the folder opens.
   Load it into Traktor like any stem file.

Always the whole file is converted. A full concert takes a few minutes.


DVD TIPS
--------
- On a DVD, the movie is in the folder VIDEO_TS in the big files
  VTS_01_1.VOB, VTS_01_2.VOB, ... (each about 1 GB). Use those, not
  VIDEO_TS.VOB. If a concert spans several VOB files, each one gives its
  own stem file.
- Copy-protected DVDs cannot be read directly. If you already have the
  DVD as an MKV or as VOB files on your disk, use those.
- To try the program first, use 5.1-test-file.mkv (included): it has a
  stereo track, an AC3 5.1 track and a DTS 5.1 track with a different
  test tone in each channel.


SETTINGS
--------
- Which 5.1 part goes into which stem. "Default" sets it back to
  Front / LFE / Center / Surround.
- Raise LFE to 0 dB peak (on by default): the subwoofer channel on DVDs
  is usually very quiet.
- Master track: same as stem 1, or silent.
- Language: automatic, Deutsch or English.
Settings are saved in Stem51.ini next to the program.


IF SOMETHING GOES WRONG
-----------------------
Everything the program does is written to logs\Stem51.log next to
Stem51.exe. Click "Show log" -> "Open log folder" and send us that file
(Reddit chat or elospeed.dev@gmail.com). That shows us exactly what
happened.


WHAT'S IN THIS FOLDER
---------------------
  Stem51.exe                  the program
  README.txt / LIESMICH.txt   this guide (English / German)
  5.1-test-file.mkv           small test file (20 seconds)
  tools\ffmpeg.exe            FFmpeg (LGPL), does the actual audio work
  tools\FFMPEG-LICENSE.txt    FFmpeg license
  tools\FFMPEG-SOURCE.txt     where to get the FFmpeg source code

Free software by Elospeed. FFmpeg is a trademark of Fabrice Bellard,
https://ffmpeg.org - this program runs ffmpeg.exe as a separate program.
