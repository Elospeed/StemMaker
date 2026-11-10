Elospeed StemPacker 0.3  -  by Elospeed  (ko-fi.com/elospeed)
====================================================================

Turns finished single tracks into Traktor stem files (.stem.mp4), WITHOUT
AI and in batches. Each song needs a master and up to four stems, e.g.
from your DAW, from 5.1 DVDs or from another separation tool. Every song
becomes one file  <song>.stem.mp4.  Deutsch: LIESMICH.txt


HOW TO
------
1. Unzip the whole folder. Keep the "tools" folder (ffmpeg.exe) and the
   "lang" folder next to StemPacker.exe.
   (In the StemMaker package StemPacker sits in AddOns\ and uses
   StemMaker's ffmpeg.)
2. Start StemPacker.exe. If Windows says "Windows protected your PC" (the
   program is not signed): "More info" -> "Run anyway".
3. Drop the folder with your tracks onto the window (or "Choose folder ...").
   StemPacker detects the naming by itself, e.g. "Song_drums",
   "Song - Bass", "Song (Vocals)", "Song (A)" to "(D)" or "Song_1" to
   "_4", even when master and stems sit in different subfolders.
   If there is no master, it is mixed from the stems.
   The list shows every song, how many files were found and what is
   missing.
4. If nothing is detected: tick "Set folders and patterns myself" and
   enter folder and name pattern for each track (see below), then
   "Find songs".
5. "Pack all". Done: the stem files load straight into Traktor.
6. To listen without Traktor: start StemPlayer.exe and open a finished
   .stem.mp4 file. M / S mute or solo each stem.


NAME PATTERNS (Set folders and patterns myself)
-----------------------------------------------
Master and stems 1 to 4 each have a folder and a pattern. The star *
stands for the song name; the file extension is not part of the pattern.
Upper/lower case does not matter.

  Example 5.1 DVD (two folders):
    Master:  folder 1   "* (DOWNMIX #1)"   finds  "Hello (DOWNMIX #1).wav"
    Stem 1:  folder 2   "* (A)"            finds  "Hello (A).wav"
    Stem 2:  empty      "* (B)"            ...
  Result:  Hello.stem.mp4  with the stems Front, LFE, Center, Rear.

  Example DAW export (one folder):
    master "*", stems "*_drums", "*_bass", "*_other", "*_vocals"
    A file that matches a stem pattern never counts as a master.

An empty folder means "same as the row above" (stem 1 like the master,
stem 2 like stem 1 and so on). A second star in a pattern stands for any
text that is not part of the song name.

The letters in the file names (A, B, _drums ...) are only used to find the
files. Inside the finished file each stem gets the name and colour set on
the right; Traktor shows them directly.


SETTINGS
--------
- Target: next to the master file, or into a folder of your choice
  (subfolders are kept).
- Format: AAC 320 kbit/s (like Traktor stems), ALAC lossless 16 bit /
  44.1 kHz, or ALAC 24 bit at the original sample rate (TEST: not yet
  checked in Traktor, please try one song first).
- Mix master from the stems: for tracks without a finished master. The
  stems are mixed without changing the level.
- Fill missing stems with silence: otherwise a song with a missing stem is
  skipped.
- Cover from the folder: if the master file has no cover, <song>.jpg,
  cover.jpg, folder.jpg or front.jpg is used.
- Overwrite existing: otherwise finished songs are skipped.
Tags (title, artist, album, BPM, key ...) and cover come from the master
file. If it has no title, the song name is used.
Saved in StemPacker.ini next to the program.


IF SOMETHING GOES WRONG
-----------------------
- "missing: Stem 2 "Hello (B)"": no file with that name (any audio
  extension) was found. If a file with a similar name exists (other
  spaces, punctuation or upper/lower case), the list shows it as
  "similar: ...". Rename the file or adjust the pattern.
- "done, warning: Stem 2 is 1.3 s shorter than the master": the file was
  packed, but one track has a different length. Listen in Traktor whether
  everything is in sync.
- A stem file does not load into a Traktor TRACK deck: that is how Traktor
  works, also with stem files from Native Instruments. Load stem files
  into a STEM deck.
Everything the program does is written to logs\StemPacker.log. "Show log"
opens it; please send us that file.


FOLDER CONTENTS
---------------
  StemPacker.exe              the program
  StemPlayer.exe              player for finished stem files (mute/solo)
  README.txt / LIESMICH.txt   this guide (English / German)
  StemPacker-User-Guide.pdf   full guide with pictures (English)
  Example\                    3 short test songs (test tones) to try it
  LICENSE.txt                 licence (MIT)
  lang\                       language files (English, Spanish)
  tools\ffmpeg.exe            FFmpeg (LGPL), does the actual audio work
  tools\FFMPEG-LICENSE.txt    FFmpeg licence
  tools\FFMPEG-SOURCE.txt     FFmpeg source code

THANKS
------
To Cuiusquemodi for the idea, the test with 178 songs and lots of
feedback.

Free software by Elospeed. FFmpeg is a trademark of Fabrice Bellard,
https://ffmpeg.org - the program runs ffmpeg.exe as a separate program.
Traktor is a trademark of Native Instruments.
