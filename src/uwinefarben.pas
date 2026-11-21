{ ============================================================================
  Unit    : uWineFarben  (Datei uwinefarben.pas)
  Programm: StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  Autor   : Elospeed
  ----------------------------------------------------------------------------
  ZWECK

  Hell oder dunkel unter Linux (Wine, AppImage). metadarkstyle wirkt dort
  nicht. Wine zeichnet Fenster, Knöpfe, Listen und Menüs aber mit den
  Windows-Systemfarben. Diese Unit schreibt beim Start eine helle oder
  dunkle Farbreihe in die Wine-Registry (HKCU\Control Panel\Colors) und
  schaltet für dunkel das helle Wine-Thema aus (ThemeManager, ThemeActive),
  sonst blieben Knöpfe und Balken weiss. Beides liest Wine nur beim Start
  eines Programms. Musste etwas geändert werden, startet StemMaker darum
  einmal neu (uDesign). Die AddOns laufen im selben Wine und sind danach
  ebenfalls hell oder dunkel.

  "Automatisch" folgt dem Linux-Desktop: Das Startskript der AppImage
  (AppRun) setzt ELOSPEED_DESKTOP_DUNKEL=1, wenn der Desktop dunkel ist
  (GNOME/Cinnamon color-scheme oder ein GTK-Thema mit "dark" im Namen).

  Die Titelleiste zeichnet unter Linux der Desktop selbst, sie folgt
  immer dem Desktop-Design.
  ============================================================================ }
unit uWineFarben;

{$mode objfpc}{$H+}

interface

{ Ist der Linux-Desktop dunkel? (Umgebungsvariable aus AppRun) }
function DesktopDunkel: Boolean;

{ Systemfarben und Wine-Thema hell oder dunkel in die Registry schreiben
  und für dieses Programm setzen. Nur unter Wine aufrufen.
  Rückgabe: True, wenn etwas geändert wurde (dann gilt es erst ganz nach
  einem Neustart des Programms). }
function WineFarbenSetzen(Dunkel: Boolean): Boolean;

{ Sind die Systemfarben gerade dunkel? (Fensterhintergrund dunkel)
  Für AddOns, die nach StemMaker starten. }
function SystemFarbenDunkel: Boolean;

implementation

uses
  Windows, SysUtils, Registry;

const
  ANZAHL = 25;
  { Reihenfolge der Farben (COLOR_...) }
  { Namen in HKCU\Control Panel\Colors (gleiche Reihenfolge) }
  REG_NAMEN: array[0..ANZAHL - 1] of string = (
    'Scrollbar', 'Background', 'ActiveTitle',
    'InactiveTitle', 'Menu', 'Window', 'WindowFrame',
    'MenuText', 'WindowText', 'TitleText', 'ActiveBorder',
    'InactiveBorder', 'AppWorkSpace', 'Hilight',
    'HilightText', 'ButtonFace', 'ButtonShadow', 'GrayText',
    'ButtonText', 'InactiveTitleText', 'ButtonHilight',
    'ButtonDkShadow', 'ButtonLight', 'InfoText', 'InfoWindow');
  REG_FARBEN = 'Control Panel\Colors';
  REG_THEMA = 'Software\Microsoft\Windows\CurrentVersion\ThemeManager';
  NUMMERN_LISTE: array[0..ANZAHL - 1] of Integer = (
    COLOR_SCROLLBAR, COLOR_BACKGROUND, COLOR_ACTIVECAPTION,
    COLOR_INACTIVECAPTION, COLOR_MENU, COLOR_WINDOW, COLOR_WINDOWFRAME,
    COLOR_MENUTEXT, COLOR_WINDOWTEXT, COLOR_CAPTIONTEXT, COLOR_ACTIVEBORDER,
    COLOR_INACTIVEBORDER, COLOR_APPWORKSPACE, COLOR_HIGHLIGHT,
    COLOR_HIGHLIGHTTEXT, COLOR_BTNFACE, COLOR_BTNSHADOW, COLOR_GRAYTEXT,
    COLOR_BTNTEXT, COLOR_INACTIVECAPTIONTEXT, COLOR_BTNHIGHLIGHT,
    COLOR_3DDKSHADOW, COLOR_3DLIGHT, COLOR_INFOTEXT, COLOR_INFOBK);
  { Hell: die Standardfarben von Wine (Thema "Light"), als $00BBGGRR }
  FARBEN_HELL: array[0..ANZAHL - 1] of DWORD = (
    $FFFFFF, $956F25, $FA9632,
    $808080, $FFFFFF, $FFFFFF, $9E9E9E,
    $000000, $000000, $000000, $FFFFFF,
    $FFFFFF, $808080, $FA9630,
    $FFFFFF, $F5F5F5, $A6A6A6, $A6A6A6,
    $000000, $C8C8C8, $FFFFFF,
    $6A6A6A, $E3E3E3, $000000, $FFFFFF);
  { Dunkel: ähnlich wie das dunkle Design unter Windows }
  FARBEN_DUNKEL: array[0..ANZAHL - 1] of DWORD = (
    $3A3A3A, $202020, $5A3A1E,
    $2B2B2B, $2B2B2B, $202020, $505050,
    $E8E8E8, $E8E8E8, $FFFFFF, $3A3A3A,
    $2B2B2B, $1A1A1A, $8A5A26,
    $FFFFFF, $2B2B2B, $1A1A1A, $8C8C8C,
    $E8E8E8, $A0A0A0, $4A4A4A,
    $101010, $3A3A3A, $E8E8E8, $2B2B2B);

function DesktopDunkel: Boolean;
begin
  Result := Trim(GetEnvironmentVariable('ELOSPEED_DESKTOP_DUNKEL')) = '1';
end;

{ $00BBGGRR -> 'R G B' wie in der Registry }
function RegText(C: DWORD): string;
begin
  Result := Format('%d %d %d', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF]);
end;

function WineFarbenSetzen(Dunkel: Boolean): Boolean;
var
  Werte: array[0..ANZAHL - 1] of DWORD;
  Nummern: array[0..ANZAHL - 1] of Integer;
  I: Integer;
  Reg: TRegistry;
  Thema: string;
begin
  Result := False;
  for I := 0 to ANZAHL - 1 do
  begin
    if Dunkel then Werte[I] := FARBEN_DUNKEL[I] else Werte[I] := FARBEN_HELL[I];
    Nummern[I] := NUMMERN_LISTE[I];
  end;
  if Dunkel then Thema := '0' else Thema := '1';

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(REG_FARBEN, True) then
    begin
      for I := 0 to ANZAHL - 1 do
        if not Reg.ValueExists(REG_NAMEN[I]) or
           (Reg.ReadString(REG_NAMEN[I]) <> RegText(Werte[I])) then
        begin
          Reg.WriteString(REG_NAMEN[I], RegText(Werte[I]));
          Result := True;
        end;
      { weitere Farben, die es nur in der Registry gibt }
      Reg.WriteString('MenuBar', RegText(Werte[4]));
      Reg.WriteString('MenuHilight', RegText(Werte[13]));
      Reg.WriteString('ButtonAlternateFace', RegText(Werte[15]));
      Reg.WriteString('GradientActiveTitle', RegText(Werte[2]));
      Reg.WriteString('GradientInactiveTitle', RegText(Werte[3]));
      Reg.CloseKey;
    end;
    if Reg.OpenKey(REG_THEMA, True) then
    begin
      if not Reg.ValueExists('ThemeActive') or (Reg.ReadString('ThemeActive') <> Thema) then
      begin
        Reg.WriteString('ThemeActive', Thema);
        Result := True;
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  { für dieses Programm sofort (Thema und gespeicherte Farben gelten erst
    nach dem Neustart) }
  if Result then
    SetSysColors(ANZAHL, Nummern[0], Werte[0]);
end;

function SystemFarbenDunkel: Boolean;
var
  C: DWORD;
begin
  C := GetSysColor(COLOR_WINDOW);
  { Helligkeit grob: (R*3 + G*6 + B) / 10 }
  Result := ((C and $FF) * 3 + ((C shr 8) and $FF) * 6 + ((C shr 16) and $FF)) div 10 < 128;
end;

end.
