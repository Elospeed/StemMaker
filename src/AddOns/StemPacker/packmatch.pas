{ ============================================================================
  packmatch.pas  -  Songs finden für den Elospeed StemPacker

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Der StemPacker setzt pro Song fünf fertige Dateien (Master + Stem 1..4)
  zu einer Traktor-Stem-Datei zusammen. Diese Unit findet heraus, welche
  Dateien zusammengehören. Keine Oberfläche, darum auch ohne Windows
  testbar.

  Für jede der fünf Rollen (Master, Stem 1..4) gibt es einen Ordner und
  ein Namensmuster. Im Muster steht ein Stern * für den Songnamen, z. B.
      Master:  "* (DOWNMIX #1)"       Ordner 1
      Stem 1:  "* (A)"                Ordner 2
  Aus "Ordner 1\Hello (DOWNMIX #1).wav" wird so der Song "Hello", dazu
  gehört "Ordner 2\Hello (A).wav". Gross-/Kleinschreibung spielt keine
  Rolle, die Dateiendung gehört nicht zum Muster. Ein zweiter Stern im
  Muster steht für beliebigen Text, der nicht zum Songnamen gehört.

  Liegen mehrere Rollen im selben Ordner (z. B. "*" für den Master und
  "*_drums" für Stem 1), zählt eine Datei, die zu einem Stem-Muster passt,
  nie als Master. Sonst wäre "Song_drums.wav" ein eigener Song.

  Mit Unterordnern: der Unterordner (relativ zum Ordner der Rolle) gehört
  zum Schlüssel, die Ordnerstruktur muss also in allen Ordnern gleich sein.

  Versionen:
    0.1  (01.11.2026)  Erste Version
  ============================================================================ }
unit packmatch;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LazFileUtils, LazUTF8;

const
  ROLE_COUNT = 5;          // 0 = Master, 1..4 = Stem 1..4
  AUDIO_EXTS = '.wav;.wave;.flac;.aif;.aiff;.mp3;.m4a;.ogg;.opus;.w64;.wv';

type
  TRoleFiles = array[0..ROLE_COUNT - 1] of string;   // '' = nicht gefunden

  { Ein gefundener Song }
  TPackSong = class
    Name   : string;        // Songname aus dem Muster (Teil beim Stern)
    SubDir : string;        // Unterordner relativ zum Ordner der Rolle ('' oder 'Album\')
    Files  : TRoleFiles;
    function FoundCount: Integer;
    function StemCount: Integer;
  end;

  TPackRules = record
    Folders : TRoleFiles;    // Ordner je Rolle ('' = wie die Rolle davor)
    Patterns: TRoleFiles;    // Muster je Rolle (ohne Endung)
    MixMaster: Boolean;      // Master aus den Stems mischen (kein Master-Muster)
    SubFolders: Boolean;     // Unterordner durchsuchen
  end;

{ Passt Name (ohne Endung) zum Muster? Songname = Teil beim ersten Stern. }
function MatchPattern(const Pattern, Name: string; out Song: string): Boolean;

{ Gültiges Muster? Genau ein Stern für den Songnamen ist Pflicht. }
function PatternValid(const Pattern: string): Boolean;

{ Ist die Endung eine bekannte Audio-Endung? }
function IsAudioFile(const FileName: string): Boolean;

{ Ordner der Rolle (leer = wie die Rolle davor, Stem 1 wie Master) }
function RoleFolder(const Rules: TPackRules; Role: Integer): string;

{ Alle Songs suchen. Ergebnis: Liste von TPackSong (Aufrufer gibt frei),
  sortiert nach Unterordner und Name. }
procedure FindSongs(const Rules: TPackRules; Songs: TList);
procedure FreeSongs(Songs: TList);

implementation

function TPackSong.FoundCount: Integer;
var r: Integer;
begin
  Result := 0;
  for r := 0 to ROLE_COUNT - 1 do
    if Files[r] <> '' then Inc(Result);
end;

function TPackSong.StemCount: Integer;
var r: Integer;
begin
  Result := 0;
  for r := 1 to ROLE_COUNT - 1 do
    if Files[r] <> '' then Inc(Result);
end;

function IsAudioFile(const FileName: string): Boolean;
var E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  Result := (E <> '') and (Pos(';' + E + ';', ';' + AUDIO_EXTS + ';') > 0);
end;

function PatternValid(const Pattern: string): Boolean;
begin
  Result := Pos('*', Pattern) > 0;
end;

function RoleFolder(const Rules: TPackRules; Role: Integer): string;
var r: Integer;
begin
  { leerer Ordner = wie die Rolle davor (Stem 2 wie Stem 1, Stem 1 wie
    Master). Ist der Master-Ordner leer (Master mischen), gilt der erste
    Stem-Ordner, der angegeben ist. }
  Result := '';
  for r := Role downto 0 do
  begin
    Result := Trim(Rules.Folders[r]);
    if Result <> '' then Break;
  end;
  if Result = '' then
    for r := 1 to ROLE_COUNT - 1 do
    begin
      Result := Trim(Rules.Folders[r]);
      if Result <> '' then Break;
    end;
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result);
end;

{ Muster-Vergleich mit Sternen (rekursiv, Namen sind kurz).
  Pat und S schon in Kleinbuchstaben. Der erste Stern merkt sich, was er
  abdeckt (Songname). }
function GlobMatch(const Pat, S: string; PI, SI: Integer; First: Boolean;
  var Cap: string): Boolean;
var
  k: Integer;
begin
  while PI <= Length(Pat) do
  begin
    if Pat[PI] = '*' then
    begin
      for k := Length(S) + 1 downto SI do
        if GlobMatch(Pat, S, PI + 1, k, False, Cap) then
        begin
          if First then Cap := Copy(S, SI, k - SI);
          Exit(True);
        end;
      Exit(False);
    end;
    if (SI > Length(S)) or (Pat[PI] <> S[SI]) then Exit(False);
    Inc(PI);
    Inc(SI);
  end;
  Result := SI > Length(S);
end;

function MatchPattern(const Pattern, Name: string; out Song: string): Boolean;
var
  P, N, Cap: string;
  Star, Start: Integer;
begin
  Song := '';
  Result := False;
  P := UTF8LowerCase(Trim(Pattern));
  N := UTF8LowerCase(Name);
  if Pos('*', P) = 0 then Exit;
  Star := Pos('*', P);
  { Teil vor dem ersten Stern muss exakt passen, danach rekursiv }
  if Copy(N, 1, Star - 1) <> Copy(P, 1, Star - 1) then Exit;
  Cap := '';
  if not GlobMatch(P, N, Star, Star, True, Cap) then Exit;
  if Cap = '' then Exit;           // leerer Songname zählt nicht
  { Songname in Original-Schreibweise aus Name holen (gleiche Bytelänge,
    weil Kleinschreibung bei Umlauten die Länge in UTF-8 nicht ändert;
    zur Sicherheit sonst die kleingeschriebene Fassung) }
  Start := Star;
  if Length(N) = Length(Name) then
    Song := Copy(Name, Start, Length(Cap))
  else
    Song := Cap;
  Song := Trim(Song);
  Result := Song <> '';
end;

{ Alle Audiodateien eines Ordners (relativer Pfad ohne Endung -> voller Pfad) }
procedure ListAudio(const Folder: string; Sub: Boolean; Names, Paths: TStrings);
var
  L: TStringList;
  i: Integer;
  Rel: string;
begin
  if (Folder = '') or not DirectoryExistsUTF8(Folder) then Exit;
  L := TStringList.Create;
  try
    FindAllFiles(L, Folder, '*', Sub);
    for i := 0 to L.Count - 1 do
      if IsAudioFile(L[i]) then
      begin
        Rel := Copy(L[i], Length(Folder) + 1, MaxInt);
        Names.Add(Rel);
        Paths.Add(L[i]);
      end;
  finally
    L.Free;
  end;
end;

function SongKey(const SubDir, Song: string): string;
begin
  Result := UTF8LowerCase(SubDir + '|' + Song);
end;

procedure FindSongs(const Rules: TPackRules; Songs: TList);
var
  Names, Paths: array[0..ROLE_COUNT - 1] of TStringList;
  Index: TStringList;      // Schlüssel -> TPackSong
  r, q, i, k, KeyRole: Integer;
  Rel, Sub, Base, Song, Dummy: string;
  S: TPackSong;
  IsStem: Boolean;

  function GetSong(const ASub, AName: string; Create: Boolean): TPackSong;
  var j: Integer;
  begin
    j := Index.IndexOf(SongKey(ASub, AName));
    if j >= 0 then Exit(TPackSong(Index.Objects[j]));
    Result := nil;
    if not Create then Exit;
    Result := TPackSong.Create;
    Result.Name := AName;
    Result.SubDir := ASub;
    Index.AddObject(SongKey(ASub, AName), Result);
  end;

begin
  for r := 0 to ROLE_COUNT - 1 do
  begin
    Names[r] := TStringList.Create;
    Paths[r] := TStringList.Create;
  end;
  Index := TStringList.Create;
  Index.Sorted := True;
  Index.Duplicates := dupIgnore;
  try
    for r := 0 to ROLE_COUNT - 1 do
      if not ((r = 0) and Rules.MixMaster) then
        ListAudio(RoleFolder(Rules, r), Rules.SubFolders, Names[r], Paths[r]);

    { Welche Rolle bestimmt die Songs? Der Master, beim Mischen Stem 1..4
      (jeder Stem kann einen Song anlegen, damit auch Songs mit fehlendem
      Stem 1 auftauchen) }
    if Rules.MixMaster then KeyRole := 1 else KeyRole := 0;

    for r := 0 to ROLE_COUNT - 1 do
    begin
      if (r = 0) and Rules.MixMaster then Continue;
      if not PatternValid(Rules.Patterns[r]) then Continue;
      for i := 0 to Names[r].Count - 1 do
      begin
        Rel := Names[r][i];
        Sub := ExtractFilePath(Rel);
        Base := ExtractFileNameOnly(Rel);
        if not MatchPattern(Rules.Patterns[r], Base, Song) then Continue;
        if r = 0 then
        begin
          { Datei passt auch zu einem Stem-Muster im selben Ordner? Dann
            ist sie kein Master }
          IsStem := False;
          for q := 1 to ROLE_COUNT - 1 do
            if PatternValid(Rules.Patterns[q]) and
               (CompareFilenames(RoleFolder(Rules, q), RoleFolder(Rules, 0)) = 0) and
               MatchPattern(Rules.Patterns[q], Base, Dummy) then
            begin
              IsStem := True;
              Break;
            end;
          if IsStem then Continue;
        end;
        S := GetSong(Sub, Song, (r = KeyRole) or Rules.MixMaster);
        if S = nil then Continue;
        if S.Files[r] = '' then S.Files[r] := Paths[r][i];
      end;
    end;

    { Ohne Master-Datei kein Song (ausser beim Mischen); Songs, die nur von
      Stems angelegt würden, gibt es oben schon nicht }
    for k := 0 to Index.Count - 1 do
      Songs.Add(Index.Objects[k]);
  finally
    Index.Free;
    for r := 0 to ROLE_COUNT - 1 do
    begin
      Names[r].Free;
      Paths[r].Free;
    end;
  end;
end;

procedure FreeSongs(Songs: TList);
var i: Integer;
begin
  for i := 0 to Songs.Count - 1 do
    TObject(Songs[i]).Free;
  Songs.Clear;
end;

end.
