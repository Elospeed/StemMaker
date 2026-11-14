{ ============================================================================
  StemTagger  -  Tags für Traktor-Stem-Dateien
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udunklerrahmen.pas  (Unit uDunklerRahmen)
  Version : wie StemTagger, siehe APP_VER in taggerform.pas
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Dunkle Titelleiste und dunkler Fensterrahmen für Programme, die selbst
  dunkel gezeichnet sind (StemPlayer, StemTagger). Windows zeichnet die
  Titelleiste sonst immer hell, auch wenn das Fenster innen dunkel ist.

  Einmal beim Start DunkleRahmenEinrichten aufrufen. Danach bekommt jedes
  Fenster des Programms, dessen Hintergrund dunkel ist, beim Aktivieren
  eine dunkle Titelleiste. Helle Fenster (z. B. Meldungen) bleiben hell.

  Geht ab Windows 10 1809 (DWM-Attribut 20, vor 20H1 hiess es 19).
  Ältere Windows und Wine: bleibt einfach hell.

  Kopie von src\udunklerrahmen.pas (StemMaker), Änderungen dort machen
  und hierher kopieren.
  ============================================================================ }
unit uDunklerRahmen;

{$mode objfpc}{$H+}

interface

uses
  Forms;

{ Titelleiste dieses Fensters dunkel machen (nur Windows) }
procedure DunklerRahmen(F: TCustomForm);
{ Ab jetzt jedes dunkle Fenster des Programms beim Aktivieren dunkel rahmen }
procedure DunkleRahmenEinrichten;

implementation

uses
  {$IFDEF WINDOWS}Windows, DynLibs,{$ENDIF} Classes, SysUtils, Graphics;

type
  TRahmenWache = class
    procedure AktivGewechselt(Sender: TObject; Form: TCustomForm);
  end;

var
  Wache: TRahmenWache = nil;

{$IFDEF WINDOWS}
type
  TDwmSetWindowAttribute = function(hwnd: HWND; dwAttribute: DWORD;
    pvAttribute: Pointer; cbAttribute: DWORD): HRESULT; stdcall;
var
  DwmLib: TLibHandle = NilHandle;
  DwmSet: TDwmSetWindowAttribute = nil;
  DwmGeladen: Boolean = False;

function DwmFunktion: TDwmSetWindowAttribute;
begin
  if not DwmGeladen then
  begin
    DwmGeladen := True;
    { Wine kennt das Attribut nicht; dort gar nicht erst versuchen }
    if GetProcAddress(GetModuleHandle('ntdll.dll'), 'wine_get_version') = nil then
    begin
      DwmLib := LoadLibrary('dwmapi.dll');
      if DwmLib <> NilHandle then
        Pointer(DwmSet) := GetProcAddress(DwmLib, 'DwmSetWindowAttribute');
    end;
  end;
  Result := DwmSet;
end;
{$ENDIF}

function IstDunkel(C: TColor): Boolean;
var
  RGB: LongInt;
begin
  RGB := ColorToRGB(C);
  Result := (Red(RGB) * 299 + Green(RGB) * 587 + Blue(RGB) * 114) div 1000 < 100;
end;

procedure DunklerRahmen(F: TCustomForm);
{$IFDEF WINDOWS}
const
  DWMWA_USE_IMMERSIVE_DARK_MODE        = 20;   // ab Windows 10 20H1
  DWMWA_USE_IMMERSIVE_DARK_MODE_ALT    = 19;   // Windows 10 1809 bis 1909
var
  Setze: TDwmSetWindowAttribute;
  Ein: LongBool;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if (F = nil) or not F.HandleAllocated then Exit;
  Setze := DwmFunktion;
  if not Assigned(Setze) then Exit;
  Ein := True;
  if Setze(F.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Ein, SizeOf(Ein)) <> S_OK then
    Setze(F.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_ALT, @Ein, SizeOf(Ein));
  {$ENDIF}
end;

procedure TRahmenWache.AktivGewechselt(Sender: TObject; Form: TCustomForm);
begin
  if (Form <> nil) and IstDunkel(Form.Color) then
    DunklerRahmen(Form);
end;

procedure DunkleRahmenEinrichten;
begin
  if Wache <> nil then Exit;
  Wache := TRahmenWache.Create;
  Screen.AddHandlerActiveFormChanged(@Wache.AktivGewechselt);
end;

finalization
  if Wache <> nil then
    Screen.RemoveHandlerActiveFormChanged(@Wache.AktivGewechselt);
  FreeAndNil(Wache);
  {$IFDEF WINDOWS}
  if DwmLib <> NilHandle then FreeLibrary(DwmLib);
  {$ENDIF}
end.
