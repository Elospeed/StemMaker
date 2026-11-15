{ ============================================================================
  Unit    : uHilfe  (Datei uhilfe.pas), Kopie für den StemPacker
            (gleich wie src\uhilfe.pas; Änderungen bitte in allen)
  Programm: StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  Autor   : Elospeed
  Stand   : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    2.4, 14.11.2026: neu (Knopf "?" und F1 in StemMaker und allen AddOns,
                     unter Wine immer die Online-Hilfe)
  ----------------------------------------------------------------------------
  ZWECK

  Die eingebaute Hilfe: Knopf "?" und Taste F1 öffnen die Anleitung im
  Browser, direkt an der passenden Stelle.

  GRUNDIDEE

    - Die Anleitung liegt als eine HTML-Datei pro Sprache neben der Exe:
      hilfe\de.html, hilfe\en.html, hilfe\es.html (Bilder eingebettet,
      geht ohne Internet). Gebaut wird sie beim Release aus
      docs/handbuch/*.md (build.py --hilfe).
    - Gibt es die eingestellte Sprache nicht, kommt Englisch.
    - Fehlt der Ordner (z. B. nur die Exe kopiert), öffnet sich dieselbe
      Seite auf der Projektseite (Internet nötig).
    - Unter Wine (Linux) immer die Projektseite, siehe HilfeZeigen.

  Welche Stelle? Jedes Fenster trägt den Anker in HelpKeyword (z. B.
  'vortest', 'stemtagger'). Die Anker sind die Marken #anker hinter den
  Kapitelüberschriften in docs/handbuch/*.md.

  Warum der Umweg über eine kleine Weiterleitungs-Datei? Windows lässt
  beim Öffnen einer lokalen Datei den Teil hinter "#" weg, der Browser
  käme immer oben an. Die Weiterleitung im Temp-Ordner springt mit
  Anker in die richtige Datei.

  BENUTZUNG

    HilfeTasteEinrichten       einmal beim Start (im .lpr); danach öffnet
                               F1 in jedem Fenster die Hilfe bei dessen
                               HelpKeyword.
    HilfeZeigen('turbo')       z. B. im OnClick eines "?"-Knopfs;
                               HilfeZeigen('') öffnet den Anfang.
  ============================================================================ }
unit uHilfe;

{$mode objfpc}{$H+}

interface

procedure HilfeZeigen(const Anker: string = '');
procedure HilfeTasteEinrichten;

implementation

uses
  Classes, SysUtils, Forms, Controls, LCLType, LCLIntf, uLang, uWine;

{ ----------------------------------------------------------------------------
  Konstanten, Typen, Variablen
  ---------------------------------------------------------------------------- }

const
  { Online-Hilfe auf der Projektseite; dahinter kommt <sprache>.html }
  HILFE_ONLINE = 'https://elospeed.github.io/StemMaker/hilfe/';

type
  { Nimmt die Tastendrücke aller Fenster entgegen. Eine Klasse ist nötig,
    weil Application nur Methoden als Handler annimmt. }
  THilfeTaste = class
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

var
  Taste: THilfeTaste = nil;                                // einzige Instanz, nil = F1 nicht eingerichtet

{ ----------------------------------------------------------------------------
  Hilfsfunktionen
  ---------------------------------------------------------------------------- }

{ DateiAdresse
  Macht aus einem Windows-Pfad eine file:-Adresse für den Browser.
  Parameter: Pfad = voller Pfad, z. B. C:\Programme\StemMaker\hilfe\de.html
  Rückgabe : z. B. file:///C:/Programme/StemMaker/hilfe/de.html
  Ablauf   : 1. \ wird zu /
             2. Leerzeichen wird %20, # wird %23 (sonst hielte der Browser
                den Rest für einen Anker); Umlaute bleiben, die Browser
                kommen damit zurecht }
function DateiAdresse(const Pfad: string): string;
begin
  Result := 'file:///' + StringReplace(Pfad, '\', '/', [rfReplaceAll]);
  Result := StringReplace(Result, ' ', '%20', [rfReplaceAll]);
  Result := StringReplace(Result, '#', '%23', [rfReplaceAll]);
end;

{ Weiterleitung
  Schreibt eine kleine HTML-Datei, die sofort zur Hilfe mit Anker springt.
  Parameter: Ziel = file:-Adresse samt Anker, z. B. ...de.html#turbo
  Rückgabe : Pfad der Weiterleitung (Temp-Ordner, StemMaker-Hilfe.html)
  Ablauf   : 1. HTML mit meta refresh und location.replace schreiben
                (zweifach, falls ein Browser eines davon nicht ausführt)
             2. dazu ein normaler Link als letzte Rettung
  Wirft eine Ausnahme, wenn der Temp-Ordner nicht schreibbar ist. }
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

{ ----------------------------------------------------------------------------
  Hilfe öffnen
  ---------------------------------------------------------------------------- }

{ HilfeZeigen
  Öffnet die Anleitung in der Programmsprache im Browser.
  Parameter: Anker = Abschnitt ohne '#', z. B. 'turbo'; leer = Anfang
  Ablauf   : 1. lokale Datei hilfe\<sprache>.html suchen, sonst Englisch
             2. unter Wine: immer online (siehe Kommentar unten)
             3. lokal ohne Anker: Datei direkt öffnen
             4. lokal mit Anker: über die Weiterleitung öffnen; geht das
                nicht, die Datei ohne Anker
             5. keine lokale Datei: online, Sprache de, es oder en }
procedure HilfeZeigen(const Anker: string);
var
  Code: string;                                            // Sprachcode, z. B. 'de'
  Ordner: string;                                          // <Programmordner>\hilfe\
  Datei: string;                                           // lokale Hilfedatei
  Teil: string;                                            // '#anker' oder leer
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
      OpenDocument(Datei);                                 // Temp nicht schreibbar: dann eben ohne Anker
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

{ ----------------------------------------------------------------------------
  Taste F1
  ---------------------------------------------------------------------------- }

{ THilfeTaste.KeyDown
  Läuft vor jedem Tastendruck in jedem Fenster des Programms.
  Parameter: Sender = Steuerelement mit dem Fokus (unbenutzt)
             Key    = gedrückte Taste; 0 = erledigt, nicht weitergeben
             Shift  = Umschalttasten; F1 gilt nur ohne
  Ablauf   : 1. nur F1 ohne Umschalt-, Strg- oder Alt-Taste
             2. HelpKeyword des aktiven Fensters als Anker nehmen
             3. Taste schlucken, damit kein Steuerelement sie nochmals sieht }
procedure THilfeTaste.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  F: TCustomForm;                                          // aktives Fenster
begin
  if (Key <> VK_F1) or (Shift <> []) then Exit;
  F := Screen.ActiveCustomForm;
  if F <> nil then
    HilfeZeigen(F.HelpKeyword)
  else
    HilfeZeigen('');
  Key := 0;
end;

{ HilfeTasteEinrichten
  Richtet F1 einmal für alle Fenster ein (Aufruf beim Start).
  Ablauf   : 1. schon eingerichtet: nichts tun
             2. THilfeTaste erzeugen und bei Application anmelden; die
                Anmeldung "Before" sieht die Taste vor dem Fenster }
procedure HilfeTasteEinrichten;
begin
  if Taste <> nil then Exit;
  Taste := THilfeTaste.Create;
  Application.AddOnKeyDownBeforeHandler(@Taste.KeyDown);
end;

{ Beim Programmende freigeben }
finalization
  FreeAndNil(Taste);
end.
