{ ============================================================================
  surround51.pas  -  5.1-Ton erkennen und auf vier Decks (A..D) aufteilen

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Was ist eine 5.1-Datei?
    Sechs Kanäle in einer Spur: FL FR (vorne links/rechts), FC (Center,
    meist Sprache/Gesang), LFE (Subwoofer, nur tiefe Töne) und zwei
    Surround-Kanäle. ffmpeg nennt das Layout "5.1(side)" (SL SR) oder
    "5.1" (BL BR). Typisch in MKV/MP4-Videos, Konzert-Mitschnitten, AC3/EAC3,
    DTS - meist mit 48 kHz.

  Aufteilung auf die Decks (immer Stereo, Mono-Kanäle auf beide Seiten):
      A_<Name>.wav   Front     FL + FR
      B_<Name>.wav   Center    FC  (mono -> links und rechts gleich)
      C_<Name>.wav   Surround  SL + SR  bzw.  BL + BR
      D_<Name>.wav   LFE       LFE (mono -> links und rechts gleich)
  Jede WAV-Datei wird danach wie ein normaler Song in 4 Stems getrennt
  (StemCLI ohne Club-Pegel, damit die Decks im Verhältnis gleich laut
  bleiben). In Traktor auf Deck A..D laden und gleichzeitig starten.

  Der ffmpeg-Aufruf selbst wird im Fenster ausgeführt (dort läuft die
  Schleife, die das Fenster bedienbar hält). Diese Unit liefert nur die
  Parameter und wertet die Ausgabe aus.

  Versionen:
    0.1  (10.10.2026)  Erste Testversion
  ============================================================================ }
unit surround51;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils;

const
  DECK_LETTERS: array[0..3] of Char = ('A', 'B', 'C', 'D');
  { Welcher 5.1-Teil landet auf welchem Deck (Anzeige im Player) }
  DECK_PARTS: array[0..3] of string = ('FRONT L/R', 'CENTER', 'SURROUND L/R', 'LFE (SUB)');

{ Sucht in der Ausgabe von "ffmpeg -i <Datei>" die erste Audiospur und
  liefert ihr Kanal-Layout (z.B. "5.1(side)", "5.1", "stereo", "7.1").
  AudioLine = die ganze Zeile (zur Anzeige). Leer, wenn keine Audiospur. }
function ParseAudioLayout(const FFmpegOutput: string; out AudioLine: string): string;

{ True, wenn das Layout von diesem Test unterstützt wird (5.1 / 5.1(side)) }
function IsSupported51(const Layout: string): Boolean;

{ Zielname für ein Deck:  <Ordner>\A_<Name>.wav }
function DeckWavName(const SourceFile, OutDir: string; Deck: Integer): string;

{ Baut die ffmpeg-Parameter für die Zerlegung in die vier WAV-Dateien.
  MaxSeconds > 0 -> nur die ersten MaxSeconds Sekunden (zum schnellen Testen). }
procedure BuildSplitArgs(const SourceFile, OutDir, Layout: string;
  MaxSeconds: Integer; Args: TStrings);

{ Ist der Dateiname ein Deck-Teil ("A_Name...")? Dann Deck 0..3, sonst -1.
  BaseName = Dateiname ohne das Präfix "A_". }
function DeckFromFileName(const FileName: string; out BaseName: string): Integer;

implementation

function ParseAudioLayout(const FFmpegOutput: string; out AudioLine: string): string;
var
  L: TStringList;
  i, p: Integer;
  S, Part: string;
  Parts: TStringList;
begin
  Result := '';
  AudioLine := '';
  L := TStringList.Create;
  Parts := TStringList.Create;
  try
    L.Text := FFmpegOutput;
    for i := 0 to L.Count - 1 do
    begin
      { Beispiel:  Stream #0:1(eng): Audio: ac3, 48000 Hz, 5.1(side), fltp, 448 kb/s }
      p := Pos('Audio:', L[i]);
      if (Pos('Stream #', L[i]) = 0) or (p = 0) then Continue;
      AudioLine := Trim(L[i]);
      S := Copy(L[i], p + Length('Audio:'), MaxInt);
      { Teile durch Komma getrennt; das Layout steht nach "xxxxx Hz" }
      Parts.StrictDelimiter := True;
      Parts.Delimiter := ',';
      Parts.DelimitedText := S;
      for p := 0 to Parts.Count - 2 do
      begin
        Part := Trim(Parts[p]);
        if (Length(Part) > 3) and (Copy(Part, Length(Part) - 2, 3) = ' Hz') then
        begin
          Result := Trim(Parts[p + 1]);
          Exit;
        end;
      end;
      Exit;   // nur die erste Audiospur auswerten
    end;
  finally
    Parts.Free;
    L.Free;
  end;
end;

function IsSupported51(const Layout: string): Boolean;
begin
  Result := (Layout = '5.1') or (Layout = '5.1(side)');
end;

function DeckWavName(const SourceFile, OutDir: string; Deck: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(OutDir) + DECK_LETTERS[Deck] + '_' +
            ExtractFileNameOnly(SourceFile) + '.wav';
end;

procedure BuildSplitArgs(const SourceFile, OutDir, Layout: string;
  MaxSeconds: Integer; Args: TStrings);
var
  SurL, SurR, Filter: string;
  d: Integer;
const
  Labels: array[0..3] of string = ('[front]', '[center]', '[rear]', '[lfe]');
begin
  { Namen der Surround-Kanäle hängen vom Layout ab }
  if Layout = '5.1(side)' then begin SurL := 'SL'; SurR := 'SR'; end
  else begin SurL := 'BL'; SurR := 'BR'; end;

  { channelsplit zerlegt in 6 Mono-Kanäle. join setzt zwei Mono-Kanäle
    zu Stereo zusammen - die map ist nötig, sonst legt ffmpeg die Mono-
    Eingänge auf den Center und vertauscht dabei links/rechts.
    pan macht aus einem Mono-Kanal Stereo (beide Seiten gleich). }
  Filter :=
    '[0:a:0]channelsplit=channel_layout=' + Layout +
      '[FL][FR][FC][LFE][' + SurL + '][' + SurR + '];' +
    '[FL][FR]join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[front];' +
    '[' + SurL + '][' + SurR + ']join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[rear];' +
    '[FC]pan=stereo|c0=c0|c1=c0[center];' +
    '[LFE]pan=stereo|c0=c0|c1=c0[lfe]';

  Args.Clear;
  Args.Add('-hide_banner');
  Args.Add('-nostdin');
  Args.Add('-loglevel'); Args.Add('error');
  Args.Add('-y');
  if MaxSeconds > 0 then
  begin
    Args.Add('-t'); Args.Add(IntToStr(MaxSeconds));   // nur Anfang lesen
  end;
  Args.Add('-i'); Args.Add(SourceFile);
  Args.Add('-filter_complex'); Args.Add(Filter);
  { Reihenfolge der Decks: A Front, B Center, C Surround, D LFE }
  for d := 0 to 3 do
  begin
    Args.Add('-map'); Args.Add(Labels[d]);
    Args.Add('-ar'); Args.Add('44100');          // wie StemMaker / Traktor-Stems
    Args.Add('-c:a'); Args.Add('pcm_s16le');
    Args.Add(DeckWavName(SourceFile, OutDir, d));
  end;
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
