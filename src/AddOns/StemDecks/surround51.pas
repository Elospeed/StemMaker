{ ============================================================================
  surround51.pas  -  5.1-Ton erkennen, aufteilen und verpacken

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Was ist eine 5.1-Datei?
    Sechs Kanäle in einer Spur: FL FR (vorne links/rechts), FC (Center,
    meist Sprache/Gesang), LFE (Subwoofer, nur tiefe Töne) und zwei
    Surround-Kanäle. ffmpeg nennt das Layout "5.1(side)" (SL SR) oder
    "5.1" (BL BR). Typisch in MKV/MP4-Videos, DVD (VOB, AC3/DTS),
    Blu-ray, mehrkanaligen FLAC/WAV - meist mit 48 kHz.

  Die vier "Teile" (immer Stereo, Mono-Kanäle auf beide Seiten gelegt):
      PART_FRONT     FL + FR
      PART_CENTER    FC
      PART_LFE       LFE   (auf Wunsch auf Spitzenpegel 0 dB angehoben)
      PART_SURROUND  SL + SR  bzw.  BL + BR

  Welcher Teil auf welchem Deck (A..D) bzw. in welchem Stem-Slot (1..4)
  landet, ist einstellbar (DeckPart). Standard nach dem Wunsch eines
  Nutzers auf r/Traktor:  A Front, B LFE (B wie Bass), C Center, D Surround.

  Zwei Ausgaben:
    1. BuildSplitArgs: vier WAV-Dateien A_/B_/C_/D_<Name>.wav,
       die danach einzeln mit KI in Stems getrennt werden (16 Stems auf
       4 Decks).
    2. BuildPackArgs: EINE Stem-Datei ohne KI - die vier Teile direkt als
       Stem 1..4 (sauber getrennte Studio-Kanäle brauchen keine Trennung).

  Der ffmpeg-Aufruf selbst wird im Fenster ausgeführt. Diese Unit liefert
  nur die Parameter und wertet die Ausgabe aus.

  Versionen:
    0.1  (10.10.2026)  Erste Testversion
    0.2  (10.10.2026)  Zuordnung einstellbar, Auswahl der Tonspur,
                       LFE-Anhebung, Verpacken in eine Stem-Datei
    0.3  (10.10.2026)  "6 channels" (5.1 ohne Layout-Angabe, z.B. AC3 in MKA)
                       wird als 5.1(side) behandelt
  ============================================================================ }
unit surround51;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils;

const
  PART_FRONT    = 0;
  PART_CENTER   = 1;
  PART_LFE      = 2;
  PART_SURROUND = 3;

  DECK_LETTERS: array[0..3] of Char = ('A', 'B', 'C', 'D');
  PART_NAMES: array[0..3] of string = ('FRONT L/R', 'CENTER', 'LFE (SUB)', 'SURROUND L/R');
  { Namen der Stems in der verpackten Stem-Datei (so zeigt Traktor sie) }
  PART_STEM_NAMES: array[0..3] of string = ('Front', 'Center', 'LFE', 'Surround');

type
  { Welcher Teil auf Deck/Slot 0..3 (A..D) liegt }
  TDeckParts = array[0..3] of Integer;

  { Eine Audiospur der Quelldatei }
  TAudioTrack = record
    Index : Integer;   // Nummer unter den Audiospuren (für "0:a:N")
    Layout: string;    // z.B. "5.1(side)", "stereo"
    Line  : string;    // ganze Zeile von ffmpeg (zur Anzeige)
  end;
  TAudioTracks = array of TAudioTrack;

const
  DEFAULT_PARTS: TDeckParts = (PART_FRONT, PART_LFE, PART_CENTER, PART_SURROUND);

{ Alle Audiospuren aus der Ausgabe von "ffmpeg -i <Datei>" }
function ParseAudioTracks(const FFmpegOutput: string): TAudioTracks;

{ True, wenn das Layout unterstützt wird (5.1 / 5.1(side)) }
function IsSupported51(const Layout: string): Boolean;

{ Gültige Zuordnung? (jeder Teil genau einmal) }
function PartsValid(const P: TDeckParts): Boolean;

{ Zielname für ein Deck:  <Ordner>\A_<Name>.wav }
function DeckWavName(const SourceFile, OutDir: string; Deck: Integer): string;

{ Parameter, um den Spitzenpegel des LFE zu messen (Ausgabe: max_volume) }
procedure BuildLfePeakArgs(const SourceFile, Layout: string; Track, MaxSeconds: Integer;
  Args: TStrings);
{ Liest "max_volume: -12.3 dB" aus der ffmpeg-Ausgabe. False = nicht gefunden }
function ParseMaxVolume(const FFmpegOutput: string; out dB: Double): Boolean;

{ Zerlegen in vier WAV-Dateien (Deck A..D gemäss Parts) }
procedure BuildSplitArgs(const SourceFile, OutDir, Layout: string;
  Track, MaxSeconds: Integer; const Parts: TDeckParts; LfeGainDb: Double;
  Args: TStrings);

{ Verpacken in EINE Stem-Datei (ohne Stem-Block, den schreibt danach
  uStemMP4.InjectStemMetadata). Slot 1..4 = Parts[0..3].
  MasterSilent: Master-Spur still statt Kopie von Slot 1. }
procedure BuildPackArgs(const SourceFile, OutFile, Layout: string;
  Track, MaxSeconds: Integer; const Parts: TDeckParts; LfeGainDb: Double;
  MasterSilent: Boolean; Args: TStrings);

{ Ist der Dateiname ein Deck-Teil ("A_Name...")? Dann Deck 0..3, sonst -1.
  BaseName = Dateiname ohne das Präfix "A_". }
function DeckFromFileName(const FileName: string; out BaseName: string): Integer;

implementation

function ParseAudioTracks(const FFmpegOutput: string): TAudioTracks;
var
  L, Parts: TStringList;
  i, p, k, N: Integer;
  S, Part, Layout: string;
begin
  Result := nil;
  N := 0;
  L := TStringList.Create;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ',';
    L.Text := FFmpegOutput;
    for i := 0 to L.Count - 1 do
    begin
      { Beispiel:  Stream #0:1[0x81](eng): Audio: dts (DTS), 48000 Hz, 5.1(side), fltp, 1536 kb/s }
      p := Pos('Audio:', L[i]);
      if (Pos('Stream #', L[i]) = 0) or (p = 0) then Continue;
      S := Copy(L[i], p + Length('Audio:'), MaxInt);
      Parts.DelimitedText := S;
      Layout := '';
      { Das Layout steht direkt nach "xxxxx Hz" }
      for k := 0 to Parts.Count - 2 do
      begin
        Part := Trim(Parts[k]);
        if (Length(Part) > 3) and (Copy(Part, Length(Part) - 2, 3) = ' Hz') then
        begin
          Layout := Trim(Parts[k + 1]);
          Break;
        end;
      end;
      SetLength(Result, N + 1);
      Result[N].Index := N;
      Result[N].Layout := Layout;
      Result[N].Line := Trim(L[i]);
      Inc(N);
    end;
  finally
    Parts.Free;
    L.Free;
  end;
end;

function IsSupported51(const Layout: string): Boolean;
begin
  { "6 channels" = 6 Kanäle ohne Layout-Angabe (z.B. AC3 nach dem Umpacken
    in MKV/MKA). Die Reihenfolge ist bei AC3/DTS/AAC trotzdem 5.1. }
  Result := (Layout = '5.1') or (Layout = '5.1(side)') or (Layout = '6 channels');
end;

{ Anfang des Filters: gewählte Spur, bei "6 channels" erst als 5.1(side)
  kennzeichnen (sonst kennt channelsplit die Kanäle nicht) }
function TrackInput(const Layout: string; Track: Integer): string;
begin
  Result := Format('[0:a:%d]', [Track]);
  if Layout = '6 channels' then
    Result := Result + 'channelmap=channel_layout=5.1(side),';
end;

{ Layout, mit dem channelsplit arbeitet }
function SplitLayout(const Layout: string): string;
begin
  if Layout = '6 channels' then Result := '5.1(side)' else Result := Layout;
end;

function PartsValid(const P: TDeckParts): Boolean;
var i, j: Integer;
begin
  Result := False;
  for i := 0 to 3 do
  begin
    if (P[i] < 0) or (P[i] > 3) then Exit;
    for j := i + 1 to 3 do
      if P[i] = P[j] then Exit;
  end;
  Result := True;
end;

function DeckWavName(const SourceFile, OutDir: string; Deck: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(OutDir) + DECK_LETTERS[Deck] + '_' +
            ExtractFileNameOnly(SourceFile) + '.wav';
end;

{ Gemeinsamer Anfang aller Aufrufe: Quelle öffnen. Grosse Werte für
  probesize/analyzeduration, damit ffmpeg auch in DVD-VOBs alle
  Tonspuren findet (dort beginnen sie oft erst später in der Datei). }
procedure AddInput(const SourceFile: string; MaxSeconds: Integer; Args: TStrings);
begin
  Args.Add('-hide_banner');
  Args.Add('-nostdin');
  Args.Add('-y');
  Args.Add('-probesize'); Args.Add('100M');
  Args.Add('-analyzeduration'); Args.Add('100M');
  if MaxSeconds > 0 then
  begin
    Args.Add('-t'); Args.Add(IntToStr(MaxSeconds));   // nur Anfang lesen
  end;
  Args.Add('-i'); Args.Add(SourceFile);
end;

{ dB-Wert mit Punkt (unabhängig von der Windows-Ländereinstellung) }
function DbStr(dB: Double): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FormatFloat('0.00', dB, FS);
end;

{ Filter, der die gewählte Spur in die vier Teile zerlegt.
  Ergebnis-Labels: [t0] Front, [t1] Center, [t2] LFE, [t3] Surround }
function SplitFilter(const Layout: string; Track: Integer; LfeGainDb: Double): string;
var SurL, SurR: string;
begin
  { Namen der Surround-Kanäle hängen vom Layout ab }
  if SplitLayout(Layout) = '5.1(side)' then begin SurL := 'SL'; SurR := 'SR'; end
  else begin SurL := 'BL'; SurR := 'BR'; end;
  { channelsplit zerlegt in 6 Mono-Kanäle. join setzt zwei Mono-Kanäle
    zu Stereo zusammen - die map ist nötig, sonst legt ffmpeg die Mono-
    Eingänge auf den Center und vertauscht dabei links/rechts.
    pan macht aus einem Mono-Kanal Stereo (beide Seiten gleich). }
  Result :=
    TrackInput(Layout, Track) + 'channelsplit=channel_layout=' + SplitLayout(Layout) +
      '[FL][FR][FC][LFE][' + SurL + '][' + SurR + '];' +
    '[FL][FR]join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[t0];' +
    '[FC]pan=stereo|c0=c0|c1=c0[t1];' +
    '[LFE]pan=stereo|c0=c0|c1=c0';
  if Abs(LfeGainDb) > 0.005 then
    Result := Result + ',volume=' + DbStr(LfeGainDb) + 'dB';
  Result := Result + '[t2];' +
    '[' + SurL + '][' + SurR + ']join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[t3]';
end;

procedure BuildLfePeakArgs(const SourceFile, Layout: string; Track, MaxSeconds: Integer;
  Args: TStrings);
begin
  Args.Clear;
  AddInput(SourceFile, MaxSeconds, Args);
  Args.Add('-filter_complex');
  Args.Add(TrackInput(Layout, Track) + 'pan=mono|c0=LFE,volumedetect[o]');
  Args.Add('-map'); Args.Add('[o]');
  Args.Add('-f'); Args.Add('null'); Args.Add('-');
end;

function ParseMaxVolume(const FFmpegOutput: string; out dB: Double): Boolean;
var
  p, e: Integer;
  S: string;
  FS: TFormatSettings;
begin
  Result := False;
  dB := 0;
  p := Pos('max_volume:', FFmpegOutput);
  if p = 0 then Exit;
  S := Copy(FFmpegOutput, p + Length('max_volume:'), 40);
  e := Pos('dB', S);
  if e = 0 then Exit;
  S := Trim(Copy(S, 1, e - 1));
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := TryStrToFloat(S, dB, FS);
end;

procedure BuildSplitArgs(const SourceFile, OutDir, Layout: string;
  Track, MaxSeconds: Integer; const Parts: TDeckParts; LfeGainDb: Double;
  Args: TStrings);
var d: Integer;
begin
  Args.Clear;
  AddInput(SourceFile, MaxSeconds, Args);
  Args.Add('-loglevel'); Args.Add('error');
  Args.Add('-filter_complex'); Args.Add(SplitFilter(Layout, Track, LfeGainDb));
  for d := 0 to 3 do
  begin
    Args.Add('-map'); Args.Add('[t' + IntToStr(Parts[d]) + ']');
    Args.Add('-ar'); Args.Add('44100');          // wie StemMaker / Traktor-Stems
    Args.Add('-c:a'); Args.Add('pcm_s16le');
    Args.Add(DeckWavName(SourceFile, OutDir, d));
  end;
end;

procedure BuildPackArgs(const SourceFile, OutFile, Layout: string;
  Track, MaxSeconds: Integer; const Parts: TDeckParts; LfeGainDb: Double;
  MasterSilent: Boolean; Args: TStrings);
var
  F, First: string;
  s: Integer;
begin
  Args.Clear;
  AddInput(SourceFile, MaxSeconds, Args);
  Args.Add('-loglevel'); Args.Add('error');
  { Master (Spur 0): Kopie von Slot 1 oder Stille. Dafür den Teil von
    Slot 1 mit asplit verdoppeln. }
  First := 't' + IntToStr(Parts[0]);
  F := SplitFilter(Layout, Track, LfeGainDb) + ';' +
       '[' + First + ']asplit=2[s0][m0];';
  if MasterSilent then F := F + '[m0]volume=0[mst]'
  else F := F + '[m0]anull[mst]';
  Args.Add('-filter_complex'); Args.Add(F);
  Args.Add('-map'); Args.Add('[mst]');
  Args.Add('-map'); Args.Add('[s0]');
  for s := 1 to 3 do
  begin
    Args.Add('-map'); Args.Add('[t' + IntToStr(Parts[s]) + ']');
  end;
  Args.Add('-c:a'); Args.Add('aac');
  Args.Add('-b:a'); Args.Add('256k');
  Args.Add('-ar'); Args.Add('44100');
  Args.Add('-ac'); Args.Add('2');
  Args.Add('-map_metadata'); Args.Add('-1');
  Args.Add('-map_chapters'); Args.Add('-1');
  { Nur der Master ist "aktiv", die Stems sind "deaktiviert" (wie StemMaker) }
  Args.Add('-disposition:a:0'); Args.Add('default');
  for s := 1 to 4 do
  begin
    Args.Add('-disposition:a:' + IntToStr(s)); Args.Add('0');
  end;
  Args.Add('-f'); Args.Add('mp4');
  Args.Add(OutFile);
end;

function DeckFromFileName(const FileName: string; out BaseName: string): Integer;
var
  N: string;
  C: Char;
begin
  Result := -1;
  N := ExtractFileName(FileName);
  BaseName := N;
  if (Length(N) < 3) or (N[2] <> '_') then Exit;
  C := UpCase(N[1]);
  if (C < 'A') or (C > 'D') then Exit;
  Result := Ord(C) - Ord('A');
  BaseName := Copy(N, 3, MaxInt);
end;

end.
