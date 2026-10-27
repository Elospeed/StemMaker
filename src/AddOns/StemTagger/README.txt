Elospeed StemTagger 0.1  -  by Elospeed  (ko-fi.com/elospeed)
================================================================

Sets title, artist, album, genre, year, track no., BPM, key, label,
comment and cover art in Traktor stem files (.stem.mp4).

WHY A SEPARATE TOOL?
  Regular tag editors sometimes rewrite a stem file in a way that makes
  Traktor load it as a normal track afterwards. StemTagger only changes the
  tag list inside the file. The 5 audio tracks and the stem data (names and
  colours of the stems) stay byte for byte the same. The new file is
  checked before it replaces the original (same track count, same stem
  data). If anything goes wrong, the original stays untouched.

INSTALLATION
  Copy StemTagger.exe into the AddOns\ folder of StemMaker. It also runs on
  its own. The language (German, English, Spanish) is taken from the
  StemMaker settings, otherwise from the Windows language.

USAGE
  - Drag stem files or whole folders onto the window
    (or "Files..." / "Folder..."; folders are searched for *.stem.mp4,
    including subfolders).
  - Select one or more rows and change the fields below.
    With several files selected, a change applies to all of them.
    Grey "<different>" means the files have different values. If you
    leave that field empty, every file keeps its own value.
  - Cover: drag a picture onto the window, "Picture..." or "Paste"
    (Ctrl+V, e.g. a picture copied in the browser). JPEG and PNG are kept
    as they are, BMP and GIF are converted to JPEG. Pictures larger than
    1000 pixels can be shrunk (checkbox at the bottom).
  - "Artist/title from file name": "Kungs - Clap Your Hands.stem.mp4"
    gives artist "Kungs" and title "Clap Your Hands". A leading track
    number ("03. ") is dropped.
  - Save (Ctrl+S) writes all changed files.
    "Discard changes" resets everything to what is in the files.
  - "Create backup copy": before the first save, <file>.bak is created
    (only once, so the real original is kept).

  Keys: Ctrl+S save, Ctrl+V paste cover, Del remove from the list,
  Ctrl+A select all.

NOTE ON TRAKTOR
  Traktor keeps the tags in its collection (collection.nml). For tracks
  that are already in Traktor, new tags show up only after reloading the
  track or after "Check Consistency". If "Write all tags to file" is on in
  Traktor, Traktor may write its own values back. The file must not be
  loaded in Traktor while saving.

NOT YET
  MP3 files will follow in a later version.

LOG
  logs\StemTagger.log next to the exe (if that folder is read-only:
  %APPDATA%\StemMaker\logs\).

LICENSE
  Free software (MIT), like Elospeed StemMaker. No third-party libraries
  apart from Free Pascal / Lazarus.
