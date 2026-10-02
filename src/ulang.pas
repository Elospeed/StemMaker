{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulang.pas  (Unit uLang)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Mehrsprachigkeit. Das Programm ist auf Deutsch geschrieben - jeder Text,
  den der Benutzer sieht, steht im Code in einer kleinen Funktion:

        Caption := _('Dateien hinzufügen...');

  _() schaut in der geladenen Sprachdatei nach, ob es für diesen deutschen
  Text eine Übersetzung gibt. Wenn ja, kommt die Übersetzung zurück,
  sonst einfach der deutsche Text. Es kann also nie "nichts" angezeigt
  werden - schlimmstenfalls steht etwas auf Deutsch da.

  DIE SPRACHDATEIEN
  Liegen im Ordner "lang" neben der Exe, z.B. lang\en.po für Englisch.
  Das ist das übliche "gettext"-Format, das man mit dem kostenlosen
  Programm Poedit bearbeiten kann:

        msgid "Dateien hinzufügen..."
        msgstr "Add files..."

  NEUE SPRACHE HINZUFÜGEN
  lang\StemMaker.pot (Vorlage mit allen Texten) nach z.B. lang\fr.po
  kopieren, mit Poedit übersetzen, fertig. StemMaker findet die Datei beim
  nächsten Start von selbst und bietet die Sprache zur Auswahl an.

  Diese Unit braucht keine Oberfläche (keine LCL) und funktioniert deshalb
  auch in StemCLI. Das Auswahlfenster liegt in uLangUI.
  ============================================================================ }
unit uLang;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils {$IFDEF WINDOWS}, Windows{$ENDIF};

{ Text übersetzen (deutsch rein -> aktuelle Sprache raus) }
function _(const S: string): string;

{ Der StemMaker-Hauptordner (mit Backslash am Ende). Normalerweise der
  Ordner der Exe. Liegt die Exe aber in einem Unterordner wie "Extras\"
  (z.B. StemCLI.exe), ist es der Ordner darüber - dort liegen tools\,
  models\, lang\ und StemMaker.ini. }
function AppBaseDir: string;

{ Sprache laden: 'de' = Original (keine Datei nötig), sonst lang\<code>.po.
  Gibt False zurück, wenn die Datei fehlt - dann bleibt es bei Deutsch. }
function LangLoad(const Code: string): Boolean;
{ aktuell geladene Sprache, z.B. 'de' oder 'en' }
function LangCode: string;
{ Ordner mit den Sprachdateien: <Programmordner>\lang\ }
function LangDir: string;
{ Sprache von Windows: 'de' wenn Windows deutsch ist, sonst 'en' }
function LangSystemDefault: string;
{ alle verfügbaren Sprachen (immer mit 'de'), z.B. ['de', 'en'] }
function LangAvailable: TStringList;
{ Name einer Sprache in ihrer eigenen Sprache, z.B. 'en' -> 'English' }
function LangDisplayName(const Code: string): string;

implementation

var
  GCode : string = 'de';
  GTable: TStringList = nil;   // sortierte Liste der deutschen Originaltexte;
                               // das "Objekt" daneben ist die Nummer der
                               // Übersetzung in GTrans
  GTrans: TStringList = nil;   // die Übersetzungen

function AppBaseDir: string;
var
  ExeDir, Parent: string;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  Result := ExeDir;
  { kein tools\-Ordner hier, aber eine Ebene höher liegt StemMaker.exe?
    -> wir sind in einem Unterordner (Extras\) }
  if not DirectoryExists(ExeDir + 'tools') then
  begin
    Parent := ExtractFilePath(ExcludeTrailingPathDelimiter(ExeDir));
    if FileExists(Parent + 'StemMaker.exe') or DirectoryExists(Parent + 'tools') then
      Result := Parent;
  end;
end;

function LangDir: string;
begin
  Result := AppBaseDir + 'lang' + PathDelim;
end;

function LangCode: string;
begin
  Result := GCode;
end;

{ ---------------------------------------------------------------------------
  Nachschlagen. GTable ist sortiert -> sehr schnelle Suche (Find).
  --------------------------------------------------------------------------- }
function _(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  if (GTable = nil) or (S = '') then Exit;
  if GTable.Find(S, I) then
    Result := GTrans[PtrInt(GTable.Objects[I])];
end;

{ ---------------------------------------------------------------------------
  .po-Datei lesen

  Aufbau (vereinfacht):
      #, fuzzy                    <- unsicher übersetzt -> ignorieren
      msgid "Erste Zeile "
      "Fortsetzung"               <- mehrzeilige Texte werden zusammengehängt
      msgstr "Translation"
  Sonderzeichen in Anführungszeichen: \n \t \" \\
  --------------------------------------------------------------------------- }
function Unescape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '\') and (I < Length(S)) then
    begin
      Inc(I);
      case S[I] of
        'n': Result := Result + LineEnding;
        't': Result := Result + #9;
        '"': Result := Result + '"';
        '\': Result := Result + '\';
      else
        Result := Result + '\' + S[I];
      end;
    end
    else
      Result := Result + S[I];
    Inc(I);
  end;
end;

{ Text zwischen dem ersten und letzten Anführungszeichen einer Zeile }
function Quoted(const Line: string): string;
var
  A, B: Integer;
begin
  A := Pos('"', Line);
  B := Length(Line);
  while (B > A) and (Line[B] <> '"') do Dec(B);
  if (A > 0) and (B > A) then
    Result := Unescape(Copy(Line, A + 1, B - A - 1))
  else
    Result := '';
end;

function LangLoad(const Code: string): Boolean;
var
  L: TStringList;
  I, Mode: Integer;       // Mode: 0 = nichts, 1 = in msgid, 2 = in msgstr
  Line, Id, Str: string;
  Fuzzy: Boolean;

  procedure Flush;
  begin
    { fertigen Eintrag übernehmen (leere/unsichere weglassen) }
    if (Id <> '') and (Str <> '') and not Fuzzy then
    begin
      GTrans.Add(Str);
      GTable.AddObject(Id, TObject(PtrInt(GTrans.Count - 1)));
    end;
    Id := ''; Str := ''; Fuzzy := False; Mode := 0;
  end;

begin
  Result := False;
  FreeAndNil(GTable);
  FreeAndNil(GTrans);
  GCode := 'de';
  if (Code = '') or SameText(Code, 'de') then
    Exit(True);                              // Deutsch = Original
  if not FileExists(LangDir + Code + '.po') then
    Exit;
  GTable := TStringList.Create;
  GTable.CaseSensitive := True;
  GTrans := TStringList.Create;
  L := TStringList.Create;
  try
    L.LoadFromFile(LangDir + Code + '.po');   // UTF-8 wie der Rest
    Id := ''; Str := ''; Fuzzy := False; Mode := 0;
    for I := 0 to L.Count - 1 do
    begin
      Line := Trim(L[I]);
      if Line = '' then
        Flush
      else if Copy(Line, 1, 2) = '#,' then
      begin
        if Mode = 2 then Flush;
        Fuzzy := Pos('fuzzy', Line) > 0;
      end
      else if Line[1] = '#' then
        { Kommentar }
      else if Copy(Line, 1, 6) = 'msgid ' then
      begin
        if Mode = 2 then
        begin
          { neuer Eintrag ohne Leerzeile davor - "fuzzy" gehört zu ihm }
          Flush;
        end;
        Id := Quoted(Line);
        Mode := 1;
      end
      else if Copy(Line, 1, 7) = 'msgstr ' then
      begin
        Str := Quoted(Line);
        Mode := 2;
      end
      else if Line[1] = '"' then
        case Mode of
          1: Id := Id + Quoted(Line);
          2: Str := Str + Quoted(Line);
        end;
    end;
    Flush;
    GTable.Sorted := True;                    // erst JETZT sortieren
    GCode := LowerCase(Code);
    Result := True;
  finally
    L.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Windows-Sprache: GetUserDefaultUILanguage liefert z.B. $0807 (Deutsch
  Schweiz) oder $0409 (Englisch USA). Die unteren 10 Bit sind die
  Hauptsprache: $07 = Deutsch.
  --------------------------------------------------------------------------- }
{$IFDEF WINDOWS}
function GetUserDefaultUILanguage: Word; stdcall; external 'kernel32.dll';
{$ENDIF}

function LangSystemDefault: string;
begin
  Result := 'en';
  {$IFDEF WINDOWS}
  if (GetUserDefaultUILanguage and $3FF) = $07 then
    Result := 'de';
  {$ELSE}
  if Pos('de', LowerCase(GetEnvironmentVariable('LANG'))) = 1 then
    Result := 'de';
  {$ENDIF}
end;

function LangAvailable: TStringList;
var
  SR: TSearchRec;
  C: string;
begin
  Result := TStringList.Create;
  Result.Add('de');
  if FindFirst(LangDir + '*.po', faAnyFile, SR) = 0 then
  try
    repeat
      C := LowerCase(ChangeFileExt(SR.Name, ''));
      if (C <> 'de') and (Result.IndexOf(C) < 0) then
        Result.Add(C);
    until FindNext(SR) <> 0;
  finally
    SysUtils.FindClose(SR);
  end;
end;

function LangDisplayName(const Code: string): string;
begin
  case LowerCase(Code) of
    'de': Result := 'Deutsch';
    'en': Result := 'English';
    'fr': Result := 'Français';
    'it': Result := 'Italiano';
    'es': Result := 'Español';
    'nl': Result := 'Nederlands';
    'pt': Result := 'Português';
    'pl': Result := 'Polski';
    'tr': Result := 'Türkçe';
  else
    Result := UpperCase(Code);
  end;
end;

finalization
  FreeAndNil(GTable);
  FreeAndNil(GTrans);
end.
