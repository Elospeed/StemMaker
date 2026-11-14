{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uhilfe.pas  (Unit uHilfe), Kopie für den StemPacker
            (gleich wie src\uhilfe.pas; Änderungen bitte in beiden)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Die eingebaute Hilfe (ab 2.4): Knopf "?" und Taste F1 öffnen die
  Anleitung im Browser, direkt an der passenden Stelle.

    - Die Anleitung liegt als eine HTML-Datei pro Sprache neben der Exe:
      hilfe\de.html, hilfe\en.html, hilfe\es.html (Bilder eingebettet,
      geht ohne Internet). Gebaut wird sie beim Release aus
      docs/handbuch/*.md (build.py --hilfe).
    - Gibt es die eingestellte Sprache nicht, kommt Englisch.
    - Fehlt der Ordner (z. B. nur die Exe kopiert), öffnet sich dieselbe
      Seite auf der Projektseite (Internet nötig).
    - Unter Wine (Linux) immer die Projektseite, siehe HilfeZeigen.

  Welche Stelle? Jedes Fenster trägt den Anker in HelpKeyword (z. B.
  'vortest'). F1 nimmt das HelpKeyword des aktiven Fensters, das
  erledigt HilfeTasteEinrichten einmal für das ganze Programm.

  Warum der Umweg über eine kleine Weiterleitungs-Datei? Windows lässt
  beim Öffnen einer lokalen Datei den Teil hinter "#" weg, der Browser
  käme immer oben an. Die Weiterleitung im Temp-Ordner springt mit
  Anker in die richtige Datei.
  ============================================================================ }
unit uHilfe;

{$mode objfpc}{$H+}

interface

{ Anleitung öffnen, Anker = Abschnitt ohne '#', leer = Anfang }
procedure HilfeZeigen(const Anker: string = '');

{ F1 in allen Fenstern: öffnet die Hilfe beim HelpKeyword des aktiven
  Fensters. Einmal beim Start aufrufen. }
procedure HilfeTasteEinrichten;

implementation

uses
  Classes, SysUtils, Forms, Controls, LCLType, LCLIntf, uLang, uWine;

const
  HILFE_ONLINE = 'https://elospeed.github.io/StemMaker/hilfe/';

type
  THilfeTaste = class
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

var
  Taste: THilfeTaste = nil;

{ Pfad als file:-Adresse, Leerzeichen und Umlaute bleiben lesbar
  (die Browser kommen damit zurecht), nur \ wird zu / }
function DateiAdresse(const Pfad: string): string;
begin
  Result := 'file:///' + StringReplace(Pfad, '\', '/', [rfReplaceAll]);
  Result := StringReplace(Result, ' ', '%20', [rfReplaceAll]);
  Result := StringReplace(Result, '#', '%23', [rfReplaceAll]);
end;

{ kleine HTML-Datei, die sofort zur Hilfe mit Anker weiterleitet }
function Weiterleitung(const Ziel: string): string;
var
  L: TStringList;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'StemMaker-Hilfe.html';
  L := TStringList.Create;
  try
    L.Add('<!DOCTYPE html><html><head><meta charset="utf-8">');
    L.Add('<meta http-equiv="refresh" content="0; url=' + Ziel + '">');
    L.Add('<title>StemMaker</title></head><body>');
    L.Add('<script>location.replace("' + Ziel + '");</script>');
    L.Add('<a href="' + Ziel + '">StemMaker</a></body></html>');
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

{ Anleitung in der Programmsprache im Browser öffnen, an der Stelle Anker
  (leer = Anfang). Lokal aus hilfe\, sonst oder unter Wine online. }
procedure HilfeZeigen(const Anker: string);
var
  Code, Ordner, Datei, Teil: string;
begin
  Code := LangCode;
  Ordner := AppBaseDir + 'hilfe' + PathDelim;
  if not FileExists(Ordner + Code + '.html') then
    Code := 'en';
  Datei := Ordner + Code + '.html';
  if Anker <> '' then Teil := '#' + Anker else Teil := '';

  { Unter Wine (Linux-AppImage) reicht Wine eine .html-Datei an das
    Linux-Programm weiter, das für HTML eingetragen ist. Das ist oft ein
    Texteditor, und den Windows-Pfad der Weiterleitung kennt Linux auch
    nicht. Eine https-Adresse öffnet dagegen sicher den Browser, mit Anker. }
  if UnterWine then
  begin
    Code := LangCode;
    if (Code <> 'de') and (Code <> 'es') then Code := 'en';
    OpenURL(HILFE_ONLINE + Code + '.html' + Teil);
    Exit;
  end;

  if FileExists(Datei) then
  begin
    if Teil = '' then
    begin
      OpenDocument(Datei);
      Exit;
    end;
    try
      OpenDocument(Weiterleitung(DateiAdresse(Datei) + Teil));
    except
      OpenDocument(Datei);     // Temp nicht schreibbar: dann eben ohne Anker
    end;
  end
  else
  begin
    { Online gibt es alle Sprachen, die es auch im Paket gibt (de, en, es) }
    Code := LangCode;
    if (Code <> 'de') and (Code <> 'es') then Code := 'en';
    OpenURL(HILFE_ONLINE + Code + '.html' + Teil);
  end;
end;

{ F1 ohne Umschalttasten: Hilfe zum aktiven Fenster (dessen HelpKeyword) }
procedure THilfeTaste.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  F: TCustomForm;
begin
  if (Key <> VK_F1) or (Shift <> []) then Exit;
  F := Screen.ActiveCustomForm;
  if F <> nil then
    HilfeZeigen(F.HelpKeyword)
  else
    HilfeZeigen('');
  Key := 0;
end;

{ F1 einmal für alle Fenster einrichten (Aufruf beim Start) }
procedure HilfeTasteEinrichten;
begin
  if Taste <> nil then Exit;
  Taste := THilfeTaste.Create;
  Application.AddOnKeyDownBeforeHandler(@Taste.KeyDown);
end;

finalization
  FreeAndNil(Taste);
end.
