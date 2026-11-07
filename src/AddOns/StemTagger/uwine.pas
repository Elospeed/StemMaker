{ ============================================================================
  uWine  -  Läuft das Programm unter Wine (Linux-AppImage)?
  ----------------------------------------------------------------------------
  Gemeinsam für StemMaker und die AddOns (StemPlayer, StemTagger);
  im StemTagger eine Kopie von src/uwine.pas aus Elospeed/StemMaker.

  Warum: Lazarus teilt ein Programm unter Windows in ein unsichtbares
  Anwendungsfenster (besitzt den Taskleisten-Knopf) und das Hauptfenster,
  das diesem untergeordnet ist. Unter Wine wird daraus unter Linux ein
  1x1-Fenster plus ein Hauptfenster mit WM_TRANSIENT_FOR auf dieses
  Hilfsfenster. Ubuntu/GNOME hält das Hauptfenster deshalb für ein
  Unterfenster: kein Minimieren-Knopf, Minimieren über die Leiste geht nicht,
  und das Dock zeigt ein Zahnrad statt des Programmsymbols.

  Lösung: Nur unter Wine bekommt das Hauptfenster selbst den Taskleisten-
  Knopf (Application.MainFormOnTaskBar). Dann ist es ein normales Fenster
  ohne Elternfenster. Unter Windows bleibt alles wie bisher.

  Aufruf: WineFensterEinrichten direkt nach Application.Initialize, vor dem
  Anlegen des Hauptfensters.
  ============================================================================ }
unit uWine;

{$mode objfpc}{$H+}

interface

{ True, wenn die Exe unter Wine läuft (ntdll.dll hat dann "wine_get_version") }
function UnterWine: Boolean;

{ Unter Wine: Hauptfenster bekommt selbst den Taskleisten-Knopf }
procedure WineFensterEinrichten;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} Forms;

var
  FGeprueft: Boolean = False;
  FWine: Boolean = False;

function UnterWine: Boolean;
{$IFDEF WINDOWS}
var
  H: HMODULE;
{$ENDIF}
begin
  if not FGeprueft then
  begin
    FGeprueft := True;
    {$IFDEF WINDOWS}
    H := GetModuleHandle('ntdll.dll');
    FWine := (H <> 0) and (GetProcAddress(H, 'wine_get_version') <> nil);
    {$ENDIF}
  end;
  Result := FWine;
end;

procedure WineFensterEinrichten;
begin
  {$IFDEF WINDOWS}
  if UnterWine then
    Application.MainFormOnTaskBar := True;
  {$ENDIF}
end;

end.
