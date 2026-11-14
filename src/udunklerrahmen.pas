{ ============================================================================
  Unit    : uDunklerRahmen  (Datei udunklerrahmen.pas)
  Programm: StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  Autor   : Elospeed
  Stand   : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    2.4, 14.11.2026: neu (dunkle Titelleiste für StemPlayer und StemTagger)
  ----------------------------------------------------------------------------
  ZWECK

  Dunkle Titelleiste und dunkler Fensterrahmen für Programme, die selbst
  dunkel gezeichnet sind (StemPlayer, StemTagger). Windows zeichnet die
  Titelleiste sonst immer hell, auch wenn das Fenster innen dunkel ist.

  GRUNDIDEE

  Windows kennt dafür das DWM-Attribut "Immersive Dark Mode" (Nummer 20,
  vor Windows 10 20H1 Nummer 19). Windows 11 kann die Titelleiste zudem
  genau in einer Farbe einfärben (Attribut 35). Die Funktion
  DwmSetWindowAttribute wird zur Laufzeit aus dwmapi.dll geholt, damit
  das Programm auch auf Windows ohne diese Funktion startet.
  Ob ein Fenster dunkel ist, entscheidet die Helligkeit seiner Farbe
  (Formel unten bei IstDunkel).

  Geht ab Windows 10 1809. Ältere Windows und Wine: bleibt einfach hell.

  BENUTZUNG

    DunklerRahmen(Self)       am Ende des Konstruktors eines dunklen
                              Fensters; dann ist die Titelleiste schon beim
                              ersten Zeigen dunkel (sonst blitzt sie weiss).
    DunkleRahmenEinrichten    einmal beim Start; danach bekommt jedes
                              dunkle Fenster des Programms beim Aktivieren
                              die dunkle Titelleiste (auch Dialoge).

  Gemeinsame Unit: StemPlayer nutzt sie aus src\, StemTagger hat eine
  Kopie in src\AddOns\StemTagger (eigenes Repository).
  ============================================================================ }
unit uDunklerRahmen;

{$mode objfpc}{$H+}

interface

uses
  Forms;

procedure DunklerRahmen(F: TCustomForm);
procedure DunkleRahmenEinrichten;

implementation

uses
  {$IFDEF WINDOWS}Windows, DynLibs,{$ENDIF} Classes, SysUtils, Graphics;

{ ----------------------------------------------------------------------------
  Typen und Variablen
  ---------------------------------------------------------------------------- }

type
  { Nimmt die Meldung "anderes Fenster ist jetzt aktiv" entgegen. Eine
    Klasse ist nötig, weil Screen nur Methoden als Handler annimmt. }
  TRahmenWache = class
    procedure AktivGewechselt(Sender: TObject; Form: TCustomForm);
  end;

var
  Wache: TRahmenWache = nil;                               // einzige Wache, nil = nicht eingerichtet

{$IFDEF WINDOWS}
type
  { Signatur von DwmSetWindowAttribute aus dwmapi.dll }
  TDwmSetWindowAttribute = function(hwnd: HWND; dwAttribute: DWORD;
    pvAttribute: Pointer; cbAttribute: DWORD): HRESULT; stdcall;
var
  DwmLib: TLibHandle = NilHandle;                          // geladene dwmapi.dll
  DwmSet: TDwmSetWindowAttribute = nil;                    // Funktion, nil = gibt es nicht
  DwmGeladen: Boolean = False;                             // schon einmal versucht?

{ ----------------------------------------------------------------------------
  Windows-Funktion holen
  ---------------------------------------------------------------------------- }

{ DwmFunktion
  Holt DwmSetWindowAttribute aus dwmapi.dll, nur beim ersten Aufruf.
  Rückgabe : die Funktion, oder nil unter Wine bzw. wenn Windows sie nicht
             hat; dann bleibt die Titelleiste wie sie ist
  Ablauf   : 1. Wine erkennen (ntdll.dll hat dort wine_get_version) und
                dann nichts laden, Wine kennt das Attribut nicht
             2. dwmapi.dll laden und die Funktion suchen
             3. Ergebnis merken, beim nächsten Mal sofort zurückgeben }
function DwmFunktion: TDwmSetWindowAttribute;
begin
  if not DwmGeladen then
  begin
    DwmGeladen := True;
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

{ ----------------------------------------------------------------------------
  Helligkeit und Titelleiste
  ---------------------------------------------------------------------------- }

{ IstDunkel
  Entscheidet, ob eine Fensterfarbe dunkel ist.
  Parameter: C = Fensterfarbe (auch Systemfarben wie clBtnFace)
  Rückgabe : True, wenn die wahrgenommene Helligkeit unter 100 von 255 liegt
  Formel   : Helligkeit = (299·Rot + 587·Grün + 114·Blau) / 1000
             (Gewichtung nach ITU-R BT.601, das Auge sieht Grün am hellsten)
  Beispiel : StemTagger dunkel $001A1817 = Rot 23, Grün 24, Blau 26
             -> (6877 + 14088 + 2964) / 1000 = 23 -> dunkel
             Windows-Grau $F0F0F0 -> 240 -> hell }
function IstDunkel(C: TColor): Boolean;
var
  RGB: LongInt;                                            // C als echte RGB-Farbe
begin
  RGB := ColorToRGB(C);
  Result := (Red(RGB) * 299 + Green(RGB) * 587 + Blue(RGB) * 114) div 1000 < 100;
end;

{ DunklerRahmen
  Schaltet die Titelleiste eines Fensters dunkel (Windows 10 ab 1809) und
  färbt sie unter Windows 11 genau in der Fensterfarbe ein.
  Parameter: F = das Fenster; nil wird ignoriert
  Ablauf   : 1. Windows-Funktion holen, fehlt sie: nichts tun
             2. Handle erzeugen (vor dem ersten Zeigen gibt es noch keins)
             3. Attribut 20 setzen, bei älterem Windows 10 Attribut 19
             4. Windows 11: Titelleistenfarbe = Fensterfarbe (Attribut 35);
                Windows 10 kennt das nicht und bleibt beim Standard-Dunkelgrau }
procedure DunklerRahmen(F: TCustomForm);
{$IFDEF WINDOWS}
const
  DWMWA_USE_IMMERSIVE_DARK_MODE     = 20;                  // ab Windows 10 20H1
  DWMWA_USE_IMMERSIVE_DARK_MODE_ALT = 19;                  // Windows 10 1809 bis 1909
  DWMWA_CAPTION_COLOR               = 35;                  // nur Windows 11
var
  Setze: TDwmSetWindowAttribute;                           // DwmSetWindowAttribute
  Ein: LongBool;                                           // Wert für "dunkel an"
  Farbe: DWORD;                                            // Titelleistenfarbe als COLORREF
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if F = nil then Exit;
  Setze := DwmFunktion;
  if not Assigned(Setze) then Exit;
  F.HandleNeeded;
  Ein := True;
  if Setze(F.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Ein, SizeOf(Ein)) <> S_OK then
    Setze(F.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_ALT, @Ein, SizeOf(Ein));
  Farbe := DWORD(ColorToRGB(F.Color));
  Setze(F.Handle, DWMWA_CAPTION_COLOR, @Farbe, SizeOf(Farbe));
  {$ENDIF}
end;

{ ----------------------------------------------------------------------------
  Automatisch für alle Fenster
  ---------------------------------------------------------------------------- }

{ TRahmenWache.AktivGewechselt
  Wird von Screen gerufen, wenn ein anderes Fenster aktiv wird.
  Parameter: Sender = Screen (unbenutzt)
             Form   = das neu aktive Fenster, kann nil sein
  Ablauf   : 1. Fenster mit dunklem Hintergrund bekommen die dunkle
                Titelleiste, helle Fenster (z. B. Meldungen) bleiben hell }
procedure TRahmenWache.AktivGewechselt(Sender: TObject; Form: TCustomForm);
begin
  if (Form <> nil) and IstDunkel(Form.Color) then
    DunklerRahmen(Form);
end;

{ DunkleRahmenEinrichten
  Meldet die Wache einmal beim Start an; danach geht alles automatisch.
  Ablauf   : 1. schon eingerichtet: nichts tun
             2. Wache erzeugen und bei Screen anmelden }
procedure DunkleRahmenEinrichten;
begin
  if Wache <> nil then Exit;
  Wache := TRahmenWache.Create;
  Screen.AddHandlerActiveFormChanged(@Wache.AktivGewechselt);
end;

{ Beim Programmende: Wache abmelden und freigeben, dwmapi.dll entladen }
finalization
  if Wache <> nil then
    Screen.RemoveHandlerActiveFormChanged(@Wache.AktivGewechselt);
  FreeAndNil(Wache);
  {$IFDEF WINDOWS}
  if DwmLib <> NilHandle then FreeLibrary(DwmLib);
  {$ENDIF}
end.
