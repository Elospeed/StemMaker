{ ============================================================================
  packjob.pas  -  ffmpeg-Aufruf für einen Song (Elospeed StemPacker)

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Baut die Parameter, mit denen ffmpeg aus Master + Stem 1..4 eine MP4 mit
  fünf Tonspuren macht (gleicher Aufbau wie in StemMaker: Spur 1 = Master,
  aktiv; Spur 2..5 = Stems, deaktiviert). Den Stem-Block (Namen, Farben)
  schreibt danach uStemMP4.InjectStemMetadata.

  Sonderfälle:
    - Kein Master (Einstellung "Master aus den Stems mischen"): die
      vorhandenen Stems werden ohne Pegeländerung zusammengemischt.
    - Ein Stem fehlt und "Fehlende Stems still füllen" ist an: die Spur
      wird aus einer vorhandenen Datei mit Lautstärke 0 gebaut, so ist sie
      genau gleich lang.
    - Tags und Cover kommen aus der Master-Datei (sonst aus dem ersten
      Stem). Hat sie kein Cover, kann ein Bild aus dem Ordner dazukommen.

  Keine Oberfläche, darum ohne Windows testbar.

  Versionen:
    0.1  (01.11.2026)  Erste Version
  ============================================================================ }
unit packjob;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils, packmatch;

type
  TPackFormat = (pfAAC, pfALAC16, pfALAC24);

  TPackOptions = record
    Format     : TPackFormat;
    AacKbps    : Integer;      // z.B. 320
    FillSilence: Boolean;      // fehlende Stems still füllen
    MixMaster  : Boolean;      // Master aus den Stems mischen
  end;

  { Was ffmpeg in MP4 nicht von selbst übernimmt (wie in StemMaker) }
  TSrcTags = record
    Title, Bpm, Key, Publisher, ISRC: string;
  end;

{ Datei, aus der Tags und Cover kommen: Master, sonst der erste Stem }
function TagSourceFile(Song: TPackSong): string;

{ Kann der Song gepackt werden? Sonst Grund in Why (deutsch, für _()). }
function SongReady(Song: TPackSong; const Opt: TPackOptions; out Why: string): Boolean;

{ ffmpeg-Parameter für die MP4 mit 5 Spuren. CoverFile: Bild aus dem Ordner
  ('' = Cover aus der Tag-Quelle, falls sie eins hat). }
procedure BuildPackArgs(Song: TPackSong; const Opt: TPackOptions;
  const CoverFile, OutFile: string; const Tags: TSrcTags; Args: TStrings);

{ Liest die Ausgabe von "ffmpeg -i <Datei> -f ffmetadata <txt>" }
function ParseFFMetadata(const MetaText: string): TSrcTags;

{ BPM als ganze Zahl (0 = unbrauchbar) }
function BpmToInt(const S: string): Integer;

{ cover.jpg, folder.jpg, front.jpg ... oder <Song>.jpg im Ordner ('' = keins) }
function FindFolderCover(const Folder, SongName: string): string;

implementation

function TagSourceFile(Song: TPackSong): string;
var r: Integer;
begin
  for r := 0 to ROLE_COUNT - 1 do
    if Song.Files[r] <> '' then Exit(Song.Files[r]);
  Result := '';
end;

function SongReady(Song: TPackSong; const Opt: TPackOptions; out Why: string): Boolean;
begin
  Why := '';
  if (Song.Files[0] = '') and not Opt.MixMaster then
    Why := 'Master fehlt'
  else if Song.StemCount = 0 then
    Why := 'Keine Stems gefunden'
  else if (Song.StemCount < 4) and not Opt.FillSilence then
    Why := 'Stems fehlen'
  else if Opt.MixMaster and (Song.Files[0] = '') and (Song.StemCount < 1) then
    Why := 'Keine Stems zum Mischen';
  Result := Why = '';
end;

procedure BuildPackArgs(Song: TPackSong; const Opt: TPackOptions;
  const CoverFile, OutFile: string; const Tags: TSrcTags; Args: TStrings);
var
  Inputs: TStringList;
  Graph, Tail: string;
  Maps: array[0..ROLE_COUNT - 1] of string;
  r, Idx, Bpm, n: Integer;

  function AddInput(const F: string): Integer;
  begin
    Result := Inputs.Add(F);
  end;

  procedure AddGraph(const S: string);
  begin
    if Graph <> '' then Graph := Graph + ';';
    Graph := Graph + S;
  end;

begin
  Inputs := TStringList.Create;
  try
    Graph := '';
    { Eingang 0 = Tag-Quelle (Master oder erster Stem) }
    AddInput(TagSourceFile(Song));

    { Stems: jede vorhandene Datei ein eigener Eingang }
    for r := 1 to ROLE_COUNT - 1 do
      if Song.Files[r] <> '' then
      begin
        if Song.Files[r] = Inputs[0] then Idx := 0 else Idx := AddInput(Song.Files[r]);
        Maps[r] := IntToStr(Idx) + ':a:0';
      end
      else
      begin
        { fehlt: Stille, so lang wie die Tag-Quelle }
        Idx := AddInput(Inputs[0]);
        AddGraph(Format('[%d:a]volume=0[s%d]', [Idx, r]));
        Maps[r] := '[s' + IntToStr(r) + ']';
      end;

    { Master }
    if Song.Files[0] <> '' then
      Maps[0] := '0:a:0'
    else
    begin
      { aus den vorhandenen Stems mischen, ohne Pegeländerung }
      Tail := '';
      n := 0;
      for r := 1 to ROLE_COUNT - 1 do
        if Song.Files[r] <> '' then
        begin
          Idx := AddInput(Song.Files[r]);
          Tail := Tail + '[' + IntToStr(Idx) + ':a]';
          Inc(n);
        end;
      if n = 1 then
        AddGraph(Tail + 'anull[m]')
      else
        AddGraph(Tail + Format('amix=inputs=%d:normalize=0:duration=longest[m]', [n]));
      Maps[0] := '[m]';
    end;

    Args.Clear;
    Args.AddStrings(['-hide_banner', '-nostdin', '-y']);
    for r := 0 to Inputs.Count - 1 do
      Args.AddStrings(['-i', Inputs[r]]);
    if CoverFile <> '' then
      Args.AddStrings(['-i', CoverFile]);
    if Graph <> '' then
      Args.AddStrings(['-filter_complex', Graph]);
    for r := 0 to ROLE_COUNT - 1 do
      Args.AddStrings(['-map', Maps[r]]);

    { Cover: Bild aus dem Ordner oder das der Tag-Quelle ("?" = optional) }
    if CoverFile <> '' then
      Args.AddStrings(['-map', IntToStr(Inputs.Count) + ':v:0'])
    else
      Args.AddStrings(['-map', '0:v:0?']);
    Args.AddStrings(['-c:v', 'copy', '-disposition:v:0', 'attached_pic']);

    case Opt.Format of
      pfALAC16: Args.AddStrings(['-c:a', 'alac', '-sample_fmt:a', 's16p', '-ar', '44100']);
      pfALAC24: Args.AddStrings(['-c:a', 'alac', '-sample_fmt:a', 's32p']);   // Abtastrate wie Quelle
    else
      Args.AddStrings(['-c:a', 'aac', '-b:a', IntToStr(Opt.AacKbps) + 'k', '-ar', '44100']);
    end;
    Args.AddStrings(['-ac', '2']);   // Mono-Spuren (z.B. LFE, Center) auf beide Seiten

    Bpm := BpmToInt(Tags.Bpm);
    if Bpm > 0 then
      Args.AddStrings(['-metadata', 'tmpo=' + IntToStr(Bpm)]);
    Args.AddStrings(['-map_metadata', '0', '-map_chapters', '-1']);
    { Ohne Titel-Tag den Songnamen als Titel nehmen (sonst zeigt Traktor
      nur den Dateinamen) }
    if Trim(Tags.Title) = '' then
      Args.AddStrings(['-metadata', 'title=' + Song.Name]);
    { Nur der Master ist aktiv, normale Player spielen dann nur ihn }
    Args.AddStrings(['-disposition:a:0', 'default',
      '-disposition:a:1', '0', '-disposition:a:2', '0',
      '-disposition:a:3', '0', '-disposition:a:4', '0',
      '-f', 'mp4', OutFile]);
  finally
    Inputs.Free;
  end;
end;

function ParseFFMetadata(const MetaText: string): TSrcTags;
var
  L: TStringList;
  i, p: Integer;
  Key, Val: string;

  { ffmpeg setzt vor '=', ';', '#', '\' einen Backslash }
  function Unescape(const S: string): string;
  var j: Integer;
  begin
    Result := '';
    j := 1;
    while j <= Length(S) do
    begin
      if (S[j] = '\') and (j < Length(S)) then Inc(j);
      Result := Result + S[j];
      Inc(j);
    end;
  end;

begin
  Result := Default(TSrcTags);
  L := TStringList.Create;
  try
    L.Text := MetaText;
    for i := 0 to L.Count - 1 do
    begin
      if (L[i] = '') or (L[i][1] in [';', '#', '[']) then Continue;
      p := Pos('=', L[i]);
      if p < 2 then Continue;
      Key := LowerCase(Trim(Copy(L[i], 1, p - 1)));
      Val := Trim(Unescape(Copy(L[i], p + 1, MaxInt)));
      if Val = '' then Continue;
      if (Key = 'title') and (Result.Title = '') then
        Result.Title := Val
      else if ((Key = 'tbpm') or (Key = 'bpm') or (Key = 'tmpo') or
          (Key = 'beats_per_minute')) and (Result.Bpm = '') then
        Result.Bpm := Val
      else if ((Key = 'tkey') or (Key = 'key') or (Key = 'initialkey') or
               (Key = 'initial_key')) and (Result.Key = '') then
        Result.Key := Val
      else if ((Key = 'publisher') or (Key = 'tpub') or (Key = 'label') or
               (Key = 'organization')) and (Result.Publisher = '') then
        Result.Publisher := Val
      else if ((Key = 'isrc') or (Key = 'tsrc')) and (Result.ISRC = '') then
        Result.ISRC := Val;
    end;
  finally
    L.Free;
  end;
end;

function BpmToInt(const S: string): Integer;
var
  T: string;
  i: Integer;
  D: Double;
  FS: TFormatSettings;
begin
  Result := 0;
  T := '';
  for i := 1 to Length(S) do
    if S[i] in ['0'..'9'] then
      T := T + S[i]
    else if (S[i] in ['.', ',']) and (Pos('.', T) = 0) then
      T := T + '.'
    else
      Break;
  if T = '' then Exit;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(T, D, FS) then Exit;
  if (D < 20) or (D > 400) then Exit;
  Result := Round(D);
end;

function FindFolderCover(const Folder, SongName: string): string;
const
  Names: array[0..5] of string = ('cover', 'folder', 'front', 'albumart', 'album', '%s');
  Exts: array[0..2] of string = ('.jpg', '.jpeg', '.png');
var
  i, e: Integer;
  N: string;
begin
  for i := High(Names) downto Low(Names) do   // zuerst <Song>.jpg, dann cover.jpg ...
  begin
    if Names[i] = '%s' then N := SongName else N := Names[i];
    for e := Low(Exts) to High(Exts) do
      if FileExistsUTF8(IncludeTrailingPathDelimiter(Folder) + N + Exts[e]) then
        Exit(IncludeTrailingPathDelimiter(Folder) + N + Exts[e]);
  end;
  Result := '';
end;

end.
