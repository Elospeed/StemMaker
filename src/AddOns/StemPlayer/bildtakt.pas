{ ============================================================================
  bildtakt.pas  -  Bildtakt für den Elospeed StemPlayer

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Zweck:
    Ruft im Hauptfenster einmal pro Bildschirmbild (meist 60 mal pro
    Sekunde) eine Methode auf, genau im Takt des Monitors.

  Warum nicht einfach ein TTimer?
    Ein Timer läuft in seinem eigenen Takt (z.B. alle 15 ms), der Monitor
    in seinem (alle 16,7 ms). Die beiden laufen auseinander: in manchen
    Bildern kommt der Abspielkopf zweimal weiter, in anderen gar nicht.
    Die Lupe bewegt sich dann ungleichmässig (Ruckeln, kleine Stopps).
    Ausserdem kommen Timer-Meldungen unter Windows erst dran, wenn sonst
    nichts zu tun ist, und verspäten sich, wenn viel gezeichnet wird.

  Wie?
    Ein Thread wartet auf den Bildwechsel des Monitors und stellt dann einen
    Aufruf in die Warteschlange des Hauptfensters (QueueAsyncCall). Ist der
    vorige Aufruf noch nicht abgearbeitet, wird kein zweiter dazugestellt.
    Warten auf den Bildwechsel, in dieser Reihenfolge:
      1. D3DKMTWaitForVerticalBlankEvent (gdi32, ab Windows 7): wartet
         direkt auf den Bildwechsel der Grafikkarte.
      2. DwmFlush (dwmapi): wartet, bis Windows das nächste Bild fertig hat.
      3. Sleep(15), falls beides fehlt (z.B. unter Wine).
    Kommt eine Methode auffällig schnell zurück (wartet also gar nicht),
    wird auf die nächste umgeschaltet.

  Versionen:
    1.0  (21.10.2026)  Erste Version (StemPlayer 1.6)
  ============================================================================ }
unit bildtakt;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Forms, dynlibs;

type
  TBildtakt = class(TThread)
  private
    FTick    : TDataEvent;   // Methode im Hauptfenster
    FPending : LongInt;      // 1 = Aufruf steht schon in der Warteschlange
    FMethode : Integer;      // 1 = Bildwechsel, 2 = DwmFlush, 3 = Sleep
    procedure DoTick(Data: PtrInt);
  protected
    procedure Execute; override;
  public
    constructor Create(ATick: TDataEvent);
    { vor dem Freigeben aufrufen: beendet den Thread und wirft noch
      wartende Aufrufe aus der Warteschlange }
    procedure Stoppen;
    property Methode: Integer read FMethode;
  end;

implementation

{$PACKRECORDS C}
type
  TD3DKMTOpenAdapterFromHdc = record
    hDc          : HDC;
    hAdapter     : LongWord;
    AdapterLuid  : Int64;        // LUID: 2 x 32 Bit
    VidPnSourceId: LongWord;
  end;
  TD3DKMTWaitForVBlank = record
    hAdapter     : LongWord;
    hDevice      : LongWord;
    VidPnSourceId: LongWord;
  end;
  TD3DKMTCloseAdapter = record
    hAdapter     : LongWord;
  end;
  TOpenAdapterFunc = function(var P: TD3DKMTOpenAdapterFromHdc): LongInt; stdcall;
  TWaitVBlankFunc  = function(var P: TD3DKMTWaitForVBlank): LongInt; stdcall;
  TCloseAdapterFunc = function(var P: TD3DKMTCloseAdapter): LongInt; stdcall;
  TDwmFlushFunc    = function: HRESULT; stdcall;

constructor TBildtakt.Create(ATick: TDataEvent);
begin
  FTick := ATick;
  FreeOnTerminate := False;
  inherited Create(False);
  Priority := tpHigher;     // pünktlich aufwachen
end;

procedure TBildtakt.DoTick(Data: PtrInt);
begin
  InterlockedExchange(FPending, 0);
  if not Terminated and Assigned(FTick) then FTick(Data);
end;

procedure TBildtakt.Stoppen;
begin
  Terminate;
  WaitFor;
  Application.RemoveAsyncCalls(Self);
end;

procedure TBildtakt.Execute;
var
  Gdi, Dwm: TLibHandle;
  OpenAdapter: TOpenAdapterFunc;
  WaitVBlank : TWaitVBlankFunc;
  CloseAdapter: TCloseAdapterFunc;
  DwmFlush   : TDwmFlushFunc;
  Oa: TD3DKMTOpenAdapterFromHdc;
  Wv: TD3DKMTWaitForVBlank;
  Ca: TD3DKMTCloseAdapter;
  Dc: HDC;
  Ok: Boolean;
  T0, Dauer: QWord;
  Schnell: Integer;   // wie oft hintereinander "zu schnell" zurück
begin
  Gdi := NilHandle;
  Dwm := NilHandle;
  OpenAdapter := nil; WaitVBlank := nil; CloseAdapter := nil; DwmFlush := nil;
  FillChar(Oa, SizeOf(Oa), 0);
  FMethode := 3;

  { 1. Bildwechsel der Grafikkarte (Hauptbildschirm) }
  Gdi := LoadLibrary('gdi32.dll');
  if Gdi <> NilHandle then
  begin
    Pointer(OpenAdapter) := GetProcAddress(Gdi, 'D3DKMTOpenAdapterFromHdc');
    Pointer(WaitVBlank) := GetProcAddress(Gdi, 'D3DKMTWaitForVerticalBlankEvent');
    Pointer(CloseAdapter) := GetProcAddress(Gdi, 'D3DKMTCloseAdapter');
    if Assigned(OpenAdapter) and Assigned(WaitVBlank) then
    begin
      Dc := GetDC(0);
      Oa.hDc := Dc;
      if OpenAdapter(Oa) = 0 then FMethode := 1;
      ReleaseDC(0, Dc);
    end;
  end;
  { 2. DwmFlush als Ersatz }
  Dwm := LoadLibrary('dwmapi.dll');
  if Dwm <> NilHandle then
    Pointer(DwmFlush) := GetProcAddress(Dwm, 'DwmFlush');
  if (FMethode = 3) and Assigned(DwmFlush) then FMethode := 2;

  Wv.hAdapter := Oa.hAdapter;
  Wv.hDevice := 0;
  Wv.VidPnSourceId := Oa.VidPnSourceId;
  Schnell := 0;

  while not Terminated do
  begin
    T0 := GetTickCount64;
    case FMethode of
      1: Ok := WaitVBlank(Wv) = 0;
      2: Ok := DwmFlush() = S_OK;
    else
      Sleep(15);
      Ok := True;
    end;
    Dauer := GetTickCount64 - T0;
    { Wartet die Methode gar nicht (Fehler oder sofort zurück), die nächste
      nehmen. GetTickCount64 hat nur ~16-ms-Schritte, darum zählen wir
      mehrere "0 ms" hintereinander. }
    if (FMethode < 3) and (not Ok or (Dauer = 0)) then
    begin
      Inc(Schnell);
      if not Ok or (Schnell >= 20) then
      begin
        Inc(FMethode);
        if (FMethode = 2) and not Assigned(DwmFlush) then FMethode := 3;
        Schnell := 0;
      end;
    end
    else if Dauer > 0 then
      Schnell := 0;
    if Terminated then Break;
    if InterlockedExchange(FPending, 1) = 0 then
      Application.QueueAsyncCall(@DoTick, 0);
  end;

  if (Oa.hAdapter <> 0) and Assigned(CloseAdapter) then
  begin
    Ca.hAdapter := Oa.hAdapter;
    CloseAdapter(Ca);
  end;
  if Gdi <> NilHandle then FreeLibrary(Gdi);
  if Dwm <> NilHandle then FreeLibrary(Dwm);
end;

end.
