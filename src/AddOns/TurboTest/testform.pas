{ ============================================================================
  StemMaker-Turbo-Test  -  Fenster und Ablauf
  ----------------------------------------------------------------------------
  Autor : Elospeed

  Ablauf (startet von selbst):
    1. Modell htdemucs laden (Hugging Face, 84 MB, Prüfsumme wie StemMaker).
       Wir dürfen das Modell nicht selbst weitergeben, darum der Download.
    2. Vortest: engine\StemOnnx.exe <modell> --vortest
       (CPU messen, Grafikkarte suchen, prüfen, messen - wie in StemMaker)
    3. Echte Trennung: musik\The-Hardline.wav (67 s) mit StemOnnx, Gerät
       automatisch (wie StemMaker). Dabei misst uLoad CPU, Kerne und
       Grafikkarte.
    4. Bericht (deutsch, für Elospeed): PC, Vortest, Trennung, Auslastung,
       komplette Ausgabe von StemOnnx. Knöpfe "Kopieren" und "Per Mail".
    5. Beim Schliessen wird aufgeräumt: Modell, Testmusik, Engine,
       Zwischendateien und (falls vorher nicht da) die gemerkte Grafikkarten-
       Prüfung von StemOnnx. Die Exe selbst löscht ein kurzer cmd-Aufruf,
       sobald das Programm zu ist. Gelöscht werden nur unsere eigenen
       Dateien, nie der ganze Ordner, falls noch anderes darin liegt.

  Texte im Fenster: Deutsch, Englisch oder Spanisch nach der Windows-Sprache.
  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit testform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs;

type
  TTestForm = class;

  { Arbeitet alle Schritte im Hintergrund ab und meldet jede Zeile }
  TTestThread = class(TThread)
  private
    FForm: TTestForm;
    FLine: string;
    FDlDone, FDlTotal: Int64;
    procedure SyncLine;
    procedure SyncDl;
    procedure Emit(const Line: string);
    procedure DlProgress(Done, Total: Int64);
    function DlCancelled: Boolean;
    function RunLines(const Exe: string; const Args: array of string;
      WithLoad: Boolean): Integer;
  protected
    procedure Execute; override;
  public
    Failed: string;                // '' = alles gut, sonst der Grund
    LoadText: string;              // Auslastung beim Trennen (uLoad)
    SepWallSec: Double;            // ganze Zeit fürs Trennen, gemessen hier
    constructor Create(AForm: TTestForm);
  end;

  TTestForm = class(TForm)
  private
    FThread: TTestThread;
    FValues: TStringList;          // VORTEST name=wert
    FRaw: TStringList;             // komplette Ausgabe für den Bericht
    FErrors: TStringList;
    FDevice: string;               // "Rechnet auf: ..."
    FSepSec, FSepPerMin: Double;   // aus der Zusammenfassung von StemOnnx
    FReport: string;
    FDone, FReportTaken: Boolean;
    FCacheExisted: Boolean;        // gab es geraet.txt schon vor dem Test?
    lblIntro, lblStep, lblResult: TLabel;
    pbTest: TProgressBar;
    mmSteps: TMemo;
    chkClean: TCheckBox;
    btnCopy, btnMail, btnClose: TButton;
    procedure StartTest(Data: PtrInt);
    procedure ThreadDone(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnMailClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure AddStep(const S: string);
    procedure BuildReport;
    procedure CleanUp;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure HandleLine(const Line: string);
    procedure HandleDl(Done, Total: Int64);
  end;

var
  MainForm: TTestForm;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} UTF8Process, Process, Clipbrd, LCLIntf, FileUtil,
  uDownload, uLoad, uLog;

{$IFDEF WINDOWS}
function GetUserDefaultUILanguage: Word; stdcall; external 'kernel32.dll';
{$ENDIF}

const
  TOOL_VERSION = '1.0.1';
  MAIL_TO = 'elospeed.dev@gmail.com';
  MODEL_NAME = 'ggml-model-htdemucs-4s-f16.bin';
  MODEL_URL = 'https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/main/' + MODEL_NAME;
  MODEL_SHA256 = '72b17c42d308982ddb5069bc3bf48b81a5aac4cb6516e4366c0fa7cef6df0064';
  MUSIC_NAME = 'The-Hardline.wav';

var
  GLang: Char = 'e';               // 'd', 'e' oder 's'

{ Text in der Sprache von Windows }
function L(const De, En, Es: string): string;
begin
  case GLang of
    'd': Result := De;
    's': Result := Es;
  else
    Result := En;
  end;
end;

procedure DetectLanguage;
begin
  {$IFDEF WINDOWS}
  case GetUserDefaultUILanguage and $3FF of
    $07: GLang := 'd';
    $0A: GLang := 's';
  else
    GLang := 'e';
  end;
  {$ENDIF}
end;

function BaseDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function EngineExe: string;
begin
  Result := BaseDir + 'engine' + PathDelim + 'StemOnnx.exe';
end;

function ModelFile: string;
begin
  Result := BaseDir + 'modell' + PathDelim + MODEL_NAME;
end;

function MusicFile: string;
begin
  Result := BaseDir + 'musik' + PathDelim + MUSIC_NAME;
end;

function WorkDir: string;
begin
  Result := BaseDir + 'temp' + PathDelim;
end;

{ Grafikkarten-Prüfung, die sich StemOnnx merkt }
function CacheFile: string;
begin
  Result := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('LOCALAPPDATA')) +
    'StemOnnx' + PathDelim + 'geraet.txt';
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

function SecText(Sec: Double): string;
var
  T: Integer;
begin
  T := Round(Sec);
  if T < 90 then
    Result := Format('%d s', [T])
  else
    Result := Format('%d:%.2d min', [T div 60, T mod 60]);
end;

{ Windows-Fehlercode in einer Zeile, z.B. "887A0004". Grafikkarten-Fehler
  (887Axxxx) sagen mehr als das allgemeine 80004005 daneben. }
function HexCode(const Line: string): string;
var
  I, N: Integer;
begin
  I := Pos('887A', UpperCase(Line));
  if (I > 0) and (I + 7 <= Length(Line)) then
    Exit(Copy(Line, I, 8));
  Result := '?';
  N := 0;
  for I := Length(Line) downto 1 do
    if Line[I] in ['0'..'9', 'A'..'F', 'a'..'f'] then
      Inc(N)
    else
    begin
      if N = 8 then Exit(Copy(Line, I + 1, 8));
      N := 0;
    end;
end;

{ für mailto: alles außer Buchstaben und Ziffern als %XX (UTF-8) }
function UrlEncode(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.'] then
      Result := Result + S[I]
    else
      Result := Result + '%' + IntToHex(Ord(S[I]), 2);
end;

{ ---------------------------------------------------------------------------
  TTestThread
  --------------------------------------------------------------------------- }
constructor TTestThread.Create(AForm: TTestForm);
begin
  FForm := AForm;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTestThread.SyncLine;
begin
  FForm.HandleLine(FLine);
end;

procedure TTestThread.SyncDl;
begin
  FForm.HandleDl(FDlDone, FDlTotal);
end;

procedure TTestThread.Emit(const Line: string);
begin
  FLine := Line;
  Synchronize(@SyncLine);
end;

procedure TTestThread.DlProgress(Done, Total: Int64);
begin
  FDlDone := Done;
  FDlTotal := Total;
  Synchronize(@SyncDl);
end;

function TTestThread.DlCancelled: Boolean;
begin
  Result := Terminated;
end;

{ Programm starten und jede Ausgabezeile weiterreichen. WithLoad: dabei die
  Auslastung messen (für die echte Trennung). }
function TTestThread.RunLines(const Exe: string; const Args: array of string;
  WithLoad: Boolean): Integer;
var
  Proc: TProcessUTF8;
  Load: TLoadSampler;
  Buf: array[0..4095] of Char;
  Pending: string;
  N, I: Integer;

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

  procedure ReadAvail;
  var
    K: Integer;
  begin
    N := Proc.Output.NumBytesAvailable;
    if N > 0 then
    begin
      if N > SizeOf(Buf) then N := SizeOf(Buf);
      N := Proc.Output.Read(Buf, N);
      for K := 0 to N - 1 do
        Pending := Pending + Buf[K];
    end;
  end;

begin
  Result := -1;
  Pending := '';
  Load := nil;
  Proc := TProcessUTF8.Create(nil);
  try
    Proc.Executable := Exe;
    for I := Low(Args) to High(Args) do
      Proc.Parameters.Add(Args[I]);
    Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    Proc.ShowWindow := swoHide;
    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        Emit('[ERROR] ' + E.Message);
        Exit;
      end;
    end;
    if WithLoad then
      Load := TLoadSampler.Create(Proc.ProcessHandle, Proc.ProcessID);
    while True do
    begin
      ReadAvail;
      if N > 0 then
        Flush(False)
      else if not Proc.Running then
        Break
      else
        Sleep(40);
      if Load <> nil then Load.Tick;
      if Terminated then
      begin
        Proc.Terminate(1);
        Exit;
      end;
    end;
    repeat
      ReadAvail;
    until N <= 0;
    Flush(True);
    Result := Proc.ExitStatus;
    if Load <> nil then
      LoadText := Load.Summary('Turbo');
  finally
    Load.Free;
    Proc.Free;
  end;
end;

procedure TTestThread.Execute;
var
  Err, Sum: string;
  T0: QWord;
begin
  { 1. Modell }
  if not FileExists(ModelFile) or (FileSHA256(ModelFile) <> MODEL_SHA256) then
  begin
    Emit('SCHRITT 1: ' + L('Modell herunterladen (84 MB)', 'Downloading model (84 MB)',
      'Descargando modelo (84 MB)'));
    ForceDirectories(ExtractFilePath(ModelFile));
    if not HttpDownload(MODEL_URL, ModelFile, @DlProgress, @DlCancelled, Err) then
    begin
      if not Terminated then
        Failed := 'Download: ' + Err;
      Exit;
    end;
    Sum := FileSHA256(ModelFile);
    if Sum <> MODEL_SHA256 then
    begin
      SysUtils.DeleteFile(ModelFile);
      Failed := 'Prüfsumme Modell falsch: ' + Sum;
      Exit;
    end;
  end;
  Emit('MODELL OK');
  if Terminated then Exit;

  { 2. Vortest }
  Emit('PHASE vortest');
  if RunLines(EngineExe, [ModelFile, '--vortest'], False) <> 0 then
  begin
    if not Terminated then Failed := 'Vortest fehlgeschlagen';
    Exit;
  end;
  if Terminated then Exit;

  { 3. Echte Trennung }
  Emit('PHASE trennen');
  ForceDirectories(WorkDir);
  T0 := GetTickCount64;
  if RunLines(EngineExe, [ModelFile, MusicFile, ExcludeTrailingPathDelimiter(WorkDir)], True) <> 0 then
  begin
    if not Terminated then Failed := 'Trennen fehlgeschlagen';
    Exit;
  end;
  SepWallSec := (GetTickCount64 - T0) / 1000;
  DeleteDirectory(ExcludeTrailingPathDelimiter(WorkDir), False);
end;

{ ---------------------------------------------------------------------------
  TTestForm
  --------------------------------------------------------------------------- }
constructor TTestForm.Create(TheOwner: TComponent);
var
  pnl: TPanel;
begin
  inherited CreateNew(TheOwner);
  DetectLanguage;
  FValues := TStringList.Create;
  FRaw := TStringList.Create;
  FErrors := TStringList.Create;
  Caption := 'StemMaker Turbo-Test ' + TOOL_VERSION;
  Position := poScreenCenter;
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  Width := 640;
  Height := 520;
  OnCloseQuery := @FormCloseQuery;
  OnClose := @FormClose;

  lblIntro := TLabel.Create(Self);
  lblIntro.Parent := Self;
  lblIntro.SetBounds(16, 12, 608, 54);
  lblIntro.AutoSize := False;
  lblIntro.WordWrap := True;
  lblIntro.Caption := L(
    'Dieser Test misst, wie schnell StemMaker 2.0 auf diesem PC Stems trennt: ' +
    'zuerst CPU und Grafikkarte, dann ein echter Song (67 s). Er lädt einmal das ' +
    'Trenn-Modell (84 MB) und dauert je nach PC 2 bis 10 Minuten. Es wird nichts installiert.',
    'This test measures how fast StemMaker 2.0 separates stems on this PC: first ' +
    'CPU and graphics card, then a real song (67 s). It downloads the separation ' +
    'model once (84 MB) and takes 2 to 10 minutes depending on the PC. Nothing is installed.',
    'Esta prueba mide lo rápido que StemMaker 2.0 separa stems en este PC: primero ' +
    'CPU y tarjeta gráfica, luego una canción real (67 s). Descarga una vez el ' +
    'modelo de separación (84 MB) y tarda de 2 a 10 minutos según el PC. No se instala nada.');

  pbTest := TProgressBar.Create(Self);
  pbTest.Parent := Self;
  pbTest.SetBounds(16, 72, 608, 22);
  pbTest.Max := 100;

  lblStep := TLabel.Create(Self);
  lblStep.Parent := Self;
  lblStep.SetBounds(16, 100, 608, 20);
  lblStep.Font.Style := [fsBold];
  lblStep.Caption := L('Vorbereiten', 'Preparing', 'Preparando');

  mmSteps := TMemo.Create(Self);
  mmSteps.Parent := Self;
  mmSteps.SetBounds(16, 124, 608, 200);
  mmSteps.ReadOnly := True;
  mmSteps.ScrollBars := ssAutoVertical;
  mmSteps.Color := clBtnFace;

  lblResult := TLabel.Create(Self);
  lblResult.Parent := Self;
  lblResult.SetBounds(16, 332, 608, 84);
  lblResult.AutoSize := False;
  lblResult.WordWrap := True;
  lblResult.Font.Style := [fsBold];

  chkClean := TCheckBox.Create(Self);
  chkClean.Parent := Self;
  chkClean.SetBounds(16, 420, 608, 22);
  chkClean.Caption := L('Beim Schliessen alles löschen (Modell, Testmusik, Programm)',
    'Delete everything when closing (model, test music, program)',
    'Borrar todo al cerrar (modelo, música de prueba, programa)');
  chkClean.Checked := True;

  pnl := TPanel.Create(Self);
  pnl.Parent := Self;
  pnl.Align := alBottom;
  pnl.Height := 52;
  pnl.BevelOuter := bvNone;

  btnCopy := TButton.Create(Self);
  btnCopy.Parent := pnl;
  btnCopy.SetBounds(16, 10, 180, 32);
  btnCopy.Caption := L('Bericht kopieren', 'Copy report', 'Copiar informe');
  btnCopy.Enabled := False;
  btnCopy.OnClick := @btnCopyClick;

  btnMail := TButton.Create(Self);
  btnMail.Parent := pnl;
  btnMail.SetBounds(204, 10, 180, 32);
  btnMail.Caption := L('Per Mail senden', 'Send by e-mail', 'Enviar por correo');
  btnMail.Enabled := False;
  btnMail.OnClick := @btnMailClick;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnl;
  btnClose.SetBounds(pnl.ClientWidth - 136, 10, 120, 32);
  btnClose.Anchors := [akTop, akRight];
  btnClose.Caption := L('Abbrechen', 'Cancel', 'Cancelar');
  btnClose.Cancel := True;
  btnClose.OnClick := @btnCloseClick;

  Application.QueueAsyncCall(@StartTest, 0);
end;

destructor TTestForm.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FValues.Free;
  FRaw.Free;
  FErrors.Free;
  inherited Destroy;
end;

procedure TTestForm.AddStep(const S: string);
begin
  mmSteps.Lines.Add(S);
  mmSteps.SelStart := Length(mmSteps.Text);
end;

procedure TTestForm.StartTest(Data: PtrInt);
begin
  FCacheExisted := FileExists(CacheFile);
  if not FileExists(EngineExe) or not FileExists(MusicFile) then
  begin
    lblStep.Caption := L('Dateien fehlen', 'Files missing', 'Faltan archivos');
    lblResult.Caption := L('Bitte das ganze ZIP entpacken und StemMaker-Turbo-Test.exe ' +
      'im entpackten Ordner starten (nicht direkt aus dem ZIP).',
      'Please extract the whole ZIP and start StemMaker-Turbo-Test.exe from the ' +
      'extracted folder (not directly from inside the ZIP).',
      'Descomprime todo el ZIP y ejecuta StemMaker-Turbo-Test.exe desde la carpeta ' +
      'descomprimida (no directamente desde el ZIP).');
    chkClean.Checked := False;
    FDone := True;
    btnClose.Caption := L('Schliessen', 'Close', 'Cerrar');
    Exit;
  end;
  FThread := TTestThread.Create(Self);
  FThread.OnTerminate := @ThreadDone;
end;

procedure TTestForm.HandleDl(Done, Total: Int64);
begin
  if Total > 0 then
  begin
    pbTest.Position := Round(10 * Done / Total);
    lblStep.Caption := Format(L('Modell herunterladen: %d von %d MB',
      'Downloading model: %d of %d MB', 'Descargando modelo: %d de %d MB'),
      [Done div 1048576, Total div 1048576]);
  end;
end;

procedure TTestForm.HandleLine(const Line: string);
var
  P, Pct: Integer;
  Txt: string;
begin
  FRaw.Add(Line);
  if Copy(Line, 1, 8) = 'SCHRITT ' then
  begin
    { Vortest: 10 bis 60 % }
    P := Pos(':', Line);
    Pct := StrToIntDef(Copy(Line, 9, P - 9), 0);
    Txt := Trim(Copy(Line, P + 1, MaxInt));
    if Pct > 1 then
      pbTest.Position := 10 + Pct div 2;
    { die Wörter von StemOnnx sind deutsch }
    if Pos('Testsignal', Txt) = 1 then Txt := L(Txt, 'Creating test signal', 'Generando señal de prueba')
    else if Pos('Modell lesen', Txt) = 1 then Txt := L(Txt, 'Reading model', 'Leyendo modelo')
    else if Pos('CPU vorbereiten', Txt) = 1 then Txt := L(Txt, 'Preparing CPU', 'Preparando CPU')
    else if Pos('CPU einrichten', Txt) = 1 then
      Txt := L(Txt, StringReplace(StringReplace(Txt, 'CPU einrichten (Durchgang', 'Warming up CPU (pass', []), ' von ', ' of ', []),
        StringReplace(StringReplace(Txt, 'CPU einrichten (Durchgang', 'Preparando CPU (pasada', []), ' von ', ' de ', []))
    else if Pos('CPU messen', Txt) = 1 then
      Txt := L(Txt, StringReplace(StringReplace(Txt, 'CPU messen (Durchgang', 'Measuring CPU (pass', []), ' von ', ' of ', []),
        StringReplace(StringReplace(Txt, 'CPU messen (Durchgang', 'Midiendo CPU (pasada', []), ' von ', ' de ', []))
    else if Pos('Grafikkarte suchen', Txt) = 1 then Txt := L(Txt, 'Looking for graphics card', 'Buscando tarjeta gráfica')
    else if Pos('Grafikkarte prüfen', Txt) = 1 then
      Txt := L('Grafikkarte prüfen (kann bis 30 s dauern)', 'Checking graphics card (may take up to 30 s)',
        'Comprobando tarjeta gráfica (puede tardar hasta 30 s)')
    else if Pos('Grafikkarte messen', Txt) = 1 then Txt := L(Txt, 'Measuring graphics card', 'Midiendo tarjeta gráfica')
    else if Txt = 'Fertig' then Txt := L('Vortest fertig', 'Pre-test done', 'Prueba previa terminada');
    lblStep.Caption := Txt;
    AddStep('• ' + Txt);
  end
  else if Line = 'MODELL OK' then
  begin
    pbTest.Position := 10;
    AddStep('• ' + L('Modell bereit', 'Model ready', 'Modelo listo'));
  end
  else if Line = 'PHASE trennen' then
  begin
    pbTest.Position := 60;
    Txt := L('Song trennen (The Hardline, 67 s)', 'Separating song (The Hardline, 67 s)',
      'Separando canción (The Hardline, 67 s)');
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
  else if Copy(Line, 1, 13) = 'Grafikkarte: ' then
  begin
    Txt := Trim(Copy(Line, 14, MaxInt));
    if Txt = 'keine gefunden' then
      Txt := L('keine Grafikkarte gefunden', 'no graphics card found', 'no se encontró tarjeta gráfica')
    else
      Txt := StringReplace(StringReplace(Txt, '|', ' (' + L('Treiber', 'driver', 'controlador') + ' ',
        [rfReplaceAll]), ';', '), ', [rfReplaceAll]) + ')';
    if Pos(Txt, mmSteps.Text) = 0 then
      AddStep('  ' + Txt);
  end
  else if Copy(Line, 1, 13) = 'Rechnet auf: ' then
  begin
    FDevice := Trim(Copy(Line, 14, MaxInt));
    if Pos('Grafikkarte', FDevice) = 1 then
      Txt := L('rechnet auf der Grafikkarte', 'running on the graphics card', 'calculando en la tarjeta gráfica')
    else
      Txt := L('rechnet auf der CPU', 'running on the CPU', 'calculando en la CPU');
    AddStep('  ' + Txt);
  end
  else if Pos('[THREAD 0] (', Line) > 0 then
  begin
    { "[THREAD 0] ( 45.000%) Abschnitt 4 von 9": 60 bis 100 % }
    P := Pos('(', Line);
    Pct := Round(DotFloat(Copy(Line, P + 1, Pos('%', Line) - P - 1), 0));
    pbTest.Position := 60 + Pct * 2 div 5;
  end
  else if Pos('Trennen      :', Line) > 0 then
    FSepSec := DotFloat(StringReplace(Copy(Line, Pos(':', Line) + 1, MaxInt), ' s', '', []), 0)
  else if Pos('Sekunden Rechenzeit pro Audiominute', Line) > 0 then
    FSepPerMin := DotFloat(Copy(Line, Pos('=>', Line) + 2, Pos(' Sekunden', Line) - Pos('=>', Line) - 2), 0)
  else if (Copy(Line, 1, 7) = '[ERROR]') or (Copy(Line, 1, 3) = '-> ') then
  begin
    FErrors.Add(Line);
    Txt := Line;
    { Meldungen von DirectML sind lang (mit Quellpfad): nur was gemacht wurde
      und den Fehlercode zeigen, ganz stehen sie im Bericht }
    if Copy(Line, 1, 7) = '[ERROR]' then
    begin
      Txt := Trim(Copy(Line, 8, MaxInt));
      P := Pos(': ', Txt);
      if (P > 0) and (Length(Txt) > 80) then
        Txt := Copy(Txt, 1, P - 1) + ': ' + L('Fehler', 'error', 'error') + ' ' + HexCode(Line);
    end;
    if Length(Txt) > 100 then Txt := Copy(Txt, 1, 97) + '...';
    AddStep('  ! ' + Txt);
  end;
end;

procedure TTestForm.ThreadDone(Sender: TObject);
var
  Gpu, S: string;
  LoadSec: Double;
begin
  FDone := True;
  btnClose.Caption := L('Schliessen', 'Close', 'Cerrar');
  BuildReport;
  btnCopy.Enabled := True;
  btnMail.Enabled := True;
  if FThread.Failed <> '' then
  begin
    lblStep.Caption := L('Test nicht vollständig', 'Test not complete', 'Prueba incompleta');
    lblResult.Caption := L('Es gab einen Fehler: ', 'There was an error: ', 'Hubo un error: ') +
      FThread.Failed + LineEnding +
      L('Bitte trotzdem den Bericht senden, er hilft uns beim Suchen.',
        'Please send the report anyway, it helps us find the cause.',
        'Envía el informe de todos modos, nos ayuda a encontrar la causa.');
    Exit;
  end;
  pbTest.Position := 100;
  lblStep.Caption := L('Fertig - bitte den Bericht senden', 'Done - please send the report',
    'Terminado - envía el informe, por favor');
  AddStep('• ' + L('Fertig', 'Done', 'Terminado'));
  { Laden des Modells kommt einmal pro Song dazu }
  if Pos('Grafikkarte', FDevice) = 1 then
    LoadSec := DotFloat(FValues.Values['gpu_laden_s'], 5)
  else
    LoadSec := DotFloat(FValues.Values['cpu_laden_s'], 5);
  Gpu := FValues.Values['gpu_name'];
  if Pos('|', Gpu) > 0 then Gpu := Copy(Gpu, 1, Pos('|', Gpu) - 1);
  if Pos('Grafikkarte', FDevice) = 1 then
    S := Format(L('Turbo rechnet hier auf der Grafikkarte (%s).',
      'Turbo runs on the graphics card here (%s).',
      'Turbo calcula aquí en la tarjeta gráfica (%s).'), [Gpu])
  else
    S := L('Turbo rechnet hier auf der CPU.', 'Turbo runs on the CPU here.', 'Turbo calcula aquí en la CPU.');
  S := S + ' ' + Format(L('Trennen: %s pro Minute Musik. Ein Song von 3 Minuten ist in etwa %s getrennt.',
    'Separation: %s per minute of music. A 3-minute song is separated in about %s.',
    'Separación: %s por minuto de música. Una canción de 3 minutos se separa en unos %s.'),
    [SecText(FSepPerMin), SecText(3 * FSepPerMin + LoadSec)]);
  lblResult.Caption := S + LineEnding + L('Bitte jetzt "Per Mail senden" oder "Bericht kopieren".',
    'Please click "Send by e-mail" or "Copy report" now.',
    'Ahora pulsa "Enviar por correo" o "Copiar informe".');
end;

procedure TTestForm.BuildReport;
var
  R: TStringList;
  I: Integer;
  S, Home: string;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  R := TStringList.Create;
  try
    R.Add('StemMaker Turbo-Test ' + TOOL_VERSION + '  ' + FormatDateTime('yyyy-mm-dd hh:nn', Now));
    R.Add('');
    R.Add('== Rechner ==');
    R.Add('  Betriebssystem : ' + SysWindowsVersion);
    R.Add('  Prozessor      : ' + SysCPUName);
    R.Add('  Kerne          : ' + IntToStr(TThread.ProcessorCount) + ' logische');
    R.Add('  Arbeitsspeicher: ' + Format('%.1f GB', [SysRAMTotalMB / 1024], FS));
    R.Add('  Grafikkarte    : ' + SysGPUInfo);
    case GLang of
      'd': R.Add('  Sprache        : de');
      's': R.Add('  Sprache        : es');
    else
      R.Add('  Sprache        : en');
    end;
    R.Add('');
    R.Add('== Ergebnis ==');
    if FThread.Failed <> '' then
      R.Add('  FEHLER         : ' + FThread.Failed);
    R.Add('  Vortest CPU    : ' + FValues.Values['cpu_s_pro_min'] + ' s pro Minute Musik, Laden ' +
      FValues.Values['cpu_laden_s'] + ' s');
    S := '  Vortest GPU    : ' + FValues.Values['gpu_name'] + ' -> ' + FValues.Values['gpu_status'];
    if FValues.Values['gpu_s_pro_min'] <> '' then
      S := S + ', ' + FValues.Values['gpu_s_pro_min'] + ' s pro Minute Musik, Laden ' +
        FValues.Values['gpu_laden_s'] + ' s';
    { Abstand nur, wenn die Grafikkarte wirklich gerechnet hat (sonst steht 0 dB) }
    if (FValues.Values['gpu_snr_db'] <> '') and (FValues.Values['gpu_s_pro_min'] <> '') then
      S := S + ', Abstand zur CPU ' + FValues.Values['gpu_snr_db'] + ' dB';
    R.Add(S);
    R.Add('  Gerät beim Song: ' + FDevice);
    R.Add(Format('  Song 67 s      : Trennen %.1f s (%.1f s pro Minute Musik), ganzer Aufruf %.1f s',
      [FSepSec, FSepPerMin, FThread.SepWallSec], FS));
    if FThread.LoadText <> '' then
      R.Add(FThread.LoadText);
    if FErrors.Count > 0 then
    begin
      R.Add('');
      R.Add('== Fehler / Hinweise ==');
      for I := 0 to FErrors.Count - 1 do
        R.Add('  ' + FErrors[I]);
    end;
    R.Add('');
    R.Add('== Ausgabe StemOnnx ==');
    for I := 0 to FRaw.Count - 1 do
      { Fortschritt und Dateinamen (mit Benutzerordner) weglassen }
      if (Pos('[THREAD 0]', FRaw[I]) = 0) and (Pos('Writing wav file', FRaw[I]) = 0) then
        R.Add('  ' + FRaw[I]);
    FReport := R.Text;
    { Benutzername kommt so nicht in den Bericht }
    Home := SysUtils.GetEnvironmentVariable('USERPROFILE');
    if Home <> '' then
      FReport := StringReplace(FReport, Home, '%USERPROFILE%', [rfReplaceAll, rfIgnoreCase]);
  finally
    R.Free;
  end;
end;

procedure TTestForm.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := FReport;
  FReportTaken := True;
  ShowMessage(L('Der Bericht ist in der Zwischenablage. Bitte in eine Mail oder Nachricht ' +
    'einfügen (Strg+V) und an ' + MAIL_TO + ' schicken.',
    'The report is on the clipboard. Please paste it (Ctrl+V) into an e-mail or message ' +
    'and send it to ' + MAIL_TO + '.',
    'El informe está en el portapapeles. Pégalo (Ctrl+V) en un correo o mensaje ' +
    'y envíalo a ' + MAIL_TO + '.'));
end;

{ mailto kann nur kurze Texte sicher übergeben (Windows begrenzt die Länge).
  Darum: ganzer Bericht in die Zwischenablage, die Mail bekommt den Anfang
  und den Hinweis zum Einfügen. }
procedure TTestForm.btnMailClick(Sender: TObject);
var
  Body: string;
begin
  Clipboard.AsText := FReport;
  FReportTaken := True;
  Body := L('Bitte hier den Bericht einfügen (Strg+V):',
    'Please paste the report here (Ctrl+V):',
    'Pega aquí el informe (Ctrl+V):') + LineEnding + LineEnding;
  if not OpenURL('mailto:' + MAIL_TO + '?subject=' + UrlEncode('StemMaker Turbo-Test') +
    '&body=' + UrlEncode(Body)) then
    ShowMessage(Format(L('Es ist kein Mailprogramm eingerichtet. Der Bericht ist in der ' +
      'Zwischenablage, bitte an %s schicken.',
      'No e-mail program is set up. The report is on the clipboard, please send it to %s.',
      'No hay programa de correo configurado. El informe está en el portapapeles, envíalo a %s.'),
      [MAIL_TO]))
  else
    ShowMessage(L('Die Mail ist geöffnet. Der ganze Bericht ist in der Zwischenablage: ' +
      'in die Mail klicken, Strg+V drücken und senden.',
      'The e-mail is open. The full report is on the clipboard: click into the e-mail, ' +
      'press Ctrl+V and send.',
      'El correo está abierto. El informe completo está en el portapapeles: haz clic ' +
      'en el correo, pulsa Ctrl+V y envía.'));
end;

procedure TTestForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TTestForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if FDone and not FReportTaken and (FReport <> '') then
    CanClose := MessageDlg(L('Der Bericht wurde noch nicht kopiert oder gesendet. Trotzdem schliessen?',
      'The report has not been copied or sent yet. Close anyway?',
      'El informe aún no se ha copiado ni enviado. ¿Cerrar de todos modos?'),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

procedure TTestForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
  end;
  if chkClean.Checked then
    CleanUp;
  CloseAction := caFree;
end;

{ Nur unsere eigenen Dateien löschen. Die Exe kann sich nicht selbst
  löschen, solange sie läuft: das macht ein versteckter cmd-Aufruf, der
  zwei Sekunden wartet. Ist der Ordner danach leer, geht er mit. }
procedure TTestForm.CleanUp;
var
  Dir, Cmd: string;
  P: TProcessUTF8;
begin
  Dir := ExcludeTrailingPathDelimiter(BaseDir);
  DeleteDirectory(Dir + PathDelim + 'temp', False);
  DeleteDirectory(Dir + PathDelim + 'modell', False);
  DeleteDirectory(Dir + PathDelim + 'musik', False);
  DeleteDirectory(Dir + PathDelim + 'engine', False);
  SysUtils.DeleteFile(Dir + PathDelim + 'LIESMICH-README.txt');
  if not FCacheExisted then
  begin
    SysUtils.DeleteFile(CacheFile);
    RemoveDir(ExtractFileDir(CacheFile));   // nur wenn leer
  end;
  {$IFDEF WINDOWS}
  Cmd := Format('ping -n 3 127.0.0.1 >nul & del /f /q "%s" & rd "%s"', [ParamStr(0), Dir]);
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := SysUtils.GetEnvironmentVariable('COMSPEC');
    if P.Executable = '' then P.Executable := 'cmd.exe';
    P.Parameters.Add('/c');
    P.Parameters.Add(Cmd);
    P.Options := [poNoConsole];
    P.ShowWindow := swoHide;
    P.CurrentDirectory := ExtractFileDir(Dir);   // nicht im Ordner selbst stehen
    try
      P.Execute;
    except
      { dann bleibt halt die Exe liegen }
    end;
  finally
    P.Free;
  end;
  {$ENDIF}
end;

end.
