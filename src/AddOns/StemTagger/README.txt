Elospeed StemTagger 1.2.0  -  by Elospeed  (ko-fi.com/elospeed)
================================================================

Sets title, artist, album, genre, year, label, comment and cover art in
Traktor stem files (.stem.mp4) and MP3 files - what Traktor and Mixxx show and search.
BPM and key are detected by Traktor and Mixxx during analysis; values that
are already in the file are kept.

WHY A SEPARATE TOOL?
  Regular tag editors sometimes rewrite a stem file in a way that makes
  Traktor load it as a normal track afterwards. StemTagger only changes the
  tag list inside the file. The 5 audio tracks and the stem data (names and
  colours of the stems) stay byte for byte the same. The new file is
  checked before it replaces the original (same track count, same stem
  data). If anything goes wrong, the original stays untouched.

INSTALLATION
  StemMaker already includes the StemTagger (AddOns\StemTagger.exe, button
  in the AddOns bar). Without StemMaker: unzip StemTagger-<version>.zip
  from the release page and start StemTagger.exe; keep the lang\ folder
  next to it. The language is taken from the StemMaker settings,
  otherwise from the Windows language (German, English, Spanish, French,
  Portuguese, Italian, Japanese, Dutch, Polish; any other language gets
  English).

USAGE
  - Drag stem files or whole folders onto the window
    (or "Files..." / "Folder..."; folders are searched for *.stem.mp4,
    including subfolders).
  - The Status column shows "No tags" or "No cover" where something is
    missing. Click a column header to sort the list (e.g. all tracks
    without a cover together), click again to reverse.
  - Select one or more rows and change the fields below.
    Every field explains in its tooltip (hover the mouse) what goes in.
    With several files selected, a change applies to all of them.
    Grey "<different>" means the files have different values. If you
    leave that field empty, every file keeps its own value.
  - Genre: pick from the list or type your own.
  - Cover: drag a picture onto the window, "Picture..." or "Paste"
    (Ctrl+V, e.g. a picture copied in the browser). JPEG and PNG are kept
    as they are, BMP and GIF are converted to JPEG. Pictures larger than
    1000 pixels can be shrunk (checkbox at the bottom).
  - "Artist/title from file name": "Kungs - Clap Your Hands.stem.mp4"
    gives artist "Kungs" and title "Clap Your Hands". A leading track
    number ("03. ") is dropped.
  - Save (Ctrl+S) writes all changed files.
    "Discard changes" resets everything to what is in the files.
    If several files were changed, StemTagger asks first.
  - "Create backup copy" (off by default): before the first save,
    <file>.bak is created (only once, so the real original is kept).

  Keys: Ctrl+S save, Ctrl+V paste cover, Del remove from the list,
  Ctrl+A select all.

NOTE ON TRAKTOR
  Traktor keeps the tags in its collection (collection.nml). For tracks
  that are already in Traktor, new tags show up only after reloading the
  track or after "Check Consistency". If "Write all tags to file" is on in
  Traktor, Traktor may write its own values back. The file must not be
  loaded in Traktor while saving.

MP3 FILES (since 1.1)
  MP3s are loaded like stem files (also when searching folders) and get
  the same fields. The tags live in the ID3v2 block at the start of the
  file. Only the entries of the changed fields are replaced. The audio
  data and everything else in the block stay byte for byte the same,
  especially Traktor's own data (beatgrid, cue points, analysis in the
  "TRAKTOR4" entry). When Traktor has already analysed the file, the
  Traktor column shows "yes" and the Status column "MP3 OK, with
  Traktor data". StemTagger writes the ID3
  version that is already in the file (2.3 or 2.4); MP3s without tags get
  ID3v2.3. Very old tags (ID3v2.2) and damaged tags are shown but not
  changed. An old ID3v1 tag at the end of the file is left as it is.

LOG
  logs\StemTagger.log next to the exe (if that folder is read-only:
  %APPDATA%\StemMaker\logs\).

LICENSE
  Free software (MIT), like Elospeed StemMaker. No third-party libraries
  apart from Free Pascal / Lazarus.
