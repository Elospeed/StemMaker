unit uLoad;

{ Auslastung von CPU, Kernen und Grafikkarte, während demucs oder Turbo
  rechnet. Wird etwa alle 2 Sekunden gemessen und am Ende als Zeilen ins
  Log geschrieben, damit man sieht, ob die Trennung alle Kerne nutzt, ob
  andere Programme mitrechnen und wie stark die Grafikkarte arbeitet.

  Gemessen wird mit den Leistungsindikatoren von Windows (PDH). Die Namen
  sind auf deutschem Windows übersetzt, darum PdhAddEnglishCounter, das
  die englischen Namen auf jedem Windows versteht:
    \Processor(*)\% Processor Time          pro Kern und "_Total"
    \GPU Engine(*)\Utilization Percentage   pro Prozess und Grafik-Engine,
                                            Instanzname "pid_1234_..._engtype_Compute"
  Der Anteil des Trenn-Programms selbst kommt aus GetProcessTimes.
  Klappt PDH nicht (alte Windows-Version, Indikatoren abgeschaltet), steht
  das im Log und es gibt nur den Anteil des Trenn-Programms. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils{$IFDEF WINDOWS}, Windows{$ENDIF};

type
  TDoubleArray = array of Double;

  TLoadSampler = class
  private
    FPid: DWORD;
    FProc: THandle;
    FQuery: THandle;
    FCpuCounter, FGpuCounter: THandle;
    FPdhOK, FGpuOK: Boolean;
    FCores: Integer;
    FSamples: Integer;               // Messungen mit gültigen Werten
    FTotalSum, FTotalMax: Double;    // ganze CPU in %
    FCoreSum: array of Double;       // pro Kern, Summe für den Schnitt
    FGpuSamples: Integer;
    FGpuSum, FGpuMax: Double;
    FGpuEngine: string;              // Engine mit der höchsten Last (z. B. Compute)
    FStartTick, FLastTick: QWord;
    FStartCpu: Int64;                // Rechenzeit des Prozesses beim Start (100 ns)
    function ProcessCpuTime: Int64;
    procedure SampleCpu;
    procedure SampleGpu;
  public
    constructor Create(ProcessHandle: THandle; Pid: DWORD);
    destructor Destroy; override;
    { etwa alle 2 s aufrufen, misst nur, wenn genug Zeit vergangen ist }
    procedure Tick;
    { fertige Logzeilen (deutsch, wie der Rest des Protokolls) }
    function Summary(const Who: string): string;
  end;

implementation

{$IFDEF WINDOWS}
const
  PDH_FMT_DOUBLE   = $00000200;
  PDH_FMT_NOCAP100 = $00008000;
  PDH_MORE_DATA    = DWORD($800007D2);

type
  TPdhFmtValue = record
    CStatus: DWORD;
    Pad: DWORD;                      // Ausrichtung der Union auf 8 Byte
    DoubleValue: Double;
  end;
  TPdhFmtItem = record
    szName: PWideChar;
    FmtValue: TPdhFmtValue;
  end;
  PPdhFmtItem = ^TPdhFmtItem;

function PdhOpenQueryW(DataSource: PWideChar; UserData: PtrUInt;
  out Query: THandle): DWORD; stdcall; external 'pdh.dll';
function PdhAddEnglishCounterW(Query: THandle; Path: PWideChar; UserData: PtrUInt;
  out Counter: THandle): DWORD; stdcall; external 'pdh.dll';
function PdhCollectQueryData(Query: THandle): DWORD; stdcall; external 'pdh.dll';
function PdhGetFormattedCounterArrayW(Counter: THandle; Format: DWORD;
  var BufferSize: DWORD; var ItemCount: DWORD; Items: Pointer): DWORD;
  stdcall; external 'pdh.dll';
function PdhCloseQuery(Query: THandle): DWORD; stdcall; external 'pdh.dll';

{ alle Instanzen eines Zählers mit Wert holen (Name -> Wert) }
function CounterArray(Counter: THandle; out Names: TStringArray;
  out Values: TDoubleArray): Boolean;
var
  Size, Count, I: DWORD;
  Buf: Pointer;
  P: PPdhFmtItem;
begin
  Result := False;
  Names := nil;
  Values := nil;
  Size := 0;
  Count := 0;
  if PdhGetFormattedCounterArrayW(Counter, PDH_FMT_DOUBLE or PDH_FMT_NOCAP100,
    Size, Count, nil) <> PDH_MORE_DATA then Exit;
  GetMem(Buf, Size);
  try
    if PdhGetFormattedCounterArrayW(Counter, PDH_FMT_DOUBLE or PDH_FMT_NOCAP100,
      Size, Count, Buf) <> 0 then Exit;
    SetLength(Names, Count);
    SetLength(Values, Count);
    P := Buf;
    for I := 0 to Count - 1 do
    begin
      Names[I] := UTF8Encode(WideString(P^.szName));
      if P^.FmtValue.CStatus <= 1 then   // 0 = gültig, 1 = neuer Wert
        Values[I] := P^.FmtValue.DoubleValue
      else
        Values[I] := 0;
      Inc(P);
    end;
    Result := True;
  finally
    FreeMem(Buf);
  end;
end;
{$ENDIF}

constructor TLoadSampler.Create(ProcessHandle: THandle; Pid: DWORD);
begin
  inherited Create;
  FProc := ProcessHandle;
  FPid := Pid;
  FCores := TThread.ProcessorCount;
  SetLength(FCoreSum, FCores);
  FStartTick := GetTickCount64;
  FLastTick := FStartTick;
  FStartCpu := ProcessCpuTime;
  {$IFDEF WINDOWS}
  if PdhOpenQueryW(nil, 0, FQuery) = 0 then
  begin
    FPdhOK := PdhAddEnglishCounterW(FQuery, '\Processor(*)\% Processor Time', 0, FCpuCounter) = 0;
    { nicht jede Grafikkarte/jeder Treiber hat diesen Zähler (ab Windows 10 1709) }
    FGpuOK := PdhAddEnglishCounterW(FQuery, '\GPU Engine(*)\Utilization Percentage', 0, FGpuCounter) = 0;
    if FPdhOK or FGpuOK then
      PdhCollectQueryData(FQuery);   // erste Messung = Ausgangswert
  end;
  {$ENDIF}
end;

destructor TLoadSampler.Destroy;
begin
  {$IFDEF WINDOWS}
  if FQuery <> 0 then PdhCloseQuery(FQuery);
  {$ENDIF}
  inherited Destroy;
end;

function TLoadSampler.ProcessCpuTime: Int64;
{$IFDEF WINDOWS}
var
  C, E, K, U: TFileTime;
begin
  Result := 0;
  if GetProcessTimes(FProc, C, E, K, U) then
    Result := (Int64(K.dwHighDateTime) shl 32 or K.dwLowDateTime) +
      (Int64(U.dwHighDateTime) shl 32 or U.dwLowDateTime);
{$ELSE}
begin
  Result := 0;
{$ENDIF}
end;

procedure TLoadSampler.SampleCpu;
{$IFDEF WINDOWS}
var
  Names: TStringArray;
  Values: TDoubleArray;
  I, Core: Integer;
  Got: Boolean;
begin
  if not FPdhOK or not CounterArray(FCpuCounter, Names, Values) then Exit;
  Got := False;
  for I := 0 to High(Names) do
    if Names[I] = '_Total' then
    begin
      FTotalSum := FTotalSum + Values[I];
      if Values[I] > FTotalMax then FTotalMax := Values[I];
      Got := True;
    end
    else
    begin
      Core := StrToIntDef(Names[I], -1);
      if (Core >= 0) and (Core < FCores) then
        FCoreSum[Core] := FCoreSum[Core] + Values[I];
    end;
  if Got then Inc(FSamples);
{$ELSE}
begin
{$ENDIF}
end;

procedure TLoadSampler.SampleGpu;
{$IFDEF WINDOWS}
var
  Names, Engines: TStringArray;
  Values, Sums: TDoubleArray;
  I, J, P: Integer;
  Eng: string;
  Best: Double;
  BestEng: string;
begin
  if not FGpuOK or not CounterArray(FGpuCounter, Names, Values) then Exit;
  { Last pro Engine-Typ dieses Prozesses addieren, der höchste zählt }
  Engines := nil;
  Sums := nil;
  for I := 0 to High(Names) do
  begin
    if Pos('pid_' + IntToStr(FPid) + '_', Names[I]) <> 1 then Continue;
    P := Pos('engtype_', Names[I]);
    if P = 0 then Continue;
    Eng := Copy(Names[I], P + 8, MaxInt);
    J := 0;
    while (J < Length(Engines)) and (Engines[J] <> Eng) do Inc(J);
    if J = Length(Engines) then
    begin
      SetLength(Engines, J + 1);
      SetLength(Sums, J + 1);
      Engines[J] := Eng;
      Sums[J] := 0;
    end;
    Sums[J] := Sums[J] + Values[I];
  end;
  if Length(Engines) = 0 then Exit;     // Prozess nutzt die Grafikkarte nicht
  Best := 0;
  BestEng := Engines[0];
  for J := 0 to High(Engines) do
    if Sums[J] > Best then
    begin
      Best := Sums[J];
      BestEng := Engines[J];
    end;
  if Best > 100 then Best := 100;
  Inc(FGpuSamples);
  FGpuSum := FGpuSum + Best;
  if Best > FGpuMax then
  begin
    FGpuMax := Best;
    FGpuEngine := BestEng;
  end;
{$ELSE}
begin
{$ENDIF}
end;

procedure TLoadSampler.Tick;
begin
  if GetTickCount64 - FLastTick < 2000 then Exit;
  FLastTick := GetTickCount64;
  {$IFDEF WINDOWS}
  if (FQuery = 0) or (PdhCollectQueryData(FQuery) <> 0) then Exit;
  SampleCpu;
  SampleGpu;
  {$ENDIF}
end;

function TLoadSampler.Summary(const Who: string): string;
var
  Wall, Own, Avg, Other: Double;
  I: Integer;
  S: string;
begin
  { Anteil des Trenn-Programms an der ganzen CPU (alle Kerne = 100 %) }
  Wall := (GetTickCount64 - FStartTick) / 1000;
  Own := 0;
  if (Wall > 0) and (FCores > 0) then
    Own := (ProcessCpuTime - FStartCpu) / 1e7 / Wall / FCores * 100;
  if Own > 100 then Own := 100;
  if FSamples = 0 then
  begin
    Result := Format('  Auslastung     : %s %.0f %% der CPU (Windows-Messwerte nicht verfügbar)',
      [Who, Own]);
    Exit;
  end;
  Avg := FTotalSum / FSamples;
  Other := Avg - Own;
  if Other < 0 then Other := 0;
  Result := Format('  Auslastung CPU : Schnitt %.0f %%, Spitze %.0f %%  (davon %s %.0f %%, andere Programme %.0f %%)',
    [Avg, FTotalMax, Who, Own, Other]);
  S := '';
  for I := 0 to FCores - 1 do
    S := S + Format('  %d: %.0f %%', [I, FCoreSum[I] / FSamples]);
  Result := Result + LineEnding + '  Kerne (Schnitt):' + S;
  if FGpuSamples > 0 then
    Result := Result + LineEnding + Format('  Grafikkarte    : Schnitt %.0f %%, Spitze %.0f %% (Engine %s)',
      [FGpuSum / FGpuSamples, FGpuMax, FGpuEngine])
  else if not FGpuOK then
    Result := Result + LineEnding + '  Grafikkarte    : Auslastung nicht messbar (Windows-Zähler fehlt)';
end;

end.
