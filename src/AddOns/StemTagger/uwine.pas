{ ============================================================================
  Unit    : uWine  (Datei uwine.pas)
  Programm: StemMaker und AddOns  -  Läuft das Programm unter Wine?
  Autor   : Elospeed
  Stand   : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    2.4, 14.11.2026: Kopie auch im StemPacker (für die Hilfe unter Wine)
    2.2.1, 07.11.2026: neu (Linux-AppImage: richtiges Fenster in GNOME)
  ----------------------------------------------------------------------------
  ZWECK

  Erkennen, ob die Exe unter Wine läuft (Linux-AppImage), und dort das
  Hauptfenster zu einem normalen Linux-Fenster machen.

  Kopie von src/uwine.pas aus Elospeed/StemMaker für den StemTagger;
  Änderungen bitte dort machen und hierher kopieren.

  GRUNDIDEE

  Wine erkennt man daran, dass seine ntdll.dll die Funktion
  "wine_get_version" hat; das echte Windows hat sie nicht.

  Lazarus teilt ein Programm unter Windows in ein unsichtbares
  Anwendungsfenster (besitzt den Taskleisten-Knopf) und das Hauptfenster,
  das diesem untergeordnet ist. Unter Wine wird daraus unter Linux ein
  1x1-Fenster plus ein Hauptfenster mit WM_TRANSIENT_FOR auf dieses
  Hilfsfenster. Ubuntu/GNOME hält das Hauptfenster deshalb für ein
  Unterfenster: kein Minimieren-Knopf, Minimieren über die Leiste geht nicht,
  und das Dock zeigt ein Zahnrad statt des Programmsymbols.
  Lösung: Nur unter Wine bekommt das Hauptfenster selbst den Taskleisten-
  Knopf (Application.MainFormOnTaskBar). Dann ist es ein normales Fenster
  ohne Elternfenster. Unter Windows bleibt alles wie bisher.

  BENUTZUNG

    WineFensterEinrichten   direkt nach Application.Initialize, vor dem
                            Anlegen des Hauptfensters.
    UnterWine               überall, wo sich Wine anders verhält (z. B.
                            uHilfe öffnet dann die Online-Hilfe).
  ============================================================================ }
unit uWine;

{$mode objfpc}{$H+}

interface

function UnterWine: Boolean;
procedure WineFensterEinrichten;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} Forms;

var
  FGeprueft: Boolean = False;                              // schon einmal geprüft?
  FWine: Boolean = False;                                  // Ergebnis der Prüfung

{ UnterWine
  Rückgabe : True, wenn die Exe unter Wine läuft
  Ablauf   : 1. beim ersten Aufruf ntdll.dll nach "wine_get_version"
                fragen und das Ergebnis merken
             2. danach nur noch das gemerkte Ergebnis liefern }
function UnterWine: Boolean;
{$IFDEF WINDOWS}
var
  H: HMODULE;                                              // ntdll.dll
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

{ WineFensterEinrichten
  Unter Wine bekommt das Hauptfenster selbst den Taskleisten-Knopf, damit
  Linux es als normales Fenster behandelt. Unter Windows: nichts.
  Ablauf   : 1. Wine erkennen
             2. Application.MainFormOnTaskBar := True (vor dem Hauptfenster) }
procedure WineFensterEinrichten;
begin
  {$IFDEF WINDOWS}
  if UnterWine then
    Application.MainFormOnTaskBar := True;
  {$ENDIF}
end;

end.
