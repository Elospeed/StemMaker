{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulog.pas  (Unit uLog)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Protokoll (Log) in eine Datei - damit man auch nach einem Absturz
  noch nachvollziehen kann, was zuletzt passiert ist.

  ECHTZEIT
  Jede Zeile wird SOFORT in die Datei geschrieben (nicht erst am Ende).
  Stürzt das Programm ab, steht alles bis zur letzten Zeile in der Datei.

  WO?
  Im Ordner "logs" neben StemMaker.exe. Pro Programmstart eine Datei:
      StemMaker_2026-10-01_13-05-22_LAEUFT.log    <- Programm läuft gerade
      StemMaker_2026-10-01_13-05-22.log           <- normal beendet
      StemMaker_2026-10-01_13-05-22_FEHLER.log    <- normal beendet, aber
                                                     unterwegs gab es Fehler
      StemMaker_2026-10-01_13-05-22_ABSTURZ.log   <- unerwartet beendet

  WIE ERKENNT MAN EINEN ABSTURZ?
  Solange das Programm läuft, endet der Name auf "_LAEUFT". Beim normalen
  Beenden wird die Datei umbenannt. Findet StemMaker beim nächsten Start
  noch eine "_LAEUFT"-Datei, wurde das Programm damals nicht sauber
  beendet (Absturz, Task-Manager, Stromausfall ...). Diese Datei wird dann
  in "_ABSTURZ" umbenannt, damit man sie sofort sieht.

  Es werden nur die letzten 20 Logs aufbewahrt, ältere werden gelöscht.

  Zusätzlich sammelt die Unit Infos über den Rechner (CPU, Kerne, RAM,
  Grafikkarte) für die Zusammenfassung im Log.
  ============================================================================ }
unit uLog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils, FileUtil
  {$IFDEF WINDOWS}, Windows{$ENDIF};

const
  { Anzeigename des Programms (Fenstertitel, Info, Log-Kopf).
    Die Dateinamen bleiben kurz: StemMaker.exe, StemMaker.ini, logs\StemMaker_... }
  APP_NAME = 'Elospeed StemMaker';
  MAX_LOGS = 20;               // so viele Log-Dateien werden aufbewahrt

{ Log-Datei für diesen Programmstart anlegen (vorher: alte "_LAEUFT"-Logs
  als Absturz markieren und auf 20 Logs aufräumen) }
procedure LogInit;
{ eine Zeile mit Zeitstempel ins Log schreiben (sofort, threadsicher).
  Ohne LogInit (z.B. in StemCLI) passiert einfach nichts. }
procedure LogLine(const S: string);
{ merkt sich, dass ein Fehler aufgetreten ist -> Name endet auf "_FEHLER" }
procedure LogMarkError;
{ Log normal abschließen und umbenennen }
procedure LogClose;
{ Ordner der Logs }
function LogDir: string;
{ Name der aktuellen Log-Datei ('' wenn keine) }
function LogFileName: string;
{ Liste der Abstürze, die beim Start gefunden wurden (für einen Hinweis) }
function LogCrashesFound: Integer;

{ Aufrufkette der aktuellen Exception als Text (für eigene try/except) }
function ExceptionStackText: string;

{ ---- Rechner-Infos ---- }
function SysCPUName: string;
function SysRAMTotalMB: Int64;
{ alle Grafikkarten mit Speicher, z.B. "NVIDIA GeForce RTX 3060 (12 GB)" }
function SysGPUInfo: string;
function SysWindowsVersion: string;
{ mehrere Zeilen mit allen Infos }
function SystemInfoText: string;

implementation

uses
  uLang;

var
  GLock     : TRTLCriticalSection;
  GStream   : TFileStream = nil;     // offene Log-Datei
  GBaseName : string = '';           // Name ohne Endung/Zusatz
  GHadError : Boolean = False;
  GCrashes  : Integer = 0;
  GLogDir   : string = '';

const
  RUNNING_TAG = '_LAEUFT';

{ ---------------------------------------------------------------------------
  Ordner bestimmen: "logs" neben der Exe. Ist der Programmordner
  schreibgeschützt (z.B. C:\Programme), nehmen wir den Benutzer-Ordner.
  --------------------------------------------------------------------------- }
function LogDir: string;
begin
  if GLogDir = '' then
  begin
    GLogDir := ExtractFilePath(ParamStr(0)) + 'logs' + PathDelim;
    if not ForceDirectories(GLogDir) or not DirectoryIsWritable(GLogDir) then
      GLogDir := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'logs' + PathDelim;
    ForceDirectories(GLogDir);
  end;
  Result := GLogDir;
end;

function LogFileName: string;
begin
  if GBaseName = '' then
    Result := ''
  else
    Result := LogDir + GBaseName + RUNNING_TAG + '.log';
end;

function LogCrashesFound: Integer;
begin
  Result := GCrashes;
end;

{ ---------------------------------------------------------------------------
  Aufräumen beim Start
  1. "_LAEUFT"-Dateien von früher -> das Programm lief damals nicht bis
     zum Ende -> in "_ABSTURZ" umbenennen und unten einen Vermerk anhängen
  2. nur die neuesten MAX_LOGS Dateien behalten. Die Namen beginnen mit
     Datum/Uhrzeit, darum sortiert eine normale Textsortierung zeitlich.
  --------------------------------------------------------------------------- }
procedure CleanupOldLogs;
var
  L: TStringList;
  I: Integer;
  F, NewName: string;
  FS: TFileStream;
  Note: string;
begin
  L := FindAllFiles(LogDir, 'StemMaker_*.log', False);
  try
    { 1. verwaiste "_LAEUFT"-Logs }
    for I := 0 to L.Count - 1 do
    begin
      F := L[I];
      if Pos(RUNNING_TAG + '.log', ExtractFileName(F)) > 0 then
      begin
        try
          FS := TFileStream.Create(F, fmOpenReadWrite or fmShareDenyNone);
          try
            FS.Seek(0, soEnd);
            Note := LineEnding + '!!! Das Programm wurde UNERWARTET beendet ' +
              '(Absturz, Task-Manager oder Stromausfall).' + LineEnding +
              '!!! Die letzten Zeilen oben zeigen, was zuletzt passiert ist.' +
              LineEnding;
            FS.WriteBuffer(Note[1], Length(Note));
          finally
            FS.Free;
          end;
        except
          { Datei evtl. noch von einem zweiten laufenden StemMaker belegt -
            dann lassen wir sie in Ruhe }
          Continue;
        end;
        NewName := StringReplace(F, RUNNING_TAG + '.log', '_ABSTURZ.log', []);
        if RenameFile(F, NewName) then
          Inc(GCrashes);
      end;
    end;
  finally
    L.Free;
  end;

  { 2. alte Logs löschen (Platz für das neue lassen) }
  L := FindAllFiles(LogDir, 'StemMaker_*.log', False);
  try
    L.Sort;                       // ältestes zuerst
    I := 0;
    while L.Count - I > MAX_LOGS - 1 do
    begin
      SysUtils.DeleteFile(L[I]);
      Inc(I);
    end;
  finally
    L.Free;
  end;
end;

procedure LogInit;
begin
  if GStream <> nil then Exit;
  try
    CleanupOldLogs;
    GBaseName := 'StemMaker_' + FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now);
    GStream := TFileStream.Create(LogFileName, fmCreate or fmShareDenyNone);
  except
    { Logging darf das Programm NIE verhindern }
    GStream := nil;
  end;
end;

{ Schreibt eine Zeile. TFileStream schreibt ohne eigenen Zwischenspeicher
  direkt an Windows - die Zeile ist damit sofort "in der Datei", auch
  wenn das Programm eine Millisekunde später abstürzt.
  Die kritische Sektion sorgt dafür, dass zwei Threads (Oberfläche und
  Worker) nicht gleichzeitig schreiben und Zeilen vermischen. }
procedure LogLine(const S: string);
var
  T: string;
begin
  if GStream = nil then Exit;
  T := FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S + LineEnding;
  EnterCriticalSection(GLock);
  try
    try
      GStream.WriteBuffer(T[1], Length(T));
    except
      { z.B. Datenträger voll - ignorieren }
    end;
  finally
    LeaveCriticalSection(GLock);
  end;
end;

procedure LogMarkError;
begin
  GHadError := True;
end;

{ Beim normalen Beenden: Datei schließen und "_LAEUFT" aus dem Namen
  entfernen (bzw. durch "_FEHLER" ersetzen) }
procedure LogClose;
var
  Running, Final: string;
begin
  if GStream = nil then Exit;
  LogLine('=== Programm normal beendet ===');
  EnterCriticalSection(GLock);
  try
    Running := LogFileName;
    FreeAndNil(GStream);
    if GHadError then
      Final := LogDir + GBaseName + '_FEHLER.log'
    else
      Final := LogDir + GBaseName + '.log';
    RenameFile(Running, Final);
  finally
    LeaveCriticalSection(GLock);
  end;
end;

{ ---------------------------------------------------------------------------
  Fehler-Protokollierung

  ExceptAddr / ExceptFrames liefern die Speicheradressen der Aufrufkette.
  BackTraceStrFunc macht daraus lesbaren Text. Weil StemMaker mit
  Zeilennummern-Infos (-gl) kompiliert wird, steht dort sogar
  "Datei.pas, Zeile 123".
  --------------------------------------------------------------------------- }
function ExceptionStackText: string;
var
  I: Integer;
  Frames: PCodePointer;
begin
  Result := '      bei ' + BackTraceStrFunc(ExceptAddr) + LineEnding;
  Frames := ExceptFrames;
  for I := 0 to ExceptFrameCount - 1 do
    Result := Result + '      von ' + BackTraceStrFunc(Frames[I]) + LineEnding;
end;

{ ---------------------------------------------------------------------------
  Rechner-Infos (Windows: aus der Registry und über Windows-Funktionen)
  --------------------------------------------------------------------------- }
{$IFDEF WINDOWS}
type
  TMemoryStatusEx = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile,
    ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual: QWord;
  end;

function GlobalMemoryStatusEx(var Buf: TMemoryStatusEx): BOOL;
  stdcall; external 'kernel32.dll';

{ einen Text-Wert aus der Registry lesen (HKEY_LOCAL_MACHINE) }
function RegReadString(const Key, Name: UnicodeString): string;
var
  H: HKEY;
  Buf: array[0..511] of WideChar;
  Size, Typ: DWORD;
begin
  Result := '';
  if RegOpenKeyExW(HKEY_LOCAL_MACHINE, PWideChar(Key), 0, KEY_READ, H) <> ERROR_SUCCESS then
    Exit;
  try
    Size := SizeOf(Buf) - 2;
    FillChar(Buf, SizeOf(Buf), 0);
    if (RegQueryValueExW(H, PWideChar(Name), nil, @Typ, @Buf[0], @Size) = ERROR_SUCCESS)
       and ((Typ = REG_SZ) or (Typ = REG_EXPAND_SZ)) then
      Result := Trim(UTF8Encode(UnicodeString(PWideChar(@Buf[0]))));
  finally
    RegCloseKey(H);
  end;
end;

{ eine Zahl (4 oder 8 Byte, egal welcher Registry-Typ) lesen }
function RegReadNumber(const Key, Name: UnicodeString): QWord;
var
  H: HKEY;
  V: QWord;
  Size, Typ: DWORD;
begin
  Result := 0;
  if RegOpenKeyExW(HKEY_LOCAL_MACHINE, PWideChar(Key), 0, KEY_READ, H) <> ERROR_SUCCESS then
    Exit;
  try
    V := 0;
    Size := SizeOf(V);
    if RegQueryValueExW(H, PWideChar(Name), nil, @Typ, @V, @Size) = ERROR_SUCCESS then
      Result := V;
  finally
    RegCloseKey(H);
  end;
end;
{$ENDIF}

function SysCPUName: string;
begin
  Result := '';
  {$IFDEF WINDOWS}
  Result := RegReadString('HARDWARE\DESCRIPTION\System\CentralProcessor\0',
    'ProcessorNameString');
  {$ENDIF}
  if Result = '' then
    Result := 'unbekannt';
end;

function SysRAMTotalMB: Int64;
{$IFDEF WINDOWS}
var
  M: TMemoryStatusEx;
{$ENDIF}
begin
  Result := 0;
  {$IFDEF WINDOWS}
  FillChar(M, SizeOf(M), 0);
  M.dwLength := SizeOf(M);
  if GlobalMemoryStatusEx(M) then
    Result := M.ullTotalPhys div (1024 * 1024);
  {$ENDIF}
end;

{ Grafikkarten aus der Registry. Windows legt pro Grafiktreiber einen
  Unterschlüssel 0000, 0001, ... unter der "Display"-Geräteklasse an.
  Dort stehen Name (DriverDesc) und Speichergröße. }
function SysGPUInfo: string;
{$IFDEF WINDOWS}
const
  DISPLAY_CLASS = 'SYSTEM\CurrentControlSet\Control\Class\' +
                  '{4d36e968-e325-11ce-bfc1-08002be10318}\';
var
  I: Integer;
  Key: UnicodeString;
  Name: string;
  Mem: QWord;
{$ENDIF}
begin
  Result := '';
  {$IFDEF WINDOWS}
  for I := 0 to 9 do
  begin
    Key := UnicodeString(DISPLAY_CLASS + Format('%.4d', [I]));
    Name := RegReadString(Key, 'DriverDesc');
    if Name = '' then Continue;
    { neuere Treiber: 8-Byte-Wert, ältere: 4-Byte-Wert }
    Mem := RegReadNumber(Key, 'HardwareInformation.qwMemorySize');
    if Mem = 0 then
      Mem := RegReadNumber(Key, 'HardwareInformation.MemorySize');
    if Result <> '' then Result := Result + ', ';
    if Mem > 0 then
      Result := Result + Format('%s (%.1f GB)', [Name, Mem / 1073741824])
    else
      Result := Result + Name;
  end;
  {$ENDIF}
  { erscheint auch in der Zusammenfassung im Protokoll-Fenster -> übersetzen }
  if Result = '' then
    Result := _('unbekannt');
end;

{ Achtung, Windows-Eigenheit: Auch Windows 11 trägt in der Registry noch
  "Windows 10 ..." als Namen ein. Erkennen kann man Windows 11 nur an der
  Build-Nummer: ab 22000 ist es Windows 11. Das korrigieren wir hier.
  Dazu kommt die Version wie "24H2", wie sie auch in den Einstellungen steht. }
function SysWindowsVersion: string;
{$IFDEF WINDOWS}
const
  KEY = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion';
var
  Build, Disp: string;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Result := RegReadString(KEY, 'ProductName');
  if Result = '' then Result := 'Windows';
  Build := RegReadString(KEY, 'CurrentBuild');
  if (StrToIntDef(Build, 0) >= 22000) and (Pos('Windows 10', Result) = 1) then
    Result := 'Windows 11' + Copy(Result, Length('Windows 10') + 1, MaxInt);
  Disp := RegReadString(KEY, 'DisplayVersion');
  if Disp <> '' then
    Result := Result + ' ' + Disp;
  Result := Result + ' (Build ' + Build + ')';
  {$ELSE}
  Result := 'kein Windows';
  {$ENDIF}
end;

function SystemInfoText: string;
begin
  Result :=
    '  Betriebssystem : ' + SysWindowsVersion + LineEnding +
    '  Prozessor      : ' + SysCPUName + LineEnding +
    '  Kerne          : ' + IntToStr(TThread.ProcessorCount) + ' logische' + LineEnding +
    '  Arbeitsspeicher: ' + Format('%.1f GB', [SysRAMTotalMB / 1024]) + LineEnding +
    '  Grafikkarte    : ' + SysGPUInfo + LineEnding +
    '                   (wird NICHT genutzt - demucs.cpp rechnet nur mit der CPU)';
end;

initialization
  InitCriticalSection(GLock);

finalization
  { falls LogClose nie aufgerufen wurde, die Datei wenigstens schließen
    (der Name bleibt dann "_LAEUFT" -> beim nächsten Start "_ABSTURZ") }
  FreeAndNil(GStream);
  DoneCriticalSection(GLock);

end.
