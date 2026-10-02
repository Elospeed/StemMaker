{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : upower.pas  (Unit uPower)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Eine Konvertierung dauert lange - auf alten Rechnern über eine Stunde.
  Wenn Windows in dieser Zeit in den Ruhezustand (Standby) geht, steht
  alles still. Und im "Energiesparmodus" läuft die CPU gebremst.
  Diese Unit kümmert sich darum, und zwar so, dass am Ende ALLES wieder
  genau so ist wie vorher:

  1. SCHLAFSPERRE
     Wir sagen Windows "ich arbeite gerade, bitte nicht schlafen gehen"
     (SetThreadExecutionState - machen Mediaplayer und Brennprogramme
     genauso). Es wird dabei KEINE Einstellung verändert. Der Bildschirm
     darf trotzdem ausgehen. Die Sperre verschwindet von selbst, sobald
     wir sie aufheben oder das Programm endet - auch bei einem Absturz.

  2. ENERGIESPARPLAN
     Nur wenn der Plan "Energiesparmodus" aktiv ist, schalten wir für die
     Dauer der Konvertierung auf "Höchstleistung" (gibt es den nicht, auf
     "Ausbalanciert"). "Ausbalanciert" lassen wir in Ruhe - dort taktet
     die CPU unter Last ohnehin hoch.
     Windows 11 hat zusätzlich den "Energiemodus" (Beste Energieeffizienz /
     Ausbalanciert / Beste Leistung). Steht der auf "Beste
     Energieeffizienz", stellen wir ihn vorübergehend auf "Ausbalanciert".

     ABSTURZSICHER: Bevor wir etwas umstellen, schreiben wir den alten
     Wert in StemMaker.ini ([Power] RestoreScheme / RestoreOverlay).
     Danach stellen wir zurück und löschen den Eintrag. Stürzt StemMaker
     ab oder fällt der Strom aus, steht der Eintrag noch da - dann stellt
     PowerRestoreAfterCrash beim nächsten Start den alten Plan wieder her.

  3. AKKU
     Ob ein Laptop am Strom hängt, kann ein Programm nicht ändern. Wir
     melden es nur (Hinweis im Protokoll und im Log).

  4. RUHEZUSTAND ERKENNEN
     Windows hat zwei Uhren: eine, die im Standby weiterläuft
     (GetTickCount64), und eine, die im Standby stehen bleibt
     (QueryUnbiasedInterruptTime). Ist die Differenz am Ende gross, war
     der PC zwischendurch im Standby - das schreiben wir ins Log, damit
     man die Zeiten richtig einordnen kann.

  Alle Windows-Funktionen werden "dynamisch" geladen (LoadLibrary /
  GetProcAddress). Fehlt eine (alte Windows-Version, Wine), wird der
  jeweilige Punkt einfach übersprungen - es gibt keinen Fehler.
  ============================================================================ }
unit uPower;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, IniFiles {$IFDEF WINDOWS}, Windows{$ENDIF}, uLog;

type
  { Was am Anfang eines Laufs gemacht wurde - wird am Ende gebraucht,
    um alles zurückzustellen und die Zusammenfassung zu schreiben }
  TPowerRun = record
    Active      : Boolean;   // PowerBeginRun wurde aufgerufen
    KeepAwake   : Boolean;   // Schlafsperre gesetzt
    SchemeSet   : Boolean;   // Energiesparplan wurde umgestellt
    OldScheme   : TGUID;
    OldName     : string;    // Name des ursprünglichen Plans
    NewName     : string;    // Name des vorübergehenden Plans
    OverlaySet  : Boolean;   // Windows-11-Energiemodus wurde umgestellt
    OldOverlay  : TGUID;
    StartTick   : QWord;     // Uhr MIT Standby-Zeit (ms)
    StartUnbias : QWord;     // Uhr OHNE Standby-Zeit (100-ns-Schritte)
    HaveUnbias  : Boolean;
  end;

{ "Netzbetrieb" / "Akku (73 %)" / "unbekannt" }
function PowerSourceText: string;
{ True, wenn sicher auf Akku gelaufen wird }
function PowerOnBattery: Boolean;
{ Name des aktiven Energiesparplans, z.B. "Ausbalanciert" }
function PowerSchemeText: string;
{ eine Zeile für das Log, z.B. "Netzbetrieb, Plan Ausbalanciert" }
function PowerInfoText: string;

{ Beim Programmstart: hat ein früherer Lauf etwas umgestellt und konnte es
  nicht mehr zurückstellen (Absturz)? Dann jetzt zurückstellen. }
procedure PowerRestoreAfterCrash(const IniName: string);

{ Vor der Konvertierung: Schlafsperre und ggf. Plan umstellen.
  KeepAwake=False -> es wird nichts verändert, nur gemessen. }
function PowerBeginRun(KeepAwake: Boolean; const IniName: string): TPowerRun;
{ Nach der Konvertierung: alles zurückstellen. Mehrfacher Aufruf schadet nicht. }
procedure PowerEndRun(var R: TPowerRun; const IniName: string);
{ Wie lange war der PC während des Laufs im Standby? (ms, 0 = gar nicht) }
function PowerSleptMS(const R: TPowerRun): QWord;
{ Zeile für die Zusammenfassung }
function PowerSummaryText(const R: TPowerRun): string;

implementation

uses
  uLang;

{$IFDEF WINDOWS}
const
  { Werte für SetThreadExecutionState }
  ES_SYSTEM_REQUIRED = $00000001;  // System nicht schlafen legen
  ES_CONTINUOUS      = $80000000;  // gilt, bis wir es wieder aufheben

  { feste Kennungen (GUIDs) der Windows-Standardpläne }
  SCHEME_POWERSAVER : TGUID = '{A1841308-3541-4FAB-BC81-F71556F20B4A}';
  SCHEME_BALANCED   : TGUID = '{381B4222-F694-41F0-9685-FF5BB260DF2E}';
  SCHEME_HIGHPERF   : TGUID = '{8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C}';
  SCHEME_ULTIMATE   : TGUID = '{E9A42B02-D5DF-448D-AA00-03F14749EB61}';

  { Windows-11-Energiemodus ("Overlay") }
  OVERLAY_BALANCED  : TGUID = '{00000000-0000-0000-0000-000000000000}';
  OVERLAY_EFFICIENT : TGUID = '{961CC777-2547-4F9D-8174-7D86181B8A7A}';
  OVERLAY_BATTERY   : TGUID = '{3AF9B8D9-7C97-431D-AD78-34A8BFEA439F}';
  OVERLAY_BESTPERF  : TGUID = '{DED574B5-45A0-4F42-8737-46345C09C238}';

type
  { Aufbau wie in der Windows-Dokumentation (SYSTEM_POWER_STATUS) }
  TSysPowerStatus = record
    ACLineStatus       : Byte;   // 0 = Akku, 1 = Netz, 255 = unbekannt
    BatteryFlag        : Byte;   // 128 = kein Akku vorhanden
    BatteryLifePercent : Byte;   // 0..100, 255 = unbekannt
    SystemStatusFlag   : Byte;
    BatteryLifeTime    : DWORD;
    BatteryFullLifeTime: DWORD;
  end;
  PGUID = ^TGUID;

  TSetThreadExecutionState   = function(esFlags: DWORD): DWORD; stdcall;
  TGetSystemPowerStatus      = function(var S: TSysPowerStatus): BOOL; stdcall;
  TQueryUnbiasedInterruptTime= function(var T: QWord): BOOL; stdcall;
  TPowerGetActiveScheme      = function(Root: HKEY; var Guid: PGUID): DWORD; stdcall;
  TPowerSetActiveScheme      = function(Root: HKEY; Guid: PGUID): DWORD; stdcall;
  TPowerReadFriendlyName     = function(Root: HKEY; Scheme, SubGroup, Setting: PGUID;
                                 Buffer: PByte; var Size: DWORD): DWORD; stdcall;
  TPowerGetOverlay           = function(var Guid: TGUID): DWORD; stdcall;
  TPowerSetOverlay           = function(constref Guid: TGUID): DWORD; stdcall;  // x64: Struktur per Adresse

var
  { Zeiger auf die Windows-Funktionen; nil = gibt es auf diesem System nicht }
  pSetThreadExecutionState   : TSetThreadExecutionState = nil;
  pGetSystemPowerStatus      : TGetSystemPowerStatus = nil;
  pQueryUnbiasedInterruptTime: TQueryUnbiasedInterruptTime = nil;
  pPowerGetActiveScheme      : TPowerGetActiveScheme = nil;
  pPowerSetActiveScheme      : TPowerSetActiveScheme = nil;
  pPowerReadFriendlyName     : TPowerReadFriendlyName = nil;
  pPowerGetOverlay           : TPowerGetOverlay = nil;
  pPowerSetOverlay           : TPowerSetOverlay = nil;
  GLoaded: Boolean = False;

{ Funktionen einmalig aus kernel32.dll und powrprof.dll holen }
procedure LoadApis;
var
  K, P: HMODULE;
begin
  if GLoaded then Exit;
  GLoaded := True;
  K := GetModuleHandle('kernel32.dll');
  if K <> 0 then
  begin
    Pointer(pSetThreadExecutionState) := GetProcAddress(K, 'SetThreadExecutionState');
    Pointer(pGetSystemPowerStatus) := GetProcAddress(K, 'GetSystemPowerStatus');
    Pointer(pQueryUnbiasedInterruptTime) := GetProcAddress(K, 'QueryUnbiasedInterruptTime');
  end;
  P := LoadLibrary('powrprof.dll');
  if P <> 0 then
  begin
    Pointer(pPowerGetActiveScheme) := GetProcAddress(P, 'PowerGetActiveScheme');
    Pointer(pPowerSetActiveScheme) := GetProcAddress(P, 'PowerSetActiveScheme');
    Pointer(pPowerReadFriendlyName) := GetProcAddress(P, 'PowerReadFriendlyName');
    { die beiden Overlay-Funktionen gibt es erst ab Windows 10 1709 }
    Pointer(pPowerGetOverlay) := GetProcAddress(P, 'PowerGetEffectiveOverlayScheme');
    Pointer(pPowerSetOverlay) := GetProcAddress(P, 'PowerSetActiveOverlayScheme');
  end;
end;

{ aktiven Plan lesen; False wenn nicht möglich }
function GetActiveScheme(out G: TGUID): Boolean;
var
  P: PGUID;
begin
  Result := False;
  LoadApis;
  if not Assigned(pPowerGetActiveScheme) then Exit;
  P := nil;
  if (pPowerGetActiveScheme(0, P) = ERROR_SUCCESS) and (P <> nil) then
  begin
    G := P^;
    LocalFree(HLOCAL(P));       // Windows hat den Speicher für uns angelegt
    Result := True;
  end;
end;

function SetActiveScheme(const G: TGUID): Boolean;
var
  Tmp: TGUID;
begin
  LoadApis;
  Tmp := G;
  Result := Assigned(pPowerSetActiveScheme) and
    (pPowerSetActiveScheme(0, @Tmp) = ERROR_SUCCESS);
end;

function GetOverlay(out G: TGUID): Boolean;
begin
  LoadApis;
  Result := Assigned(pPowerGetOverlay) and (pPowerGetOverlay(G) = ERROR_SUCCESS);
end;

function SetOverlay(const G: TGUID): Boolean;
begin
  LoadApis;
  Result := Assigned(pPowerSetOverlay) and (pPowerSetOverlay(G) = ERROR_SUCCESS);
end;

{ Name eines Plans: zuerst so, wie Windows ihn anzeigt (in der Sprache
  des Benutzers), sonst unsere eigenen Namen für die Standardpläne }
function SchemeName(const G: TGUID): string;
var
  Buf: array[0..511] of Byte;
  Size: DWORD;
  Tmp: TGUID;
begin
  Result := '';
  LoadApis;
  if Assigned(pPowerReadFriendlyName) then
  begin
    Tmp := G;
    Size := SizeOf(Buf) - 2;
    FillChar(Buf, SizeOf(Buf), 0);
    if pPowerReadFriendlyName(0, @Tmp, nil, nil, @Buf[0], Size) = ERROR_SUCCESS then
      Result := Trim(UTF8Encode(WideString(PWideChar(@Buf[0]))));
  end;
  if Result <> '' then Exit;
  if IsEqualGUID(G, SCHEME_POWERSAVER) then Result := _('Energiesparmodus')
  else if IsEqualGUID(G, SCHEME_BALANCED) then Result := _('Ausbalanciert')
  else if IsEqualGUID(G, SCHEME_HIGHPERF) then Result := _('Höchstleistung')
  else if IsEqualGUID(G, SCHEME_ULTIMATE) then Result := _('Ultimative Leistung')
  else Result := Format(_('eigener Plan %s'), [GUIDToString(G)]);
end;

function OverlayName(const G: TGUID): string;
begin
  if IsEqualGUID(G, OVERLAY_EFFICIENT) then Result := _('Beste Energieeffizienz')
  else if IsEqualGUID(G, OVERLAY_BATTERY) then Result := _('Bessere Akkuleistung')
  else if IsEqualGUID(G, OVERLAY_BESTPERF) then Result := _('Beste Leistung')
  else if IsEqualGUID(G, OVERLAY_BALANCED) then Result := _('Ausbalanciert')
  else Result := GUIDToString(G);
end;

{ ist der Windows-11-Energiemodus auf "sparen" gestellt? }
function OverlayIsSaving(const G: TGUID): Boolean;
begin
  Result := IsEqualGUID(G, OVERLAY_EFFICIENT) or IsEqualGUID(G, OVERLAY_BATTERY);
end;

function UnbiasedNow(out T: QWord): Boolean;
begin
  LoadApis;
  T := 0;
  Result := Assigned(pQueryUnbiasedInterruptTime) and pQueryUnbiasedInterruptTime(T);
end;
{$ENDIF}

{ ---------------------------------------------------------------------------
  Abfragen (verändern nichts)
  --------------------------------------------------------------------------- }
function PowerOnBattery: Boolean;
{$IFDEF WINDOWS}
var
  S: TSysPowerStatus;
{$ENDIF}
begin
  Result := False;
  {$IFDEF WINDOWS}
  LoadApis;
  FillChar(S, SizeOf(S), 0);
  if Assigned(pGetSystemPowerStatus) and pGetSystemPowerStatus(S) then
    Result := (S.ACLineStatus = 0) and (S.BatteryFlag and 128 = 0);
  {$ENDIF}
end;

function PowerSourceText: string;
{$IFDEF WINDOWS}
var
  S: TSysPowerStatus;
{$ENDIF}
begin
  Result := _('unbekannt');
  {$IFDEF WINDOWS}
  LoadApis;
  FillChar(S, SizeOf(S), 0);
  if not (Assigned(pGetSystemPowerStatus) and pGetSystemPowerStatus(S)) then Exit;
  case S.ACLineStatus of
    1: Result := _('Netzbetrieb');
    0: if S.BatteryLifePercent <= 100 then
         Result := Format(_('Akku (%d %%)'), [S.BatteryLifePercent])
       else
         Result := _('Akku');
  end;
  {$ENDIF}
end;

function PowerSchemeText: string;
{$IFDEF WINDOWS}
var
  G, O: TGUID;
{$ENDIF}
begin
  Result := _('unbekannt');
  {$IFDEF WINDOWS}
  if GetActiveScheme(G) then
    Result := SchemeName(G);
  { Windows 11: den Energiemodus nur nennen, wenn er nicht "Ausbalanciert" ist }
  if GetOverlay(O) and not IsEqualGUID(O, OVERLAY_BALANCED) then
    Result := Result + Format(_(', Energiemodus %s'), [OverlayName(O)]);
  {$ENDIF}
end;

function PowerInfoText: string;
begin
  Result := PowerSourceText + ', Plan ' + PowerSchemeText;
end;

{ ---------------------------------------------------------------------------
  Nach Absturz zurückstellen
  --------------------------------------------------------------------------- }
procedure PowerRestoreAfterCrash(const IniName: string);
{$IFDEF WINDOWS}
var
  Ini: TIniFile;
  S: string;
  G: TGUID;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  try
    Ini := TIniFile.Create(IniName);
    try
      S := Ini.ReadString('Power', 'RestoreScheme', '');
      if S <> '' then
      begin
        G := StringToGUID(S);
        if SetActiveScheme(G) then
          LogLine('Energie: Der letzte Lauf konnte den Energiesparplan nicht ' +
            'zurückstellen - jetzt wieder auf "' + SchemeName(G) + '" gestellt.')
        else
          LogLine('Energie: Konnte den alten Energiesparplan ' + S +
            ' nicht wiederherstellen.');
        Ini.DeleteKey('Power', 'RestoreScheme');
      end;
      S := Ini.ReadString('Power', 'RestoreOverlay', '');
      if S <> '' then
      begin
        G := StringToGUID(S);
        if SetOverlay(G) then
          LogLine('Energie: Windows-Energiemodus wieder auf "' + OverlayName(G) +
            '" gestellt (letzter Lauf wurde unterbrochen).');
        Ini.DeleteKey('Power', 'RestoreOverlay');
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      LogLine('Energie: Wiederherstellen fehlgeschlagen: ' + E.Message);
  end;
  {$ENDIF}
end;

{ ---------------------------------------------------------------------------
  Lauf beginnen / beenden
  --------------------------------------------------------------------------- }
function PowerBeginRun(KeepAwake: Boolean; const IniName: string): TPowerRun;
{$IFDEF WINDOWS}
var
  Ini: TIniFile;
  G, O: TGUID;
{$ENDIF}
begin
  Result := Default(TPowerRun);      // alles auf 0 / leer
  Result.Active := True;
  Result.StartTick := GetTickCount64;
  {$IFDEF WINDOWS}
  Result.HaveUnbias := UnbiasedNow(Result.StartUnbias);
  if not KeepAwake then
  begin
    LogLine('Energie: "PC wach halten" ist aus - Windows darf in den Ruhezustand gehen.');
    Exit;
  end;

  { 1. Schlafsperre }
  if Assigned(pSetThreadExecutionState) and
     (pSetThreadExecutionState(ES_CONTINUOUS or ES_SYSTEM_REQUIRED) <> 0) then
  begin
    Result.KeepAwake := True;
    LogLine('Energie: Schlafsperre aktiv - der PC geht während der Konvertierung ' +
      'nicht in den Ruhezustand (Bildschirm darf ausgehen).');
  end
  else
    LogLine('Energie: Schlafsperre konnte nicht gesetzt werden.');

  try
    Ini := TIniFile.Create(IniName);
    try
      { 2. Energiesparplan - nur bei "Energiesparmodus" umstellen }
      if GetActiveScheme(G) and IsEqualGUID(G, SCHEME_POWERSAVER) then
      begin
        Result.OldScheme := G;
        Result.OldName := SchemeName(G);
        { ZUERST den alten Wert sichern, DANN umstellen (absturzsicher) }
        Ini.WriteString('Power', 'RestoreScheme', GUIDToString(G));
        if SetActiveScheme(SCHEME_HIGHPERF) then
          Result.NewName := SchemeName(SCHEME_HIGHPERF)
        else if SetActiveScheme(SCHEME_BALANCED) then
          Result.NewName := SchemeName(SCHEME_BALANCED);
        if Result.NewName <> '' then
        begin
          Result.SchemeSet := True;
          LogLine('Energie: Plan "' + Result.OldName + '" -> vorübergehend "' +
            Result.NewName + '" (wird danach zurückgestellt)');
        end
        else
        begin
          Ini.DeleteKey('Power', 'RestoreScheme');
          LogLine('Energie: Plan "' + Result.OldName + '" konnte nicht ' +
            'umgestellt werden - die Konvertierung läuft gebremst.');
        end;
      end;

      { 3. Windows-11-Energiemodus - nur bei "Energieeffizienz"/"Akku" }
      if GetOverlay(O) and OverlayIsSaving(O) then
      begin
        Result.OldOverlay := O;
        Ini.WriteString('Power', 'RestoreOverlay', GUIDToString(O));
        if SetOverlay(OVERLAY_BALANCED) then
        begin
          Result.OverlaySet := True;
          LogLine('Energie: Windows-Energiemodus "' + OverlayName(O) +
            '" -> vorübergehend "Ausbalanciert"');
        end
        else
          Ini.DeleteKey('Power', 'RestoreOverlay');
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      LogLine('Energie: Umstellen fehlgeschlagen: ' + E.Message);
  end;
  {$ENDIF}
end;

procedure PowerEndRun(var R: TPowerRun; const IniName: string);
{$IFDEF WINDOWS}
var
  Ini: TIniFile;
{$ENDIF}
begin
  if not R.Active then Exit;
  R.Active := False;
  {$IFDEF WINDOWS}
  { Schlafsperre aufheben: nur ES_CONTINUOUS = "keine Wünsche mehr" }
  if R.KeepAwake and Assigned(pSetThreadExecutionState) then
  begin
    pSetThreadExecutionState(ES_CONTINUOUS);
    LogLine('Energie: Schlafsperre aufgehoben');
  end;
  try
    Ini := TIniFile.Create(IniName);
    try
      if R.SchemeSet then
      begin
        if SetActiveScheme(R.OldScheme) then
          LogLine('Energie: Plan wieder auf "' + R.OldName + '" gestellt')
        else
          LogLine('Energie: Plan konnte NICHT auf "' + R.OldName +
            '" zurückgestellt werden - bitte in den Windows-Einstellungen prüfen.');
        Ini.DeleteKey('Power', 'RestoreScheme');
      end;
      if R.OverlaySet then
      begin
        if SetOverlay(R.OldOverlay) then
          LogLine('Energie: Windows-Energiemodus wieder auf "' +
            OverlayName(R.OldOverlay) + '" gestellt');
        Ini.DeleteKey('Power', 'RestoreOverlay');
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      LogLine('Energie: Zurückstellen fehlgeschlagen: ' + E.Message);
  end;
  {$ENDIF}
end;

function PowerSleptMS(const R: TPowerRun): QWord;
{$IFDEF WINDOWS}
var
  NowUnbias, Wall, Awake: QWord;
{$ENDIF}
begin
  Result := 0;
  {$IFDEF WINDOWS}
  if not R.HaveUnbias or not UnbiasedNow(NowUnbias) then Exit;
  Wall := GetTickCount64 - R.StartTick;               // ms, inkl. Standby
  Awake := (NowUnbias - R.StartUnbias) div 10000;     // 100 ns -> ms
  if Wall > Awake + 5000 then                         // < 5 s = Messrauschen
    Result := Wall - Awake;
  {$ENDIF}
end;

function PowerSummaryText(const R: TPowerRun): string;
begin
  Result := PowerSourceText;
  if R.SchemeSet then
    Result := Result + Format(_(', Plan %s -> %s (zurückgestellt)'),
      [R.OldName, R.NewName])
  else
    Result := Result + Format(_(', Plan %s'), [PowerSchemeText]);
  if R.KeepAwake then
    Result := Result + _(', PC wurde wach gehalten')
  else
    Result := Result + _(', ohne Schlafsperre');
end;

end.
