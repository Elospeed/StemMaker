{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ustemjob.pas  (Unit uStemJob)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Diese Unit macht die eigentliche Arbeit: aus EINER Audiodatei (MP3, WAV,
  FLAC, ...) wird EINE Traktor-Stem-Datei (*.stem.mp4).
  Das Prinzip ist das gleiche wie bei Stemgen
  (github.com/axeldelafosse/stemgen), nur ohne Python.

  DER ABLAUF IN 5 SCHRITTEN

    1. ffmpeg     : Eingangsdatei auspacken -> mix.wav
                    (44.1 kHz, Stereo - so will es das Trenn-Modell)
    2. demucs.cpp : mix.wav in 4 Spuren zerlegen:
                    drums.wav, bass.wav, other.wav, vocals.wav
                    (demucs.cpp = C++-Version von Demucs, dem KI-Modell von
                     Meta; github.com/sevagh/demucs.cpp)
    3. ffmpeg     : Master + 4 Stems als 5 Audiospuren in EINE MP4 packen
                    (AAC oder ALAC). Tags und Cover werden aus der
                    Originaldatei übernommen. Nur Spur 1 (Master) ist
                    "aktiv" - die anderen 4 liest nur Traktor.
    4. uStemMP4   : die NI-Stem-Infos (Namen/Farben) in die MP4 schreiben
    5.            : fertige Datei an den Zielort verschieben, Temp aufräumen

  Die externen Programme (ffmpeg, demucs) werden unsichtbar im Hintergrund
  gestartet. Ihre Text-Ausgabe lesen wir mit, um daraus den Fortschritt
  (Prozent) zu berechnen und bei Fehlern die letzten Zeilen anzuzeigen.

  Wichtig: Wir starten die Programme über TProcessUTF8 (aus LazUtils).
  Damit funktionieren auch Dateinamen mit Umlauten unter Windows.
  ============================================================================ }
unit uStemJob;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UTF8Process, Process, FileUtil, LazFileUtils, IniFiles,
  {$IFDEF CPUX86_64}cpu,{$ENDIF}     // Unit 'cpu' = AVX2-Erkennung
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  uStemMP4, uLog;

type
  { Welches Trenn-Modell benutzt wird }
  TStemModel = (smHTDemucs,     // Demucs v4 - Standard
                smHTDemucsFT,   // Demucs v4 fine-tuned - beste Qualität, 4 Modelle
                smHDemucsV3);   // Demucs v3 - schneller

  { Audio-Format in der Stem-Datei }
  TStemCodec = (scAAC,          // verlustbehaftet, NI-Standard
                scALAC);        // verlustfrei (Apple Lossless), große Dateien

  { Rückmeldungen an die Oberfläche (oder an die Konsole):
    OnLog      = eine Textzeile fürs Protokoll
    OnProgress = Fortschritt 0..100 % der aktuellen Datei + Name des Schritts }
  TStemLogEvent = procedure(const Msg: string) of object;
  TStemProgressEvent = procedure(Percent: Integer; const Stage: string) of object;

  { Alle Einstellungen für einen Durchlauf }
  TStemSettings = record
    FFmpegExe   : string;   // voller Pfad zu ffmpeg.exe
    DemucsDir   : string;   // Ordner mit den demucs-Programmen
    ModelsDir   : string;   // Ordner mit den Modelldateien (ggml-model-*.bin)
    OutputDir   : string;   // Zielordner; leer = neben der Originaldatei
    Model       : TStemModel;
    Threads     : Integer;  // in wie viele Teile demucs den Song aufteilt
    Codec       : TStemCodec;
    AACBitrate  : Integer;  // kbit/s bei AAC, z.B. 256 (NI-Standard) oder 320
                            // bei AACAuto: die HÖCHSTE erlaubte Bitrate
    AACAuto     : Boolean;  // True = Bitrate passend zur Quelle wählen
                            // (siehe ChooseAACBitrate)
    Stems       : TStemInfoArray;   // Namen + Farben der 4 Stems
    Overwrite   : Boolean;  // vorhandene *.stem.mp4 überschreiben?
    KeepTemp    : Boolean;  // Temp-Ordner behalten (zur Fehlersuche)
    Normalize   : Boolean;  // Lautstärke angleichen: alle 5 Spuren gleich
                            // anheben, bis die Spitze bei ca. -1 dB liegt
    BassFix     : Boolean;  // Tiefbass unter 80 Hz von "Other" in "Bass"
    OutFile     : string;   // fester Zielname (voller Pfad), z.B. "Intro (2).stem.mp4"
                            // bei gleichen Namen; leer = aus OutputDir berechnen
  end;

  { eigene Exception-Klasse, damit "Abbrechen" kein Fehler ist }
  EStemCancelled = class(Exception);

  { TStemJob - verarbeitet eine Datei. Pro Datei wird ein neues Objekt
    erzeugt, Run aufgerufen und das Objekt wieder freigegeben. }
  TStemJob = class
  private
    FSettings  : TStemSettings;
    FCancelled : Boolean;          // wird von Cancel gesetzt
    FOnLog     : TStemLogEvent;
    FOnProgress: TStemProgressEvent;
    FTail      : TStringList;      // die letzten Ausgabezeilen (für Fehlermeldungen)
    { für die Fortschrittsberechnung aus der demucs-Ausgabe: }
    FThreadPct : array[0..127] of Double;   // Prozent je demucs-Teil
    FPhase     : Integer;          // bei htdemucs_ft: welches der 4 Modelle läuft
    FPhaseCount: Integer;          // 1 oder 4 Modelle nacheinander
    { jeder Arbeitsschritt belegt einen Bereich des Fortschrittsbalkens: }
    FStageLo, FStageHi: Integer;   // z.B. 4..90 % für demucs
    FStageName : string;
    FDurationSec: Double;          // Länge des Songs (aus ffmpeg-Ausgabe)
    FSkipped   : Boolean;          // True = übersprungen, Ziel existierte schon
    FPeakMemMB : Integer;          // höchster RAM-Verbrauch von demucs (MB)
    FLastLogPct: Integer;          // zuletzt ins Log geschriebene 10-%-Stufe
    { Angaben zur Quelldatei (aus der ffmpeg-Ausgabe beim Dekodieren): }
    FSrcCodec  : string;           // z.B. 'mp3', 'flac', 'aac'
    FSrcKbps   : Integer;          // Bitrate der Audiospur, 0 = unbekannt
    FSrcDone   : Boolean;          // True = Eingangs-Infos fertig gelesen
    FUsedKbps  : Integer;          // tatsächlich verwendete AAC-Bitrate
    { Lautheit der Master-Spur der fertigen Stem-Datei (ffmpeg-Filter
      ebur128, Werte aus der Zusammenfassung am Ende): }
    FLoudScan  : Boolean;          // True = gerade läuft die Lautheits-Messung
    FLoudI     : Double;           // Integrierte Lautheit in LUFS
    FLoudLRA   : Double;           // Lautheitsumfang (Loudness Range) in LU
    FTruePeak  : Double;           // True Peak in dBFS (über 0 = Übersteuerung)
    FLoudFound : Boolean;          // True = I: wurde gefunden
    FPeakFound : Boolean;          // True = Peak: wurde gefunden
    { Pegel-Messung für "Lautstärke angleichen" (ffmpeg-Filter astats): }
    FLevelScan : Boolean;          // True = gerade läuft die Pegel-Messung
    FMaxPeak   : Double;           // höchste Spitze aller Spuren in dBFS
    FMaxFound  : Boolean;          // True = mindestens ein Wert gefunden
    procedure Log(const Msg: string);
    procedure Progress(Percent: Integer; const Stage: string);
    procedure SetStage(Lo, Hi: Integer; const Name: string);
    function RunTool(const Exe: string; const Args: array of string;
      IsDemucs: Boolean): Integer;
    procedure HandleLine(const Line: string; IsDemucs: Boolean);
    function DemucsExePath: string;
    function DemucsModelArg: string;
    function OmpThreads: Integer;
  public
    constructor Create(const ASettings: TStemSettings);
    destructor Destroy; override;
    { Wandelt InputFile um. OutFile = Name der fertigen *.stem.mp4.
      Rückgabe True = erfolgreich, sonst steht der Grund in ErrMsg. }
    function Run(const InputFile: string; out OutFile, ErrMsg: string): Boolean;
    { Bricht einen laufenden Run ab (darf aus einem anderen Thread kommen) }
    procedure Cancel;
    { Prüft ob ffmpeg, demucs und die Modelldateien vorhanden sind }
    function CheckTools(out Problems: string): Boolean;
    property Skipped: Boolean read FSkipped;
    { wie viel Arbeitsspeicher demucs maximal gebraucht hat (0 = unbekannt) }
    property PeakMemMB: Integer read FPeakMemMB;
    { AAC-Bitrate der letzten Datei (0 = ALAC) }
    property UsedKbps: Integer read FUsedKbps;
    { Anzahl Kerne, die jedes demucs-Teilstück zusätzlich nutzt }
    function OmpThreadsPublic: Integer;
    property OnLog: TStemLogEvent read FOnLog write FOnLog;
    property OnProgress: TStemProgressEvent read FOnProgress write FOnProgress;
  end;

const
  { Anzeigenamen der Modelle (Reihenfolge = TStemModel) }
  StemModelNames: array[TStemModel] of string = (
    'htdemucs (Standard, Demucs v4)',
    'htdemucs_ft (beste Qualität, ca. 4x langsamer)',
    'hdemucs_mmi (Demucs v3, schneller)');
  { Hinweis: StemModelNames bleibt deutsch (feste Konstante, _() geht hier
    nicht). Für die ANZEIGE StemModelDisplayName benutzen - das übersetzt. }

  { Diese Dateitypen nehmen wir an (ffmpeg kann sie alle lesen) }
  SupportedInputExt: array[0..9] of string = (
    '.mp3', '.wav', '.wave', '.flac', '.aif', '.aiff', '.m4a', '.aac',
    '.ogg', '.opus');

{ Anzeigename eines Modells in der aktuellen Sprache (für Auswahlliste/Log) }
function StemModelDisplayName(M: TStemModel): string;
{ Ist die Datei ein unterstütztes Audioformat? (nach Dateiendung) }
function IsSupportedInput(const FileName: string): Boolean;
{ Standard-Einstellungen (Werkzeuge in tools\ und models\ neben der Exe) }
function DefaultStemSettings: TStemSettings;
{ Hängt unter Windows '.exe' an einen Programmnamen an }
function ExeName(const Base: string): string;
{ Name der Zieldatei: '<Titel>.stem.mp4' im Zielordner
  (oder neben der Originaldatei, wenn OutputDir leer ist) }
function StemOutputName(const InputFile, OutputDir: string): string;
{ Wie StemOutputName, aber eindeutig innerhalb einer Liste: Landen zwei
  Dateien auf demselben Namen (z.B. A\Intro.mp3 und B\Intro.mp3 im selben
  Ausgabeordner, oder Song.mp3 + Song.wav nebeneinander), bekommt die
  zweite "Intro (2).stem.mp4", die dritte "(3)" usw.
  Used = schon vergebene Namen; der neue Name wird dort eingetragen.
  Used muss mit NewUsedNameList angelegt werden. }
function UniqueStemOutputName(const InputFile, OutputDir: string;
  Used: TStringList): string;
{ leere Namensliste für UniqueStemOutputName (sortiert, Gross/klein egal
  - wie bei Windows-Dateinamen) }
function NewUsedNameList: TStringList;
{ Beim Programmstart: Arbeitsordner in %TEMP%\StemMaker, die von einem
  Absturz übrig sind, löschen. Ordner, die gerade ein anderer StemMaker
  oder StemCLI benutzt, bleiben stehen. Ergebnis = Anzahl gelöschter
  Ordner, FreedMB = freigegebener Platz. }
function CleanupStaleTempDirs(out FreedMB: Int64): Integer;

{ Name der Einstellungsdatei: StemMaker.ini neben der Exe (portabel).
  Ist der Programmordner schreibgeschützt (z.B. unter C:\Programme),
  wird stattdessen der Benutzer-Konfigurationsordner genommen. }
function StemIniFileName: string;
{ Liest die Werkzeug-Pfade [Tools] und das gewählte Modell aus der INI }
procedure LoadToolSettings(var S: TStemSettings);
{ Welches demucs-Programm wird für das Modell benutzt?
  (automatisch die schnelle AVX2- oder die kompatible Version) }
function DemucsExeFor(const DemucsDir: string; Model: TStemModel): string;
{ Welche Modelldateien braucht das Modell? (volle Pfade) }
function ModelFilesFor(const ModelsDir: string; Model: TStemModel): TStringArray;
{ Kann die CPU AVX2? (Befehlssatz für schnelle Berechnungen, ab ca. 2013) }
function CpuHasAVX2: Boolean;
{ Kann die CPU AVX? (Vorgänger von AVX2, ab ca. 2011 - z.B. Sandy Bridge) }
function CpuHasAVX: Boolean;
{ Anzahl ECHTER Prozessorkerne (ohne Hyperthreading), von Windows abgefragt }
function PhysicalCoreCount: Integer;
{ empfohlene Anzahl demucs-Teile für diesen Rechner (Einstellung "Auto") }
function AutoThreads: Integer;
{ höchstens so viele Teile erlaubt der Arbeitsspeicher }
function AutoThreadsRAMLimit: Integer;
{ AAC-Bitrate passend zur Quelle wählen (Einstellung "AAC automatisch") }
function ChooseAACBitrate(const SrcCodec: string; SrcKbps, MaxKbps: Integer): Integer;
{ Name der demucs-Version, die verwendet wird: 'AVX2', 'AVX' oder 'generic' }
function DemucsVariantName(const ExePath: string): string;

implementation

uses
  uLang;

const
  { Sperrdatei in jedem Arbeitsordner unter %TEMP%\StemMaker\<Lauf>\ }
  TEMP_LOCK_NAME = 'in-arbeit.lock';
  { Ordner ohne Sperrdatei (z.B. "Temp-Ordner behalten") werden erst nach
    so vielen Stunden beim Start gelöscht }
  TEMP_MAX_AGE_H = 12;
  { Dateinamen der Modelle - genau so heißen sie auch auf Hugging Face }
  FT_MODELS: array[0..3] of string = (
    'ggml-model-htdemucs_ft_drums-4s-f16.bin',
    'ggml-model-htdemucs_ft_bass-4s-f16.bin',
    'ggml-model-htdemucs_ft_other-4s-f16.bin',
    'ggml-model-htdemucs_ft_vocals-4s-f16.bin');
  HT_MODEL = 'ggml-model-htdemucs-4s-f16.bin';
  V3_MODEL = 'ggml-model-hdemucs_mmi-v3-f16.bin';

  { So nennt demucs.cpp seine 4 Ausgabedateien (feste Reihenfolge) }
  STEM_WAVS: array[0..3] of string = (
    'target_0_drums.wav', 'target_1_bass.wav',
    'target_2_other.wav', 'target_3_vocals.wav');

  { ---- Klang-Optionen (siehe StemFilter und TStemJob.Run) ---- }
  { Bass-Fix: bis zu dieser Frequenz wandert der Tiefbass von "Other" nach
    "Bass". Gemessen am 4.10.2026 gegen Traktor Pro 4: Traktor legt den
    Tiefbass in den Bass-Stem, demucs lässt einen Rest in "Other". }
  BASSFIX_HZ = '80';
  { Der Tiefpass läuft vorwärts UND rückwärts (siehe StemFilter). Dafür
    hält ffmpeg die ganze Spur im Speicher - bei sehr langen Dateien (DJ-Mixe)
    wird der Bass-Fix deshalb ausgelassen. 20 min = ca. 1 GB RAM. }
  BASSFIX_MAX_SEC = 20 * 60;
  { Lautstärke angleichen: Ziel für die höchste Sample-Spitze aller Spuren.
    AAC hebt Spitzen beim Kodieren leicht an - mit -1,5 dB landet der
    True Peak der fertigen Datei bei ungefähr -1 dB. }
  NORM_TARGET_DB = -1.5;
  { höchstens so viel anheben (fast stille Dateien nicht ins Rauschen ziehen) }
  NORM_MAX_GAIN_DB = 24.0;
  { kleinere Änderungen lohnen das Neuberechnen nicht }
  NORM_MIN_GAIN_DB = 0.1;
  { astats: nur die Gesamt-Spitze ausgeben (eine Zeile pro Spur) }
  ASTATS_PEAK = 'astats=measure_perchannel=none:measure_overall=Peak_level';

{ Baut den ffmpeg-Filter für die 4 Stems.
    InL  = Eingänge in der Reihenfolge Drums, Bass, Other, Vocals, z.B. '[2:a]'
    OutL = Namen der Ausgänge, z.B. '[a1]'
    Tail = Filter, der an jede Spur angehängt wird (z.B. ',volume=11.6dB'),
           leer = nichts
  Jede Spur wird zuerst in Gleitkomma umgewandelt (aformat=...flt). So kann
  beim Rechnen nichts abgeschnitten werden.

  Bass-Fix (wenn BassFix = True):
    tief  = Other durch einen Tiefpass (2x lowpass = steile Flanke, 80 Hz)
    Other = Other - tief      (pan: c0=c0-c2 heißt linker Kanal minus
    Bass  = Bass  + tief       linker Kanal des zweiten Eingangs)
  Wichtig: Ein normaler Tiefpass verschiebt die Phase, dann passt "tief"
  nicht mehr zum Bass in Other - Abziehen würde den Rest sogar lauter
  machen (getestet). Darum läuft der Tiefpass einmal vorwärts und einmal
  rückwärts (areverse), so heben sich die Verschiebungen auf.
  Was Other verliert, bekommt Bass genau dazu - die Summe aller Stems
  bleibt also exakt gleich. amerge legt die zwei Stereo-Eingänge zu
  4 Kanälen zusammen (c0/c1 = erster, c2/c3 = zweiter Eingang). }
function StemFilter(const InL, OutL: array of string; const Tail: string;
  BassFix: Boolean): string;
const
  FLT = 'aformat=sample_fmts=flt';
begin
  Result :=
    InL[0] + FLT + Tail + OutL[0] + ';' +
    InL[3] + FLT + Tail + OutL[3] + ';';
  if BassFix then
    Result := Result +
      InL[2] + FLT + ',asplit=2[bfo1][bfo2];' +
      '[bfo1]lowpass=f=' + BASSFIX_HZ + ',lowpass=f=' + BASSFIX_HZ +
        ',areverse,lowpass=f=' + BASSFIX_HZ + ',lowpass=f=' + BASSFIX_HZ +
        ',areverse,asplit=2[bfl1][bfl2];' +
      '[bfo2][bfl1]amerge=inputs=2,pan=stereo|c0=c0-c2|c1=c1-c3' + Tail + OutL[2] + ';' +
      InL[1] + FLT + '[bfb];' +
      '[bfb][bfl2]amerge=inputs=2,pan=stereo|c0=c0+c2|c1=c1+c3' + Tail + OutL[1]
  else
    Result := Result +
      InL[1] + FLT + Tail + OutL[1] + ';' +
      InL[2] + FLT + Tail + OutL[2];
end;

function StemModelDisplayName(M: TStemModel): string;
begin
  { gleiche Texte wie in StemModelNames, aber übersetzbar }
  case M of
    smHTDemucsFT: Result := _('htdemucs_ft (beste Qualität, ca. 4x langsamer)');
    smHDemucsV3 : Result := _('hdemucs_mmi (Demucs v3, schneller)');
  else
    Result := _('htdemucs (Standard, Demucs v4)');
  end;
end;

function ExeName(const Base: string): string;
begin
  {$IFDEF WINDOWS}
  Result := Base + '.exe';
  {$ELSE}
  Result := Base;
  {$ENDIF}
end;

function IsSupportedInput(const FileName: string): Boolean;
var
  E: string;
  I: Integer;
begin
  E := LowerCase(ExtractFileExt(FileName));
  for I := Low(SupportedInputExt) to High(SupportedInputExt) do
    if E = SupportedInputExt[I] then
      Exit(True);
  Result := False;
end;

function DefaultStemSettings: TStemSettings;
var
  AppDir: string;
begin
  AppDir := AppBaseDir;   // StemMaker-Hauptordner (auch wenn die Exe in Extras\ liegt)
  Result := Default(TStemSettings);
  Result.FFmpegExe  := AppDir + 'tools' + PathDelim + ExeName('ffmpeg');
  Result.DemucsDir  := AppDir + 'tools';
  Result.ModelsDir  := AppDir + 'models';
  Result.OutputDir  := '';
  Result.Model      := smHTDemucs;
  Result.Threads    := AutoThreads;    // siehe AutoThreads
  Result.Codec      := scAAC;
  Result.AACBitrate := 320;            // Obergrenze ...
  Result.AACAuto    := True;           // ... Bitrate richtet sich nach der Quelle
  Result.Stems      := DefaultStemInfo;
  Result.Overwrite  := False;
  Result.KeepTemp   := False;
  Result.Normalize  := True;           // Standard: Club-Pegel
  Result.BassFix    := True;           // Standard: Bass-Fix an
  Result.OutFile    := '';             // Zielname aus OutputDir berechnen
end;

function StemOutputName(const InputFile, OutputDir: string): string;
var
  Dir: string;
begin
  if OutputDir = '' then
    Dir := ExtractFilePath(InputFile)
  else
    Dir := IncludeTrailingPathDelimiter(OutputDir);
  Result := Dir + ExtractFileNameOnly(InputFile) + '.stem.mp4';
end;

function NewUsedNameList: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;   // Windows: "intro" = "Intro"
  Result.Sorted := True;           // schnelles Suchen auch bei 10000 Dateien
  Result.Duplicates := dupIgnore;
end;

function UniqueStemOutputName(const InputFile, OutputDir: string;
  Used: TStringList): string;
var
  Base: string;
  N, Dummy: Integer;
begin
  Result := StemOutputName(InputFile, OutputDir);
  Base := Copy(Result, 1, Length(Result) - Length('.stem.mp4'));
  N := 1;
  while Used.Find(Result, Dummy) do
  begin
    Inc(N);
    Result := Base + ' (' + IntToStr(N) + ').stem.mp4';
  end;
  Used.Add(Result);
end;

{ Zeitpunkt der letzten Änderung in einem Ordner: der Ordner selbst und
  alle Dateien darin; Bytes = Gesamtgrösse der Dateien }
function NewestChange(const Dir: string; out Bytes: Int64): TDateTime;
var
  SR: TSearchRec;
  Files: TStringList;
  I: Integer;
  Age: LongInt;
begin
  Result := 0;
  Bytes := 0;
  if FindFirst(ExcludeTrailingPathDelimiter(Dir), faDirectory, SR) = 0 then
  begin
    Result := FileDateToDateTime(SR.Time);
    SysUtils.FindClose(SR);
  end;
  Files := FindAllFiles(Dir, '*', True);
  try
    for I := 0 to Files.Count - 1 do
    begin
      Inc(Bytes, FileSizeUtf8(Files[I]));
      Age := FileAgeUTF8(Files[I]);
      if (Age <> -1) and (FileDateToDateTime(Age) > Result) then
        Result := FileDateToDateTime(Age);
    end;
  finally
    Files.Free;
  end;
end;

function CleanupStaleTempDirs(out FreedMB: Int64): Integer;
var
  Base, Dir, Lock: string;
  Dirs: TStringList;
  I: Integer;
  Bytes: Int64;
  Newest: TDateTime;
  Stale: Boolean;
begin
  Result := 0;
  FreedMB := 0;
  Base := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'StemMaker';
  if not DirectoryExists(Base) then Exit;
  Dirs := FindAllDirectories(Base, False);
  try
    for I := 0 to Dirs.Count - 1 do
    begin
      Dir := IncludeTrailingPathDelimiter(Dirs[I]);
      Lock := Dir + TEMP_LOCK_NAME;
      Newest := NewestChange(Dir, Bytes);
      if FileExists(Lock) then
        { Sperrdatei da: Lässt sie sich löschen, ist der Besitzer nicht
          mehr da (Absturz). Ist sie noch offen, arbeitet dort gerade ein
          anderer StemMaker/StemCLI -> stehen lassen. }
        Stale := SysUtils.DeleteFile(Lock)
      else
        { keine Sperrdatei ("Temp-Ordner behalten" oder ältere Version):
          erst nach TEMP_MAX_AGE_H Stunden löschen }
        Stale := (Now - Newest) * 24 > TEMP_MAX_AGE_H;
      if Stale and DeleteDirectory(Dirs[I], False) then
      begin
        Inc(Result);
        Inc(FreedMB, Bytes);
      end;
    end;
  finally
    Dirs.Free;
  end;
  FreedMB := FreedMB div 1048576;
end;

function StemIniFileName: string;
begin
  { Immer "StemMaker.ini" - auch für StemCLI.exe. So nutzen beide
    Programme dieselben Einstellungen (Sprache, Werkzeug-Pfade, Tempo).
    (Bis 1.5 hat StemCLI fälschlich nach "StemCLI.ini" gesucht.) }
  Result := AppBaseDir + 'StemMaker.ini';
  if not DirectoryIsWritable(ExtractFilePath(Result)) then
  begin
    { Programmordner schreibgeschützt (z.B. C:\Programme):
      dann %APPDATA%\StemMaker\StemMaker.ini }
    Result := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
      'StemMaker' + PathDelim;
    ForceDirectories(Result);
    Result := Result + 'StemMaker.ini';
  end;
end;

procedure LoadToolSettings(var S: TStemSettings);
var
  Ini: TIniFile;
  M: Integer;
begin
  if not FileExists(StemIniFileName) then
    Exit;                          // noch keine INI -> Standardwerte bleiben
  Ini := TIniFile.Create(StemIniFileName);
  try
    S.FFmpegExe := Ini.ReadString('Tools', 'FFmpeg', S.FFmpegExe);
    S.DemucsDir := Ini.ReadString('Tools', 'DemucsDir', S.DemucsDir);
    S.ModelsDir := Ini.ReadString('Tools', 'ModelsDir', S.ModelsDir);
    M := Ini.ReadInteger('Main', 'Model', Ord(S.Model));
    if (M >= Ord(Low(TStemModel))) and (M <= Ord(High(TStemModel))) then
      S.Model := TStemModel(M);
    { Klang-Optionen aus dem Hauptfenster - so macht StemCLI dasselbe }
    S.Normalize := Ini.ReadBool('Main', 'Normalize', S.Normalize);
    S.BassFix := Ini.ReadBool('Main', 'BassFix', S.BassFix);
  finally
    Ini.Free;
  end;
end;

function CpuHasAVX2: Boolean;
begin
  {$IFDEF CPUX86_64}
  Result := AVX2Support;           // kommt aus der FPC-Unit 'cpu'
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function CpuHasAVX: Boolean;
begin
  {$IFDEF CPUX86_64}
  Result := AVXSupport;            // prüft auch, ob Windows AVX freigibt
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

{$IFDEF WINDOWS}
{ Windows-Funktion, die die Prozessor-Struktur beschreibt. Für jeden
  echten Kern gibt es einen Eintrag vom Typ "RelationProcessorCore". }
function GetLogicalProcessorInformation(Buffer: Pointer; var ReturnLength: DWORD): BOOL;
  stdcall; external 'kernel32.dll';
{$ENDIF}

function PhysicalCoreCount: Integer;
{$IFDEF WINDOWS}
var
  Len: DWORD;
  Buf: array of Byte;
  P: PByte;
  Entry: Integer;
  ItemSize: Integer;
{$ENDIF}
begin
  Result := 0;
  {$IFDEF WINDOWS}
  { 1. Aufruf: Windows sagt, wie viel Platz es braucht
    2. Aufruf: Daten holen und die "Kern"-Einträge zählen }
  ItemSize := 32;                  // Größe eines Eintrags unter 64 Bit
  Len := 0;
  GetLogicalProcessorInformation(nil, Len);
  if Len > 0 then
  begin
    SetLength(Buf, Len);
    if GetLogicalProcessorInformation(@Buf[0], Len) then
    begin
      P := @Buf[0];
      for Entry := 0 to Integer(Len) div ItemSize - 1 do
      begin
        if PDWORD(P + SizeOf(PtrUInt))^ = 0 then   // RelationProcessorCore
          Inc(Result);
        Inc(P, ItemSize);
      end;
    end;
  end;
  {$ENDIF}
  { Notlösung, falls die Abfrage nicht klappt: logische Kerne / 2 }
  if Result < 1 then
    Result := TThread.ProcessorCount div 2;
  if Result < 1 then
    Result := 1;
end;

{ Empfehlung für die Anzahl demucs-Teile ("Auto"):
  demucs teilt den Song in so viele Stücke und rechnet sie gleichzeitig.
  Jedes Stück nutzt zusätzlich mehrere Kerne (OmpThreads).
  Laut dem demucs.cpp-Autor ist "4 Stücke x 4 Kerne" auf 16 Kernen am
  schnellsten. Daher: so viele Teile wie ECHTE Kerne, höchstens 4.
  Beispiele:  4 Kerne (i5-2500)       -> 4 Teile x 1 Kern
              8 Kerne / 16 Threads    -> 4 Teile x 2 Kerne
              16 Kerne / 32 Threads   -> 4 Teile x 4 Kerne

  ZWEITE GRENZE: ARBEITSSPEICHER
  Jeder Teil braucht beim Standardmodell gut 2 GB RAM (gemessen auf dem
  i5-2500 mit einem 12-Minuten-Track: 2 Teile = 4.8 GB, 4 Teile = 8.6 GB).
  Reicht der RAM nicht, lagert Windows auf die Festplatte aus - dann wird
  es nicht schneller, sondern VIEL langsamer. Deshalb: pro Teil 2.3 GB
  einplanen und 2 GB für Windows und andere Programme frei lassen.
              8 GB RAM  -> höchstens 2 Teile
              16 GB RAM -> höchstens 4 Teile }
const
  RAM_PER_PART_MB = 2300;
  RAM_RESERVE_MB  = 2048;

function AutoThreadsRAMLimit: Integer;
var
  MB: Int64;
begin
  MB := SysRAMTotalMB;
  if MB <= 0 then
    Exit(4);                                      // unbekannt -> keine Grenze
  Result := (MB - RAM_RESERVE_MB) div RAM_PER_PART_MB;
  if Result < 1 then Result := 1;
end;

function AutoThreads: Integer;
begin
  Result := PhysicalCoreCount;
  if Result > 4 then Result := 4;
  if Result > AutoThreadsRAMLimit then Result := AutoThreadsRAMLimit;
  if Result < 1 then Result := 1;
end;

{ ---------------------------------------------------------------------------
  "AAC automatisch": welche Bitrate passt zur Quelle?

  Grundsatz: Besser als die Quelle wird es nie. Eine 256er-MP3 mit 320
  zu speichern macht die Datei nur grösser, nicht besser.
  Deshalb nehmen wir die nächste übliche Stufe, die mindestens so hoch
  ist wie die Quelle:
      Quelle 320 kbit/s          -> 320
      Quelle 256 kbit/s          -> 256
      Quelle 245 kbit/s (VBR)    -> 256
      Quelle 192 kbit/s          -> 192
      Quelle 128 kbit/s          -> 192  (!)
  Warum bei 128 trotzdem 192? Jedes Neu-Kodieren verliert nochmals etwas.
  Bei sehr niedriger Bitrate hört man das (zweimal "zusammengepresst").
  192 kbit/s AAC ist sicher genug, dass nichts Zusätzliches verloren geht.
  Verlustfreie Quellen (WAV, FLAC, ALAC, AIFF) und unbekannte Bitraten
  bekommen die eingestellte Obergrenze.
  --------------------------------------------------------------------------- }
function ChooseAACBitrate(const SrcCodec: string; SrcKbps, MaxKbps: Integer): Integer;
const
  STEPS: array[0..2] of Integer = (192, 256, 320);
var
  C: string;
  I: Integer;
begin
  C := LowerCase(SrcCodec);
  if (SrcKbps <= 0) or (Pos('pcm', C) = 1) or (C = 'flac') or (C = 'alac') or
     (C = 'wavpack') or (C = 'ape') then
    Exit(MaxKbps);
  Result := STEPS[High(STEPS)];
  for I := Low(STEPS) to High(STEPS) do
    if STEPS[I] >= SrcKbps - 5 then        // 5 kbit/s Toleranz (z.B. 251 -> 256)
    begin
      Result := STEPS[I];
      Break;
    end;
  if Result > MaxKbps then
    Result := MaxKbps;
end;

function DemucsVariantName(const ExePath: string): string;
begin
  if Pos(PathDelim + 'generic' + PathDelim, ExePath) > 0 then
    Result := 'generic'
  else if Pos(PathDelim + 'avx' + PathDelim, ExePath) > 0 then
    Result := 'AVX'
  else
    Result := 'AVX2';
end;

function DemucsExeFor(const DemucsDir: string; Model: TStemModel): string;
var
  D, Base: string;
begin
  D := IncludeTrailingPathDelimiter(DemucsDir);
  { für jedes Modell gibt es ein eigenes demucs-Programm
    ("_mt" = multi-threaded, rechnet mehrere Teile gleichzeitig) }
  case Model of
    smHTDemucsFT: Base := ExeName('demucs_ft_mt.cpp.main');
    smHDemucsV3 : Base := ExeName('demucs_v3_mt.cpp.main');
  else
    Base := ExeName('demucs_mt.cpp.main');
  end;
  Result := D + Base;
  { Es gibt drei Versionen - je neuer die CPU, desto schneller:
      tools\          AVX2  (ab ca. 2013, z.B. Intel Haswell, AMD Ryzen)
      tools\avx\      AVX   (ab ca. 2011, z.B. Intel Sandy/Ivy Bridge)
      tools\generic\  ohne AVX (ältere CPUs)
    Eine Version mit Befehlen, die die CPU nicht kennt, würde sofort
    abstürzen - darum wird hier sorgfältig ausgewählt. }
  if not CpuHasAVX2 then
  begin
    if CpuHasAVX and FileExists(D + 'avx' + PathDelim + Base) then
      Result := D + 'avx' + PathDelim + Base
    else if FileExists(D + 'generic' + PathDelim + Base) then
      Result := D + 'generic' + PathDelim + Base;
  end;
end;

function ModelFilesFor(const ModelsDir: string; Model: TStemModel): TStringArray;
var
  D: string;
  I: Integer;
begin
  Result := nil;
  D := IncludeTrailingPathDelimiter(ModelsDir);
  case Model of
    smHTDemucsFT:
      begin
        { fine-tuned: ein eigenes Modell pro Stem = 4 Dateien }
        SetLength(Result, 4);
        for I := 0 to 3 do
          Result[I] := D + FT_MODELS[I];
      end;
    smHDemucsV3:
      begin
        SetLength(Result, 1);
        Result[0] := D + V3_MODEL;
      end;
  else
    begin
      SetLength(Result, 1);
      Result[0] := D + HT_MODEL;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  TStemJob
  --------------------------------------------------------------------------- }
constructor TStemJob.Create(const ASettings: TStemSettings);
begin
  inherited Create;
  FSettings := ASettings;
  { Threads auf einen sinnvollen Bereich begrenzen }
  if FSettings.Threads < 1 then
    FSettings.Threads := 1;
  if FSettings.Threads > High(FThreadPct) + 1 then
    FSettings.Threads := High(FThreadPct) + 1;
  FTail := TStringList.Create;
end;

destructor TStemJob.Destroy;
begin
  FTail.Free;
  inherited Destroy;
end;

procedure TStemJob.Cancel;
begin
  { nur ein Merker - RunTool prüft ihn regelmäßig und beendet dann das
    laufende Programm }
  FCancelled := True;
end;

procedure TStemJob.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

procedure TStemJob.Progress(Percent: Integer; const Stage: string);
begin
  if Percent < 0 then Percent := 0;
  if Percent > 100 then Percent := 100;
  { nur in die Log-Datei: alle 10 % eine Zeile - so sieht man nach einem
    Absturz, wie weit es gekommen ist }
  if (Percent div 10) > FLastLogPct then
  begin
    FLastLogPct := Percent div 10;
    LogLine(Format('    Fortschritt %d %% (%s)', [Percent, Stage]));
  end;
  if Assigned(FOnProgress) then
    FOnProgress(Percent, Stage);
end;

{ Legt fest, welchen Bereich des Fortschrittsbalkens der nächste Schritt
  belegt. Beispiel: demucs läuft von 4 % bis 90 %. Meldet demucs "50 %",
  zeigen wir 4 + (90-4) * 0.5 = 47 % an. }
procedure TStemJob.SetStage(Lo, Hi: Integer; const Name: string);
begin
  FStageLo := Lo;
  FStageHi := Hi;
  FStageName := Name;
  Progress(Lo, Name);
end;

function TStemJob.DemucsExePath: string;
begin
  Result := DemucsExeFor(FSettings.DemucsDir, FSettings.Model);
end;

{ Erster Parameter für demucs: die Modelldatei - bzw. bei htdemucs_ft der
  ganze Ordner (das Programm sucht sich die 4 Dateien darin selbst) }
function TStemJob.DemucsModelArg: string;
var
  D: string;
begin
  D := IncludeTrailingPathDelimiter(FSettings.ModelsDir);
  case FSettings.Model of
    smHTDemucs  : Result := D + HT_MODEL;
    smHTDemucsFT: Result := ExcludeTrailingPathDelimiter(FSettings.ModelsDir);
    smHDemucsV3 : Result := D + V3_MODEL;
  end;
end;

{ Wie viele Kerne darf JEDES demucs-Teilstück zusätzlich benutzen?
  Echte Kerne (PhysicalCoreCount) geteilt durch die Anzahl Teilstücke.
  Beispiel: 8 echte Kerne, 4 Teile -> 8 / 4 = 2 pro Teil. }
function TStemJob.OmpThreads: Integer;
var
  Physical: Integer;
begin
  Physical := PhysicalCoreCount;
  Result := Physical div FSettings.Threads;
  if Result < 1 then Result := 1;
end;

function TStemJob.OmpThreadsPublic: Integer;
begin
  Result := OmpThreads;
end;

{$IFDEF WINDOWS}
{ Windows-Funktion zum Abfragen des Speicherverbrauchs eines Prozesses }
type
  TProcessMemoryCounters = record
    cb: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize, WorkingSetSize,
    QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage,
    QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage,
    PagefileUsage, PeakPagefileUsage: PtrUInt;
  end;

function GetProcessMemoryInfo(Process: THandle; var Counters: TProcessMemoryCounters;
  cb: DWORD): BOOL; stdcall; external 'psapi.dll';

{ höchster RAM-Verbrauch ("Peak Working Set") eines Prozesses in MB }
function PeakMemoryMB(H: THandle): Integer;
var
  C: TProcessMemoryCounters;
begin
  Result := 0;
  FillChar(C, SizeOf(C), 0);
  C.cb := SizeOf(C);
  if GetProcessMemoryInfo(H, C, SizeOf(C)) then
    Result := C.PeakWorkingSetSize div (1024 * 1024);
end;

{ ---- Windows-Job-Objekt: Hilfsprogramme sterben mit StemMaker ----------
  ffmpeg und demucs laufen als eigene Prozesse. Wird StemMaker hart
  beendet (Absturz, Task-Manager), würde demucs sonst im Hintergrund
  weiterrechnen - nach einem Neustart liefen dann zwei Trennungen
  gleichzeitig. Darum kommen alle Hilfsprogramme in ein "Job-Objekt" mit
  der Einstellung "beim Schliessen alle Prozesse beenden". Das Handle
  darauf wird nie geschlossen: Windows schliesst es, wenn StemMaker endet
  (egal wie), und beendet dabei alle Prozesse im Job. }
const
  JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $2000;
  JobObjectExtendedLimitInformation  = 9;

type
  { Aufbau wie in der Windows-Doku (winnt.h), normale Ausrichtung }
  TJobBasicLimitInfo = record
    PerProcessUserTimeLimit: Int64;
    PerJobUserTimeLimit: Int64;
    LimitFlags: DWORD;
    MinimumWorkingSetSize: PtrUInt;
    MaximumWorkingSetSize: PtrUInt;
    ActiveProcessLimit: DWORD;
    Affinity: PtrUInt;
    PriorityClass: DWORD;
    SchedulingClass: DWORD;
  end;
  TJobIoCounters = record
    ReadOperationCount, WriteOperationCount, OtherOperationCount,
    ReadTransferCount, WriteTransferCount, OtherTransferCount: QWord;
  end;
  TJobExtendedLimitInfo = record
    BasicLimitInformation: TJobBasicLimitInfo;
    IoInfo: TJobIoCounters;
    ProcessMemoryLimit, JobMemoryLimit,
    PeakProcessMemoryUsed, PeakJobMemoryUsed: PtrUInt;
  end;

function SmCreateJobObject(lpJobAttributes: Pointer; lpName: PWideChar): THandle;
  stdcall; external 'kernel32.dll' name 'CreateJobObjectW';
function SmSetInformationJobObject(hJob: THandle; InfoClass: DWORD;
  lpInfo: Pointer; cbInfo: DWORD): BOOL;
  stdcall; external 'kernel32.dll' name 'SetInformationJobObject';
function SmAssignProcessToJobObject(hJob, hProcess: THandle): BOOL;
  stdcall; external 'kernel32.dll' name 'AssignProcessToJobObject';

var
  ToolJob: THandle = 0;    // 0 = (noch) kein Job-Objekt

{ Job-Objekt anlegen (einmal beim Programmstart, siehe initialization) }
procedure CreateToolJob;
var
  Info: TJobExtendedLimitInfo;
begin
  ToolJob := SmCreateJobObject(nil, nil);
  if ToolJob = 0 then Exit;
  FillChar(Info, SizeOf(Info), 0);
  Info.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if not SmSetInformationJobObject(ToolJob, JobObjectExtendedLimitInformation,
    @Info, SizeOf(Info)) then
  begin
    CloseHandle(ToolJob);
    ToolJob := 0;
  end;
end;

{ gestartetes Hilfsprogramm in den Job stecken. Klappt das nicht (z.B.
  Windows 7, wenn StemMaker selbst schon in einem fremden Job läuft),
  läuft alles wie bisher weiter - nur ohne diesen Schutz. }
procedure AddToToolJob(hProcess: THandle);
begin
  if ToolJob <> 0 then
    SmAssignProcessToJobObject(ToolJob, hProcess);
end;
{$ENDIF}

function TStemJob.CheckTools(out Problems: string): Boolean;
var
  I: Integer;
  Files: TStringArray;
begin
  Problems := '';
  if not FileExists(FSettings.FFmpegExe) then
    Problems := Problems + Format(_('ffmpeg nicht gefunden: %s'), [FSettings.FFmpegExe]) + LineEnding;
  if not FileExists(DemucsExePath) then
    Problems := Problems + Format(_('demucs.cpp nicht gefunden: %s'), [DemucsExePath]) + LineEnding;
  Files := ModelFilesFor(FSettings.ModelsDir, FSettings.Model);
  for I := 0 to High(Files) do
    if not FileExists(Files[I]) then
      Problems := Problems + Format(_('Modell fehlt: %s'), [Files[I]]) + LineEnding;
  Result := Problems = '';
end;

{ ---------------------------------------------------------------------------
  HandleLine - wertet eine Ausgabezeile von ffmpeg oder demucs aus

  ffmpeg schreibt z.B.:
      "Duration: 00:03:21.45, ..."   -> Länge des Songs merken
      "... time=00:01:02.33 ..."     -> so weit ist ffmpeg schon
  daraus ergibt sich der Fortschritt in Prozent.

  demucs schreibt z.B.:
      "[THREAD 3] ( 42.308%) Freq: decoder 3"
      "DRUMS	 [THREAD 0] ( 12.000%) ..."      (htdemucs_ft: 4 Modelle nacheinander)
  Jedes Teilstück (THREAD) meldet seine eigenen Prozente. Der Gesamt-
  fortschritt ist der Durchschnitt aller Teilstücke.
  --------------------------------------------------------------------------- }
procedure TStemJob.HandleLine(const Line: string; IsDemucs: Boolean);

  { liest eine Zeitangabe "hh:mm:ss.xx" und gibt Sekunden zurück }
  function ParseTime(const S: string; out Sec: Double): Boolean;
  var
    H, M: Integer;
    X: Double;
    FS: TFormatSettings;
  begin
    Result := False;
    Sec := 0;
    if Length(S) < 8 then Exit;
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';          // ffmpeg nutzt immer den Punkt
    if not TryStrToInt(Copy(S, 1, 2), H) then Exit;
    if not TryStrToInt(Copy(S, 4, 2), M) then Exit;
    if not TryStrToFloat(Copy(S, 7, 5), X, FS) then Exit;
    Sec := H * 3600 + M * 60 + X;
    Result := True;
  end;

var
  P, Q, T, I, N: Integer;
  Pct, Sum, Sec: Double;
  NumStr: string;
  FS: TFormatSettings;
begin
  if Trim(Line) = '' then Exit;

  { Ausgabe der Programme auch ins Log schreiben - aber ohne die vielen
    Fortschritts- und Ladezeilen, sonst wird das Log riesig }
  if (Pos('time=', Line) = 0) and (Pos('%)', Line) = 0) and
     (Pos('tensor', Line) = 0) and (Pos(', type = ', Line) = 0) then
    LogLine('    | ' + Line);

  { die letzten 25 Zeilen merken - bei einem Fehler zeigen wir sie an }
  FTail.Add(Line);
  while FTail.Count > 25 do
    FTail.Delete(0);

  if FLoudScan then
  begin
    { ---- Lautheits-Messung (ebur128-Zusammenfassung) ----
      ffmpeg schreibt am Ende z.B.:
          I:         -9.1 LUFS
          LRA:        5.3 LU
          Peak:       0.4 dBFS
      Die Zahl steht zwischen dem ":" und der Einheit. Der Punkt ist bei
      ffmpeg immer der Dezimaltrenner. }
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    NumStr := Trim(Line);
    if (Copy(NumStr, 1, 2) = 'I:') and (Pos('LUFS', NumStr) > 0) then
      FLoudFound := TryStrToFloat(Trim(Copy(NumStr, 3, Pos('LUFS', NumStr) - 3)), FLoudI, FS)
    else if (Copy(NumStr, 1, 4) = 'LRA:') and (Pos(' LU', NumStr) > 0) then
      TryStrToFloat(Trim(Copy(NumStr, 5, Pos(' LU', NumStr) - 5)), FLoudLRA, FS)
    else if (Copy(NumStr, 1, 5) = 'Peak:') and (Pos('dBFS', NumStr) > 0) then
      FPeakFound := TryStrToFloat(Trim(Copy(NumStr, 6, Pos('dBFS', NumStr) - 6)), FTruePeak, FS);
    Exit;
  end;

  if FLevelScan then
  begin
    { ---- Pegel-Messung (astats) ----
      ffmpeg schreibt am Ende für jede gemessene Spur z.B.:
          [Parsed_astats_3 @ 0000...] Peak level dB: -13.497830
      Wir merken uns den höchsten Wert über alle Spuren. Stille Spuren
      melden "-inf" - das lässt TryStrToFloat einfach durchfallen. }
    P := Pos('Peak level dB:', Line);
    if P > 0 then
    begin
      FS := DefaultFormatSettings;
      FS.DecimalSeparator := '.';
      if TryStrToFloat(Trim(Copy(Line, P + 14, MaxInt)), Sec, FS) then
        if (not FMaxFound) or (Sec > FMaxPeak) then
        begin
          FMaxPeak := Sec;
          FMaxFound := True;
        end;
    end;
    Exit;
  end;

  if not IsDemucs then
  begin
    { ---- ffmpeg ---- }
    { Infos zur Quelle aus der ERSTEN Audiospur der Eingangsdatei, z.B.
        "Stream #0:0: Audio: mp3 (mp3float), 44100 Hz, stereo, fltp, 320 kb/s"
      Sobald "Output #" kommt, beschreibt ffmpeg die Ausgabe (unser WAV) -
      die interessiert hier nicht mehr. }
    if not FSrcDone then
    begin
      if Pos('Output #', Line) > 0 then
        FSrcDone := True
      else
      begin
        P := Pos(': Audio: ', Line);
        if (P > 0) and (FSrcCodec = '') then
        begin
          NumStr := Trim(Copy(Line, P + 9, MaxInt));
          Q := 1;
          while (Q <= Length(NumStr)) and not (NumStr[Q] in [' ', ',', '(']) do
            Inc(Q);
          FSrcCodec := Copy(NumStr, 1, Q - 1);
          { Bitrate: Zahl direkt vor " kb/s" }
          Q := Pos(' kb/s', Line);
          if Q > 0 then
          begin
            T := Q - 1;
            while (T > 0) and (Line[T] in ['0'..'9']) do Dec(T);
            FSrcKbps := StrToIntDef(Copy(Line, T + 1, Q - T - 1), 0);
          end;
        end;
      end;
    end;
    P := Pos('Duration: ', Line);
    if (P > 0) and ParseTime(Copy(Line, P + 10, 11), Sec) and (Sec > 0) then
      if FDurationSec <= 0 then
        FDurationSec := Sec;
    P := Pos('time=', Line);
    if (P > 0) and (FDurationSec > 0) and ParseTime(Copy(Line, P + 5, 11), Sec) then
      Progress(FStageLo + Round((FStageHi - FStageLo) * Sec / FDurationSec),
        FStageName);
    Exit;
  end;

  { ---- demucs ---- }
  { wichtige Zeilen ins Protokoll übernehmen }
  if Pos('Writing wav file', Line) > 0 then
    Log('  ' + Trim(Line));
  if (Pos('[ERROR]', Line) > 0) or (Pos('Error', Line) > 0) then
    Log('  ' + Trim(Line));

  { bei htdemucs_ft: erkennen, welches der 4 Modelle gerade rechnet }
  if FPhaseCount > 1 then
  begin
    N := -1;
    if Pos('DRUMS', Line) = 1 then N := 0
    else if Pos('BASS', Line) = 1 then N := 1
    else if Pos('OTHER', Line) = 1 then N := 2
    else if Pos('VOCALS', Line) = 1 then N := 3;
    if (N >= 0) and (N <> FPhase) then
    begin
      FPhase := N;
      FillChar(FThreadPct, SizeOf(FThreadPct), 0);   // neues Modell -> neu zählen
    end;
  end;

  { Prozentzahl suchen: steht zwischen "(" und "%)" }
  P := Pos('%)', Line);
  if P = 0 then Exit;
  Q := P - 1;
  while (Q > 0) and (Line[Q] in ['0'..'9', '.', ' ']) do
    Dec(Q);
  if (Q < 1) or (Line[Q] <> '(') then Exit;
  NumStr := Trim(Copy(Line, Q + 1, P - Q - 1));
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(NumStr, Pct, FS) then Exit;

  { Nummer des Teilstücks lesen: "[THREAD 3]" -> 3 }
  T := 0;
  I := Pos('[THREAD ', Line);
  if I > 0 then
  begin
    NumStr := '';
    Inc(I, 8);
    while (I <= Length(Line)) and (Line[I] in ['0'..'9']) do
    begin
      NumStr := NumStr + Line[I];
      Inc(I);
    end;
    T := StrToIntDef(NumStr, 0);
  end;
  if (T < 0) or (T > High(FThreadPct)) then Exit;
  if Pct > FThreadPct[T] then
    FThreadPct[T] := Pct;          // Fortschritt dieses Teilstücks merken

  { Durchschnitt über alle Teilstücke }
  N := FSettings.Threads;
  if Pos('[THREAD ', Line) = 0 then N := 1;
  Sum := 0;
  for I := 0 to N - 1 do
    Sum := Sum + FThreadPct[I];
  { Anteil 0..1: bei htdemucs_ft zählt jedes der 4 Modelle ein Viertel }
  Pct := (FPhase + (Sum / N) / 100) / FPhaseCount;
  Progress(FStageLo + Round((FStageHi - FStageLo) * Pct), FStageName);
end;

{ Parameter mit Leerzeichen in Anführungszeichen setzen - so sieht der
  Aufruf im Log aus wie in der Eingabeaufforderung }
function QuoteArg(const A: string): string;
begin
  if (Pos(' ', A) > 0) or (A = '') then
    Result := '"' + A + '"'
  else
    Result := A;
end;

function ArgsToText(L: TStrings): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to L.Count - 1 do
  begin
    if I > 0 then Result := Result + ' ';
    Result := Result + QuoteArg(L[I]);
  end;
end;

{ ---------------------------------------------------------------------------
  RunTool - startet ein externes Programm und wartet, bis es fertig ist

  - Das Programm läuft unsichtbar (kein schwarzes Konsolenfenster).
  - Seine Ausgabe (stdout + stderr) wird laufend gelesen und Zeile für
    Zeile an HandleLine weitergegeben.
  - Wurde Cancel aufgerufen, wird das Programm sofort beendet.
  Rückgabe: Exit-Code des Programms (0 = alles gut).
  --------------------------------------------------------------------------- }
function TStemJob.RunTool(const Exe: string; const Args: array of string;
  IsDemucs: Boolean): Integer;
var
  LastMemCheck: QWord;
  Mem: Integer;
  Proc: TProcessUTF8;
  Buf: array[0..4095] of Char;
  Pending: string;                 // angefangene Zeile, noch ohne Zeilenende
  N, I, K: Integer;

  { gibt alle vollständigen Zeilen aus Pending an HandleLine weiter.
    Zeilenende ist #10 oder #13 (ffmpeg nutzt #13 für seine Statuszeile). }
  procedure Flush(Final: Boolean);
  var
    J, Start: Integer;
  begin
    Start := 1;
    for J := 1 to Length(Pending) do
      if Pending[J] in [#10, #13] then
      begin
        HandleLine(Copy(Pending, Start, J - Start), IsDemucs);
        Start := J + 1;
      end;
    Delete(Pending, 1, Start - 1);
    if Final and (Pending <> '') then
    begin
      HandleLine(Pending, IsDemucs);
      Pending := '';
    end;
  end;

begin
  FTail.Clear;
  Pending := '';
  LastMemCheck := 0;
  Mem := 0;
  Proc := TProcessUTF8.Create(nil);
  try
    Proc.Executable := Exe;
    for I := Low(Args) to High(Args) do
      Proc.Parameters.Add(Args[I]);
    { Ausgabe umleiten, stderr zu stdout dazunehmen, kein Konsolenfenster }
    Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    if IsDemucs then
    begin
      { Für demucs die Umgebungsvariable OMP_NUM_THREADS setzen.
        Sonst würde JEDES Teilstück alle Kerne benutzen wollen und die
        Teilstücke würden sich gegenseitig ausbremsen.
        Dafür die bestehende Umgebung kopieren und den Wert ersetzen. }
      for I := 1 to GetEnvironmentVariableCount do
        if Pos('OMP_NUM_THREADS=', UpperCase(GetEnvironmentString(I))) <> 1 then
          Proc.Environment.Add(GetEnvironmentString(I));
      Proc.Environment.Add('OMP_NUM_THREADS=' + IntToStr(OmpThreads));
    end;
    Proc.ShowWindow := swoHide;
    { Aufruf ins Log - mit allen Parametern, damit man ihn notfalls von
      Hand in einer Eingabeaufforderung nachstellen kann }
    LogLine('  Starte: ' + QuoteArg(Exe) + ' ' + ArgsToText(Proc.Parameters));
    Proc.Execute;
    {$IFDEF WINDOWS}
    AddToToolJob(Proc.ProcessHandle);   // stirbt mit StemMaker, siehe oben
    {$ENDIF}

    { Hauptschleife: Ausgabe lesen, solange das Programm läuft }
    while True do
    begin
      N := Proc.Output.NumBytesAvailable;
      if N > 0 then
      begin
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := Proc.Output.Read(Buf, N);
        for K := 0 to N - 1 do
          Pending := Pending + Buf[K];
        Flush(False);
      end
      else if not Proc.Running then
        Break                      // Programm ist fertig
      else
        Sleep(40);                 // kurz warten, CPU schonen

      {$IFDEF WINDOWS}
      { etwa jede Sekunde den Speicherverbrauch von demucs abfragen und
        den höchsten Wert merken }
      if IsDemucs and (GetTickCount64 - LastMemCheck > 1000) then
      begin
        LastMemCheck := GetTickCount64;
        Mem := PeakMemoryMB(Proc.ProcessHandle);
        if Mem > FPeakMemMB then FPeakMemMB := Mem;
      end;
      {$ENDIF}

      if FCancelled then
      begin
        Proc.Terminate(1);         // Programm hart beenden
        LogLine('  Abgebrochen durch Benutzer');
        { Text wird nicht angezeigt (Run fängt EStemCancelled ab) }
        raise EStemCancelled.Create('Abgebrochen');
      end;
    end;

    { was noch in der Leitung steckt, auch noch lesen }
    repeat
      N := Proc.Output.NumBytesAvailable;
      if N > 0 then
      begin
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := Proc.Output.Read(Buf, N);
        for K := 0 to N - 1 do
          Pending := Pending + Buf[K];
      end;
    until N <= 0;
    Flush(True);
    Result := Proc.ExitStatus;
    {$IFDEF WINDOWS}
    { Speicherverbrauch abfragen, solange das Prozess-Handle noch offen ist }
    if IsDemucs then
    begin
      Mem := PeakMemoryMB(Proc.ProcessHandle);
      if Mem > FPeakMemMB then FPeakMemMB := Mem;
      if FPeakMemMB > 0 then
        LogLine(Format('  demucs Speicher (Spitze): %d MB', [FPeakMemMB]))
      else
        LogLine('  demucs Speicher (Spitze): unbekannt');
    end;
    {$ENDIF}
    LogLine(Format('  Beendet mit Code %d', [Result]));
  finally
    Proc.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Run - wandelt eine Datei in eine Stem-Datei um (die 5 Schritte von oben)
  --------------------------------------------------------------------------- }
function TStemJob.Run(const InputFile: string; out OutFile, ErrMsg: string): Boolean;
var
  WorkDir, MixWav, StemDir, TmpMp4, Problems, Err: string;
  SrcText: string;                 // Quelle als Text fürs Log, z.B. 'mp3 320 kbit/s'
  Args: TStringList;
  I, Code: Integer;
  T0, RunMS: QWord;                // Stoppuhr für diese Datei (ms)
  InBytes, OutBytes: Int64;        // Größe Originaldatei / fertige Stem-Datei
  StatResult: string;              // fürs Statistik-CSV: OK / Fehler / Abbruch
  GainDb: Double;                  // Lautstärke angleichen: Änderung in dB
  DoBassFix: Boolean;              // Bass-Fix für diese Datei wirklich machen
  Tail, Graph: string;             // ffmpeg-Filter für Klang-Optionen
  DotFS: TFormatSettings;          // Zahlen für ffmpeg immer mit Punkt
  LockH: THandle;                  // Sperrdatei im Temp-Ordner (siehe unten)

  { Sekunden Rechenzeit pro Minute Musik - der Vergleichswert, um Modelle
    und PCs miteinander zu vergleichen (0 = Länge unbekannt) }
  function SecPerAudioMin: Double;
  begin
    if FDurationSec > 0 then
      Result := (RunMS / 1000) / (FDurationSec / 60)
    else
      Result := 0;
  end;

  { eine Zeile in logs\statistik.csv schreiben (siehe uLog.LogStatRow) }
  procedure WriteStat;
  const
    { feste Kurznamen fürs CSV (nicht übersetzt, damit Auswertungen über
      alle Sprachen gleich bleiben) }
    MODEL_IDS: array[TStemModel] of string = ('htdemucs', 'htdemucs_ft', 'hdemucs_mmi');
  var
    FS: TFormatSettings;
    Fmt: string;

    { Messwert als Text, leer wenn nicht gemessen }
    function LoudText(Found: Boolean; V: Double): string;
    begin
      if Found then
        Result := FormatFloat('0.0', V, FS)
      else
        Result := '';
    end;

  begin
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := ',';      // Dezimal-Komma fürs deutsche Excel
    if FSettings.Codec = scALAC then
      Fmt := 'ALAC'
    else
      Fmt := Format('AAC %d', [FUsedKbps]);
    LogStatRow(
      ['Datum', 'Datei', 'Endung', 'Groesse_MB', 'Laenge_s', 'Quelle',
       'Quelle_kbps', 'Modell', 'Teile', 'Kerne_je_Teil', 'Stem_Format',
       'Stem_MB', 'Umwandlung_s', 's_pro_Audiominute', 'RAM_Spitze_MB',
       'LUFS', 'LRA_LU', 'TruePeak_dBFS', 'CPU', 'Ergebnis'],
      [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
       ExtractFileName(InputFile),
       LowerCase(ExtractFileExt(InputFile)),
       FormatFloat('0.00', InBytes / 1048576, FS),
       FormatFloat('0.0', FDurationSec, FS),
       FSrcCodec,
       IntToStr(FSrcKbps),
       MODEL_IDS[FSettings.Model],
       IntToStr(FSettings.Threads),
       IntToStr(OmpThreads),
       Fmt,
       FormatFloat('0.00', OutBytes / 1048576, FS),
       FormatFloat('0.0', RunMS / 1000, FS),
       FormatFloat('0.0', SecPerAudioMin, FS),
       IntToStr(FPeakMemMB),
       LoudText(FLoudFound, FLoudI),
       LoudText(FLoudFound, FLoudLRA),
       LoudText(FPeakFound, FTruePeak),
       SysCPUName,
       StatResult]);
  end;

  { Fehler auslösen und dabei die letzten Ausgabezeilen des Programms
    anhängen - die sagen meistens, was schief ging }
  procedure Fail(const Msg: string);
  var
    S: string;
  begin
    S := Msg;
    if FTail.Count > 0 then
      S := S + LineEnding + _('--- letzte Ausgabe ---') + LineEnding + FTail.Text;
    raise Exception.Create(S);
  end;

  { die Parameterliste als Array für RunTool }
  function ArgsArray: TStringArray;
  var
    J: Integer;
  begin
    Result := nil;
    SetLength(Result, Args.Count);
    for J := 0 to Args.Count - 1 do
      Result[J] := Args[J];
  end;

begin
  Result := False;
  ErrMsg := '';
  FCancelled := False;
  FDurationSec := 0;
  FSkipped := False;
  FPeakMemMB := 0;
  FLastLogPct := 0;
  FSrcCodec := '';
  FSrcKbps := 0;
  FSrcDone := False;
  FUsedKbps := 0;
  FLoudScan := False;
  FLoudFound := False;
  FPeakFound := False;
  FLoudI := 0;
  FLoudLRA := 0;
  FTruePeak := 0;
  FLevelScan := False;
  FMaxFound := False;
  FMaxPeak := 0;
  GainDb := 0;
  DoBassFix := False;
  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  if FSettings.OutFile <> '' then
    OutFile := FSettings.OutFile      // vorgegeben (eindeutig gemacht)
  else
    OutFile := StemOutputName(InputFile, FSettings.OutputDir);
  WorkDir := '';
  LockH := feInvalidHandle;
  T0 := GetTickCount64;
  RunMS := 0;
  InBytes := 0;
  OutBytes := 0;
  StatResult := '';
  Log('== ' + ExtractFileName(InputFile));
  Args := TStringList.Create;
  try
    try
      { ---- Vorprüfungen ------------------------------------------------- }
      if not FileExists(InputFile) then
        raise Exception.Create(Format(_('Datei nicht gefunden: %s'), [InputFile]));
      if not CheckTools(Problems) then
        raise Exception.Create(Trim(Problems));
      if FileExists(OutFile) and not FSettings.Overwrite then
      begin
        { schon erledigt -> überspringen, das ist kein Fehler }
        FSkipped := True;
        ErrMsg := _('Stem-Datei existiert schon');
        Log('  ' + Format(_('übersprungen, existiert schon: %s'), [OutFile]));
        Exit;
      end;
      { Dateigröße fürs Log und die Statistik (Länge kommt nach dem Dekodieren) }
      InBytes := FileSizeUtf8(InputFile);
      Log('  ' + Format(_('Dateigröße: %.1f MB'), [InBytes / 1048576]));
      if not DirectoryExists(ExtractFilePath(OutFile)) then
        if not ForceDirectories(ExtractFilePath(OutFile)) then
          raise Exception.Create(_('Ausgabeordner kann nicht erstellt werden'));

      { ---- Arbeitsordner im Windows-Temp anlegen ------------------------
        z.B. %TEMP%\StemMaker\20260929_211530123_4711\
        Datum/Uhrzeit + Zufallszahl -> jeder Durchlauf hat seinen eigenen
        Ordner. Die Dateinamen darin sind ohne Umlaute (sicher für demucs). }
      WorkDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'StemMaker' +
        PathDelim + FormatDateTime('yyyymmdd_hhnnsszzz', Now) + '_' +
        IntToStr(Random(100000)) + PathDelim;
      if not ForceDirectories(WorkDir) then
        raise Exception.Create(Format(_('Temp-Ordner kann nicht erstellt werden: %s'), [WorkDir]));
      { Sperrdatei: bleibt offen, solange wir hier arbeiten. Stürzt
        StemMaker ab, gibt Windows sie frei - dann darf der nächste Start
        den Ordner löschen (siehe CleanupStaleTempDirs). }
      LockH := FileCreate(WorkDir + TEMP_LOCK_NAME, fmShareExclusive, 438);
      MixWav  := WorkDir + 'mix.wav';
      StemDir := WorkDir + 'stems';
      TmpMp4  := WorkDir + 'out.mp4';

      { ---- 1. Eingangsdatei -> WAV 44.1 kHz Stereo ---------------------- }
      SetStage(0, 4, _('Dekodieren'));
      Args.Clear;
      Args.AddStrings(['-hide_banner', '-nostdin', '-y',
        '-i', InputFile,           // Eingangsdatei
        '-map', '0:a:0',           // nur die erste Audiospur
        '-vn',                     // kein Bild/Cover
        '-ac', '2',                // Stereo
        '-ar', '44100',            // 44.1 kHz (darauf ist Demucs trainiert)
        '-c:a', 'pcm_s16le',       // unkomprimiertes 16-Bit-WAV
        MixWav]);
      Code := RunTool(FSettings.FFmpegExe, ArgsArray, False);
      if (Code <> 0) or not FileExists(MixWav) then
        Fail(Format(_('ffmpeg konnte die Datei nicht dekodieren (Code %d)'), [Code]));
      if FDurationSec > 0 then
        Log('  ' + Format(_('Länge: %d:%.2d min'), [Trunc(FDurationSec) div 60,
          Trunc(FDurationSec) mod 60]));
      FSrcDone := True;          // beim späteren Zusammenbauen nicht neu lesen

      { Welche Bitrate bekommt die Stem-Datei? }
      if FSettings.Codec = scAAC then
      begin
        if FSettings.AACAuto then
          FUsedKbps := ChooseAACBitrate(FSrcCodec, FSrcKbps, FSettings.AACBitrate)
        else
          FUsedKbps := FSettings.AACBitrate;
        if FSrcKbps > 0 then
          SrcText := Format('%s %d kbit/s', [FSrcCodec, FSrcKbps])
        else if FSrcCodec <> '' then
          SrcText := FSrcCodec
        else
          SrcText := _('unbekannt');
        if FSettings.AACAuto then
          Log('  ' + Format(_('Quelle: %s -> Stem-Datei AAC %d kbit/s (automatisch)'),
            [SrcText, FUsedKbps]))
        else
          Log('  ' + Format(_('Quelle: %s -> Stem-Datei AAC %d kbit/s'), [SrcText, FUsedKbps]));
      end;

      { ---- 2. Trennen mit demucs.cpp ------------------------------------
        Aufruf: demucs <Modell> <mix.wav> <Ausgabeordner> <Anzahl Teile>
        Ergebnis: target_0_drums.wav ... target_3_vocals.wav }
      SetStage(4, 90, _('Stems trennen (demucs)'));
      FillChar(FThreadPct, SizeOf(FThreadPct), 0);
      FPhase := 0;
      if FSettings.Model = smHTDemucsFT then FPhaseCount := 4 else FPhaseCount := 1;
      Log('  ' + Format(_('demucs: %s (%s), %d Teile x je %d Kerne'),
        [ExtractFileName(DemucsExePath), DemucsVariantName(DemucsExePath),
         FSettings.Threads, OmpThreads]));
      Code := RunTool(DemucsExePath, [DemucsModelArg, MixWav, StemDir,
        IntToStr(FSettings.Threads)], True);
      if Code <> 0 then
        Fail(Format(_('demucs.cpp ist fehlgeschlagen (Code %d)'), [Code]));
      for I := 0 to 3 do
        if not FileExists(StemDir + PathDelim + STEM_WAVS[I]) then
          Fail(Format(_('demucs.cpp hat %s nicht erzeugt'), [STEM_WAVS[I]]));

      DoBassFix := FSettings.BassFix and (FDurationSec > 0) and
        (FDurationSec <= BASSFIX_MAX_SEC);
      if DoBassFix then
        Log('  ' + Format(_('Bass-Fix: Tiefbass unter %s Hz von Other nach Bass'), [BASSFIX_HZ]))
      else if FSettings.BassFix then
        Log('  ' + _('Bass-Fix ausgelassen: Datei zu lang (über 20 min) oder Länge unbekannt'));

      { ---- 2b. Lautstärke angleichen: Pegel messen ----------------------
        Gemessen wird die höchste Spitze von Master, den 4 Stems (schon mit
        Bass-Fix) und der Summe der 4 Stems - so spielt Traktor sie ab.
        Alle 5 Spuren bekommen danach DENSELBEN Wert, damit Master und
        Stems gleich laut bleiben. Kein Limiter: die Dynamik bleibt wie im
        Original. Laute Club-Tracks ändern sich kaum, leise werden auf
        Club-Pegel gebracht. Schlägt die Messung fehl, bleibt der Pegel
        einfach wie er ist. }
      if FSettings.Normalize then
      begin
        SetStage(90, 91, _('Pegel messen'));
        Graph := StemFilter(['[1:a]', '[2:a]', '[3:a]', '[4:a]'],
          ['[s0]', '[s1]', '[s2]', '[s3]'], '', DoBassFix) + ';' +
          '[0:a]' + ASTATS_PEAK + ',anullsink;';
        for I := 0 to 3 do
          Graph := Graph + Format('[s%d]asplit=2[m%d][n%d];[m%d]%s,anullsink;',
            [I, I, I, I, ASTATS_PEAK]);
        Graph := Graph + '[n0][n1][n2][n3]amerge=inputs=4,' +
          'pan=stereo|c0=c0+c2+c4+c6|c1=c1+c3+c5+c7,' + ASTATS_PEAK + '[sum]';
        Args.Clear;
        Args.AddStrings(['-hide_banner', '-nostdin', '-y', '-i', MixWav]);
        for I := 0 to 3 do
          Args.AddStrings(['-i', StemDir + PathDelim + STEM_WAVS[I]]);
        Args.AddStrings(['-filter_complex', Graph, '-map', '[sum]', '-f', 'null', '-']);
        FLevelScan := True;
        try
          Code := RunTool(FSettings.FFmpegExe, ArgsArray, False);
        finally
          FLevelScan := False;
        end;
        if (Code = 0) and FMaxFound then
        begin
          GainDb := NORM_TARGET_DB - FMaxPeak;
          if GainDb > NORM_MAX_GAIN_DB then
            GainDb := NORM_MAX_GAIN_DB;
          if Abs(GainDb) < NORM_MIN_GAIN_DB then
            GainDb := 0;
          { FormatFloat statt Format: Format kennt kein "+" vor der Zahl }
          Log('  ' + Format(_('Lautstärke angleichen: %s dB (höchste Spitze vorher %.1f dBFS)'),
            [FormatFloat('+0.0;-0.0;0.0', GainDb), FMaxPeak]));
        end
        else
          Log('  ' + _('Lautstärke angleichen: Pegel konnte nicht gemessen werden, bleibt unverändert'));
      end;

      { ---- 3. MP4 mit 5 Audiospuren bauen -------------------------------
        Eingänge für ffmpeg:
          0 = Originaldatei  (nur für Tags und Cover)
          1 = mix.wav        (Master = Spur 1)
          2..5 = die 4 Stems (Spur 2..5) }
      SetStage(91, 98, _('Stem-Datei kodieren'));
      Args.Clear;
      Args.AddStrings(['-hide_banner', '-nostdin', '-y',
        '-i', InputFile,
        '-i', MixWav]);
      for I := 0 to 3 do
        Args.AddStrings(['-i', StemDir + PathDelim + STEM_WAVS[I]]);
      { welche Eingänge in welcher Reihenfolge in die Datei kommen }
      if DoBassFix or (GainDb <> 0) then
      begin
        { mit Klang-Optionen: die Spuren laufen durch den Filter
          (Bass-Fix und/oder gemeinsame Lautstärke-Änderung) }
        if GainDb <> 0 then
          Tail := ',volume=' + FormatFloat('0.00', GainDb, DotFS) + 'dB'
        else
          Tail := '';
        Graph := '[1:a]aformat=sample_fmts=flt' + Tail + '[a0];' +
          StemFilter(['[2:a]', '[3:a]', '[4:a]', '[5:a]'],
            ['[a1]', '[a2]', '[a3]', '[a4]'], Tail, DoBassFix);
        Args.AddStrings(['-filter_complex', Graph,
          '-map', '[a0]', '-map', '[a1]', '-map', '[a2]',
          '-map', '[a3]', '-map', '[a4]']);
      end
      else
        Args.AddStrings(['-map', '1:a:0', '-map', '2:a:0', '-map', '3:a:0',
          '-map', '4:a:0', '-map', '5:a:0']);
      Args.AddStrings([
        '-map', '0:v:0?',                   // Cover, falls vorhanden ("?" = optional)
        '-c:v', 'copy', '-disposition:v:0', 'attached_pic']);
      { Audio-Format }
      if FSettings.Codec = scALAC then
        Args.AddStrings(['-c:a', 'alac', '-sample_fmt:a', 's16p'])
      else
        Args.AddStrings(['-c:a', 'aac', '-b:a', IntToStr(FUsedKbps) + 'k']);
      Args.AddStrings(['-ar', '44100', '-ac', '2',
        '-map_metadata', '0',               // Tags (Titel, Artist, ...) vom Original
        '-map_chapters', '-1',              // keine Kapitel
        { Nur die Master-Spur ist "aktiv". Die anderen 4 werden als
          "deaktiviert" markiert - normale Player spielen dann nur den
          Master, Traktor nimmt die Stems. (Wie MP4Box "#ID=Z:disable") }
        '-disposition:a:0', 'default',
        '-disposition:a:1', '0', '-disposition:a:2', '0',
        '-disposition:a:3', '0', '-disposition:a:4', '0',
        '-f', 'mp4', TmpMp4]);
      Code := RunTool(FSettings.FFmpegExe, ArgsArray, False);
      if (Code <> 0) or not FileExists(TmpMp4) then
        Fail(Format(_('ffmpeg konnte die Stem-Datei nicht erstellen (Code %d)'), [Code]));

      { ---- 4. NI-Stem-Infos hineinschreiben ----------------------------- }
      SetStage(98, 99, _('Stem-Metadaten schreiben'));
      if not InjectStemMetadata(TmpMp4, BuildStemJSON(FSettings.Stems), Err) then
        raise Exception.Create(Format(_('Stem-Metadaten: %s'), [Err]));
      { Kontrolle: es müssen genau 5 Spuren drin sein }
      if CountTracks(TmpMp4) <> 5 then
        raise Exception.Create(_('Ergebnis hat nicht 5 Audiospuren'));

      { ---- Lautheit der Master-Spur messen -----------------------------
        Nur zur Info (Log + Statistik), die Datei wird NICHT verändert.
        Gemessen wird die fertige AAC/ALAC-Spur, weil AAC-Kodieren die
        Spitzen leicht anheben kann (True Peak über 0 dBFS = Übersteuerung).
        Schlägt die Messung fehl, ist das kein Fehler der Umwandlung. }
      SetStage(99, 99, _('Lautheit messen'));
      FLoudScan := True;
      try
        RunTool(FSettings.FFmpegExe, ['-hide_banner', '-nostdin', '-nostats',
          '-i', TmpMp4, '-map', '0:a:0',
          '-af', 'ebur128=peak=true:framelog=quiet',
          '-f', 'null', '-'], False);
      except
        on E: EStemCancelled do raise;
        on E: Exception do
          Log('  ' + Format(_('Lautheit konnte nicht gemessen werden: %s'), [E.Message]));
      end;
      FLoudScan := False;
      if FLoudFound then
      begin
        if FPeakFound then
          Log('  ' + Format(_('Lautheit Master: %.1f LUFS, Umfang %.1f LU, True Peak %.1f dBFS'),
            [FLoudI, FLoudLRA, FTruePeak]))
        else
          Log('  ' + Format(_('Lautheit Master: %.1f LUFS, Umfang %.1f LU'), [FLoudI, FLoudLRA]));
        if FPeakFound and (FTruePeak > 0) then
          Log('  ' + _('Hinweis: True Peak über 0 dBFS - die Master-Spur kann beim Abspielen leicht übersteuern'));
      end;

      { ---- 5. an den Zielort verschieben --------------------------------
        RenameFile klappt nur auf dem gleichen Laufwerk. Liegt das Ziel auf
        einem anderen Laufwerk (z.B. D:), wird stattdessen kopiert. }
      if FileExists(OutFile) then
        if not SysUtils.DeleteFile(OutFile) then
          raise Exception.Create(_('Bestehende Zieldatei kann nicht ersetzt werden'));
      if not RenameFile(TmpMp4, OutFile) then
        if not FileUtil.CopyFile(TmpMp4, OutFile) then
          raise Exception.Create(Format(_('Kann Zieldatei nicht schreiben: %s'), [OutFile]));

      Progress(100, _('Fertig'));
      Log('  -> ' + OutFile);
      { Kennzahlen dieser Datei: Größe der Stem-Datei und Tempo.
        "s pro Audiominute" ist unabhängig von der Song-Länge und taugt
        darum zum Vergleichen (Modelle, PCs, Einstellungen). }
      OutBytes := FileSizeUtf8(OutFile);
      RunMS := GetTickCount64 - T0;
      if FDurationSec > 0 then
        Log('  ' + Format(_('Stem-Datei: %.1f MB, Tempo: %.1f s pro Minute Musik (%s)'),
          [OutBytes / 1048576, SecPerAudioMin, StemModelDisplayName(FSettings.Model)]))
      else
        Log('  ' + Format(_('Stem-Datei: %.1f MB'), [OutBytes / 1048576]));
      StatResult := 'OK';
      Result := True;
    except
      on E: EStemCancelled do
      begin
        { ErrMsg bleibt absichtlich deutsch: uMain erkennt den Abbruch
          an genau diesem Text (Err = 'Abgebrochen') }
        ErrMsg := 'Abgebrochen';
        StatResult := 'Abbruch';
        Log('  ' + _('abgebrochen'));
      end;
      on E: Exception do
      begin
        ErrMsg := E.Message;
        StatResult := 'Fehler';
        Log('  ' + _('FEHLER: ') + E.Message);
        LogMarkError;
      end;
    end;
  finally
    { aufräumen - passiert IMMER, auch nach Fehler oder Abbruch }
    Args.Free;
    { Statistik-Zeile (übersprungene Dateien zählen nicht - da wurde nichts
      gerechnet) }
    if StatResult <> '' then
    begin
      if RunMS = 0 then
        RunMS := GetTickCount64 - T0;
      WriteStat;
    end;
    if LockH <> feInvalidHandle then
      FileClose(LockH);
    if (WorkDir <> '') and DirectoryExists(WorkDir) then
    begin
      if FSettings.KeepTemp then
      begin
        { Sperrdatei weg - der Ordner bleibt zur Fehlersuche liegen und
          wird erst nach TEMP_MAX_AGE_H Stunden beim Start gelöscht }
        SysUtils.DeleteFile(WorkDir + TEMP_LOCK_NAME);
        Log('  ' + Format(_('Temp-Ordner behalten: %s'), [WorkDir]));
      end
      else
        DeleteDirectory(ExcludeTrailingPathDelimiter(WorkDir), False);
    end;
  end;
end;

initialization
  Randomize;     // Zufallsgenerator für die Temp-Ordnernamen starten
  {$IFDEF WINDOWS}
  CreateToolJob; // Hilfsprogramme enden mit StemMaker (siehe oben)
  {$ENDIF}

end.
