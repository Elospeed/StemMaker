{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uupdate.pas  (Unit uUpdate, ohne Oberfläche)
  Version : 1.7
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  update.json liegt im Repository (Zweig main) und sagt StemMaker:
    - welche Version die neueste ist, mit Text "Was ist neu"
    - wo das Release-ZIP liegt und welche SHA-256-Prüfsumme es hat
    - wo die feste ffmpeg-Version liegt (+ Prüfsumme)
    - wo die Modelle liegen (+ Prüfsummen)
  Zieht eine Datei um, muss nur update.json auf GitHub geändert werden -
  alle installierten StemMaker finden sie dann beim nächsten Start.
  Aufbau und Pflege: docs/UPDATE-JSON.md

  UPDATE INSTALLIEREN (InstallUpdate)
    1. Release-ZIP herunterladen und Prüfsumme kontrollieren (uUpdateUI)
    2. in einen Hilfsordner neben der Exe entpacken
    3. jede Datei an ihren Platz kopieren. Die alte Datei wird dabei NICHT
       gelöscht, sondern zu <Name>.old umbenannt (eine laufende Exe kann
       Windows nicht überschreiben, umbenennen geht). Die .old-Dateien
       räumt der nächste Start weg (CleanupOldFiles).
       Geht unterwegs etwas schief (z.B. Virenscanner sperrt eine Datei),
       wird alles zurückgedreht: neue Dateien weg, .old zurückbenennen.
       StemMaker bleibt dann vollständig auf der alten Version.
    4. NIE angefasst werden: StemMaker.ini, die Warteschlange, logs\,
       models\ und tools\ffmpeg.exe (liegen auch nicht im ZIP, aber sicher
       ist sicher).

  In der INI:
    [Update]
    AutoCheck=1        beim Start nach Updates suchen (0 = aus)
    SkipVersion=1.8    diese Version nicht mehr anbieten ("Überspringen")
    [Download]
    UpdateJsonURL=...  andere Adresse für update.json (zum Testen)
  ============================================================================ }
unit uUpdate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, fpjson, jsonparser, FileUtil, LazFileUtils,
  Math, uDownload, uLang, uStemJob;

const
  DEF_UPDATE_JSON_URL =
    'https://raw.githubusercontent.com/Elospeed/StemMaker/main/update.json';
  UPDATE_TIMEOUT_MS = 5000;     // länger wird beim Start nie gewartet
  UPDATE_ZIP_NAME = 'StemMaker-update.zip';   // Download im Temp-Ordner

type
  TUpdateInfo = record
    Valid      : Boolean;
    Version    : string;        // z.B. '1.7'
    Date       : string;
    PageURL    : string;        // Release-Seite (für "Mehr Infos")
    Notes      : string;        // "Was ist neu" in der aktuellen Sprache
    ZipURL     : string;        // Release-ZIP
    ZipSHA256  : string;
    FFmpegURL  : string;        // feste ffmpeg-Version (ZIP)
    FFmpegSHA256: string;
    FFmpegEntry: string;        // Dateiname im ZIP, normalerweise ffmpeg.exe
    FFmpegMB   : Integer;
    FFmpegVer  : string;
    ModelBaseURL: string;
    ModelHashes: TStringList;   // Name=Prüfsumme (nil, wenn keine)
  end;

{ update.json holen und auswerten. Info.ModelHashes muss der Aufrufer mit
  FreeUpdateInfo freigeben. }
function FetchUpdateInfo(TimeoutMS: Integer; out Info: TUpdateInfo;
  out ErrMsg: string): Boolean;
procedure FreeUpdateInfo(var Info: TUpdateInfo);

{ Prüfsumme eines Modells aus update.json ('' = unbekannt) }
function ModelHash(const Info: TUpdateInfo; const FileName: string): string;

{ Ist Remote neuer als Local? Vergleicht Zahl für Zahl: 1.10 > 1.9 }
function IsNewerVersion(const Remote, Local: string): Boolean;

{ INI-Einstellungen }
function UpdateAutoCheck(const IniName: string): Boolean;
procedure UpdateSetAutoCheck(const IniName: string; Value: Boolean);
function UpdateSkipVersion(const IniName: string): string;
procedure UpdateSetSkipVersion(const IniName, Version: string);

{ entpacktes Update an seinen Platz bringen (siehe oben) }
function InstallUpdate(const ZipFile, AppDir: string; out ErrMsg: string): Boolean;

{ *.old von einem früheren Update wegräumen, dazu Download-Reste im Temp-Ordner }
procedure CleanupOldFiles(const AppDir: string);

implementation

function JStr(O: TJSONObject; const Name: string): string;
begin
  Result := Trim(O.Get(Name, ''));
end;

function UpdateJsonURL: string;
var
  Ini: TIniFile;
begin
  Result := DEF_UPDATE_JSON_URL;
  if not FileExists(StemIniFileName) then Exit;
  Ini := TIniFile.Create(StemIniFileName);
  try
    Result := Trim(Ini.ReadString('Download', 'UpdateJsonURL', DEF_UPDATE_JSON_URL));
    if Result = '' then Result := DEF_UPDATE_JSON_URL;
  finally
    Ini.Free;
  end;
end;

function FetchUpdateInfo(TimeoutMS: Integer; out Info: TUpdateInfo;
  out ErrMsg: string): Boolean;
var
  Text: string;
  D: TJSONData;
  O, F, M, H: TJSONObject;
  I: Integer;
begin
  Info := Default(TUpdateInfo);
  Result := False;
  if not HttpGetText(UpdateJsonURL, TimeoutMS, Text, ErrMsg) then
    Exit;
  D := nil;
  { Alles in try/except: Ein einzelner falscher Eintrag (z.B. null statt Text)
    darf nicht unbemerkt die ganze Prüfung abbrechen - dann steht wenigstens
    der Grund im Log. }
  try
    try
      D := GetJSON(Text);
      if not (D is TJSONObject) then
      begin
        ErrMsg := 'update.json: kein Objekt';
        Exit;
      end;
      O := TJSONObject(D);
      Info.Version := JStr(O, 'version');
      Info.Date := JStr(O, 'date');
      Info.PageURL := JStr(O, 'page');
      { Die Seite wird im Browser geöffnet (OpenURL). Nur echte Web-Adressen
        zulassen - ein Eintrag wie "C:\...\x.exe" oder "file://..." würde
        sonst ein Programm auf dem PC starten. }
      if Pos('https://', LowerCase(Info.PageURL)) <> 1 then
        Info.PageURL := '';
      { "Was ist neu" in der eingestellten Sprache, sonst Englisch, sonst Deutsch }
      Info.Notes := JStr(O, 'notes_' + LangCode);
      if Info.Notes = '' then Info.Notes := JStr(O, 'notes_en');
      if Info.Notes = '' then Info.Notes := JStr(O, 'notes_de');
      Info.ZipURL := JStr(O, 'zip_url');
      Info.ZipSHA256 := LowerCase(JStr(O, 'zip_sha256'));
      if O.Find('ffmpeg', F) then
      begin
        Info.FFmpegURL := JStr(F, 'url');
        Info.FFmpegSHA256 := LowerCase(JStr(F, 'sha256'));
        Info.FFmpegEntry := JStr(F, 'entry');
        Info.FFmpegMB := F.Get('size_mb', 0);
        Info.FFmpegVer := JStr(F, 'version');
      end;
      if Info.FFmpegEntry = '' then Info.FFmpegEntry := 'ffmpeg.exe';
      if O.Find('models', M) then
      begin
        Info.ModelBaseURL := JStr(M, 'base_url');
        if M.Find('sha256', H) then
        begin
          Info.ModelHashes := TStringList.Create;
          for I := 0 to H.Count - 1 do
            { nur Texte übernehmen - null oder Zahlen werden übersprungen }
            if (H.Items[I].JSONType = jtString) and (Trim(H.Items[I].AsString) <> '') then
              Info.ModelHashes.Values[H.Names[I]] := LowerCase(Trim(H.Items[I].AsString));
        end;
      end;
      Info.Valid := Info.Version <> '';
      Result := Info.Valid;
      if not Result then
        ErrMsg := 'update.json: "version" fehlt oder ist kein Text ' +
          '(Version in Anführungszeichen schreiben, z.B. "1.8")';
    except
      on E: Exception do
      begin
        ErrMsg := 'update.json: ' + E.Message;
        Result := False;
      end;
    end;
  finally
    D.Free;
    if not Result then
      FreeUpdateInfo(Info);
  end;
end;

procedure FreeUpdateInfo(var Info: TUpdateInfo);
begin
  FreeAndNil(Info.ModelHashes);
end;

function ModelHash(const Info: TUpdateInfo; const FileName: string): string;
begin
  Result := '';
  if Info.ModelHashes <> nil then
    Result := Info.ModelHashes.Values[ExtractFileName(FileName)];
end;

function IsNewerVersion(const Remote, Local: string): Boolean;
var
  R, L: TStringArray;
  I, A, B: Integer;
begin
  Result := False;
  R := Remote.Split(['.']);
  L := Local.Split(['.']);
  for I := 0 to Max(High(R), High(L)) do
  begin
    A := 0; B := 0;
    if I <= High(R) then A := StrToIntDef(R[I], 0);
    if I <= High(L) then B := StrToIntDef(L[I], 0);
    if A <> B then
      Exit(A > B);
  end;
end;

function UpdateAutoCheck(const IniName: string): Boolean;
var
  Ini: TIniFile;
begin
  Result := True;
  if not FileExists(IniName) then Exit;
  Ini := TIniFile.Create(IniName);
  try
    Result := Ini.ReadBool('Update', 'AutoCheck', True);
  finally
    Ini.Free;
  end;
end;

procedure UpdateSetAutoCheck(const IniName: string; Value: Boolean);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteBool('Update', 'AutoCheck', Value);
    finally
      Ini.Free;
    end;
  except
  end;
end;

function UpdateSkipVersion(const IniName: string): string;
var
  Ini: TIniFile;
begin
  Result := '';
  if not FileExists(IniName) then Exit;
  Ini := TIniFile.Create(IniName);
  try
    Result := Ini.ReadString('Update', 'SkipVersion', '');
  finally
    Ini.Free;
  end;
end;

procedure UpdateSetSkipVersion(const IniName, Version: string);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteString('Update', 'SkipVersion', Version);
    finally
      Ini.Free;
    end;
  except
  end;
end;

{ Darf diese Datei (Pfad relativ zum StemMaker-Ordner) ersetzt werden? }
function IsProtected(const Rel: string): Boolean;
var
  R: string;
begin
  R := LowerCase(StringReplace(Rel, '/', '\', [rfReplaceAll]));
  Result := (R = 'stemmaker.ini') or (Pos('stemmaker_queue', R) = 1) or
    (Pos('logs\', R) = 1) or (Pos('models\', R) = 1) or
    (R = 'tools\ffmpeg.exe') or (R = 'addons\stemplayer.ini');
end;

{ Eine Datei an ihren Platz bringen. Gibt es das Ziel schon, wird es zu
  <Name>.old umbenannt (siehe oben). Done merkt sich jede gelegte Datei
  ("1" = alte Datei liegt als .old daneben, "0" = war neu), damit
  RollBack alles zurückdrehen kann. }
function PlaceFile(const Src, Dest: string; Done: TStrings; out ErrMsg: string): Boolean;
var
  HadOld: Boolean;
begin
  Result := False;
  ErrMsg := '';
  ForceDirectories(ExtractFilePath(Dest));
  HadOld := FileExists(Dest);
  if HadOld then
  begin
    if FileExists(Dest + '.old') then
      SysUtils.DeleteFile(Dest + '.old');
    if not RenameFile(Dest, Dest + '.old') then
    begin
      ErrMsg := Format(_('Kann %s nicht ersetzen'), [Dest]);
      Exit;
    end;
  end;
  if HadOld then
    Done.Add('1' + Dest)
  else
    Done.Add('0' + Dest);
  Result := FileUtil.CopyFile(Src, Dest);
  if not Result then
    ErrMsg := Format(_('Kann %s nicht schreiben'), [Dest]);
end;

{ Halbe Installation zurückdrehen: rückwärts jede neue Datei löschen und
  die .old wieder zurückbenennen }
procedure RollBack(Done: TStrings);
var
  I: Integer;
  Dest: string;
begin
  for I := Done.Count - 1 downto 0 do
  begin
    Dest := Copy(Done[I], 2, MaxInt);
    if FileExists(Dest) then
      SysUtils.DeleteFile(Dest);
    if Done[I][1] = '1' then
      RenameFile(Dest + '.old', Dest);
  end;
end;

function InstallUpdate(const ZipFile, AppDir: string; out ErrMsg: string): Boolean;
var
  Tmp, Root, Rel: string;
  Files: TStringList;
  Dirs: TStringList;
  Done: TStringList;
  I: Integer;
begin
  Result := False;
  Tmp := IncludeTrailingPathDelimiter(AppDir) + '_update_tmp' + PathDelim;
  if DirectoryExists(Tmp) then
    DeleteDirectory(ExcludeTrailingPathDelimiter(Tmp), False);
  if not ExtractZipAll(ZipFile, Tmp, ErrMsg) then
  begin
    { halb entpackten Hilfsordner nicht liegen lassen }
    DeleteDirectory(ExcludeTrailingPathDelimiter(Tmp), False);
    Exit;
  end;
  Files := nil;
  Dirs := TStringList.Create;
  Done := TStringList.Create;
  try
    { Liegt im ZIP alles in einem Ordner "StemMaker\"? Dann ist dieser
      Ordner die Wurzel (so ist das Release-ZIP aufgebaut). }
    Root := Tmp;
    if not FileExists(Tmp + 'StemMaker.exe') then
    begin
      FindAllDirectories(Dirs, Tmp, False);
      for I := 0 to Dirs.Count - 1 do
        if FileExists(IncludeTrailingPathDelimiter(Dirs[I]) + 'StemMaker.exe') then
        begin
          Root := IncludeTrailingPathDelimiter(Dirs[I]);
          Break;
        end;
    end;
    if not FileExists(Root + 'StemMaker.exe') then
    begin
      ErrMsg := _('Das Update-ZIP enthält keine StemMaker.exe');
      Exit;
    end;
    Files := FindAllFiles(Root, '*', True);
    for I := 0 to Files.Count - 1 do
    begin
      Rel := ExtractRelativePath(Root, Files[I]);
      if IsProtected(Rel) then
        Continue;
      if not PlaceFile(Files[I], IncludeTrailingPathDelimiter(AppDir) + Rel, Done, ErrMsg) then
      begin
        RollBack(Done);
        ErrMsg := ErrMsg + LineEnding + _('Die alte Version wurde wiederhergestellt.');
        Exit;
      end;
    end;
    Result := True;
  finally
    Files.Free;
    Dirs.Free;
    Done.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Tmp), False);
  end;
end;

procedure CleanupOldFiles(const AppDir: string);
var
  L: TStringList;
  I: Integer;
  Zip: string;
begin
  { Reste eines abgebrochenen oder hängengebliebenen Update-Downloads im
    Temp-Ordner (Name wie in uUpdateUI) }
  Zip := GetTempDir(False) + UPDATE_ZIP_NAME;
  if FileExists(Zip) then SysUtils.DeleteFile(Zip);
  if FileExists(Zip + '.part') then SysUtils.DeleteFile(Zip + '.part');
  if not DirectoryExists(AppDir) then Exit;
  L := FindAllFiles(AppDir, '*.old', True);
  try
    for I := 0 to L.Count - 1 do
      if Pos(PathDelim + 'models' + PathDelim, L[I]) = 0 then
        SysUtils.DeleteFile(L[I]);   // klappt nicht, wenn sie noch läuft - dann beim nächsten Mal
  finally
    L.Free;
  end;
end;

end.
