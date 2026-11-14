{ ============================================================================
  Unit    : uDesign  (Datei udesign.pas)
  Programm: StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  Autor   : Elospeed
  Stand   : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    2.4, 14.11.2026: neu (Design hell, dunkel oder wie Windows)
  ----------------------------------------------------------------------------
  ZWECK

  Hell oder dunkel. In den Einstellungen wählbar:
    Automatisch  wie Windows (Einstellungen > Personalisierung > Farben,
                 "Standard-App-Modus"), das ist der Standard
    Hell         immer hell
    Dunkel       immer dunkel
  Gespeichert in StemMaker.ini, [Main] Design=auto|hell|dunkel.

  GRUNDIDEE

  Die LCL kann unter Windows selbst kein dunkles Design. Das übernimmt
  die Bibliothek metadarkstyle (Ordner darkstyle, siehe
  THIRD-PARTY-NOTICES.md): Sie färbt Fenster, Knöpfe, Listen, Menüs und
  Titelleisten um. Das geht nur einmal beim Start, bevor das erste
  Fenster entsteht. Darum gilt eine Änderung erst nach einem Neustart
  (die Einstellungen fragen dann, ob StemMaker neu starten soll).

  Braucht Windows 10 ab 1809. Ältere Windows und Wine bleiben hell.
  Selbst gezeichnete Teile (Statusspalte, Ko-fi-Knopf, AddOn-Leiste)
  fragen DunklesDesign in uStatusDraw ab.

  BENUTZUNG

    StemMaker.lpr   DesignAnwenden(IniName) ganz am Anfang, vor
                    Application.Initialize und vor dem ersten Fenster.
    uSettings       DesignLesen zeigt die gespeicherte Wahl an,
                    DesignSpeichern schreibt die neue Wahl.
  ============================================================================ }
unit uDesign;

{$mode objfpc}{$H+}

interface

{ ----------------------------------------------------------------------------
  Typen und öffentliche Prozeduren
  ---------------------------------------------------------------------------- }

type
  { Wahl in den Einstellungen }
  TDesignWahl = (
    dwAuto,                                                // wie Windows
    dwHell,                                                // immer hell
    dwDunkel                                               // immer dunkel
  );

function DesignLesen(const IniName: string): TDesignWahl;
procedure DesignSpeichern(const IniName: string; W: TDesignWahl);
procedure DesignAnwenden(const IniName: string);

implementation

uses
  SysUtils, IniFiles, uStatusDraw
  {$IFDEF LCLWIN32}
  , uDarkStyleParams, uMetaDarkStyle, uDarkStyleSchemes
  {$ENDIF};

{ ----------------------------------------------------------------------------
  Konstanten
  ---------------------------------------------------------------------------- }

const
  { So steht die Wahl in der INI (Reihenfolge wie TDesignWahl) }
  INI_WERTE: array[TDesignWahl] of string = ('auto', 'hell', 'dunkel');

{ ----------------------------------------------------------------------------
  INI lesen und schreiben
  ---------------------------------------------------------------------------- }

{ DesignLesen
  Liest die Design-Wahl aus der INI.
  Parameter: IniName = voller Pfad der StemMaker.ini
  Rückgabe : gespeicherte Wahl; fehlt sie, ist sie unbekannt oder ist die
             INI nicht lesbar, dann dwAuto (wie Windows)
  Ablauf   : 1. [Main] Design lesen, Gross/Klein und Leerzeichen egal
             2. mit INI_WERTE vergleichen und die passende Wahl nehmen }
function DesignLesen(const IniName: string): TDesignWahl;
var
  Ini: TIniFile;                                           // die StemMaker.ini
  S: string;                                               // gelesener Wert, klein
  W: TDesignWahl;                                          // Laufvariable
begin
  Result := dwAuto;
  try
    Ini := TIniFile.Create(IniName);
    try
      S := LowerCase(Trim(Ini.ReadString('Main', 'Design', 'auto')));
    finally
      Ini.Free;
    end;
    for W := Low(TDesignWahl) to High(TDesignWahl) do
      if S = INI_WERTE[W] then
        Result := W;
  except
    { INI nicht lesbar: Automatisch }
  end;
end;

{ DesignSpeichern
  Schreibt die Design-Wahl in die INI. Sie gilt erst ab dem nächsten Start,
  weil metadarkstyle nur einmal beim Start umfärben kann.
  Parameter: IniName = voller Pfad der StemMaker.ini
             W       = neue Wahl
  Ablauf   : 1. [Main] Design=auto|hell|dunkel schreiben
             2. Fehler (INI schreibgeschützt) still übergehen }
procedure DesignSpeichern(const IniName: string; W: TDesignWahl);
var
  Ini: TIniFile;                                           // die StemMaker.ini
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteString('Main', 'Design', INI_WERTE[W]);
    finally
      Ini.Free;
    end;
  except
    { INI nicht schreibbar: Wahl gilt nur bis zum Ende }
  end;
end;

{ ----------------------------------------------------------------------------
  Beim Start anwenden
  ---------------------------------------------------------------------------- }

{ DesignAnwenden
  Stellt metadarkstyle nach der gespeicherten Wahl ein und merkt sich in
  DunklesDesign (uStatusDraw), ob das Programm jetzt dunkel ist.
  Nur Windows-Widgetset; muss vor dem ersten Fenster laufen, sonst bleiben
  schon erzeugte Fenster hell.
  Parameter: IniName = voller Pfad der StemMaker.ini
  Ablauf   : 1. Wahl lesen und PreferredAppMode setzen
             2. ApplyMetaDarkStyle färbt alle späteren Fenster um
             3. IsDarkModeEnabled sagt, ob es wirklich dunkel ist (bei
                Automatisch hängt das von Windows ab) }
procedure DesignAnwenden(const IniName: string);
begin
  {$IFDEF LCLWIN32}
  case DesignLesen(IniName) of
    dwHell  : PreferredAppMode := pamForceLight;
    dwDunkel: PreferredAppMode := pamForceDark;
  else
    PreferredAppMode := pamAllowDark;                      // wie Windows
  end;
  try
    ApplyMetaDarkStyle(DefaultDark);
  except
    { sollte nie passieren - dann eben hell }
  end;
  DunklesDesign := IsDarkModeEnabled;
  {$ENDIF}
end;

end.
