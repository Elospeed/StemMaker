Elospeed StemDecks 0.2 (test build)  -  by Elospeed  (ko-fi.com/elospeed)
=========================================================================

Turns a 5.1 recording (e.g. a concert DVD) into Traktor stems.
Test build, not a finished product. Deutsch: LIESMICH.txt

THE FOUR 5.1 PARTS
  FRONT L/R      front left/right (stereo)
  CENTER         center (mono, put on both sides)
  LFE (SUB)      subwoofer (mono, optionally raised to 0 dB peak)
  SURROUND L/R   surround/back left/right (stereo)
  Default mapping:  A / slot 1 = Front,   B / slot 2 = LFE,
                    C / slot 3 = Center,  D / slot 4 = Surround
  Change it under SETTINGS (saved in StemDecks.ini).

SETUP
  Unzip the folder and start StemDecks.exe. It needs ffmpeg.exe: if it is
  not next to the exe (or in tools\), the program asks for it once
  (free download: ffmpeg.org, e.g. the "essentials" Windows build).
  "5.1 -> 4 DECKS" also needs StemCLI.exe from StemMaker
  (github.com/Elospeed/StemMaker). Easiest: put StemDecks.exe into
  StemMaker's AddOns\ folder.

1) 5.1 -> 1 STEM  (no AI, fast)
  The four parts become stems 1..4 of one file <name>.stem.mp4.
  Master = same as slot 1, or silent (SETTINGS).

2) 5.1 -> 4 DECKS  (with AI)
  Writes A_/B_/C_/D_<name>.wav and separates each one into 4 stems with
  StemCLI (no club level) -> A_/B_/C_/D_<name>.stem.mp4 = 16 stems on
  4 decks.

  If the file has several 5.1 audio tracks (DVD: AC3 and DTS), you are
  asked which one to use. Optionally only the first 3 minutes (quicker for
  testing).
  File types: mkv, mka, mp4, m4v, m4a, mov, ac3, eac3, dts, thd, wav, flac,
  vob, ts, m2ts, mts, avi, webm, ogg, opus.
  DVD: use the big VOB files of the movie (VTS_01_1.VOB ...). ffmpeg cannot
  read copy-protected DVDs.

3) PLAYING FOUR DECKS
  "LOAD DECKS" and pick an A_ file: B_/C_/D_ from the same folder are
  loaded onto decks B..D automatically. One shared play/pause, all decks
  stay sample-accurately in sync.

  Space / P   play / pause        1 .. 4   mute deck A..D
  Arrows      -/+ 5 seconds       Home     back to the start
  Ctrl+O      load decks

LOG
  Everything that happens is written to logs\StemDecks.log next to the exe
  (the LOG button shows it). If something goes wrong, please send us this
  file.

NOTE
  The player decodes the stems into the temp folder (about 10 MB per stem
  and minute). Everything is deleted when you close the program.
