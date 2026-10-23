{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uturbotest.pas  (Unit uTurboTest)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Fenster "Turbo-Vortest" (ab 2.0). Es kommt beim ersten Start mit
  Turbo von selbst, ausserdem nach einem Wechsel von Grafikkarte oder
  Treiber und jederzeit über Einstellungen -> "Vortest ...".

  Ablauf:
    1. StemOnnx.exe <modell> --vortest  rechnet einen Abschnitt eines
       erzeugten Testsignals auf der CPU und (wenn vorhanden) auf der
       Grafikkarte und vergleicht beide. Fortschritt kommt als
       "SCHRITT <prozent>: <text>", das Ergebnis als "VORTEST name=wert"
       (siehe run_vortest in engines/onnx/src/stemonnx.c).
    2. ffmpeg kodiert 30 s Sinustöne in 5 AAC-Spuren, wie bei einer echten
       Stem-Datei. Daraus kommt die Zeit fürs Kodieren. Erzeugte Signale
       (Sinus, Rauschen, Akkorde) kodieren etwa doppelt so langsam wie
       Musik (gemessen 23.10.2026: 14 s gegen 7 s für 30 s), darum zählt
       die Hälfte. Nach dem ersten echten Track rechnet das Hauptfenster
       ohnehin mit dem gemessenen Tempo (uQueue.SpeedLearn).
    3. Ergebnis: worauf StemMaker rechnet, und wie lange ein Track von
       3 Minuten etwa dauert. Die Prognose steht schon während des Tests
       da (vorläufig) und wird mit jedem Messwert genauer.

  Jede Zeile des Tests geht sofort ins Log (uLog.LogLine schreibt ohne
  Zwischenspeicher), damit man bei Problemen genau sieht, bei welchem
  Schritt es hakt. Das Ergebnis kommt in StemMaker.ini, Abschnitt [Turbo],
  und als Tempo in [Speed] (für die Zeitschätzung im Hauptfenster).

  StemOnnx merkt sich das Ergebnis der Grafikkarte zusätzlich selbst
  (%LOCALAPPDATA%\StemOnnx\geraet.txt), damit beim Trennen keine Zeit
  für die Prüfung draufgeht.

  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uTurboTest;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  uStemJob;

{ Fenster zeigen und gleich testen (modal). S = aktuelle Einstellungen
  (Pfade, Gerät). }
procedure ShowTurboTest(const S: TStemSettings);

{ Braucht es beim Start einen Vortest? Ja, wenn Turbo rechnen würde, ein
  passendes Modell da ist und noch nie getestet wurde, oder wenn sich
  Grafikkarte oder Treiber seit dem letzten Test geändert haben.
  Reason = kurzer Grund fürs Log. }
function TurboTestNeeded(const S: TStemSettings; out Reason: string): Boolean;

{ Ergebnis des letzten Vortests in einer Zeile (für die Einstellungen),
  '' = noch nie getestet }
function TurboTestSummary: string;

implementation

uses
  IniFiles, UTF8Process, Process, uLang, uLog, uQueue;

const
  { Abschnitte pro Minute Musik: StemOnnx rechnet 7,8-s-Abschnitte mit 25 %
    Überlappung, also alle 0,75 * 343980 Samples einen (bei 44,1 kHz) }
  SEG_PER_MIN = 60 * 44100 / 257985;
  ENC_TEST_SEC = 30;               // so viele Sekunden kodiert der Test
  ENC_MUSIC_FACTOR = 0.5;          // Musik kodiert etwa doppelt so schnell wie Sinustöne

type
  TfrmTurboTest = class;

  { Führt den Test im Hintergrund aus und reicht jede Zeile weiter }
  TTurboTestThread = class(TThread)
  private
    FForm: TfrmTurboTest;
    FSettings: TStemSettings;
    FModel: string;
    FLine: string;
    FProc: TProcessUTF8;
    procedure SyncLine;
    procedure Emit(const Line: string);
    function RunLines(const Exe: string; const Args: array of string): Integer;
  protected
    procedure Execute; override;
  public
    ExitCode: Integer;             // von StemOnnx
    Aborted: Boolean;              // abgebrochen (Fenster zu)
    EncodeSec: Double;             // Zeit für ENC_TEST_SEC Sekunden, 0 = nicht gemessen
    constructor Create(AForm: TfrmTurboTest; const S: TStemSettings; const AModel: string);
    procedure Abort;
  end;

  TfrmTurboTest = class(TForm)
  private
    FSettings: TStemSettings;
    FModel: string;
    FThread: TTurboTestThread;
    FValues: TStringList;          // VORTEST name=wert
    FCpuSeg, FGpuSeg: Double;      // gemessene Sekunden pro Abschnitt (0 = noch nicht)
    FErrors: Integer;
    FDone: Boolean;
    lblIntro, lblStep, lblVerdict, lblForecast: TLabel;
    pbTest: TProgressBar;
    mmSteps: TMemo;
    btnAgain, btnClose: TButton;
    procedure StartTest(Data: PtrInt);
    procedure ThreadDone(Sender: TObject);
    procedure btnAgainClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure AddStep(const S: string);
    function Num(const Key: string): Double;
    function GpuUsed: Boolean;
    function Forecast(FT: Boolean; out Final: Boolean): Double;
    procedure ShowForecast;
    procedure ShowResult;
    procedure SaveResult;
  public
    constructor CreateTest(const S: TStemSettings);
    destructor Destroy; override;
    procedure HandleLine(const Line: string);
  end;

{ Zahl mit Punkt lesen (StemOnnx schreibt immer den Punkt) }
function DotFloat(const S: string; Default: Double): Double;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := StrToFloatDef(Trim(S), Default, FS);
end;

{ Sekunden lesbar: "45 s" oder "2:05 min" }
function SecText(Sec: Double): string;
var
  T: Integer;
begin
  T := Round(Sec);
  if T < 90 then
    Result := Format(_('%d s'), [T])
  else
    Result := Format(_('%d:%.2d min'), [T div 60, T mod 60]);
end;

{ Grund aus StemOnnx ("aus: nicht schneller als die CPU (...)") in der
  Sprache von StemMaker. Die Wörter von StemOnnx sind fest (deutsch). }
function ReasonText(const Status: string): string;
begin
  if Pos('nicht einschalten', Status) > 0 then
    Result := _('lässt sich nicht einschalten')
  else if Pos('abgestürzt', Status) > 0 then
    Result := _('ist beim Test abgestürzt')
  else if Pos('mitten im Song', Status) > 0 then
    Result := _('ist mitten im Song ausgestiegen')
  else if Pos('ungenau', Status) > 0 then
    Result := _('rechnet ungenau')
  else if Pos('falsch', Status) > 0 then
    Result := _('rechnet falsch')
  else if Pos('nicht schneller', Status) > 0 then
    Result := _('ist nicht schneller als die CPU')
  else
    Result := Status;
end;

{ Modell für den Test: htdemucs, sonst das erste von htdemucs_ft (gleicher
  Aufbau, rechnet gleich schnell) }
function TestModelFile(const S: TStemSettings): string;
var
  F: TStringArray;
begin
  F := ModelFilesFor(S.ModelsDir, smHTDemucs);
  Result := F[0];
  if FileExists(Result) then Exit;
  F := ModelFilesFor(S.ModelsDir, smHTDemucsFT);
  Result := F[0];
  if not FileExists(Result) then
    Result := '';
end;

{ ---------------------------------------------------------------------------
  TTurboTestThread
  --------------------------------------------------------------------------- }
constructor TTurboTestThread.Create(AForm: TfrmTurboTest; const S: TStemSettings;
  const AModel: string);
begin
  FForm := AForm;
  FSettings := S;
  FModel := AModel;
  ExitCode := -1;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTurboTestThread.SyncLine;
begin
  FForm.HandleLine(FLine);
end;

procedure TTurboTestThread.Emit(const Line: string);
begin
  LogLine('  Vortest | ' + Line);
  FLine := Line;
  Synchronize(@SyncLine);
end;

procedure TTurboTestThread.Abort;
begin
  Aborted := True;
  Terminate;
  { RunLines prüft Terminated und beendet das Programm }
end;

{ Programm starten und jede Ausgabezeile an Emit geben. Rückgabe: Exit-Code,
  -1 = liess sich nicht starten oder abgebrochen }
function TTurboTestThread.RunLines(const Exe: string; const Args: array of string): Integer;
var
  Buf: array[0..4095] of Char;
  Pending: string;
  N, I, K: Integer;

  procedure Flush(Final: Boolean);
  var
    J, Start: Integer;
  begin
    Start := 1;
    for J := 1 to Length(Pending) do
      if Pending[J] in [#10, #13] then
      begin
        if J > Start then
          Emit(Copy(Pending, Start, J - Start));
        Start := J + 1;
      end;
    Delete(Pending, 1, Start - 1);
    if Final and (Trim(Pending) <> '') then
      Emit(Pending);
  end;

begin
  Result := -1;
  Pending := '';
  FProc := TProcessUTF8.Create(nil);
  try
    FProc.Executable := Exe;
    for I := Low(Args) to High(Args) do
      FProc.Parameters.Add(Args[I]);
    FProc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    FProc.ShowWindow := swoHide;
    LogLine('  Vortest | Starte: ' + Exe + ' ' + StringReplace(FProc.Parameters.Text,
      LineEnding, ' ', [rfReplaceAll]));
    try
      FProc.Execute;
    except
      on E: Exception do
      begin
        Emit('[ERROR] ' + E.Message);
        Exit;
      end;
    end;
    while True do
    begin
      N := FProc.Output.NumBytesAvailable;
      if N > 0 then
      begin
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := FProc.Output.Read(Buf, N);
        for K := 0 to N - 1 do
          Pending := Pending + Buf[K];
        Flush(False);
      end
      else if not FProc.Running then
        Break
      else
        Sleep(40);
      if Terminated then
      begin
        FProc.Terminate(1);
        LogLine('  Vortest | abgebrochen');
        Exit;
      end;
    end;
    repeat
      N := FProc.Output.NumBytesAvailable;
      if N > 0 then
      begin
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := FProc.Output.Read(Buf, N);
        for K := 0 to N - 1 do
          Pending := Pending + Buf[K];
      end;
    until N <= 0;
    Flush(True);
    Result := FProc.ExitStatus;
    LogLine(Format('  Vortest | Beendet mit Code %d', [Result]));
  finally
    FreeAndNil(FProc);
  end;
end;

procedure TTurboTestThread.Execute;
var
  Tmp: string;
  T0: QWord;
  Code: Integer;
begin
  ExitCode := RunLines(OnnxExeFor(FSettings.OnnxDir), [FModel, '--vortest']);
  if Terminated or (ExitCode <> 0) then Exit;
  { Kodieren messen: 5 Sinustöne als 5 AAC-Spuren wie eine Stem-Datei }
  if not FileExists(FSettings.FFmpegExe) then Exit;
  Emit('SCHRITT 95: ' + _('Kodieren messen (ffmpeg, 5 Spuren)'));
  Tmp := GetTempDir(False) + 'StemMaker-vortest.mp4';
  T0 := GetTickCount64;
  Code := RunLines(FSettings.FFmpegExe, ['-hide_banner', '-nostdin', '-y', '-v', 'error',
    '-f', 'lavfi', '-i', Format('sine=f=55:r=44100:d=%d', [ENC_TEST_SEC]),
    '-f', 'lavfi', '-i', Format('sine=f=110:r=44100:d=%d', [ENC_TEST_SEC]),
    '-f', 'lavfi', '-i', Format('sine=f=220:r=44100:d=%d', [ENC_TEST_SEC]),
    '-f', 'lavfi', '-i', Format('sine=f=440:r=44100:d=%d', [ENC_TEST_SEC]),
    '-f', 'lavfi', '-i', Format('sine=f=880:r=44100:d=%d', [ENC_TEST_SEC]),
    '-map', '0:a', '-map', '1:a', '-map', '2:a', '-map', '3:a', '-map', '4:a',
    '-ac', '2', '-c:a', 'aac', '-b:a', '320k', '-f', 'mp4', Tmp]);
  if (Code = 0) and not Terminated then
  begin
    EncodeSec := (GetTickCount64 - T0) / 1000;
    Emit(Format('KODIEREN %.2f', [EncodeSec], DefaultFormatSettings));
  end;
  SysUtils.DeleteFile(Tmp);
end;

{ ---------------------------------------------------------------------------
  TfrmTurboTest
  --------------------------------------------------------------------------- }
constructor TfrmTurboTest.CreateTest(const S: TStemSettings);
var
  pnl: TPanel;
begin
  inherited CreateNew(nil);
  FSettings := S;
  FValues := TStringList.Create;
  Caption := _('Turbo-Vortest');
  Position := poMainFormCenter;
  BorderStyle := bsDialog;
  Width := 600;
  Height := 470;
  OnCloseQuery := @FormCloseQuery;

  lblIntro := TLabel.Create(Self);
  lblIntro.Parent := Self;
  lblIntro.SetBounds(16, 12, 568, 40);
  lblIntro.AutoSize := False;
  lblIntro.WordWrap := True;
  lblIntro.Caption := _('StemMaker misst einmal, wie schnell dieser PC Stems ' +
    'trennt: zuerst die CPU, dann die Grafikkarte. Das dauert etwa eine Minute.');

  pbTest := TProgressBar.Create(Self);
  pbTest.Parent := Self;
  pbTest.SetBounds(16, 58, 568, 22);
  pbTest.Max := 100;

  lblStep := TLabel.Create(Self);
  lblStep.Parent := Self;
  lblStep.SetBounds(16, 86, 568, 20);
  lblStep.Font.Style := [fsBold];
  lblStep.Caption := _('Vorbereiten');

  { Stichworte: was schon gemacht wurde und was gerade läuft }
  mmSteps := TMemo.Create(Self);
  mmSteps.Parent := Self;
  mmSteps.SetBounds(16, 110, 568, 150);
  mmSteps.ReadOnly := True;
  mmSteps.ScrollBars := ssAutoVertical;
  mmSteps.Color := clBtnFace;

  lblVerdict := TLabel.Create(Self);
  lblVerdict.Parent := Self;
  lblVerdict.SetBounds(16, 270, 568, 60);
  lblVerdict.AutoSize := False;
  lblVerdict.WordWrap := True;
  lblVerdict.Font.Style := [fsBold];

  lblForecast := TLabel.Create(Self);
  lblForecast.Parent := Self;
  lblForecast.SetBounds(16, 334, 568, 60);
  lblForecast.AutoSize := False;
  lblForecast.WordWrap := True;

  pnl := TPanel.Create(Self);
  pnl.Parent := Self;
  pnl.Align := alBottom;
  pnl.Height := 48;
  pnl.BevelOuter := bvNone;

  btnAgain := TButton.Create(Self);
  btnAgain.Parent := pnl;
  btnAgain.SetBounds(16, 8, 150, 32);
  btnAgain.Caption := _('Erneut testen');
  btnAgain.Enabled := False;
  btnAgain.OnClick := @btnAgainClick;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnl;
  btnClose.SetBounds(pnl.ClientWidth - 126, 8, 110, 32);
  btnClose.Anchors := [akTop, akRight];
  btnClose.Caption := _('Abbrechen');
  btnClose.Cancel := True;
  btnClose.OnClick := @btnCloseClick;

  Application.QueueAsyncCall(@StartTest, 0);
end;

destructor TfrmTurboTest.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Abort;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FValues.Free;
  inherited Destroy;
end;

procedure TfrmTurboTest.AddStep(const S: string);
begin
  mmSteps.Lines.Add(S);
  mmSteps.SelStart := Length(mmSteps.Text);   // ans Ende scrollen
end;

procedure TfrmTurboTest.StartTest(Data: PtrInt);
begin
  FValues.Clear;
  FCpuSeg := 0;
  FGpuSeg := 0;
  FErrors := 0;
  FDone := False;
  mmSteps.Clear;
  pbTest.Position := 0;
  lblVerdict.Caption := '';
  lblForecast.Caption := '';
  btnAgain.Enabled := False;
  btnClose.Caption := _('Abbrechen');
  LogLine('=== Turbo-Vortest ===');
  FModel := TestModelFile(FSettings);
  if not FileExists(OnnxExeFor(FSettings.OnnxDir)) then
  begin
    lblStep.Caption := _('Turbo fehlt');
    lblVerdict.Caption := Format(_('StemOnnx.exe wurde nicht gefunden (%s). ' +
      'StemMaker trennt mit demucs.cpp (Klassisch).'), [OnnxExeFor(FSettings.OnnxDir)]);
    LogLine('  Vortest | StemOnnx.exe fehlt: ' + OnnxExeFor(FSettings.OnnxDir));
    FDone := True;
    btnAgain.Enabled := True;
    btnClose.Caption := _('Schliessen');
    Exit;
  end;
  if FModel = '' then
  begin
    lblStep.Caption := _('Modell fehlt');
    lblVerdict.Caption := _('Für den Test braucht es das Modell htdemucs oder ' +
      'htdemucs_ft. Es wird beim Start von StemMaker heruntergeladen.');
    LogLine('  Vortest | kein Modell gefunden');
    FDone := True;
    btnAgain.Enabled := True;
    btnClose.Caption := _('Schliessen');
    Exit;
  end;
  FThread := TTurboTestThread.Create(Self, FSettings, FModel);
  FThread.OnTerminate := @ThreadDone;
end;

{ letzter Windows-Fehlercode in einer Zeile, z.B. "887A0004" (8 Hex-Ziffern) }
function HexCode(const Line: string): string;
var
  I, N: Integer;
begin
  { Grafikkarten-Fehler von Windows (887Axxxx, z.B. 887A0006 = Karte hängt)
    sagen mehr als das allgemeine 80004005 daneben }
  I := Pos('887A', UpperCase(Line));
  if (I > 0) and (I + 7 <= Length(Line)) then
    Exit(Copy(Line, I, 8));
  Result := '?';
  N := 0;
  for I := Length(Line) downto 1 do
  begin
    if Line[I] in ['0'..'9', 'A'..'F', 'a'..'f'] then
      Inc(N)
    else
    begin
      if N = 8 then Exit(Copy(Line, I + 1, 8));
      N := 0;
    end;
  end;
end;

{ "CPU messen (Durchgang 3 von 4)": Which = 1 -> 3, Which = 2 -> 4 }
function RoundNo(const Txt: string; Which: Integer): Integer;
var
  I, N: Integer;
  Cur: string;
begin
  Result := 0;
  N := 0;
  Cur := '';
  for I := 1 to Length(Txt) + 1 do
    if (I <= Length(Txt)) and (Txt[I] in ['0'..'9']) then
      Cur := Cur + Txt[I]
    else if Cur <> '' then
    begin
      Inc(N);
      if N = Which then Exit(StrToIntDef(Cur, 0));
      Cur := '';
    end;
end;

{ Eine Zeile vom Test (im Hauptthread) }
procedure TfrmTurboTest.HandleLine(const Line: string);
var
  P, Pct, K: Integer;
  Txt, Act: string;
  V: Double;
begin
  if Copy(Line, 1, 8) = 'SCHRITT ' then
  begin
    { "SCHRITT 45: CPU messen (Durchgang 4 von 4)" - StemOnnx bis 90 %,
      danach das Kodieren }
    P := Pos(':', Line);
    Pct := StrToIntDef(Copy(Line, 9, P - 9), 0);
    Txt := Trim(Copy(Line, P + 1, MaxInt));
    if Pct < 95 then Pct := Pct * 9 div 10;
    pbTest.Position := Pct;
    { die Wörter von StemOnnx sind deutsch: für andere Sprachen übersetzen }
    if Pos('Testsignal', Txt) = 1 then Txt := _('Testsignal erzeugen')
    else if Pos('Modell lesen', Txt) = 1 then Txt := _('Modell lesen')
    else if Pos('CPU vorbereiten', Txt) = 1 then Txt := _('CPU vorbereiten')
    else if Pos('CPU einrichten', Txt) = 1 then
      Txt := Format(_('CPU einrichten (Durchgang %d von %d)'), [RoundNo(Txt, 1), RoundNo(Txt, 2)])
    else if Pos('CPU messen', Txt) = 1 then
      Txt := Format(_('CPU messen (Durchgang %d von %d)'), [RoundNo(Txt, 1), RoundNo(Txt, 2)])
    else if Pos('Grafikkarte suchen', Txt) = 1 then Txt := _('Grafikkarte suchen')
    else if Pos('Grafikkarte prüfen', Txt) = 1 then Txt := _('Grafikkarte prüfen (kann bis 30 s dauern)')
    else if Pos('Grafikkarte messen', Txt) = 1 then Txt := _('Grafikkarte messen')
    else if Txt = 'Fertig' then Txt := _('Trennen gemessen');
    lblStep.Caption := Txt;
    AddStep('• ' + Txt);
  end
  else if Copy(Line, 1, 8) = 'VORTEST ' then
  begin
    Txt := Copy(Line, 9, MaxInt);
    P := Pos('=', Txt);
    if P > 0 then
      FValues.Values[Copy(Txt, 1, P - 1)] := Copy(Txt, P + 1, MaxInt);
  end
  else if Copy(Line, 1, 9) = 'KODIEREN ' then
    { Wert kommt über EncodeSec, hier nur fürs Log (siehe Emit) }
  else if Copy(Line, 1, 4) = 'CPU ' then
  begin
    { "CPU Durchgang 3: 4.08 s" - ab Durchgang 3 zählt es (1 und 2 richten ein) }
    K := StrToIntDef(Copy(Line, 15, 1), 0);
    P := Pos(': ', Line);
    if (Pos('Durchgang', Line) > 0) and (K >= 3) and (P > 0) then
    begin
      V := DotFloat(Copy(Line, P + 2, Pos(' s', Copy(Line, P + 2, MaxInt)) - 1), 0);
      if (V > 0) and ((FCpuSeg = 0) or (V < FCpuSeg)) then
        FCpuSeg := V;
      ShowForecast;
    end;
  end
  else if Copy(Line, 1, 22) = 'Grafikkarte Durchgang ' then
  begin
    P := Pos(': ', Line);
    if P > 0 then
    begin
      V := DotFloat(Copy(Line, P + 2, Pos(' s', Copy(Line, P + 2, MaxInt)) - 1), 0);
      if (V > 0) and ((FGpuSeg = 0) or (V < FGpuSeg)) then
        FGpuSeg := V;
      ShowForecast;
    end;
  end
  else if Copy(Line, 1, 13) = 'Grafikkarte: ' then
  begin
    Txt := Trim(Copy(Line, 14, MaxInt));
    if Txt = 'keine gefunden' then
      AddStep('  ' + _('keine Grafikkarte gefunden'))
    else
    begin
      { "Name|Treiber;Name|Treiber" -> "Name (Treiber ...), ..." }
      Txt := StringReplace(StringReplace(Txt, '|', ' (' + _('Treiber') + ' ',
        [rfReplaceAll]), ';', '), ', [rfReplaceAll]);
      if Pos('(', Txt) > 0 then Txt := Txt + ')';
      AddStep('  ' + Txt);
    end;
  end
  else if (Copy(Line, 1, 7) = '[ERROR]') or (Copy(Line, 1, 3) = '-> ') then
  begin
    Txt := Line;
    if Copy(Line, 1, 7) = '[ERROR]' then
    begin
      Inc(FErrors);
      { Meldungen von DirectML sind lang ("E:\_work\...\dml_provider_factory.cc
        ... 887A0004"): nur was gemacht wurde und den Fehlercode zeigen,
        ganz stehen sie im Log }
      Txt := Trim(Copy(Line, 8, MaxInt));
      P := Pos(': ', Txt);
      if (P > 0) and (Length(Txt) > 80) then
      begin
        { was StemOnnx gerade tat (deutsch) für andere Sprachen übersetzen }
        Act := Copy(Txt, 1, P - 1);
        if Act = 'Grafikkarte einschalten' then Act := _('Grafikkarte einschalten')
        else if Act = 'Sitzung vorbereiten' then Act := _('Sitzung vorbereiten')
        else if Act = 'Trennen auf der Grafikkarte' then Act := _('Trennen auf der Grafikkarte')
        else if Act = 'Trennen' then Act := _('Trennen');
        Txt := Act + ': ' + Format(_('Fehler %s'), [HexCode(Line)]);
      end;
      Txt := '! ' + Txt;
    end;
    if Length(Txt) > 110 then Txt := Copy(Txt, 1, 107) + '...';
    AddStep('  ' + Txt);
  end;
end;

function TfrmTurboTest.Num(const Key: string): Double;
begin
  Result := DotFloat(FValues.Values[Key], 0);
end;

{ Rechnet Turbo auf der Grafikkarte? (Test bestanden und nicht "nur CPU") }
function TfrmTurboTest.GpuUsed: Boolean;
begin
  Result := (FValues.Values['gpu_status'] = 'ein') and
    (FSettings.TurboDevice = tdAuto) and (Num('gpu_s_pro_min') > 0);
end;

{ Sekunden für einen Track von 3 Minuten. Final = alle Messwerte da.
  Vorläufig: Laden und Kodieren grob geschätzt, Trennen schon gemessen. }
function TfrmTurboTest.Forecast(FT: Boolean; out Final: Boolean): Double;
var
  Load, SPM, Enc: Double;
  Models: Integer;
begin
  Final := FDone and (FValues.Count > 0);
  if GpuUsed then
  begin
    Load := Num('gpu_laden_s');
    SPM := Num('gpu_s_pro_min');
  end
  else
  begin
    Load := Num('cpu_laden_s');
    SPM := Num('cpu_s_pro_min');
    { noch keine Grafikkarte gemessen: die schnellere Messung nehmen }
    if (FGpuSeg > 0) and (FSettings.TurboDevice = tdAuto) and not FDone then
      SPM := FGpuSeg * SEG_PER_MIN
    else if SPM <= 0 then
      SPM := FCpuSeg * SEG_PER_MIN;
  end;
  if Load <= 0 then Load := 5;
  if (FThread <> nil) and (FThread.EncodeSec > 0) then
    { Kodieren + Pegel- und Lautheits-Messung (ffmpeg liest dafür noch
      zweimal alle Spuren, gut 30 % dazu) }
    Enc := FThread.EncodeSec * ENC_MUSIC_FACTOR * (180 / ENC_TEST_SEC) * 1.3
  else
  begin
    Enc := 15;
    Final := False;
  end;
  if FT then Models := 4 else Models := 1;
  { + 3 s für Dekodieren, Tags und Start der Programme }
  Result := Models * Load + Models * 3 * SPM + Enc + 3;
end;

procedure TfrmTurboTest.ShowForecast;
var
  V4, FT: Double;
  Final: Boolean;
  S: string;
begin
  if (FCpuSeg <= 0) and (Num('cpu_s_pro_min') <= 0) then Exit;
  V4 := Forecast(False, Final);
  FT := Forecast(True, Final);
  S := Format(_('Ein Track von 3 Minuten dauert hier etwa %s mit htdemucs (Standard) ' +
    'und %s mit htdemucs_ft (beste Qualität).'), [SecText(V4), SecText(FT)]);
  if not Final then
    S := S + ' ' + _('(vorläufig, wird mit jedem Messwert genauer)');
  lblForecast.Caption := S;
end;

procedure TfrmTurboTest.ShowResult;
var
  Status, Gpu, S: string;
begin
  Status := FValues.Values['gpu_status'];
  Gpu := StringReplace(FValues.Values['gpu_name'], ';', ', ', [rfReplaceAll]);
  { "NVIDIA GeForce RTX 4060 Ti|32.0.15.6094" -> nur der Name }
  if Pos('|', Gpu) > 0 then
    Gpu := Copy(Gpu, 1, Pos('|', Gpu) - 1);
  if (FThread = nil) or (FThread.ExitCode <> 0) or (FValues.Count = 0) then
  begin
    lblStep.Caption := _('Vortest fehlgeschlagen');
    if FThread <> nil then
      S := IntToStr(FThread.ExitCode)
    else
      S := '-';
    lblVerdict.Caption := Format(_('Der Vortest hat nicht geklappt (Code %s). ' +
      'StemMaker versucht Turbo trotzdem und nimmt sonst demucs.cpp (Klassisch). ' +
      'Die Einzelheiten stehen im Log.'), [S]);
    lblForecast.Caption := '';
    LogLine('  Vortest | Ergebnis: fehlgeschlagen, Code ' + S);
    Exit;
  end;
  pbTest.Position := 100;
  lblStep.Caption := _('Fertig');
  AddStep('• ' + _('Fertig'));
  if GpuUsed then
    S := Format(_('StemMaker trennt auf diesem PC mit der Grafikkarte (%s): ' +
      'etwa %s Rechenzeit pro Minute Musik (CPU: %s).'),
      [Gpu, SecText(Num('gpu_s_pro_min')), SecText(Num('cpu_s_pro_min'))])
  else if Status = 'ein' then
    S := Format(_('Die Grafikkarte (%s) würde funktionieren, eingestellt ist aber ' +
      '"Nur CPU". StemMaker trennt mit der CPU: etwa %s pro Minute Musik.'),
      [Gpu, SecText(Num('cpu_s_pro_min'))])
  else if (Status = 'keine') or (Gpu = '') then
    S := Format(_('Keine Grafikkarte gefunden. StemMaker trennt mit der CPU: ' +
      'etwa %s Rechenzeit pro Minute Musik.'), [SecText(Num('cpu_s_pro_min'))])
  else
    S := Format(_('Die Grafikkarte (%s) %s. StemMaker trennt mit der CPU: ' +
      'etwa %s Rechenzeit pro Minute Musik.'),
      [Gpu, ReasonText(Status), SecText(Num('cpu_s_pro_min'))]);
  lblVerdict.Caption := S;
  ShowForecast;
  LogLine('  Vortest | Ergebnis: ' + S);
  LogLine('  Vortest | Prognose: ' + lblForecast.Caption);
end;

{ Ergebnis in StemMaker.ini: [Turbo] und das Tempo in [Speed] }
procedure TfrmTurboTest.SaveResult;
var
  Ini: TIniFile;
  Final: Boolean;
  V4, FT: Double;
begin
  if (FThread = nil) or (FThread.ExitCode <> 0) or (FValues.Count = 0) then Exit;
  V4 := Forecast(False, Final);
  FT := Forecast(True, Final);
  try
    Ini := TIniFile.Create(StemIniFileName);
    try
      Ini.WriteString('Turbo', 'VortestKarten', FValues.Values['gpu_name']);
      Ini.WriteString('Turbo', 'VortestDatum', FormatDateTime('yyyy-mm-dd hh:nn', Now));
      Ini.WriteString('Turbo', 'VortestErgebnis', lblVerdict.Caption);
    finally
      Ini.Free;
    end;
  except
    { schreibgeschützt: dann kommt der Test beim nächsten Start wieder }
  end;
  { Zeitschätzung im Hauptfenster: Sekunden pro Minute Musik }
  SpeedStore(StemIniFileName, smHTDemucs, True, V4 / 3);
  SpeedStore(StemIniFileName, smHTDemucsFT, True, FT / 3);
end;

procedure TfrmTurboTest.ThreadDone(Sender: TObject);
begin
  FDone := True;
  if not FThread.Aborted then
  begin
    ShowResult;
    SaveResult;
  end;
  btnAgain.Enabled := True;
  btnClose.Caption := _('Schliessen');
end;

procedure TfrmTurboTest.btnAgainClick(Sender: TObject);
begin
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  StartTest(0);
end;

procedure TfrmTurboTest.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmTurboTest.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { läuft noch: abbrechen. Der Test kommt dann beim nächsten Start wieder. }
  if (FThread <> nil) and not FDone then
  begin
    FThread.OnTerminate := nil;
    FThread.Abort;
    FThread.WaitFor;
    FreeAndNil(FThread);
    LogLine('  Vortest | vom Benutzer abgebrochen');
  end;
  CanClose := True;
end;

procedure ShowTurboTest(const S: TStemSettings);
var
  F: TfrmTurboTest;
begin
  F := TfrmTurboTest.CreateTest(S);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ Grafikkarten von StemOnnx abfragen ("KARTEN Name|Treiber;..."), kurz }
function CurrentCards(const S: TStemSettings; out Cards: string): Boolean;
var
  P: TProcessUTF8;
  L: TStringList;
  I: Integer;
  T0: QWord;
begin
  Result := False;
  Cards := '';
  P := TProcessUTF8.Create(nil);
  L := TStringList.Create;
  try
    P.Executable := OnnxExeFor(S.OnnxDir);
    P.Parameters.Add('--karten');
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHide;
    try
      P.Execute;
      T0 := GetTickCount64;
      while P.Running and (GetTickCount64 - T0 < 5000) do
        Sleep(20);
      if P.Running then
      begin
        P.Terminate(1);
        Exit;
      end;
      L.LoadFromStream(P.Output);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
      if Copy(L[I], 1, 7) = 'KARTEN ' then
      begin
        Cards := Trim(Copy(L[I], 8, MaxInt));
        Result := True;
      end
      else if L[I] = 'KARTEN' then
        Result := True;            // keine Grafikkarte
  finally
    L.Free;
    P.Free;
  end;
end;

function TurboTestNeeded(const S: TStemSettings; out Reason: string): Boolean;
var
  Ini: TIniFile;
  Old, Cards: string;
  Tested: Boolean;
begin
  Result := False;
  Reason := '';
  if not TurboFor(S) then Exit;
  if TestModelFile(S) = '' then Exit;        // erst nach dem Modell-Download
  Ini := TIniFile.Create(StemIniFileName);
  try
    Tested := Ini.ValueExists('Turbo', 'VortestDatum');
    Old := Ini.ReadString('Turbo', 'VortestKarten', '');
  finally
    Ini.Free;
  end;
  if not Tested then
  begin
    Reason := 'noch nie getestet';
    Exit(True);
  end;
  if CurrentCards(S, Cards) and (Cards <> Old) then
  begin
    Reason := 'Grafikkarte oder Treiber geändert: ' + Cards;
    Exit(True);
  end;
end;

function TurboTestSummary: string;
var
  Ini: TIniFile;
begin
  Result := '';
  try
    Ini := TIniFile.Create(StemIniFileName);
    try
      if Ini.ValueExists('Turbo', 'VortestDatum') then
        Result := Ini.ReadString('Turbo', 'VortestErgebnis', '') + ' (' +
          Ini.ReadString('Turbo', 'VortestDatum', '') + ')';
    finally
      Ini.Free;
    end;
  except
  end;
end;

end.
