{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uinit.pas  (Unit uInit)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Startfenster. Bevor das eigentliche Programm aufgeht, wird geprüft,
  ob alles da ist und funktioniert. Die Prüfungen werden nacheinander
  sichtbar abgehakt:

    Prozessor    : Anzahl Kerne, AVX2 ja/nein (-> schnelle oder kompatible
                   demucs-Version)
    ffmpeg       : vorhanden und startet (Version wird angezeigt)
    demucs.cpp   : vorhanden und startet
    Modell       : Modelldatei(en) vorhanden, Größe plausibel, Dateikopf
                   stimmt (erkennt z.B. einen abgebrochenen Download)
    Temp-Ordner  : man darf dort schreiben
    Weitere      : welche optionalen Modelle installiert sind (nur Info)

  Ist alles grün, schließt sich das Fenster nach knapp einer Sekunde von
  selbst und das Hauptfenster geht auf.

  Fehlen ffmpeg oder das Modell (typisch beim allerersten Start), bietet
  das Fenster einen Button "Herunterladen" an. Der Download läuft in
  einem eigenen Thread (Hintergrund), damit das Fenster nicht einfriert
  und man abbrechen kann. Danach wird automatisch neu geprüft.

  Das Fenster wird komplett im Code aufgebaut (keine .lfm-Datei), weil
  es sehr einfach ist und so alles an einer Stelle steht.
  ============================================================================ }
unit uInit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, LazFileUtils, FileUtil, UTF8Process, Process, IniFiles,
  uStemJob, uDownload, uLog, uUpdate;

{ Zeigt das Prüffenster an.
  Model     = dieses Modell muss vorhanden sein (wird sonst angeboten)
  AutoClose = True: bei Erfolg automatisch weiter (Programmstart)
              False: Aufruf aus dem Hauptfenster (Modell nachladen)
  Rückgabe  = True, wenn StemMaker (weiter)laufen soll. }
function RunStartupCheck(Model: TStemModel; AutoClose: Boolean): Boolean;

implementation

uses
  uLang;

const
  { Download-Adressen (lassen sich in der INI überschreiben, siehe DownloadURL) }
  DEF_FFMPEG_ZIP_URL = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/' +
                       'latest/ffmpeg-master-latest-win64-lgpl.zip';
  DEF_MODEL_BASE_URL = 'https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/main/';
  FFMPEG_MB = 60;                       // ungefähre Downloadgröße für die Anzeige (feste Version aus update.json)
  MIN_MODEL_SIZE = 40 * 1024 * 1024;    // echte Modelle sind 53..160 MB groß

  { Zeilennummern der Prüfliste }
  ROW_CPU = 0; ROW_FFMPEG = 1; ROW_DEMUCS = 2; ROW_MODEL = 3; ROW_TEMP = 4;
  ROW_EXTRA = 5;

type
  { Zustand einer Prüfzeile -> bestimmt Symbol und Farbe }
  TCheckState = (csWait, csRunning, csOK, csWarn, csFail, csInfo);

  { eine Zeile im Fenster: Symbol | Titel | Detailtext }
  TCheckRow = record
    Icon, Title, Detail: TLabel;
  end;

  { ein Download-Auftrag }
  TDlJob = record
    URL     : string;   // woher
    Dest    : string;   // wohin (endgültiger Dateiname)
    ZipEntry: string;   // leer = direkt speichern; sonst diese Datei aus dem ZIP holen
    Caption : string;   // Anzeigename
    SizeMB  : Integer;  // ungefähre Größe für die Anzeige
    IniKey  : string;   // 'FFmpegZipURL' / 'ModelBaseURL': Adresse aus update.json,
                        // ausser sie ist in der INI fest eingetragen
  end;

  TfrmInit = class;

  { ---------------------------------------------------------------------------
    TDlThread - lädt alle Aufträge nacheinander im Hintergrund.
    Anzeigen im Fenster laufen über Synchronize, weil man Oberflächen-
    Elemente nur aus dem Hauptthread anfassen darf.
    --------------------------------------------------------------------------- }
  TDlThread = class(TThread)
  private
    FForm: TfrmInit;
    FJobs: array of TDlJob;
    FIndex: Integer;               // welcher Auftrag gerade läuft
    FDone, FTotal: Int64;          // Fortschritt des aktuellen Downloads
    procedure Progress(Done, Total: Int64);
    function Cancelled: Boolean;
    procedure SyncProgress;
    procedure SyncJobStart;
  protected
    procedure Execute; override;
  public
    ErrMsg: string;                // leer = alles gut
    constructor Create(AForm: TfrmInit; const Jobs: array of TDlJob);
  end;

  { ---------------------------------------------------------------------------
    TfrmInit - das Startfenster
    --------------------------------------------------------------------------- }
  TfrmInit = class(TForm)
  private
    FRows: array of TCheckRow;
    lblHead, lblStatus, lblDlTime: TLabel;
    FDlStart: QWord;               // Startzeit des aktuellen Downloads (ms)
    pb: TProgressBar;
    btnDownload, btnRetry, btnStartAnyway, btnQuit, btnCancel: TButton;
    tmrStart, tmrClose: TTimer;
    FSettings: TStemSettings;
    FAutoClose: Boolean;
    FJobs: array of TDlJob;        // was heruntergeladen werden muss
    FFatal: Boolean;               // Problem, das ein Download NICHT löst
    FThread: TDlThread;            // läuft gerade ein Download?
    function AddRow(const ATitle: string): Integer;
    procedure SetRow(I: Integer; State: TCheckState; const ADetail: string);
    procedure AddJob(const URL, Dest, ZipEntry, ACaption: string; SizeMB: Integer;
      const IniKey: string = '');
    procedure RunChecks;
    procedure ShowResult;
    procedure SetBusy(Busy: Boolean);
    procedure ArrangeButtons;
    procedure tmrStartTimer(Sender: TObject);
    procedure tmrCloseTimer(Sender: TObject);
    procedure btnDownloadClick(Sender: TObject);
    procedure btnRetryClick(Sender: TObject);
    procedure btnStartAnywayClick(Sender: TObject);
    procedure btnQuitClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure DlDone(Sender: TObject);
    procedure FreeDlThread(Data: PtrInt);
    procedure FormCloseQueryInit(Sender: TObject; var CanClose: Boolean);
  public
    constructor CreateInit(AModel: TStemModel; AAutoClose: Boolean);
    procedure DlJobStart(Index, Count: Integer; const ACaption: string);
    procedure DlProgress(Done, Total: Int64);
  end;

{ ---------------------------------------------------------------------------
  Hilfsfunktionen
  --------------------------------------------------------------------------- }

{ Download-Adresse holen. Standard ist die Konstante oben - man kann sie
  aber in StemMaker.ini überschreiben, falls eine Quelle mal umzieht:
      [Download]
      FFmpegZipURL=https://...
      ModelBaseURL=https://... }
function DownloadURL(const Key, Default: string): string;
var
  Ini: TIniFile;
begin
  Result := Default;
  if not FileExists(StemIniFileName) then
    Exit;
  Ini := TIniFile.Create(StemIniFileName);
  try
    Result := Trim(Ini.ReadString('Download', Key, Default));
    if Result = '' then
      Result := Default;
  finally
    Ini.Free;
  end;
end;

{ Ist die Adresse in StemMaker.ini fest eingetragen? Dann hat sie Vorrang
  vor update.json (für Leute mit eigener Quelle). }
function DownloadURLFromIni(const Key: string): Boolean;
var
  Ini: TIniFile;
begin
  Result := False;
  if (Key = '') or not FileExists(StemIniFileName) then
    Exit;
  Ini := TIniFile.Create(StemIniFileName);
  try
    Result := Trim(Ini.ReadString('Download', Key, '')) <> '';
  finally
    Ini.Free;
  end;
end;

{ sorgt dafür, dass eine Adresse mit '/' endet (damit man den Dateinamen
  einfach anhängen kann) }
function IncludeTrailingURLDelim(const U: string): string;
begin
  Result := U;
  if (Result <> '') and (Result[Length(Result)] <> '/') then
    Result := Result + '/';
end;

{ Startet ein Programm kurz, wartet bis es fertig ist (max. 15 Sekunden)
  und gibt seine komplette Text-Ausgabe zurück. Wird benutzt, um zu testen,
  ob ffmpeg und demucs überhaupt starten. }
function RunCapture(const Exe: string; const Args: array of string;
  out Output: string; out ExitCode: Integer): Boolean;
var
  P: TProcessUTF8;
  Buf: array[0..4095] of Char;
  N, I: Integer;
  T0: QWord;
begin
  Output := '';
  ExitCode := -1;
  Result := False;
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := Exe;
    for I := Low(Args) to High(Args) do
      P.Parameters.Add(Args[I]);
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHide;
    try
      P.Execute;
    except
      on E: Exception do
      begin
        { Programm konnte gar nicht gestartet werden }
        Output := E.Message;
        Exit;
      end;
    end;
    T0 := GetTickCount64;
    repeat
      N := P.Output.NumBytesAvailable;
      if N > 0 then
      begin
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := P.Output.Read(Buf, N);
        SetLength(Output, Length(Output) + N);
        Move(Buf, Output[Length(Output) - N + 1], N);
      end
      else if P.Running then
      begin
        Sleep(20);
        Application.ProcessMessages;   // Fenster bleibt bedienbar
      end;
      if GetTickCount64 - T0 > 15000 then
      begin
        P.Terminate(1);                 // hängt -> abbrechen
        Output := Output + _(' [Zeitlimit]');
        Exit;
      end;
    until (not P.Running) and (P.Output.NumBytesAvailable = 0);
    ExitCode := P.ExitStatus;
    Result := True;
  finally
    P.Free;
  end;
end;

{ erste Zeile eines Textes }
function FirstLine(const S: string): string;
var
  P: Integer;
begin
  Result := S;
  P := Pos(#10, Result);
  if P > 0 then SetLength(Result, P - 1);
  Result := Trim(Result);
end;

{ Prüft eine Modelldatei:
  1. vorhanden?
  2. groß genug? (ein abgebrochener Download oder eine Fehlerseite ist klein)
  3. stimmt die Kennung am Dateianfang? demucs.cpp-Modelle beginnen mit
     den Bytes "dmc4" (v4), "dmc3" (v3) oder "dmc6" (6-Stem) - rückwärts
     gespeichert, deshalb die Zahlen $646D6334 usw.
  Detail = Text für die Anzeige ("fehlt", "80 MB", ...) }
function CheckModelFile(const FN: string; out Detail: string): Boolean;
var
  FS: TFileStream;
  Magic: LongWord;
  Size: Int64;
begin
  Result := False;
  if not FileExists(FN) then
  begin
    Detail := _('fehlt');
    Exit;
  end;
  Size := FileUtil.FileSize(FN);
  if Size < MIN_MODEL_SIZE then
  begin
    Detail := Format(_('beschädigt (nur %d KB)'), [Size div 1024]);
    Exit;
  end;
  Magic := 0;
  try
    FS := TFileStream.Create(FN, fmOpenRead or fmShareDenyNone);
    try
      FS.ReadBuffer(Magic, 4);
    finally
      FS.Free;
    end;
  except
    Detail := _('nicht lesbar');
    Exit;
  end;
  Magic := LEtoN(Magic);
  if (Magic <> $646D6334) and (Magic <> $646D6333) and (Magic <> $646D6336) then
  begin
    Detail := _('keine gültige Modelldatei');
    Exit;
  end;
  Detail := Format('%d MB', [Size div (1024 * 1024)]);
  Result := True;
end;

{ kurzer Anzeigename eines Modells }
function ModelShortName(M: TStemModel): string;
begin
  case M of
    smHTDemucsFT: Result := 'htdemucs_ft';
    smHDemucsV3 : Result := 'hdemucs_mmi (v3)';
  else
    Result := 'htdemucs';
  end;
end;

{ ungefähre Größe einer Modelldatei in MB (für die Anzeige) }
function ModelSizeMB(M: TStemModel): Integer;
begin
  case M of
    smHTDemucsFT: Result := 81;     // pro Datei, es sind 4 Dateien
    smHDemucsV3 : Result := 160;
  else
    Result := 81;
  end;
end;

{ ---------------------------------------------------------------------------
  TDlThread
  --------------------------------------------------------------------------- }
constructor TDlThread.Create(AForm: TfrmInit; const Jobs: array of TDlJob);
var
  I: Integer;
begin
  inherited Create(True);          // True = noch nicht starten
  FreeOnTerminate := False;        // wir geben ihn selbst frei (FreeDlThread)
  FForm := AForm;
  SetLength(FJobs, Length(Jobs));
  for I := 0 to High(Jobs) do
    FJobs[I] := Jobs[I];
end;

{ wird von HttpDownload im Thread aufgerufen -> an das Fenster weitergeben }
procedure TDlThread.Progress(Done, Total: Int64);
begin
  FDone := Done;
  FTotal := Total;
  Synchronize(@SyncProgress);
end;

{ HttpDownload fragt regelmäßig: abbrechen? -> ja, wenn Terminate gerufen wurde }
function TDlThread.Cancelled: Boolean;
begin
  Result := Terminated;
end;

procedure TDlThread.SyncProgress;
begin
  FForm.DlProgress(FDone, FTotal);
end;

procedure TDlThread.SyncJobStart;
begin
  FForm.DlJobStart(FIndex, Length(FJobs), FJobs[FIndex].Caption);
end;

{ Der eigentliche Hintergrund-Ablauf: Auftrag für Auftrag laden.
  ZIP-Aufträge (ffmpeg) werden zuerst ins Temp geladen und dann wird nur
  die benötigte Datei herausgeholt. }
procedure TDlThread.Execute;
var
  I: Integer;
  Target, E, Hash, Got: string;
  Info: TUpdateInfo;
  HaveInfo: Boolean;
begin
  ErrMsg := '';
  { Zuerst update.json holen (max. 5 s): Dort stehen die festen Download-
    Adressen und die SHA-256-Prüfsummen. Klappt das nicht (offline, GitHub
    gestört), wird mit den eingebauten Adressen geladen - ohne Prüfsumme. }
  HaveInfo := FetchUpdateInfo(UPDATE_TIMEOUT_MS, Info, E);
  if HaveInfo then
    LogLine(Format('update.json gelesen (Version %s, ffmpeg %s)', [Info.Version, Info.FFmpegVer]))
  else
    LogLine('update.json nicht erreichbar (' + E + ') - eingebaute Download-Adressen, ohne Prüfsumme');
  try
  for I := 0 to High(FJobs) do
  begin
    if Terminated then
    begin
      ErrMsg := _('Abgebrochen');
      Exit;
    end;
    { Adresse und Prüfsumme aus update.json übernehmen }
    Hash := '';
    if HaveInfo then
    begin
      if FJobs[I].IniKey = 'FFmpegZipURL' then
      begin
        if (Info.FFmpegURL <> '') and not DownloadURLFromIni('FFmpegZipURL') then
        begin
          FJobs[I].URL := Info.FFmpegURL;
          FJobs[I].ZipEntry := Info.FFmpegEntry;
          Hash := Info.FFmpegSHA256;
          if Info.FFmpegMB > 0 then FJobs[I].SizeMB := Info.FFmpegMB;
        end;
      end
      else if FJobs[I].IniKey = 'ModelBaseURL' then
      begin
        if (Info.ModelBaseURL <> '') and not DownloadURLFromIni('ModelBaseURL') then
          FJobs[I].URL := IncludeTrailingURLDelim(Info.ModelBaseURL) +
            ExtractFileName(FJobs[I].Dest);
        Hash := ModelHash(Info, FJobs[I].Dest);
      end;
    end;
    FIndex := I;
    Synchronize(@SyncJobStart);
    LogLine('Download: ' + FJobs[I].URL);
    ForceDirectories(ExtractFilePath(FJobs[I].Dest));   // tools\ bzw. models\
    if FJobs[I].ZipEntry <> '' then
      Target := GetTempDir(False) + 'stemmaker_download.zip'
    else
      Target := FJobs[I].Dest;
    if not HttpDownload(FJobs[I].URL, Target, @Progress, @Cancelled, E) then
    begin
      ErrMsg := FJobs[I].Caption + ': ' + E;
      Exit;
    end;
    { Prüfsumme kontrollieren (wenn update.json eine kennt) }
    if Hash <> '' then
    begin
      Got := FileSHA256(Target);
      if not SameText(Got, Hash) then
      begin
        LogLine(Format('Prüfsumme falsch: %s  erwartet %s  erhalten %s', [Target, Hash, Got]));
        SysUtils.DeleteFile(Target);
        ErrMsg := FJobs[I].Caption + ': ' + _('Prüfsumme (SHA-256) stimmt nicht - ' +
          'die Datei wurde verworfen. Bitte später nochmals versuchen.');
        Exit;
      end;
      LogLine('Prüfsumme OK (SHA-256): ' + ExtractFileName(FJobs[I].Dest));
    end;
    if FJobs[I].ZipEntry <> '' then
    begin
      if not ExtractSingleFromZip(Target, FJobs[I].ZipEntry, FJobs[I].Dest, E) then
        ErrMsg := FJobs[I].Caption + ': ' + E;
      SysUtils.DeleteFile(Target);                        // ZIP wird nicht mehr gebraucht
      if ErrMsg <> '' then
        Exit;
    end;
  end;
  finally
    FreeUpdateInfo(Info);
  end;
end;

{ ---------------------------------------------------------------------------
  TfrmInit - Fenster aufbauen
  --------------------------------------------------------------------------- }
constructor TfrmInit.CreateInit(AModel: TStemModel; AAutoClose: Boolean);

  { kleiner Helfer: einen Button erzeugen }
  function MakeButton(const ACaption: string; AWidth: Integer;
    AHandler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.OnClick := AHandler;
  end;

begin
  { CreateNew statt Create: dieses Fenster hat keine .lfm-Datei }
  inherited CreateNew(nil);
  FAutoClose := AAutoClose;
  { Pfade genauso ermitteln wie das Hauptprogramm (Standard + INI) }
  FSettings := DefaultStemSettings;
  LoadToolSettings(FSettings);
  FSettings.Model := AModel;

  Caption := Format(_('%s - Start'), [APP_NAME]);
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 600;
  ClientHeight := 330;
  OnCloseQuery := @FormCloseQueryInit;

  { Überschrift }
  lblHead := TLabel.Create(Self);
  lblHead.Parent := Self;
  lblHead.AutoSize := False;
  lblHead.SetBounds(16, 12, 568, 24);
  lblHead.Caption := _('Installation wird geprüft ...');
  lblHead.Font.Style := [fsBold];
  lblHead.Font.Height := -15;

  { die Prüfzeilen (Reihenfolge = ROW_...-Konstanten) }
  AddRow(_('Prozessor'));
  AddRow('ffmpeg');
  AddRow('demucs.cpp');
  AddRow(Format(_('Modell %s'), [ModelShortName(AModel)]));
  AddRow(_('Temp-Ordner'));
  AddRow(_('Weitere Modelle'));

  { Statuszeile unter der Liste (zweizeilig) }
  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.AutoSize := False;
  lblStatus.WordWrap := True;
  lblStatus.SetBounds(16, 212, 568, 34);

  { Fortschrittsbalken - nur während des Downloads sichtbar.
    Max 1000 statt 100 -> feinere Anzeige bei großen Dateien }
  pb := TProgressBar.Create(Self);
  pb.Parent := Self;
  pb.SetBounds(16, 250, 568, 16);
  pb.Smooth := True;
  pb.Max := 1000;
  pb.Visible := False;

  { Zeile unter dem Balken: vergangene / verbleibende Zeit + Tempo }
  lblDlTime := TLabel.Create(Self);
  lblDlTime.Parent := Self;
  lblDlTime.AutoSize := False;
  lblDlTime.SetBounds(16, 268, 568, 16);
  lblDlTime.Caption := '';

  { Buttons - die Position setzt ArrangeButtons }
  btnCancel      := MakeButton(_('Abbrechen'), 100, @btnCancelClick);
  btnDownload    := MakeButton(_('Herunterladen'), 215, @btnDownloadClick);
  btnRetry       := MakeButton(_('Erneut prüfen'), 110, @btnRetryClick);
  btnStartAnyway := MakeButton(_('Trotzdem starten'), 125, @btnStartAnywayClick);
  btnQuit        := MakeButton(_('Beenden'), 85, @btnQuitClick);
  btnDownload.Font.Style := [fsBold];

  { tmrStart: die Prüfung startet erst, wenn das Fenster schon sichtbar ist
    (sonst sähe man das Abhaken nicht) }
  tmrStart := TTimer.Create(Self);
  tmrStart.Interval := 150;
  tmrStart.OnTimer := @tmrStartTimer;
  { tmrClose: bei Erfolg kurz "Alles bereit" zeigen, dann schließen }
  tmrClose := TTimer.Create(Self);
  tmrClose.Enabled := False;
  tmrClose.Interval := 900;
  tmrClose.OnTimer := @tmrCloseTimer;

  SetBusy(True);
  btnCancel.Visible := False;
end;

{ fügt eine Prüfzeile hinzu (Symbol, Titel, Detail) und gibt ihre Nummer zurück }
function TfrmInit.AddRow(const ATitle: string): Integer;
var
  Y: Integer;
begin
  Result := Length(FRows);
  SetLength(FRows, Result + 1);
  Y := 48 + Result * 26;           // 26 Pixel pro Zeile
  with FRows[Result] do
  begin
    Icon := TLabel.Create(Self);
    Icon.Parent := Self;
    Icon.SetBounds(18, Y, 20, 20);
    Icon.Font.Style := [fsBold];
    Icon.Font.Height := -15;
    {$IFDEF WINDOWS}
    { Die Zeichen ✓ und ✗ gibt es sicher in der Windows-Schrift
      "Segoe UI Symbol" (ab Windows 7) - in normalen Schriften teils nicht }
    Icon.Font.Name := 'Segoe UI Symbol';
    {$ENDIF}
    Title := TLabel.Create(Self);
    Title.Parent := Self;
    Title.SetBounds(44, Y + 1, 150, 20);
    Title.Caption := ATitle;
    Detail := TLabel.Create(Self);
    Detail.Parent := Self;
    Detail.AutoSize := False;
    Detail.SetBounds(200, Y + 1, 384, 20);
    Detail.ShowHint := True;       // langer Text -> als Tooltip lesbar
  end;
  SetRow(Result, csWait, '');
end;

{ setzt Symbol, Farbe und Text einer Prüfzeile }
procedure TfrmInit.SetRow(I: Integer; State: TCheckState; const ADetail: string);
begin
  with FRows[I] do
  begin
    case State of
      csWait   : begin Icon.Caption := '·';  Icon.Font.Color := clGrayText; end;
      csRunning: begin Icon.Caption := '…';  Icon.Font.Color := clGrayText; end;
      csOK     : begin Icon.Caption := '✓';  Icon.Font.Color := clGreen;    end;
      csWarn   : begin Icon.Caption := '!';  Icon.Font.Color := $0080FF;    end; // orange
      csFail   : begin Icon.Caption := '✗';  Icon.Font.Color := clRed;      end;
      csInfo   : begin Icon.Caption := 'i';  Icon.Font.Color := clNavy;     end;
    end;
    Detail.Caption := ADetail;
    Detail.Hint := ADetail;
  end;
end;

{ merkt sich einen Download-Auftrag }
procedure TfrmInit.AddJob(const URL, Dest, ZipEntry, ACaption: string; SizeMB: Integer;
  const IniKey: string);
var
  N: Integer;
begin
  N := Length(FJobs);
  SetLength(FJobs, N + 1);
  FJobs[N].URL := URL;
  FJobs[N].Dest := Dest;
  FJobs[N].ZipEntry := ZipEntry;
  FJobs[N].Caption := ACaption;
  FJobs[N].SizeMB := SizeMB;
  FJobs[N].IniKey := IniKey;
end;

{ ---------------------------------------------------------------------------
  RunChecks - alle Prüfungen nacheinander

  Nach jeder Prüfung wird Application.ProcessMessages aufgerufen, damit
  man das Abhaken im Fenster auch sieht. Fehlende Dateien, die man
  herunterladen kann, kommen in die Auftragsliste FJobs. Probleme, die ein
  Download nicht löst (demucs fehlt, Temp nicht beschreibbar), setzen
  FFatal.
  --------------------------------------------------------------------------- }
procedure TfrmInit.RunChecks;
var
  Outp, Detail, Exe, T, Extra: string;
  Code, I, MissingMB: Integer;
  Files: TStringArray;
  M: TStemModel;
  AllOK: Boolean;
begin
  SetBusy(True);
  FJobs := nil;
  FFatal := False;
  for I := 0 to High(FRows) do
    SetRow(I, csWait, '');
  lblHead.Caption := _('Installation wird geprüft ...');
  lblStatus.Caption := '';
  Application.ProcessMessages;

  { ---- Prozessor: nur Info, wird nie rot ------------------------------- }
  if CpuHasAVX2 then T := _('AVX2 (schnelle Version)')
  else if CpuHasAVX then T := _('AVX (mittlere Version)')
  else T := _('kein AVX (kompatible Version)');
  SetRow(ROW_CPU, csOK, Format(_('%d Kerne (%d logisch), %s'),
    [PhysicalCoreCount, TThread.ProcessorCount, T]));
  Application.ProcessMessages;

  { ---- ffmpeg: vorhanden? startet es? ------------------------------------
    Test: "ffmpeg -version" muss mit "ffmpeg version" beginnen }
  SetRow(ROW_FFMPEG, csRunning, _('prüfe ...'));
  Application.ProcessMessages;
  if not FileExists(FSettings.FFmpegExe) then
  begin
    {$IFDEF WINDOWS}
    SetRow(ROW_FFMPEG, csFail, Format(_('fehlt - wird heruntergeladen (ca. %d MB)'), [FFMPEG_MB]));
    AddJob(DownloadURL('FFmpegZipURL', DEF_FFMPEG_ZIP_URL), FSettings.FFmpegExe,
      'ffmpeg.exe', 'ffmpeg', FFMPEG_MB, 'FFmpegZipURL');
    {$ELSE}
    SetRow(ROW_FFMPEG, csFail, Format(_('fehlt: %s'), [FSettings.FFmpegExe]));
    FFatal := True;
    {$ENDIF}
  end
  else if RunCapture(FSettings.FFmpegExe, ['-hide_banner', '-version'], Outp, Code)
          and (Code = 0) and (Pos('ffmpeg version', Outp) = 1) then
  begin
    { "ffmpeg version N-12345-gabc Copyright ..." -> nur den Versionsteil zeigen }
    T := FirstLine(Outp);
    I := Pos(' Copyright', T);
    if I > 0 then SetLength(T, I - 1);
    SetRow(ROW_FFMPEG, csOK, T);
  end
  else
  begin
    { vorhanden, startet aber nicht (z.B. kaputt) -> neu laden anbieten }
    SetRow(ROW_FFMPEG, csFail, Format(_('startet nicht: %s'), [FirstLine(Outp)]));
    {$IFDEF WINDOWS}
    AddJob(DownloadURL('FFmpegZipURL', DEF_FFMPEG_ZIP_URL), FSettings.FFmpegExe,
      'ffmpeg.exe', _('ffmpeg (neu)'), FFMPEG_MB, 'FFmpegZipURL');
    {$ELSE}
    FFatal := True;
    {$ENDIF}
  end;
  Application.ProcessMessages;

  { ---- demucs.cpp: vorhanden? startet es? --------------------------------
    Ohne Parameter gibt demucs nur "Usage: ..." aus und beendet sich.
    Steht "Usage" in der Ausgabe, läuft das Programm auf diesem PC.
    (demucs liegt im StemMaker-ZIP, kann also nicht nachgeladen werden) }
  SetRow(ROW_DEMUCS, csRunning, _('prüfe ...'));
  Application.ProcessMessages;
  Exe := DemucsExeFor(FSettings.DemucsDir, FSettings.Model);
  if not FileExists(Exe) then
  begin
    SetRow(ROW_DEMUCS, csFail, Format(_('fehlt: %s - StemMaker-ZIP bitte komplett neu entpacken'),
      [ExtractFileName(Exe)]));
    FFatal := True;
  end
  else if RunCapture(Exe, [], Outp, Code) and (Pos('Usage', Outp) > 0) then
  begin
    SetRow(ROW_DEMUCS, csOK, Format(_('%s startet (%s-Version)'),
      [ExtractFileName(Exe), DemucsVariantName(Exe)]));
  end
  else
  begin
    SetRow(ROW_DEMUCS, csFail, Format(_('%s startet nicht (Code %d) %s'),
      [ExtractFileName(Exe), Code, FirstLine(Outp)]));
    FFatal := True;
  end;
  Application.ProcessMessages;

  { ---- Modell: alle benötigten Dateien prüfen -------------------------- }
  SetRow(ROW_MODEL, csRunning, _('prüfe ...'));
  Application.ProcessMessages;
  Files := ModelFilesFor(FSettings.ModelsDir, FSettings.Model);
  MissingMB := 0;
  Detail := '';
  for I := 0 to High(Files) do
    if not CheckModelFile(Files[I], T) then
    begin
      { fehlt oder kaputt -> Download-Auftrag }
      AddJob(IncludeTrailingURLDelim(DownloadURL('ModelBaseURL', DEF_MODEL_BASE_URL)) +
        ExtractFileName(Files[I]), Files[I], '',
        ExtractFileName(Files[I]), ModelSizeMB(FSettings.Model), 'ModelBaseURL');
      Inc(MissingMB, ModelSizeMB(FSettings.Model));
      if Detail = '' then Detail := T;
    end;
  if MissingMB > 0 then
    SetRow(ROW_MODEL, csFail, Format(_('%s - wird heruntergeladen (ca. %d MB)'),
      [Detail, MissingMB]))
  else
  begin
    CheckModelFile(Files[0], T);
    if Length(Files) > 1 then
      T := Format(_('%d Dateien OK'), [Length(Files)])
    else
      T := ExtractFileName(Files[0]) + ', ' + T;
    SetRow(ROW_MODEL, csOK, T);
  end;
  Application.ProcessMessages;

  { ---- Temp-Ordner: Testdatei anlegen und wieder löschen ----------------- }
  T := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'StemMaker';
  try
    ForceDirectories(T);
    with TFileStream.Create(T + PathDelim + 'schreibtest.tmp', fmCreate) do
      Free;
    SysUtils.DeleteFile(T + PathDelim + 'schreibtest.tmp');
    SetRow(ROW_TEMP, csOK, T);
  except
    on E: Exception do
    begin
      SetRow(ROW_TEMP, csFail, Format(_('nicht beschreibbar: %s'), [T]));
      FFatal := True;
    end;
  end;

  { ---- weitere Modelle: nur zur Info anzeigen, was sonst noch da ist ----- }
  Extra := '';
  for M := Low(TStemModel) to High(TStemModel) do
    if M <> FSettings.Model then
    begin
      Files := ModelFilesFor(FSettings.ModelsDir, M);
      AllOK := True;
      for I := 0 to High(Files) do
        if not CheckModelFile(Files[I], T) then
          AllOK := False;
      if Extra <> '' then Extra := Extra + ',  ';
      Extra := Extra + ModelShortName(M) + BoolToStr(AllOK, ' ✓', ' –');
    end;
  SetRow(ROW_EXTRA, csInfo, Extra);

  ShowResult;
end;

{ Zeigt das Ergebnis der Prüfung an. Drei Fälle:
  1. alles OK           -> "Alles bereit", Fenster schließt sich
  2. nur Dateien fehlen -> Button "Herunterladen" anbieten
  3. echtes Problem     -> rot markiert, "Trotzdem starten" / "Beenden" }
procedure TfrmInit.ShowResult;
var
  I, MB: Integer;
  Names: string;
begin
  SetBusy(False);
  MB := 0;
  for I := 0 to High(FJobs) do
    Inc(MB, FJobs[I].SizeMB);

  btnDownload.Visible := Length(FJobs) > 0;
  btnDownload.Caption := Format(_('Herunterladen (ca. %d MB)'), [MB]);
  ArrangeButtons;

  if (not FFatal) and (Length(FJobs) = 0) then
  begin
    { Fall 1 }
    lblHead.Caption := _('Alles bereit');
    lblStatus.Caption := Format(_('%s wird gestartet ...'), [APP_NAME]);
    btnStartAnyway.Caption := _('Starten');
    if FAutoClose then
      tmrClose.Enabled := True      // kurz stehen lassen, dann zu
    else
      ModalResult := mrOK;          // aus dem Hauptfenster: sofort zurück
  end
  else if not FFatal then
  begin
    { Fall 2 }
    lblHead.Caption := _('Es fehlen noch Dateien');
    Names := '';
    for I := 0 to High(FJobs) do
    begin
      if Names <> '' then Names := Names + ', ';
      Names := Names + FJobs[I].Caption;
    end;
    lblStatus.Caption := Format(_('Diese Dateien werden einmalig aus dem Internet geladen: ' +
      '%s. Danach startet StemMaker automatisch.'), [Names]);
    btnDownload.SetFocus;
  end
  else
  begin
    { Fall 3 }
    lblHead.Caption := _('Problem gefunden');
    lblStatus.Caption := _('Mindestens eine Prüfung ist fehlgeschlagen (rot). ' +
      'Details erscheinen beim Überfahren der Zeile mit der Maus.');
  end;
end;

{ sperrt die Buttons, solange geprüft wird }
procedure TfrmInit.SetBusy(Busy: Boolean);
begin
  btnDownload.Enabled := not Busy;
  btnRetry.Enabled := not Busy;
  btnStartAnyway.Enabled := not Busy;
  if Busy then
    btnDownload.Visible := False;
  ArrangeButtons;
end;

{ Ordnet die sichtbaren Buttons rechtsbündig in einer festen Reihenfolge an:
  [Abbrechen] [Herunterladen] [Erneut prüfen] [Trotzdem starten] [Beenden]
  Unsichtbare Buttons werden übersprungen, damit keine Lücken entstehen. }
procedure TfrmInit.ArrangeButtons;
var
  Order: array[0..4] of TButton;
  I, X: Integer;
begin
  Order[0] := btnCancel;
  Order[1] := btnDownload;
  Order[2] := btnRetry;
  Order[3] := btnStartAnyway;
  Order[4] := btnQuit;
  X := ClientWidth - 16;
  for I := High(Order) downto Low(Order) do
    if Order[I].Visible then
    begin
      X := X - Order[I].Width;
      Order[I].SetBounds(X, ClientHeight - 44, Order[I].Width, 30);
      X := X - 8;                  // Abstand zwischen den Buttons
    end;
end;

procedure TfrmInit.tmrStartTimer(Sender: TObject);
begin
  tmrStart.Enabled := False;       // nur einmal auslösen
  RunChecks;
end;

procedure TfrmInit.tmrCloseTimer(Sender: TObject);
begin
  tmrClose.Enabled := False;
  ModalResult := mrOK;             // Fenster schließen, Hauptprogramm startet
end;

{ ---------------------------------------------------------------------------
  Download
  --------------------------------------------------------------------------- }
procedure TfrmInit.btnDownloadClick(Sender: TObject);
begin
  { während des Downloads nur "Abbrechen" anbieten }
  SetBusy(True);
  btnQuit.Visible := False;
  btnStartAnyway.Visible := False;
  btnRetry.Visible := False;
  btnCancel.Visible := True;
  pb.Visible := True;
  pb.Position := 0;
  ArrangeButtons;
  lblHead.Caption := _('Download läuft ...');
  { Thread erzeugen und starten; DlDone wird aufgerufen, wenn er fertig ist }
  FThread := TDlThread.Create(Self, FJobs);
  FThread.OnTerminate := @DlDone;
  FThread.Start;
end;

{ ein neuer Auftrag beginnt (vom Thread per Synchronize aufgerufen) }
procedure TfrmInit.DlJobStart(Index, Count: Integer; const ACaption: string);
begin
  lblStatus.Caption := Format(_('Lade %s  (%d von %d)'), [ACaption, Index + 1, Count]);
  pb.Position := 0;
  FDlStart := GetTickCount64;      // Stoppuhr für diese Datei starten
  lblDlTime.Caption := '';
end;

{ Fortschritt anzeigen (vom Thread per Synchronize aufgerufen) }
procedure TfrmInit.DlProgress(Done, Total: Int64);

  { Millisekunden -> "1:23" }
  function Dur(MS: QWord): string;
  var
    Sec: QWord;
  begin
    Sec := MS div 1000;
    Result := Format('%d:%.2d', [Sec div 60, Sec mod 60]);
  end;

var
  S, Rest: string;
  MS: QWord;
  Speed: Double;
begin
  if Total > 0 then
  begin
    { Größe bekannt -> richtiger Balken + "12.3 / 80.1 MB" }
    pb.Style := pbstNormal;
    pb.Position := Round(Done * 1000 / Total);
    S := Format('%.1f / %.1f MB', [Done / 1048576, Total / 1048576]);
  end
  else
  begin
    { Größe unbekannt -> Lauflicht-Balken + nur die geladene Menge }
    pb.Style := pbstMarquee;
    S := Format('%.1f MB', [Done / 1048576]);
  end;
  lblHead.Caption := Format(_('Download läuft ...  %s'), [S]);

  { Zeitanzeige: vergangen, Tempo und - wenn die Größe bekannt ist -
    die Restzeit. Restzeit = noch fehlende Bytes / bisheriges Tempo. }
  MS := GetTickCount64 - FDlStart;
  if MS < 500 then Exit;           // ganz am Anfang noch nichts anzeigen
  Speed := Done / (MS / 1000);     // Bytes pro Sekunde
  if (Total > 0) and (Speed > 0) and (MS > 3000) then
    Rest := Format(_('ca. %s'), [Dur(Round((Total - Done) / Speed * 1000))])
  else
    Rest := _('wird berechnet ...');
  lblDlTime.Caption := Format(_('vergangen %s   |   verbleibend %s   |   %.1f MB/s'),
    [Dur(MS), Rest, Speed / 1048576]);
end;

{ Thread ist fertig (erfolgreich, mit Fehler oder abgebrochen) }
procedure TfrmInit.DlDone(Sender: TObject);
var
  Err: string;
begin
  Err := FThread.ErrMsg;
  { Den Thread erst etwas später freigeben: wir befinden uns gerade noch
    IN seinem Ende-Ereignis. }
  Application.QueueAsyncCall(@FreeDlThread, PtrInt(FThread));
  FThread := nil;
  pb.Visible := False;
  pb.Style := pbstNormal;
  lblDlTime.Caption := '';
  btnCancel.Visible := False;
  btnQuit.Visible := True;
  btnStartAnyway.Visible := True;
  btnRetry.Visible := True;
  ArrangeButtons;
  if Err <> '' then
  begin
    SetBusy(False);
    btnDownload.Visible := Length(FJobs) > 0;
    ArrangeButtons;
    lblHead.Caption := _('Download fehlgeschlagen');
    lblStatus.Caption := Err + LineEnding +
      _('Internetverbindung prüfen und "Herunterladen" erneut klicken.');
  end
  else
    { Nicht direkt RunChecks aufrufen: wir sind hier noch mitten im
      Thread-Ende (OnTerminate). Die Prüfung startet per Timer kurz danach. }
    tmrStart.Enabled := True;
end;

procedure TfrmInit.FreeDlThread(Data: PtrInt);
var
  T: TDlThread;
begin
  T := TDlThread(Data);
  T.WaitFor;
  T.Free;
end;

{ ---------------------------------------------------------------------------
  Buttons
  --------------------------------------------------------------------------- }
procedure TfrmInit.btnRetryClick(Sender: TObject);
begin
  RunChecks;
end;

procedure TfrmInit.btnStartAnywayClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TfrmInit.btnQuitClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmInit.btnCancelClick(Sender: TObject);
begin
  if FThread <> nil then
  begin
    lblStatus.Caption := _('Breche ab ...');
    FThread.Terminate;             // der Thread merkt das beim nächsten Stück
  end;
end;

{ Fenster wird geschlossen (z.B. mit X) - laufenden Download sauber beenden }
procedure TfrmInit.FormCloseQueryInit(Sender: TObject; var CanClose: Boolean);
begin
  if FThread <> nil then
  begin
    FThread.OnTerminate := nil;
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  CanClose := True;
end;

{ ---------------------------------------------------------------------------
  Aufruf von außen
  --------------------------------------------------------------------------- }
function RunStartupCheck(Model: TStemModel; AutoClose: Boolean): Boolean;
var
  F: TfrmInit;
begin
  F := TfrmInit.CreateInit(Model, AutoClose);
  try
    Result := F.ShowModal = mrOK;
  finally
    F.Free;
  end;
end;

end.
