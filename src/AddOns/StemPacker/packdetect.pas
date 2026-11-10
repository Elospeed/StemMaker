{ ============================================================================
  packdetect.pas  -  Benennung automatisch erkennen (Einfach-Modus)

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Im Einfach-Modus zieht man nur einen Ordner in den StemPacker. Diese
  Unit schaut sich die Audiodateien darin an (mit Unterordnern) und sucht
  die Benennung, zu der die meisten Songs vollständig passen:

    - Wörter:  "Song_drums", "Song - Bass", "Song (Vocals)", "Song [Other]"
               mit verschiedenen Trennzeichen und üblichen Namen
               (vocals/vocal/vox/voice, other/melody/instruments ...)
    - Nummern: "Song_1" bis "Song_4", Master "Song_0"
    - 5.1-DVD: "Song (A)" bis "Song (D)", Master "Song (DOWNMIX #1)"

  Danach sucht sie den Master (gleicher Name ohne Zusatz, "_mix",
  "_master" ...). Gibt es zu weniger als der Hälfte der Songs einen
  Master, wird der Master aus den Stems gemischt.

  Liegt jede Spur in genau einem Ordner (z. B. Master in "Downmix", Stems
  in "Spuren"), bekommt jede Rolle ihren eigenen Ordner. Sonst wird der
  gezogene Ordner mit Unterordnern durchsucht (z. B. ein Unterordner pro
  Album mit allen Spuren darin).

  Keine Oberfläche, darum auch ohne Windows testbar.

  Versionen:
    0.3  (07.11.2026)  Erste Version
  ============================================================================ }
unit packdetect;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils, LazUTF8, packmatch;

type
  { Art der erkannten Benennung }
  TDetectKind = (dkNone, dkWords, dkNumbers, dkDvd);

  TDetectResult = record
    Kind     : TDetectKind;
    Rules    : TPackRules;   // Ordner, Muster, Master mischen, Unterordner
    Songs    : Integer;      // Songs mit mindestens einem Stem
    Complete : Integer;      // Songs mit allen vier Stems
    Masters  : Integer;      // davon mit Master-Datei
  end;

{ Ordner untersuchen. Kind = dkNone, wenn keine Benennung passt. }
function DetectLayout(const Folder: string): TDetectResult;

implementation

type
  TStemPatterns = array[1..ROLE_COUNT - 1] of string;

const
  { Trennzeichen und Klammern um das Spurwort; %s = Wort.
    Reihenfolge = Vorrang bei Gleichstand (längere Trenner zuerst, sonst
    gewinnt " " und der Songname endet auf " -") }
  WORD_STYLES: array[0..10] of string = (
    '* - %s', '* (%s)', '* [%s]', '*' + #95 + '(%s)',  { #95 = _ (sonst hält i18n.py das für einen Text) }
    '*_[%s]', '*_%s', '*-%s',
    '*.%s', '*(%s)', '* %s', '*%s');

  { Übliche Namen je Stem, Traktor-Reihenfolge Drums, Bass, Other, Vox }
  WORDS_DRUMS: array[0..2] of string = ('drums', 'drum', 'percussion');
  WORDS_BASS : array[0..0] of string = ('bass');
  WORDS_OTHER: array[0..5] of string = ('other', 'melody', 'instruments', 'music', 'synth', 'others');
  WORDS_VOX  : array[0..3] of string = ('vocals', 'vocal', 'vox', 'voice');

  { Nummern: Trenner vor der Ziffer }
  NUMBER_STYLES: array[0..3] of string = ('*_%d', '* - %d', '*-%d', '* (%d)');

  { Master-Kandidaten bei Wörtern; %s = Trenner-Stil wie oben }
  MASTER_WORDS: array[0..5] of string = ('mix', 'master', 'original', 'full', 'main', 'stereo');

var
  { Dateien des untersuchten Ordners (relativ: Unterordner\Name.ext) }
  GNames: TStringList;

{ Zählt für ein Muster: Songname (klein) -> Unterordner. Ergebnis = Anzahl
  Treffer. Map kann nil sein (nur zählen). Exclude: Dateien, die zu einem
  dieser Muster passen, zählen nicht (für den Master "*"). }
function CountPattern(const Pattern: string; Map: TStringList;
  const Exclude: TStemPatterns; UseExclude: Boolean): Integer;
var
  i, q: Integer;
  Base, Song, Dummy, Key: string;
  Skip: Boolean;
begin
  Result := 0;
  for i := 0 to GNames.Count - 1 do
  begin
    Base := ExtractFileNameOnly(GNames[i]);
    if not MatchPattern(Pattern, Base, Song) then Continue;
    if UseExclude then
    begin
      Skip := False;
      for q := Low(Exclude) to High(Exclude) do
        if (Exclude[q] <> '') and MatchPattern(Exclude[q], Base, Dummy) then
        begin
          Skip := True;
          Break;
        end;
      if Skip then Continue;
    end;
    Inc(Result);
    if Map <> nil then
    begin
      { Songname -> Unterordner; gleiche Songnamen in verschiedenen
        Unterordnern (z. B. zwei Alben) bleiben einzeln drin }
      Key := UTF8LowerCase(Song);
      if Map.IndexOf(Key + '=' + ExtractFilePath(GNames[i])) < 0 then
        Map.Add(Key + '=' + ExtractFilePath(GNames[i]));
    end;
  end;
end;

{ Bestes Wort einer Rolle für einen Stil (meiste Treffer) }
function BestWord(const Style: string; const Words: array of string): string;
var
  i, N, Best: Integer;
  Dummy: TStemPatterns;
begin
  Result := Format(Style, [Words[0]]);
  Best := 0;
  Dummy := Default(TStemPatterns);
  for i := Low(Words) to High(Words) do
  begin
    N := CountPattern(Format(Style, [Words[i]]), nil, Dummy, False);
    if N > Best then
    begin
      Best := N;
      Result := Format(Style, [Words[i]]);
    end;
  end;
end;

{ Ein Kandidat wird bewertet und, wenn besser, in Best übernommen }
procedure Evaluate(Kind: TDetectKind; const Stems: TStemPatterns;
  const MasterCands: array of string; const Folder: string;
  var Best: TDetectResult);
var
  Maps: array[0..ROLE_COUNT - 1] of TStringList;
  AllSongs: TStringList;
  r, i, k, Complete, Masters, MBest: Integer;
  Dirs: array[0..ROLE_COUNT - 1] of string;
  OneDir: array[0..ROLE_COUNT - 1] of Boolean;
  MasterPat, Song: string;
  Tmp: TStringList;
  Res: TDetectResult;
  NoEx: TStemPatterns;
begin
  NoEx := Default(TStemPatterns);
  for r := 0 to ROLE_COUNT - 1 do Maps[r] := TStringList.Create;
  AllSongs := TStringList.Create;
  AllSongs.Sorted := True;
  AllSongs.Duplicates := dupIgnore;
  try
    for r := 1 to ROLE_COUNT - 1 do
    begin
      CountPattern(Stems[r], Maps[r], NoEx, False);
      for i := 0 to Maps[r].Count - 1 do
        AllSongs.Add(Maps[r].Names[i]);
    end;
    { vollständig = alle vier Stems da }
    Complete := 0;
    for i := 0 to AllSongs.Count - 1 do
    begin
      k := 0;
      for r := 1 to ROLE_COUNT - 1 do
        if Maps[r].IndexOfName(AllSongs[i]) >= 0 then Inc(k);
      if k = ROLE_COUNT - 1 then Inc(Complete);
    end;
    if Complete = 0 then Exit;

    { bester Master: zu wie vielen Songs gibt es eine Master-Datei? }
    MasterPat := '';
    MBest := 0;
    for k := Low(MasterCands) to High(MasterCands) do
    begin
      Tmp := TStringList.Create;
      try
        CountPattern(MasterCands[k], Tmp, Stems, True);
        Masters := 0;
        for i := 0 to AllSongs.Count - 1 do
          if Tmp.IndexOfName(AllSongs[i]) >= 0 then Inc(Masters);
        if Masters > MBest then
        begin
          MBest := Masters;
          MasterPat := MasterCands[k];
        end;
      finally
        Tmp.Free;
      end;
    end;

    { besser als der bisher beste? Zuerst vollständige Songs, dann Master }
    if (Best.Kind <> dkNone) and
       ((Complete < Best.Complete) or
        ((Complete = Best.Complete) and (MBest <= Best.Masters))) then Exit;

    Res := Default(TDetectResult);
    Res.Kind := Kind;
    Res.Songs := AllSongs.Count;
    Res.Complete := Complete;
    Res.Masters := MBest;
    for r := 1 to ROLE_COUNT - 1 do
      Res.Rules.Patterns[r] := Stems[r];
    { weniger als die Hälfte mit Master: Master aus den Stems mischen }
    Res.Rules.MixMaster := (MasterPat = '') or (MBest * 2 < AllSongs.Count);
    if Res.Rules.MixMaster then
      Res.Rules.Patterns[0] := '*'
    else
    begin
      Res.Rules.Patterns[0] := MasterPat;
      CountPattern(MasterPat, Maps[0], Stems, True);
    end;

    { Ordner: liegt jede Rolle in genau einem Unterordner? }
    for r := 0 to ROLE_COUNT - 1 do
    begin
      Dirs[r] := '';
      OneDir[r] := True;
      if (r = 0) and Res.Rules.MixMaster then Continue;
      for i := 0 to Maps[r].Count - 1 do
      begin
        Song := Maps[r].ValueFromIndex[i];
        if i = 0 then Dirs[r] := Song
        else if CompareFilenames(Song, Dirs[r]) <> 0 then OneDir[r] := False;
      end;
    end;
    k := 0;
    for r := 0 to ROLE_COUNT - 1 do
      if not OneDir[r] then Inc(k);
    if k = 0 then
    begin
      { jede Rolle in ihrem Ordner, keine Unterordner durchsuchen }
      Res.Rules.SubFolders := False;
      for r := 0 to ROLE_COUNT - 1 do
        if (r = 0) and Res.Rules.MixMaster then
          Res.Rules.Folders[r] := ''
        else
          Res.Rules.Folders[r] := ExcludeTrailingPathDelimiter(
            IncludeTrailingPathDelimiter(Folder) + Dirs[r]);
    end
    else
    begin
      { verteilt: gezogenen Ordner mit Unterordnern durchsuchen, alle
        Spuren eines Songs liegen dann im selben Unterordner }
      Res.Rules.SubFolders := True;
      for r := 0 to ROLE_COUNT - 1 do Res.Rules.Folders[r] := '';
      if Res.Rules.MixMaster then
        Res.Rules.Folders[1] := ExcludeTrailingPathDelimiter(Folder)
      else
        Res.Rules.Folders[0] := ExcludeTrailingPathDelimiter(Folder);
    end;
    Best := Res;
  finally
    for r := 0 to ROLE_COUNT - 1 do Maps[r].Free;
    AllSongs.Free;
  end;
end;

function DetectLayout(const Folder: string): TDetectResult;
var
  Paths: TStringList;
  s, i, n: Integer;
  St: TStemPatterns;
  Masters: array of string;
begin
  Result := Default(TDetectResult);
  Result.Kind := dkNone;
  if (Folder = '') or not DirectoryExistsUTF8(Folder) then Exit;
  GNames := TStringList.Create;
  Paths := TStringList.Create;
  try
    ListAudio(IncludeTrailingPathDelimiter(Folder), True, GNames, Paths);
    if GNames.Count = 0 then Exit;

    { 1. Wörter }
    for s := Low(WORD_STYLES) to High(WORD_STYLES) do
    begin
      St[1] := BestWord(WORD_STYLES[s], WORDS_DRUMS);
      St[2] := BestWord(WORD_STYLES[s], WORDS_BASS);
      St[3] := BestWord(WORD_STYLES[s], WORDS_OTHER);
      St[4] := BestWord(WORD_STYLES[s], WORDS_VOX);
      { Master: Name ohne Zusatz oder mit "mix", "master" ... im selben Stil }
      SetLength(Masters, 1 + Length(MASTER_WORDS));
      Masters[0] := '*';
      for i := 0 to High(MASTER_WORDS) do
        Masters[i + 1] := Format(WORD_STYLES[s], [MASTER_WORDS[i]]);
      Evaluate(dkWords, St, Masters, Folder, Result);
    end;

    { 2. Nummern 1..4, Master 0 }
    for s := Low(NUMBER_STYLES) to High(NUMBER_STYLES) do
    begin
      for n := 1 to ROLE_COUNT - 1 do
        St[n] := Format(NUMBER_STYLES[s], [n]);
      SetLength(Masters, 2);
      Masters[0] := Format(NUMBER_STYLES[s], [0]);
      Masters[1] := '*';
      Evaluate(dkNumbers, St, Masters, Folder, Result);
    end;

    { 3. 5.1-DVD: A..D, Master DOWNMIX }
    St[1] := '* (A)'; St[2] := '* (B)'; St[3] := '* (C)'; St[4] := '* (D)';
    SetLength(Masters, 3);
    Masters[0] := '* (DOWNMIX #1)';
    Masters[1] := '* (DOWNMIX)';
    Masters[2] := '*';
    Evaluate(dkDvd, St, Masters, Folder, Result);
  finally
    Paths.Free;
    FreeAndNil(GNames);
  end;
end;

end.
