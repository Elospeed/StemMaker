{ ============================================================================
  Unit    : uPackDesign  (Datei upackdesign.pas)
  Programm: Elospeed StemPacker  -  fertige Spuren zu Stem-Dateien packen
  Autor   : Elospeed
  Stand   : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    0.3.1 (mit StemMaker 2.4), 14.11.2026: neu (hell oder dunkel wie StemMaker)
  ----------------------------------------------------------------------------
  ZWECK

  Der StemPacker soll aussehen wie StemMaker: hell, dunkel oder wie
  Windows, je nach der Wahl in den StemMaker-Einstellungen.

  GRUNDIDEE

  Liest "Design" aus StemMaker.ini ([Main] Design=auto|hell|dunkel), zuerst
  im StemMaker-Ordner, dann in %APPDATA%\StemMaker. Fehlt die Angabe
  (StemPacker allein), gilt Automatisch = wie Windows.

  Wie in StemMaker (uDesign) färbt die Bibliothek metadarkstyle (Ordner
  ..\..\darkstyle) Fenster, Knöpfe, Listen, Menüs und die Titelleiste um.
  Das geht nur einmal beim Start, vor dem ersten Fenster. Braucht Windows 10
  ab 1809; ältere Windows und Wine bleiben hell.

  BENUTZUNG

    StemPacker.lpr   PackDesignAnwenden ganz am Anfang, vor
                     Application.Initialize. Mehr ist nicht nötig; die
                     selbst gezeichnete Statusspalte fragt DunklesDesign
                     in uStatusDraw ab.
  ============================================================================ }
unit uPackDesign;

{$mode objfpc}{$H+}

interface

procedure PackDesignAnwenden;

implementation

uses
  SysUtils, IniFiles, uLang, uStatusDraw
  {$IFDEF LCLWIN32}
  , uDarkStyleParams, uMetaDarkStyle, uDarkStyleSchemes
  {$ENDIF};

{ ----------------------------------------------------------------------------
  Wahl aus StemMaker.ini lesen
  ---------------------------------------------------------------------------- }

{ DesignWert
  Sucht die Design-Wahl von StemMaker.
  Rückgabe : 'auto', 'hell' oder 'dunkel' (klein geschrieben);
             leer = keine StemMaker.ini mit Design gefunden
  Ablauf   : 1. StemMaker.ini im Programmordner (portable Installation,
                der StemPacker liegt dann in AddOns\ daneben; AppBaseDir
                zeigt auf den StemMaker-Ordner)
             2. sonst %APPDATA%\StemMaker\StemMaker.ini (normale Installation)
             3. der erste gefundene Wert gewinnt }
function DesignWert: string;
var
  Ini: TIniFile;                                           // gerade gelesene INI
  IniName: string;                                         // voller Pfad der INI
  i: Integer;                                              // 1 = Programmordner, 2 = APPDATA
begin
  Result := '';
  for i := 1 to 2 do
  begin
    if i = 1 then
      IniName := AppBaseDir + 'StemMaker.ini'
    else
      IniName := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
        'StemMaker' + PathDelim + 'StemMaker.ini';
    if not FileExists(IniName) then Continue;
    try
      Ini := TIniFile.Create(IniName);
      try
        Result := LowerCase(Trim(Ini.ReadString('Main', 'Design', '')));
      finally
        Ini.Free;
      end;
    except
      Result := '';
    end;
    if Result <> '' then Break;
  end;
end;

{ ----------------------------------------------------------------------------
  Beim Start anwenden
  ---------------------------------------------------------------------------- }

{ PackDesignAnwenden
  Wie uDesign.DesignAnwenden in StemMaker: metadarkstyle nach der Wahl
  einstellen und DunklesDesign für uStatusDraw setzen. Nur unter dem
  Windows-Widgetset; muss vor dem ersten Fenster laufen.
  Ablauf   : 1. Wahl lesen (leer oder 'auto' = wie Windows)
             2. PreferredAppMode setzen und ApplyMetaDarkStyle aufrufen
             3. IsDarkModeEnabled in DunklesDesign übernehmen }
procedure PackDesignAnwenden;
{$IFDEF LCLWIN32}
var
  W: string;                                               // gelesene Wahl
{$ENDIF}
begin
  {$IFDEF LCLWIN32}
  W := DesignWert;
  if W = 'hell' then
    PreferredAppMode := pamForceLight
  else if W = 'dunkel' then
    PreferredAppMode := pamForceDark
  else
    PreferredAppMode := pamAllowDark;                      // wie Windows
  try
    ApplyMetaDarkStyle(DefaultDark);
  except
    { sollte nie passieren - dann eben hell }
  end;
  DunklesDesign := IsDarkModeEnabled;
  {$ENDIF}
end;

end.
