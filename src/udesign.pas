{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udesign.pas  (Unit uDesign)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Hell oder dunkel (ab 2.4). In den Einstellungen wählbar:
    Automatisch  wie Windows (Einstellungen > Personalisierung > Farben,
                 "Standard-App-Modus"), das ist der Standard
    Hell         immer hell
    Dunkel       immer dunkel
  Gespeichert in StemMaker.ini, [Main] Design=auto|hell|dunkel.

  Die LCL kann unter Windows selbst kein dunkles Design. Das übernimmt
  die Bibliothek metadarkstyle (Ordner darkstyle, siehe
  THIRD-PARTY-NOTICES.md): Sie färbt Fenster, Knöpfe, Listen, Menüs und
  Titelleisten um. Das geht nur einmal beim Start, bevor das erste
  Fenster entsteht. Darum gilt eine Änderung erst nach einem Neustart.

  Braucht Windows 10 ab 1809. Ältere Windows und Wine bleiben hell.
  Selbst gezeichnete Teile (Statusspalte, Ko-fi-Knopf, AddOn-Leiste)
  fragen DunklesDesign in uStatusDraw ab.
  ============================================================================ }
unit uDesign;

{$mode objfpc}{$H+}

interface

type
  TDesignWahl = (dwAuto, dwHell, dwDunkel);

{ Wahl aus der INI lesen (fehlt sie: Automatisch) }
function DesignLesen(const IniName: string): TDesignWahl;
{ Wahl in die INI schreiben (gilt ab dem nächsten Start) }
procedure DesignSpeichern(const IniName: string; W: TDesignWahl);
{ Beim Start einmal aufrufen, vor dem ersten Fenster.
  Setzt DunklesDesign in uStatusDraw. }
procedure DesignAnwenden(const IniName: string);

implementation

uses
  SysUtils, IniFiles, uStatusDraw
  {$IFDEF LCLWIN32}
  , uDarkStyleParams, uMetaDarkStyle, uDarkStyleSchemes
  {$ENDIF};

const
  INI_WERTE: array[TDesignWahl] of string = ('auto', 'hell', 'dunkel');

function DesignLesen(const IniName: string): TDesignWahl;
var
  Ini: TIniFile;
  S: string;
  W: TDesignWahl;
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

procedure DesignSpeichern(const IniName: string; W: TDesignWahl);
var
  Ini: TIniFile;
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

procedure DesignAnwenden(const IniName: string);
begin
  {$IFDEF LCLWIN32}
  case DesignLesen(IniName) of
    dwHell  : PreferredAppMode := pamForceLight;
    dwDunkel: PreferredAppMode := pamForceDark;
  else
    PreferredAppMode := pamAllowDark;     // wie Windows
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
