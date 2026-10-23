{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : umain.pas  (Unit uMain, Hauptfenster; Layout in umain.lfm)
  Version : siehe APP_VERSION weiter unten (einzige Stelle im Code)
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Hauptfenster. Hier passiert alles, was der Benutzer sieht:
    - Dateiliste (Dateien hinzufügen, per Drag & Drop, ganze Ordner)
    - Einstellungen (Ausgabeordner, Modell, Format, Klang-Optionen);
      alles Weitere im Fenster "Einstellungen" (Zahnrad, uSettings)
    - Start / Abbrechen, Fortschrittsbalken und Protokoll
    - Symbol im Infobereich (neben der Uhr): Fortschritt beim Drüberfahren,
      Meldung wenn fertig, auf Wunsch "minimieren nur dorthin"

  Die eigentliche Umwandlung macht uStemJob. Weil die pro Song mehrere
  Minuten dauert, läuft sie in einem eigenen Thread (TStemWorker).
  Sonst wäre das Fenster so lange eingefroren.

  WICHTIG ZU THREADS:
  Ein Hintergrund-Thread darf die Oberfläche (Labels, Balken, Liste) NICHT
  direkt verändern. Er legt die Werte deshalb in Feldern ab (FSync...) und
  ruft Synchronize auf. Synchronize führt die angegebene Methode im
  Hauptthread aus - dort ist das Anfassen der Oberfläche erlaubt.

  Die Einstellungen werden in StemMaker.ini gespeichert (neben der Exe).
  ============================================================================ }
unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Spin, EditBtn, Buttons, IniFiles, LCLIntf, FileUtil, LazFileUtils,
  Clipbrd, Menus, uSingleInstance, {$IFDEF WINDOWS}Windows,{$ENDIF} uStemMP4, uStemJob, uInit, uLog, uInfo,
  uPower, uLang, uLangUI, uQueue, uReport, Process, UTF8Process, uUpdate, uUpdateUI,
  uSettings, uStatusDraw, uDonate, uTurboTest;

{$I version.inc}   // APP_VERSION

const
  APP_AUTHOR  = 'Elospeed';

type
  TfrmMain = class;

  { Zustand einer Datei in der Liste. Die Logik arbeitet mit diesem Wert,
    nicht mit dem angezeigten Text - der ist je nach Sprache verschieden. }
  TItemState = (isRunning, isOK, isSkipped, isCancelled, isFailed);

  { ---------------------------------------------------------------------------
    TStemWorker - arbeitet die Dateiliste im Hintergrund ab
    --------------------------------------------------------------------------- }
  TStemWorker = class(TThread)
  private
    FForm    : TfrmMain;
    FSettings: TStemSettings;
    FFiles   : TStringList;        // volle Pfade der zu bearbeitenden Dateien
    FOutFiles: TStringList;        // Zielname je Datei (siehe PlannedOutFiles)
    FIndexes : array of Integer;   // zugehörige Zeile in der Dateiliste
    FJob     : TStemJob;           // der gerade laufende Auftrag
    FLock    : TRTLCriticalSection;// schützt FJob (Zugriff aus 2 Threads)
    { Werte, die per Synchronize an das Fenster gehen: }
    FSyncMsg   : string;
    FSyncPct   : Integer;
    FSyncStage : string;
    FSyncItem  : Integer;
    FSyncStatus: TItemState;
    FSyncDone  : Integer;
    FSyncOut   : string;           // fertige Stem-Datei (leer = keine)
    FSyncTurbo : Boolean;          // diese Datei hat Turbo getrennt (für das Tempo-Lernen)
    FLastPct   : Integer;          // zuletzt gemeldete Prozentzahl
    FCancelled : Boolean;
    procedure JobLog(const Msg: string);
    procedure JobProgress(Percent: Integer; const Stage: string);
    procedure SyncLog;
    procedure SyncProgress;
    procedure SyncStatus;
  protected
    procedure Execute; override;
  public
    OKCount, FailCount, SkipCount: Integer;   // Zähler für die Zusammenfassung
    CancelCount: Integer;                      // abgebrochen (zählt nicht als Fehler)
    MaxPeakMemMB: Integer;                     // höchster RAM-Bedarf von demucs
    OmpPerPart  : Integer;                     // Kerne pro demucs-Teilstück
    TurboCount  : Integer;                     // Dateien mit Turbo getrennt
    ClassicCount: Integer;                     // Dateien mit demucs.cpp getrennt
    TurboDev    : string;                      // Turbo: Gerät der letzten Datei
    constructor Create(AForm: TfrmMain; const ASettings: TStemSettings);
    destructor Destroy; override;
    procedure AddFile(const FileName, OutFile: string; ListIndex: Integer);
    procedure Cancel;
  end;

  { ---------------------------------------------------------------------------
    TfrmMain - das Hauptfenster (Komponenten sind in umain.lfm angeordnet)
    --------------------------------------------------------------------------- }
  TfrmMain = class(TForm)
    btnAddFiles: TButton;
    btnInfo: TButton;
    btnCopyLog: TButton;
    btnAddFolder: TButton;
    btnRemove: TButton;
    btnClear: TButton;
    btnCheck: TButton;
    btnStart: TButton;
    btnCancel: TButton;
    btnOpenOut: TButton;
    btnListen: TButton;
    btnSettings: TBitBtn;
    chkOpenWhenDone: TCheckBox;
    cbModel: TComboBox;
    cbFormat: TComboBox;
    chkBeside: TCheckBox;
    chkShutdown: TCheckBox;
    chkNormalize: TCheckBox;
    chkBassFix: TCheckBox;
    edtOut: TDirectoryEdit;
    gbSettings: TGroupBox;
    lblDrop: TLabel;
    lblOut: TLabel;
    lblModel: TLabel;
    lblFormat: TLabel;
    lblTools: TLabel;
    lblStage: TLabel;
    lblTotal: TLabel;
    lblFileTime: TLabel;
    lvFiles: TListView;
    memLog: TMemo;
    dlgOpen: TOpenDialog;
    dlgFolder: TSelectDirectoryDialog;
    pnlTop: TPanel;
    pbAccent: TPaintBox;
    pnlRun: TPanel;
    pbFile: TProgressBar;
    pbTotal: TProgressBar;
    splLog: TSplitter;
    tmrTime: TTimer;
    procedure btnAddFilesClick(Sender: TObject);
    procedure btnAddFolderClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnCheckClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure btnOpenOutClick(Sender: TObject);
    procedure btnListenClick(Sender: TObject);
    procedure lvFilesDblClick(Sender: TObject);
    procedure lvFilesCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
      SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure pbAccentPaint(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure chkBesideChange(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure cbModelChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure tmrTimeTimer(Sender: TObject);
    procedure btnInfoClick(Sender: TObject);
    procedure btnCopyLogClick(Sender: TObject);
  private
    FWorker: TStemWorker;          // nil = gerade keine Umwandlung
    FTotal : Integer;              // Anzahl Dateien im aktuellen Durchlauf
    FIniName: string;
    FToolFFmpeg, FToolDemucs, FToolModels: string;   // Werkzeug-Pfade
    FPrefs: TStemPrefs;            // Werte aus dem Fenster "Einstellungen" (uSettings)
    { für die Zeitanzeige unter den Balken: }
    FRunStart  : QWord;            // Startzeitpunkt des ganzen Durchlaufs (ms)
    FFileStart : QWord;            // Startzeitpunkt der aktuellen Datei (ms)
    FFilePct   : Integer;          // Fortschritt der aktuellen Datei 0..100
    FFilesDone : Integer;          // Anzahl schon fertiger Dateien
    FOKTimeMS  : QWord;            // Summe der Dauer aller erfolgreichen Dateien
    FOKCount   : Integer;          // Anzahl erfolgreicher Dateien (für den Schnitt)
    FStageName : string;           // aktueller Arbeitsschritt (z.B. "Stems trennen")
    FStageT0   : QWord;            // wann der Schritt begonnen hat
    FStagePct0 : Integer;          // bei wie viel Prozent er begonnen hat
    FRunSettings: TStemSettings;   // Einstellungen des laufenden Durchlaufs (fürs Log)
    FPower     : TPowerRun;        // Schlafsperre/Energieplan des laufenden Durchlaufs
    FProber    : TDurationProber;  // ermittelt im Hintergrund die Song-Längen
    FProbeAgain: Boolean;          // während der Abfrage kamen neue Dateien dazu
    FChangePending: Boolean;       // AfterListChange ist schon angemeldet
    FRestoring : Boolean;          // Liste wird gerade aus der Datei geladen
    FOKAudioMS : Int64;            // Musik-Länge aller fertigen Dateien (für das Tempo)
    FItemTurbo : Boolean;          // die gemeldete Datei lief mit Turbo (sonst demucs.cpp)
    FCurIndex  : Integer;          // Zeile der Datei, die gerade läuft
    FUserCancelled: Boolean;       // Benutzer hat "Abbrechen" gedrückt
    FLastOutFile: string;          // zuletzt fertig gewordene Stem-Datei (dieser Durchlauf)
    FUpdate    : TUpdateInfo;      // gefundenes Update (ohne ModelHashes)
    FHasUpdate : Boolean;          // ... wartet darauf, angeboten zu werden
    { Symbol im Infobereich (neben der Uhr), siehe "Symbol neben der Uhr" }
    FTray      : TTrayIcon;
    FTrayTimer : TTimer;           // fragt ab, ob ein zweiter Start "zeig dich" will
    FInTray    : Boolean;          // Fenster ist gerade ins Symbol versteckt
    FTrayNotice: Boolean;          // "fertig"-Meldung wurde gezeigt, noch nicht gesehen
    FDonatePending: Boolean;       // Spenden-Hinweis fällig, wartet bis StemMaker vorne ist
    procedure ShowDonate(Data: PtrInt);
    procedure SetupTray;
    procedure UpdateTray;
    procedure TrayProgress;
    procedure HideToTray;
    procedure ShowFromTray;
    procedure TrayClick(Sender: TObject);
    procedure TrayQuitClick(Sender: TObject);
    procedure TrayTimerTick(Sender: TObject);
    procedure AppMinimize(Sender: TObject);
    procedure AppActivate(Sender: TObject);
    procedure TrayNotifyDone(OK, Skipped, Failed: Integer; const Total: string);
    procedure AppEndSession(Sender: TObject);
    procedure UpdateFound(const Info: TUpdateInfo);
    procedure OfferUpdate(Data: PtrInt);
    procedure CheckTurboTest(Data: PtrInt);
    function ItemOutFile(Index: Integer): string;
    function ItemOutDir(Index: Integer): string;
    function PlannedOutFiles: TStringArray;
    procedure OpenInPlayer(const StemFile: string);
    procedure ShowInExplorer(const FileName: string);
    procedure UpdateTimes;
    procedure EndPower;
    procedure WriteRunSummary(W: TStemWorker);
    procedure TestError(Data: PtrInt);
    procedure TestCrash(Data: PtrInt);
    procedure OfferCrashReport(Data: PtrInt);
    procedure AddInput(const FileName: string; const Root: string = '');
    procedure AddFolder(const Dir: string);
    { Sammlungs-Funktionen (Warteschlange merken, Längen, Schätzung) }
    procedure ListChanged;
    procedure AfterListChange(Data: PtrInt);
    procedure SaveQueueNow;
    procedure RestoreQueue;
    procedure StartProbe;
    procedure StopProbe;
    procedure ProberDone(Sender: TObject);
    procedure FreeProber(Data: PtrInt);
    procedure DurationResult(const Path: string; DurMS: Int64);
    procedure UpdateEstimate;
    function ItemDurMS(Index: Integer): Int64;
    function RateMsPerMs: Double;
    function ShutdownCountdown: Boolean;
    procedure AskShutdown(Data: PtrInt);
    function CurrentSettings: TStemSettings;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure UpdateToolStatus;
    procedure SetRunning(Running: Boolean);
    procedure WorkerDone(Sender: TObject);
    procedure FreeWorker(Data: PtrInt);
  public
    procedure AddLog(const Msg: string);
    procedure SetFileProgress(Percent: Integer; const Stage: string);
    procedure SetItemStatus(Index: Integer; Status: TItemState; Done: Integer);
    procedure SetItemOutFile(Index: Integer; const FileName: string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

const
  { Zustand einer Zeile der Dateiliste. Er steht im Data-Feld der Zeile
    (eine Zahl, kein Text - der angezeigte Text ist ja je nach Sprache
    verschieden). }
  ST_WAIT   = 0;     // wartet (auch: unterbrochen)
  ST_OK     = 1;     // fertig
  ST_SKIP   = 2;     // übersprungen (Stem-Datei gab es schon)
  ST_FAIL   = 3;     // Fehler
  ST_CANCEL = 4;     // abgebrochen
  ST_RUN    = 5;     // läuft gerade

  { Spalten der Dateiliste (SubItems):
      0 = Status (sichtbar)          1 = voller Pfad (sichtbar)
      2 = Basisordner (unsichtbar)   3 = Länge in ms (unsichtbar, -1 = unbekannt)
      4 = fertige Stem-Datei (unsichtbar, erst nach der Umwandlung vorhanden) }

function ItemState(Item: TListItem): Integer;
begin
  Result := Integer(PtrInt(Item.Data));
end;

procedure SetState(Item: TListItem; St: Integer);
begin
  Item.Data := Pointer(PtrInt(St));
end;

{ ---------------------------------------------------------------------------
  Farben umrechnen

  Lazarus speichert Farben als TColor im Format $00BBGGRR (Blau zuerst!).
  Traktor erwartet aber '#RRGGBB' wie im Web. Diese zwei Funktionen
  rechnen hin und her.
  --------------------------------------------------------------------------- }
function ColorToHex(C: TColor): string;
var
  RGB: LongInt;
begin
  RGB := ColorToRGB(C);            // Systemfarben (clBtnFace ...) auflösen
  Result := Format('#%.2X%.2X%.2X', [RGB and $FF, (RGB shr 8) and $FF,
    (RGB shr 16) and $FF]);
end;

function HexToColor(const S: string; Def: TColor): TColor;
var
  V: LongInt;
begin
  Result := Def;                   // bei ungültigem Text: Standardfarbe
  if (Length(S) = 7) and (S[1] = '#') and TryStrToInt('$' + Copy(S, 2, 6), V) then
    Result := TColor(((V shr 16) and $FF) or (V and $FF00) or ((V and $FF) shl 16));
end;

{ ---------------------------------------------------------------------------
  Zeit schön formatieren: Millisekunden -> "4:07" bzw. "1:02:33"
  --------------------------------------------------------------------------- }
function FormatDuration(MS: QWord): string;
var
  Sec: QWord;
begin
  Sec := MS div 1000;
  if Sec >= 3600 then
    Result := Format('%d:%.2d:%.2d', [Sec div 3600, (Sec mod 3600) div 60, Sec mod 60])
  else
    Result := Format('%d:%.2d', [Sec div 60, Sec mod 60]);
end;

{ ---------------------------------------------------------------------------
  TStemWorker
  --------------------------------------------------------------------------- }
constructor TStemWorker.Create(AForm: TfrmMain; const ASettings: TStemSettings);
begin
  inherited Create(True);          // True = erst mit Start loslaufen
  FreeOnTerminate := False;
  FForm := AForm;
  FSettings := ASettings;
  FFiles := TStringList.Create;
  FOutFiles := TStringList.Create;
  InitCriticalSection(FLock);
end;

destructor TStemWorker.Destroy;
begin
  FFiles.Free;
  FOutFiles.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

{ eine Datei in die Warteschlange stellen }
procedure TStemWorker.AddFile(const FileName, OutFile: string; ListIndex: Integer);
begin
  FFiles.Add(FileName);
  FOutFiles.Add(OutFile);
  SetLength(FIndexes, Length(FIndexes) + 1);
  FIndexes[High(FIndexes)] := ListIndex;
end;

{ Abbrechen: wird aus dem Hauptthread aufgerufen. FJob wird gleichzeitig
  vom Worker-Thread gesetzt/gelöscht - deshalb die "kritische Sektion",
  damit nie beide Threads gleichzeitig darauf zugreifen. }
procedure TStemWorker.Cancel;
begin
  EnterCriticalSection(FLock);
  try
    FCancelled := True;
    if FJob <> nil then
      FJob.Cancel;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{ Protokollzeile vom Job -> ans Fenster weiterreichen }
procedure TStemWorker.JobLog(const Msg: string);
begin
  FSyncMsg := Msg;
  Synchronize(@SyncLog);
end;

{ Fortschritt vom Job -> ans Fenster weiterreichen.
  Nur bei Änderung, sonst würde das Fenster unnötig oft neu gezeichnet. }
procedure TStemWorker.JobProgress(Percent: Integer; const Stage: string);
begin
  if (Percent = FLastPct) and (Stage = FSyncStage) then
    Exit;
  FLastPct := Percent;
  FSyncPct := Percent;
  FSyncStage := Stage;
  Synchronize(@SyncProgress);
end;

{ die Sync...-Methoden laufen im Hauptthread (über Synchronize) }
procedure TStemWorker.SyncLog;
begin
  FForm.AddLog(FSyncMsg);
end;

procedure TStemWorker.SyncProgress;
begin
  FForm.SetFileProgress(FSyncPct, FSyncStage);
end;

procedure TStemWorker.SyncStatus;
begin
  { zuerst die Zieldatei merken - SetItemStatus kann sie schon brauchen }
  if FSyncOut <> '' then
    FForm.SetItemOutFile(FSyncItem, FSyncOut);
  FForm.FItemTurbo := FSyncTurbo;
  FForm.SetItemStatus(FSyncItem, FSyncStatus, FSyncDone);
end;

{ Hauptschleife des Threads: Datei für Datei umwandeln.
  Das Ganze steckt in try/except: Ein Fehler im Hintergrund-Thread würde
  sonst still verschluckt. So landet er mit Aufrufkette im Log. }
procedure TStemWorker.Execute;
var
  I: Integer;
  OutF, Err: string;
  Job: TStemJob;
  OK, WasSkipped: Boolean;
  FileSettings: TStemSettings;
begin
  try
  for I := 0 to FFiles.Count - 1 do
  begin
    if FCancelled or Terminated then
      Break;

    { Status in der Liste auf "läuft..." setzen }
    FSyncItem := FIndexes[I];
    FSyncStatus := isRunning;
    FSyncDone := I;
    FSyncOut := '';
    Synchronize(@SyncStatus);

    { Einstellungen für DIESE Datei: der Zielname steht schon fest
      (TfrmMain.PlannedOutFiles - Ordner, Unterordner, eindeutige Namen).
      TStemJob legt fehlende Ordner selbst an. }
    FileSettings := FSettings;
    FileSettings.OutFile := FOutFiles[I];

    { neuen Job anlegen und merken (für Cancel) }
    Job := TStemJob.Create(FileSettings);
    EnterCriticalSection(FLock);
    FJob := Job;
    LeaveCriticalSection(FLock);
    try
      Job.OnLog := @JobLog;
      Job.OnProgress := @JobProgress;
      FLastPct := -1;
      OK := Job.Run(FFiles[I], OutF, Err);      // <- hier passiert die Arbeit
      WasSkipped := Job.Skipped;
      if Job.PeakMemMB > MaxPeakMemMB then
        MaxPeakMemMB := Job.PeakMemMB;
      OmpPerPart := Job.OmpThreadsPublic;
      FSyncTurbo := Job.UsedTurbo;
      if OK and not WasSkipped then
        if Job.UsedTurbo then
        begin
          Inc(TurboCount);
          TurboDev := Job.TurboDevName;
        end
        else
          Inc(ClassicCount);
    finally
      EnterCriticalSection(FLock);
      FJob := nil;
      LeaveCriticalSection(FLock);
      Job.Free;
    end;

    { Ergebnis in der Liste anzeigen und zählen }
    if OK then
    begin
      Inc(OKCount);
      FSyncStatus := isOK;
    end
    else if WasSkipped then
    begin
      Inc(SkipCount);
      FSyncStatus := isSkipped;
    end
    else
    begin
      { Abbruch erkennen: am eigenen Flag und - falls uStemJob den Text
        übersetzt - sowohl am deutschen als auch am übersetzten Text.
        Ein Abbruch ist kein Fehler und wird deshalb extra gezählt. }
      if FCancelled or (Err = 'Abgebrochen') or (Err = _('Abgebrochen')) then
      begin
        Inc(CancelCount);
        FSyncStatus := isCancelled;
      end
      else
      begin
        Inc(FailCount);
        FSyncStatus := isFailed;
      end;
    end;
    FSyncItem := FIndexes[I];
    FSyncDone := I + 1;
    { Name der Stem-Datei mitgeben (auch bei "existiert schon" - die Datei
      gibt es ja), damit "Anhören" und "Ordner öffnen" sie finden }
    if OK or WasSkipped then
      FSyncOut := OutF
    else
      FSyncOut := '';
    Synchronize(@SyncStatus);
    FSyncOut := '';
  end;
  except
    on E: Exception do
    begin
      LogMarkError;
      LogLine('!!! FEHLER im Hintergrund-Thread: ' + E.ClassName + ': ' + E.Message);
      LogLine('    Aufrufkette:' + LineEnding + ExceptionStackText);
      FSyncMsg := Format(_('FEHLER im Hintergrund: %s (Details im Log)'), [E.Message]);
      Synchronize(@SyncLog);
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  TfrmMain - Start und Ende
  --------------------------------------------------------------------------- }
procedure TfrmMain.FormCreate(Sender: TObject);
var
  M: TStemModel;
  I: Integer;
begin
  TranslateComponent(Self);   // Texte aus umain.lfm übersetzen (uLangUI)
  { Dialog-Titel und Dateifilter werden von TranslateComponent nicht
    erfasst - deshalb hier (gleicher Inhalt wie in umain.lfm) }
  dlgOpen.Title := _('Audiodateien wählen');
  dlgOpen.Filter := 'Audio (*.mp3;*.wav;*.flac;*.aif;*.aiff;*.m4a;*.aac;*.ogg;*.opus)|' +
    '*.mp3;*.wav;*.wave;*.flac;*.aif;*.aiff;*.m4a;*.aac;*.ogg;*.opus|MP3 (*.mp3)|*.mp3|' +
    _('Alle Dateien') + '|*.*';
  dlgFolder.Title := _('Ordner mit Audiodateien wählen');

  Caption := Format(_('%s %s  -  Traktor Stems (*.stem.mp4) aus Audiodateien'),
    [APP_NAME, APP_VERSION]);

  { Modell-Auswahl füllen (Texte kommen aus uStemJob) }
  cbModel.Items.Clear;
  for M := Low(TStemModel) to High(TStemModel) do
    cbModel.Items.Add(StemModelDisplayName(M));
  cbModel.ItemIndex := 0;
  cbFormat.ItemIndex := 0;
  LoadGearGlyph(btnSettings);      // Zahnrad-Symbol (uSettings)

  FIniName := StemIniFileName;
  LoadSettings;
  SetupTray;
  UpdateToolStatus;
  SetRunning(False);
  AddLog(Format(_('%s %s - bereit. Dateien hinzufügen oder ins Fenster ziehen.'),
    [APP_NAME, APP_VERSION]));
  { versteckte Test-Schalter (nur für Entwicklung/Support):
      --test-fehler   löst einen Fehler aus -> Log-Name "_FEHLER" + Aufrufkette
      --test-absturz  beendet das Programm hart -> nächster Start "_ABSTURZ" }
  if Application.HasOption('test-fehler') then
    Application.QueueAsyncCall(@TestError, 0);
  if Application.HasOption('test-absturz') then
    Application.QueueAsyncCall(@TestCrash, 0);
  ReportAppVersion := APP_VERSION;   // für den Kopf des Fehlerberichts
  { nach einem Absturz einmal fragen, ob ein Fehlerbericht gesendet werden soll }
  if LogLastCrashFile <> '' then
    Application.QueueAsyncCall(@OfferCrashReport, 0);
  if LogCrashesFound > 0 then
    if LogCrashesFound = 1 then
      AddLog(_('Hinweis: Der letzte Lauf wurde unerwartet beendet - Details im ' +
        'Log mit "_ABSTURZ" im Namen (Info -> Logs-Ordner öffnen).'))
    else
      AddLog(Format(_('Hinweis: %d frühere Läufe wurden unerwartet beendet - Details ' +
        'in den Logs mit "_ABSTURZ" im Namen (Info -> Logs-Ordner öffnen).'),
        [LogCrashesFound]));

  { Liste vom letzten Mal wiederherstellen (falls StemMaker abgestürzt
    ist oder mit offener Liste beendet wurde) }
  FCurIndex := -1;
  RestoreQueue;

  { Dateien, die beim Start übergeben wurden (z.B. auf StemMaker.exe
    gezogen oder über "Senden an") gleich in die Liste übernehmen }
  for I := 1 to ParamCount do
    if FileExists(ParamStr(I)) or DirectoryExists(ParamStr(I)) then
      AddInput(ParamStr(I));

  { Update-Prüfung im Hintergrund (max. 5 s, abschaltbar, siehe uUpdateUI) }
  StartUpdateCheck(APP_VERSION, @UpdateFound);
  { Turbo-Vortest beim ersten Start (oder nach neuer Grafikkarte/Treiber) }
  Application.QueueAsyncCall(@CheckTurboTest, 0);
end;

{ Beim ersten Start mit Turbo einmal messen, wie schnell dieser PC ist und
  ob die Grafikkarte mitmacht (uTurboTest). Danach nur noch, wenn sich
  Grafikkarte oder Treiber geändert haben. }
procedure TfrmMain.CheckTurboTest(Data: PtrInt);
var
  Reason: string;
begin
  if FWorker <> nil then Exit;     // läuft schon etwas: nicht stören
  if not TurboTestNeeded(CurrentSettings, Reason) then Exit;
  LogLine('Turbo-Vortest nötig: ' + Reason);
  ShowTurboTest(CurrentSettings);
  UpdateEstimate;                  // Zeitschätzung mit dem neuen Tempo
end;

{ ---------------------------------------------------------------------------
  Update gefunden (aus uUpdateUI, im Hauptthread). Nie während einer
  Umwandlung anbieten - dann erst in WorkerDone.
  --------------------------------------------------------------------------- }
procedure TfrmMain.UpdateFound(const Info: TUpdateInfo);
begin
  FUpdate := Info;
  FUpdate.ModelHashes := nil;      // gehört uUpdateUI und wird dort freigegeben
  FHasUpdate := True;
  if FWorker = nil then
    Application.QueueAsyncCall(@OfferUpdate, 0)
  else
    AddLog(Format(_('StemMaker %s ist verfügbar - das Update wird nach der ' +
      'Umwandlung angeboten.'), [Info.Version]));
end;

procedure TfrmMain.OfferUpdate(Data: PtrInt);
begin
  if (not FHasUpdate) or (FWorker <> nil) then
    Exit;
  FHasUpdate := False;
  if ShowUpdateDialog(FUpdate, APP_VERSION) then
    Close;                         // neuer StemMaker wartet schon (--nach-update)
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  CancelUpdateCheck;
  StopProbe;
  SaveQueueNow;      // letzter Stand der Liste
  EndPower;          // falls noch etwas umgestellt ist: zurückstellen
  SaveSettings;
  LogLine('Hauptfenster wird geschlossen');
end;

{ ---------------------------------------------------------------------------
  Info und Log kopieren
  --------------------------------------------------------------------------- }
procedure TfrmMain.TestError(Data: PtrInt);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('x');
    LogLine('Test: greife absichtlich auf Zeile 5 einer Liste mit 1 Zeile zu');
    AddLog(L[5]);                  // -> EStringListError
  finally
    L.Free;
  end;
end;

procedure TfrmMain.TestCrash(Data: PtrInt);
begin
  LogLine('Test: Programm wird jetzt hart beendet (simulierter Absturz)');
  {$IFDEF WINDOWS}
  TerminateProcess(GetCurrentProcess, 99);   // wie Task-Manager "Task beenden"
  {$ELSE}
  Halt(99);
  {$ENDIF}
end;

{ Beim Start ein "_ABSTURZ"-Log gefunden: Fehlerbericht anbieten.
  Nur eine Frage - gesendet wird erst im Fenster "Fehlerbericht senden",
  und auch dort nur, wenn der Nutzer selbst auf Mail/GitHub klickt. }
procedure TfrmMain.OfferCrashReport(Data: PtrInt);
begin
  if QuestionDlg(_('Unerwartet beendet'),
    _('StemMaker wurde beim letzten Mal unerwartet beendet.') + LineEnding +
    LineEnding + _('Möchtest du Elospeed einen Fehlerbericht schicken? Du siehst ' +
    'den Bericht vorher, es wird nichts automatisch gesendet.'), mtInformation,
    [mrYes, _('Bericht ansehen...'), mrNo, _('Nein, danke'), 'IsDefault'], 0) = mrYes then
    ShowErrorReport(LogLastCrashFile, _('Programm wurde unerwartet beendet'));
end;

procedure TfrmMain.btnInfoClick(Sender: TObject);
begin
  ShowInfoDialog(APP_VERSION, APP_AUTHOR, @UpdateFound);
end;

procedure TfrmMain.btnCopyLogClick(Sender: TObject);
begin
  Clipboard.AsText := memLog.Text;
  { kurze Bestätigung in der Titelzeile des Buttons }
  btnCopyLog.Caption := _('Kopiert ✓');
  Application.ProcessMessages;
  Sleep(700);
  btnCopyLog.Caption := _('Log kopieren');
end;

{ Beim Schließen: läuft noch eine Umwandlung, erst nachfragen }
procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FWorker <> nil then
  begin
    CanClose := MessageDlg(_('Konvertierung läuft'),
      _('Die Konvertierung läuft noch. Abbrechen und beenden?'),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
    if CanClose then
    begin
      FWorker.OnTerminate := nil;  // WorkerDone soll nicht mehr kommen
      FWorker.Cancel;
      FWorker.WaitFor;             // warten bis demucs/ffmpeg beendet sind
      FreeAndNil(FWorker);
      EndPower;                    // Schlafsperre/Energieplan zurückstellen
    end;
  end;
  if CanClose then
    StopProbe;                     // Längen-Abfrage im Hintergrund beenden
end;

{ ---------------------------------------------------------------------------
  Einstellungen laden / speichern (StemMaker.ini)
  --------------------------------------------------------------------------- }
procedure TfrmMain.LoadSettings;
var
  Ini: TIniFile;
  D: TStemSettings;
  I: Integer;
begin
  D := DefaultStemSettings;
  FPrefs := DefaultStemPrefs;
  { Engine steht in [Turbo] und wird vom Einstellungs-Fenster selbst
    gespeichert (uStemJob.SaveTurboSettings), hier nur für die Anzeige }
  LoadTurboSettings(D);
  FPrefs.Engine := D.Engine;
  FPrefs.TurboDevice := D.TurboDevice;
  Ini := TIniFile.Create(FIniName);
  try
    edtOut.Directory := Ini.ReadString('Main', 'OutputDir', '');
    chkBeside.Checked := Ini.ReadBool('Main', 'BesideInput', edtOut.Directory = '');
    cbModel.ItemIndex := Ini.ReadInteger('Main', 'Model', 0);
    if cbModel.ItemIndex < 0 then cbModel.ItemIndex := 0;
    { "FormatV2": ab 1.5 gibt es "AAC automatisch" als ersten Eintrag.
      Der alte Schlüssel "Format" hatte eine andere Reihenfolge und wird
      deshalb nicht mehr gelesen - alle starten mit "automatisch". }
    cbFormat.ItemIndex := Ini.ReadInteger('Main', 'FormatV2', 0);
    if cbFormat.ItemIndex < 0 then cbFormat.ItemIndex := 0;
    FPrefs.Threads := Ini.ReadInteger('Main', 'Threads', D.Threads);
    { "Auto" ist Standard: dann wird bei JEDEM Start neu für den aktuellen
      Rechner gerechnet (wichtig, wenn der Ordner auf einen anderen PC
      kopiert wird) }
    FPrefs.ThreadsAuto := Ini.ReadBool('Main', 'ThreadsAuto', True);
    FPrefs.Overwrite := Ini.ReadBool('Main', 'Overwrite', False);
    FPrefs.KeepTree := Ini.ReadBool('Main', 'KeepTree', True);
    FPrefs.KeepAwake := Ini.ReadBool('Main', 'KeepAwake', True);
    { Symbol neben der Uhr (ab 1.7.1) }
    FPrefs.TrayMinimize := Ini.ReadBool('Main', 'TrayMinimize', False);
    FPrefs.TrayNotify := Ini.ReadBool('Main', 'TrayNotify', True);
    { Klang-Optionen (ab 1.7), Standard an }
    chkNormalize.Checked := Ini.ReadBool('Main', 'Normalize', D.Normalize);
    chkBassFix.Checked := Ini.ReadBool('Main', 'BassFix', D.BassFix);
    { ab 1.7: nach der Umwandlung den Ordner zeigen (Standard an) }
    chkOpenWhenDone.Checked := Ini.ReadBool('Main', 'OpenWhenDone', True);
    for I := 0 to 3 do
    begin
      FPrefs.StemNames[I] := Ini.ReadString('Stems', 'Name' + IntToStr(I + 1), D.Stems[I].Name);
      FPrefs.StemColors[I] := HexToColor(
        Ini.ReadString('Stems', 'Color' + IntToStr(I + 1), D.Stems[I].Color),
        HexToColor(D.Stems[I].Color, clBlack));
    end;
    { Werkzeug-Pfade: normalerweise tools\ und models\ neben der Exe.
      Wer ein vorhandenes ffmpeg nutzen will, kann das in der INI ändern. }
    FToolFFmpeg := Ini.ReadString('Tools', 'FFmpeg', D.FFmpegExe);
    FToolDemucs := Ini.ReadString('Tools', 'DemucsDir', D.DemucsDir);
    FToolModels := Ini.ReadString('Tools', 'ModelsDir', D.ModelsDir);
    Width  := Ini.ReadInteger('Window', 'Width', Width);
    Height := Ini.ReadInteger('Window', 'Height', Height);
  finally
    Ini.Free;
  end;
  { "Auto": Teile passend zu diesem PC neu ausrechnen }
  if FPrefs.ThreadsAuto then
    FPrefs.Threads := AutoThreads;
  if FPrefs.Threads < 1 then
    FPrefs.Threads := 1;
  chkBesideChange(nil);
end;

procedure TfrmMain.SaveSettings;
var
  Ini: TIniFile;
  S: TStemSettings;
  I: Integer;
begin
  S := CurrentSettings;
  try
    Ini := TIniFile.Create(FIniName);
    try
      Ini.WriteString('Main', 'OutputDir', edtOut.Directory);
      Ini.WriteBool('Main', 'BesideInput', chkBeside.Checked);
      Ini.WriteInteger('Main', 'Model', cbModel.ItemIndex);
      Ini.WriteInteger('Main', 'FormatV2', cbFormat.ItemIndex);
      Ini.WriteInteger('Main', 'Threads', FPrefs.Threads);
      Ini.WriteBool('Main', 'ThreadsAuto', FPrefs.ThreadsAuto);
      Ini.WriteBool('Main', 'Overwrite', FPrefs.Overwrite);
      Ini.WriteBool('Main', 'KeepTree', FPrefs.KeepTree);
      Ini.WriteBool('Main', 'KeepAwake', FPrefs.KeepAwake);
      Ini.WriteBool('Main', 'TrayMinimize', FPrefs.TrayMinimize);
      Ini.WriteBool('Main', 'TrayNotify', FPrefs.TrayNotify);
      Ini.WriteBool('Main', 'Normalize', chkNormalize.Checked);
      Ini.WriteBool('Main', 'BassFix', chkBassFix.Checked);
      Ini.WriteBool('Main', 'OpenWhenDone', chkOpenWhenDone.Checked);
      for I := 0 to 3 do
      begin
        Ini.WriteString('Stems', 'Name' + IntToStr(I + 1), S.Stems[I].Name);
        Ini.WriteString('Stems', 'Color' + IntToStr(I + 1), S.Stems[I].Color);
      end;
      Ini.WriteString('Tools', 'FFmpeg', FToolFFmpeg);
      Ini.WriteString('Tools', 'DemucsDir', FToolDemucs);
      Ini.WriteString('Tools', 'ModelsDir', FToolModels);
      Ini.WriteInteger('Window', 'Width', Width);
      Ini.WriteInteger('Window', 'Height', Height);
    finally
      Ini.Free;
    end;
  except
    { Einstellungen sind nicht lebenswichtig - wenn das Speichern nicht
      klappt (z.B. schreibgeschützt), einfach weitermachen }
  end;
end;

{ Sammelt alle Einstellungen aus dem Fenster in einen TStemSettings-Record }
function TfrmMain.CurrentSettings: TStemSettings;
var
  I: Integer;
begin
  Result := DefaultStemSettings;
  LoadTurboSettings(Result);       // Engine (Turbo/Klassisch) aus [Turbo]
  Result.FFmpegExe := FToolFFmpeg;
  Result.DemucsDir := FToolDemucs;
  Result.ModelsDir := FToolModels;
  if chkBeside.Checked then
    Result.OutputDir := ''                        // neben der Originaldatei
  else
    Result.OutputDir := edtOut.Directory;
  Result.Model := TStemModel(cbModel.ItemIndex);
  Result.Threads := FPrefs.Threads;
  { 0 = AAC automatisch, 1 = AAC 256, 2 = AAC 320, 3 = ALAC }
  Result.AACAuto := False;
  case cbFormat.ItemIndex of
    1: begin Result.Codec := scAAC; Result.AACBitrate := 256; end;
    2: begin Result.Codec := scAAC; Result.AACBitrate := 320; end;
    3: Result.Codec := scALAC;
  else
    begin Result.Codec := scAAC; Result.AACBitrate := 320; Result.AACAuto := True; end;
  end;
  Result.Overwrite := FPrefs.Overwrite;
  Result.Normalize := chkNormalize.Checked;
  Result.BassFix := chkBassFix.Checked;
  for I := 0 to 3 do
  begin
    Result.Stems[I].Name := Trim(FPrefs.StemNames[I]);
    Result.Stems[I].Color := ColorToHex(FPrefs.StemColors[I]);
  end;
end;

{ grüne/rote Statuszeile unter den Einstellungen aktualisieren }
procedure TfrmMain.UpdateToolStatus;
var
  Job: TStemJob;
  Problems: string;
begin
  Job := TStemJob.Create(CurrentSettings);
  try
    if Job.CheckTools(Problems) then
    begin
      if TurboFor(CurrentSettings) then
        lblTools.Caption := _('Tools: ffmpeg, Turbo, demucs.cpp und Modell gefunden')
      else
        lblTools.Caption := _('Tools: ffmpeg, demucs.cpp und Modell gefunden');
      lblTools.Font.Color := clGreen;
      lblTools.Hint := '';
    end
    else
    begin
      lblTools.Caption := Format(_('Fehlt: %s'), [StringReplace(Trim(Problems),
        LineEnding, '  |  ', [rfReplaceAll])]);
      lblTools.Font.Color := clRed;
      lblTools.Hint := Trim(Problems);
    end;
  finally
    Job.Free;
  end;
end;

{ Modell gewechselt: fehlen dafür Dateien, bieten wir den Download an
  (über das gleiche Prüffenster wie beim Programmstart) }
procedure TfrmMain.cbModelChange(Sender: TObject);
var
  Job: TStemJob;
  Problems: string;
  Missing: Boolean;
begin
  Job := TStemJob.Create(CurrentSettings);
  try
    Missing := not Job.CheckTools(Problems);
  finally
    Job.Free;
  end;
  if Missing and (MessageDlg(_('Modell nicht installiert'),
    Format(_('Für "%s" fehlen noch Dateien.'), [cbModel.Text]) + LineEnding +
    _('Jetzt herunterladen?'), mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
    RunStartupCheck(TStemModel(cbModel.ItemIndex), False);
  UpdateToolStatus;
  UpdateEstimate;                  // anderes Modell = andere Dauer
end;

{ Zahnrad "Weitere Einstellungen...": Fenster aus uSettings zeigen.
  Bei OK sofort in StemMaker.ini speichern (falls StemMaker später
  abstürzt, ist die Änderung trotzdem da). }
procedure TfrmMain.btnSettingsClick(Sender: TObject);
begin
  if ShowSettingsDialog(FPrefs, chkBeside.Checked, FToolFFmpeg, FToolDemucs,
    FToolModels) then
  begin
    SaveSettings;
    UpdateToolStatus;              // Engine kann sich geändert haben
    UpdateEstimate;                // andere Teile-Zahl oder Engine = andere Dauer
    pbAccent.Invalidate;           // Stem-Farben können sich geändert haben
    lvFiles.Invalidate;
  end;
end;

procedure TfrmMain.chkBesideChange(Sender: TObject);
begin
  { "neben Originaldatei" an -> Ausgabeordner-Feld ausgrauen }
  edtOut.Enabled := not chkBeside.Checked;
end;

{ ---------------------------------------------------------------------------
  Anzeige (wird vom Worker über Synchronize aufgerufen)
  --------------------------------------------------------------------------- }
procedure TfrmMain.AddLog(const Msg: string);
begin
  LogLine(Msg);                    // gleichzeitig in die Log-Datei (sofort)
  memLog.Lines.Add(Msg);
  memLog.SelStart := Length(memLog.Text);   // ans Ende scrollen
end;

{ Fortschritt der aktuellen Datei (vom Worker gemeldet).
  Der Gesamtbalken setzt sich zusammen aus "fertige Dateien" + "Anteil der
  aktuellen Datei". Beispiel: 5 Dateien, 2 fertig, aktuelle bei 50 %
  -> (2*100 + 50) / 5 = 50 % gesamt. }
procedure TfrmMain.SetFileProgress(Percent: Integer; const Stage: string);
var
  S: string;
begin
  { neuer Arbeitsschritt? -> Startzeit und Startprozent merken (für die
    Restzeit-Schätzung, siehe UpdateTimes) }
  if Stage <> FStageName then
  begin
    FStageName := Stage;
    FStageT0 := GetTickCount64;
    FStagePct0 := Percent;
  end;
  FFilePct := Percent;
  pbFile.Position := Percent;
  { Prozent auch in die Zeile der Liste schreiben. Gezeichnet wird dort ein
    kleiner Balken (lvFilesCustomDrawSubItem); der Text ändert sich nur, damit
    die Zeile neu gezeichnet wird, und bleibt für Bildschirmleser lesbar. }
  if (FCurIndex >= 0) and (FCurIndex < lvFiles.Items.Count) and
     (ItemState(lvFiles.Items[FCurIndex]) = ST_RUN) then
  begin
    S := Format('%s %d %%', [_('läuft...'), Percent]);
    if lvFiles.Items[FCurIndex].SubItems[0] <> S then
      lvFiles.Items[FCurIndex].SubItems[0] := S;
  end;
  lblStage.Caption := Format('%s  (%d %%)', [Stage, Percent]);
  if FTotal > 0 then
    pbTotal.Position := Round((FFilesDone * 100 + Percent) / FTotal);
  UpdateTimes;
  TrayProgress;
end;

{ Status einer Datei in der Liste setzen ("läuft...", "OK", "Fehler", ...).
  Done = Anzahl Dateien, die jetzt fertig sind. }
procedure TfrmMain.SetItemStatus(Index: Integer; Status: TItemState; Done: Integer);
var
  S, Dur: string;
begin
  case Status of
    isRunning:
      begin
        S := _('läuft...');
        FCurIndex := Index;
        { neue Datei beginnt -> Stoppuhr für die Datei neu starten }
        FFileStart := GetTickCount64;
        FFilePct := 0;
        FStageName := '';          // Schritt-Tempo für die neue Datei neu messen
      end;
    isOK:
      begin
        { fertig -> benötigte Zeit merken und anzeigen }
        Dur := FormatDuration(GetTickCount64 - FFileStart);
        S := Format(_('OK (%s)'), [Dur]);
        Inc(FOKTimeMS, GetTickCount64 - FFileStart);   // für die Gesamt-Schätzung
        Inc(FOKCount);
        { Tempo lernen: wie lange pro Minute Musik? (für künftige Schätzungen) }
        if ItemDurMS(Index) > 0 then
        begin
          Inc(FOKAudioMS, ItemDurMS(Index));
          { nach dem Tempo der Engine, die wirklich getrennt hat (Rückfall = demucs.cpp) }
          SpeedLearn(FIniName, FRunSettings.Model, FItemTurbo,
            GetTickCount64 - FFileStart, ItemDurMS(Index));
        end;
        AddLog(Format(_('  Dauer: %s'), [Dur]));
        { für "Ordner nach der Umwandlung öffnen" und "Anhören" }
        FLastOutFile := ItemOutFile(Index);
      end;
    isSkipped:   S := _('existiert schon');
    isCancelled: S := _('abgebrochen');
  else
    S := _('Fehler');
  end;
  if (Index >= 0) and (Index < lvFiles.Items.Count) then
  begin
    { Zustand im Data-Feld der Zeile merken (nicht am Text erkennen,
      der ist je nach Sprache anders) - siehe btnStartClick / SaveQueueNow }
    case Status of
      isRunning:   SetState(lvFiles.Items[Index], ST_RUN);
      isOK:        SetState(lvFiles.Items[Index], ST_OK);
      isSkipped:   SetState(lvFiles.Items[Index], ST_SKIP);
      isCancelled: SetState(lvFiles.Items[Index], ST_CANCEL);
    else
      SetState(lvFiles.Items[Index], ST_FAIL);
    end;
    lvFiles.Items[Index].SubItems[0] := S;
    lvFiles.Items[Index].MakeVisible(False);  // Zeile ins Bild scrollen
  end;
  FFilesDone := Done;
  if FTotal > 0 then
    pbTotal.Position := Round(Done * 100 / FTotal);
  UpdateTimes;
  SaveQueueNow;                    // Stand sofort sichern (Absturz, Stromausfall)
end;

{ ---------------------------------------------------------------------------
  Zeitanzeige unter den Balken

    oberer Balken (aktuelle Datei):
      "Datei:  vergangen 2:13   |   verbleibend ca. 2:30"
    unterer Balken (alle Dateien):
      "Gesamt (Datei 2 von 5):  vergangen 8:40   |   verbleibend ca. 21:00"

  So wird geschätzt (Einzelheiten bei den Kommentaren unten):
    - aktuelle Datei: aus dem Tempo des laufenden Arbeitsschritts, oder
      solange es das noch nicht gibt, aus Song-Länge x gelerntem Tempo
    - Gesamt: Rest der aktuellen Datei + Länge aller wartenden Songs x
      Tempo. Sind noch nicht alle Längen bekannt, ersatzweise Anzahl
      wartender Dateien x durchschnittliche Dauer der fertigen Dateien.

  Wird bei jeder Fortschrittsmeldung UND jede Sekunde vom Timer
  aufgerufen - so läuft die Uhr auch weiter, wenn demucs gerade länger
  nichts meldet.
  --------------------------------------------------------------------------- }
procedure TfrmMain.UpdateTimes;
var
  Now64, FileMS, RunMS: QWord;
  FileTotalMS, FileRestMS, AvgMS, TotalRestMS: Double;
  StageMS: QWord;
  StageGain: Integer;
  Waiting, Current: Integer;
  FileRest, TotalRest: string;
  CanEstimate: Boolean;
  CurDur, WaitAudio: Int64;
  WaitUnknown, I: Integer;
  Rate: Double;
begin
  if FWorker = nil then
    Exit;                          // läuft nichts -> Anzeige stehen lassen
  Now64 := GetTickCount64;
  FileMS := Now64 - FFileStart;
  RunMS := Now64 - FRunStart;

  { --- aktuelle Datei ---
    Die Restzeit wird aus dem Tempo des AKTUELLEN Arbeitsschritts
    berechnet (z.B. "Stems trennen"), nicht aus dem ganzen Balken.
    Grund: Das Dekodieren füllt die ersten Prozent in einer Sekunde -
    würde man das mitrechnen, wäre die Schätzung am Anfang viel zu
    optimistisch (gesehen auf einem alten PC: angezeigt 1 h, real > 2 h).
    Tempo = gewonnene Prozent / Zeit seit Beginn des Schritts
    Rest  = fehlende Prozent / Tempo }
  StageMS := Now64 - FStageT0;
  StageGain := FFilePct - FStagePct0;
  CanEstimate := (StageMS >= 5000) and (StageGain >= 1);
  FileTotalMS := 0;
  FileRestMS := 0;
  { Länge der laufenden Datei und Tempo (ms Rechenzeit pro ms Musik) }
  CurDur := 0;
  if FCurIndex >= 0 then
    CurDur := ItemDurMS(FCurIndex);
  Rate := RateMsPerMs;
  if CanEstimate then
  begin
    FileRestMS := (100 - FFilePct) * (StageMS / StageGain);
    FileTotalMS := FileMS + FileRestMS;          // geschätzte Gesamtdauer der Datei
    FileRest := Format(_('ca. %s'), [FormatDuration(Round(FileRestMS))]);
  end
  else if CurDur > 0 then
  begin
    { noch kein eigenes Tempo für diese Datei: aus Song-Länge x Tempo }
    FileTotalMS := CurDur * Rate;
    FileRestMS := FileTotalMS - FileMS;
    if FileRestMS < 0 then FileRestMS := 0;
    CanEstimate := True;
    FileRest := Format(_('ca. %s'), [FormatDuration(Round(FileRestMS))]);
  end
  else
    FileRest := _('wird berechnet ...');
  lblFileTime.Caption := Format(_('Datei:  vergangen %s   |   verbleibend %s'),
    [FormatDuration(FileMS), FileRest]);

  { --- Gesamt ---
    Am genauesten: Länge aller wartenden Songs x Tempo. Das geht, sobald
    alle Längen bekannt sind (TDurationProber). Sonst wie früher:
    Anzahl wartender Dateien x durchschnittliche Dauer. }
  WaitAudio := 0;
  WaitUnknown := 0;
  for I := 0 to lvFiles.Items.Count - 1 do
    if ItemState(lvFiles.Items[I]) = ST_WAIT then
      if ItemDurMS(I) > 0 then
        Inc(WaitAudio, ItemDurMS(I))
      else
        Inc(WaitUnknown);
  Waiting := FTotal - FFilesDone - 1;            // Dateien NACH der aktuellen
  if Waiting < 0 then Waiting := 0;
  if FOKCount > 0 then
    AvgMS := FOKTimeMS / FOKCount                // Schnitt der fertigen Dateien
  else
    AvgMS := FileTotalMS;                        // noch keine fertig
  if CanEstimate and (WaitUnknown = 0) then
  begin
    TotalRestMS := FileRestMS + WaitAudio * Rate;
    TotalRest := Format(_('ca. %s'), [FormatDuration(Round(TotalRestMS))]);
  end
  else if CanEstimate or ((FOKCount > 0) and (FFilePct = 0)) then
  begin
    TotalRestMS := FileRestMS + Waiting * AvgMS;
    if (not CanEstimate) then                    // neue Datei hat gerade begonnen
      TotalRestMS := (Waiting + 1) * AvgMS;
    TotalRest := Format(_('ca. %s'), [FormatDuration(Round(TotalRestMS))]);
  end
  else
    TotalRest := _('wird berechnet ...');
  Current := FFilesDone + 1;
  if Current > FTotal then Current := FTotal;
  lblTotal.Caption := Format(_('Gesamt (Datei %d von %d):  vergangen %s   |   verbleibend %s'),
    [Current, FTotal, FormatDuration(RunMS), TotalRest]);
end;

procedure TfrmMain.tmrTimeTimer(Sender: TObject);
begin
  UpdateTimes;
end;

{ ---------------------------------------------------------------------------
  Dateiliste
  Spalten: Datei | Status | Pfad  (voller Pfad steht in SubItems[1])
  --------------------------------------------------------------------------- }
procedure TfrmMain.AddInput(const FileName: string; const Root: string);
var
  I: Integer;
  Item: TListItem;
begin
  if DirectoryExists(FileName) then
  begin
    AddFolder(FileName);           // Ordner -> alle Audiodateien darin
    Exit;
  end;
  if not IsSupportedInput(FileName) then
  begin
    AddLog(Format(_('Übersprungen (Format nicht unterstützt): %s'), [ExtractFileName(FileName)]));
    Exit;
  end;
  if Pos('.stem.', LowerCase(ExtractFileName(FileName))) > 0 then
    Exit;                          // ist schon eine Stem-Datei
  for I := 0 to lvFiles.Items.Count - 1 do
    if SameFileName(lvFiles.Items[I].SubItems[1], FileName) then
      Exit;                        // steht schon in der Liste
  Item := lvFiles.Items.Add;
  Item.Caption := ExtractFileName(FileName);
  Item.SubItems.Add(_('wartet'));
  Item.SubItems.Add(FileName);
  Item.SubItems.Add(Root);         // unsichtbar: Basisordner
  Item.SubItems.Add('');           // unsichtbar: Länge (kommt von TDurationProber)
  SetState(Item, ST_WAIT);
  ListChanged;
end;

{ alle Audiodateien eines Ordners inkl. Unterordner hinzufügen.
  Als Basisordner (für "Unterordner nachbauen") gilt der Ordner ÜBER dem
  hinzugefügten - so bleibt dessen Name erhalten:
    "D:\Musik\House" hinzugefügt -> Basis "D:\Musik"
    -> Ausgabe <Ausgabeordner>\House\2024\track.stem.mp4 }
procedure TfrmMain.AddFolder(const Dir: string);
var
  L: TStringList;
  I, Skipped: Integer;
  Root: string;
begin
  Root := ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
  L := FindAllFiles(Dir, '*.*', True);   // True = auch Unterordner
  try
    L.Sort;
    for I := 0 to L.Count - 1 do
      if IsSupportedInput(L[I]) then
        AddInput(L[I], Root);
  finally
    L.Free;
  end;
  { Ordner mit zu langem Pfad (über 259 Zeichen) kann Windows nicht
    auflisten. FindAllFiles überspringt sie still, die Musik darin fehlt
    dann ohne Hinweis in der Liste. Darum hier nachzählen und melden.
    Gemeldet wird nur der oberste zu lange Ordner, die Ordner darunter
    findet Windows ohnehin nicht. }
  Skipped := 0;
  if DirTooLongToList(Dir) then
  begin
    Inc(Skipped);
    AddLog(Format(_('Ordner übersprungen, Pfad zu lang: %s'), [Dir]));
  end
  else
  begin
    L := FindAllDirectories(Dir, True);
    try
      for I := 0 to L.Count - 1 do
        if DirTooLongToList(L[I]) then
        begin
          Inc(Skipped);
          AddLog(Format(_('Ordner übersprungen, Pfad zu lang: %s'), [L[I]]));
        end;
    finally
      L.Free;
    end;
  end;
  if Skipped > 0 then
    MessageDlg(Format(_('%d Ordner konnten nicht gelesen werden, weil ihr Pfad ' +
      'länger als %d Zeichen ist. Musik darin fehlt in der Liste.') + LineEnding +
      LineEnding + _('Abhilfe: den Ordner weiter oben ablegen (z. B. direkt unter ' +
      'D:\Musik) oder Ordnernamen kürzen. Die Ordner stehen im Log.'),
      [Skipped, MAX_PATH_CHARS]), mtWarning, [mbOK], 0);
end;

{ Drag & Drop aus dem Explorer (AllowDropFiles ist im Formular aktiv) }
procedure TfrmMain.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  I: Integer;
begin
  if FWorker <> nil then Exit;     // während der Arbeit nichts ändern
  lvFiles.BeginUpdate;
  try
    for I := Low(FileNames) to High(FileNames) do
      AddInput(FileNames[I]);
  finally
    lvFiles.EndUpdate;
  end;
end;

procedure TfrmMain.btnAddFilesClick(Sender: TObject);
var
  I: Integer;
begin
  if dlgOpen.Execute then
  begin
    lvFiles.BeginUpdate;
    try
      for I := 0 to dlgOpen.Files.Count - 1 do
        AddInput(dlgOpen.Files[I]);
    finally
      lvFiles.EndUpdate;
    end;
  end;
end;

procedure TfrmMain.btnAddFolderClick(Sender: TObject);
begin
  if dlgFolder.Execute then
  begin
    lvFiles.BeginUpdate;
    try
      AddFolder(dlgFolder.FileName);
    finally
      lvFiles.EndUpdate;
    end;
  end;
end;

{ markierte Zeilen entfernen (von hinten nach vorne, sonst verrutschen
  die Nummern beim Löschen) }
procedure TfrmMain.btnRemoveClick(Sender: TObject);
var
  I: Integer;
begin
  for I := lvFiles.Items.Count - 1 downto 0 do
    if lvFiles.Items[I].Selected then
      lvFiles.Items.Delete(I);
  ListChanged;
end;

procedure TfrmMain.btnClearClick(Sender: TObject);
begin
  { nachfragen - die gespeicherte Warteschlange ist danach auch weg }
  if (lvFiles.Items.Count > 0) and (MessageDlg(
    Format(_('Alle %d Dateien aus der Liste entfernen?'), [lvFiles.Items.Count]) +
    LineEnding + _('Bereits erstellte Stem-Dateien bleiben erhalten.'),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  lvFiles.Items.Clear;
  QueueDelete;                     // gespeicherte Liste ebenfalls löschen
  lblTotal.Caption := '';
end;

{ "Stem prüfen...": zeigt Anzahl Spuren und die Stem-Infos einer Datei an }
procedure TfrmMain.btnCheckClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  J: string;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := _('Stem-Datei prüfen');
    Dlg.Filter := _('Stem-Dateien') + ' (*.stem.mp4;*.stem.m4a;*.mp4)|*.stem.mp4;*.stem.m4a;*.mp4|' +
      _('Alle Dateien') + '|*.*';
    if Dlg.Execute then
    try
      J := ReadStemJSON(Dlg.FileName);
      AddLog(Format(_('== Prüfung: %s'), [ExtractFileName(Dlg.FileName)]));
      AddLog(Format(_('  Audiospuren: %d (Stem = 5)'), [CountTracks(Dlg.FileName)]));
      if J = '' then
        AddLog(_('  KEIN Stem-Metadatenblock gefunden - keine gültige Stem-Datei'))
      else
        AddLog(Format(_('  Stem-Metadaten: %s'), [J]));
    except
      on E: Exception do
        AddLog(Format(_('  Fehler: %s'), [E.Message]));
    end;
  finally
    Dlg.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Fertige Stem-Dateien: Ordner zeigen und im StemPlayer anhören
  --------------------------------------------------------------------------- }

{ Wo liegt (bzw. landet) die Stem-Datei einer Zeile?
  Nach der Umwandlung steht der genaue Name in Spalte 4. Fehlt er (z.B.
  bei einer Liste vom letzten Mal), wird er wie in TStemWorker.Execute aus
  den aktuellen Einstellungen berechnet. }
function TfrmMain.ItemOutFile(Index: Integer): string;
var
  Item: TListItem;
begin
  Result := '';
  if (Index < 0) or (Index >= lvFiles.Items.Count) then Exit;
  Item := lvFiles.Items[Index];
  if (Item.SubItems.Count > 4) and (Item.SubItems[4] <> '') then
    Exit(Item.SubItems[4]);
  Result := PlannedOutFiles[Index];
end;

{ Ausgabeordner einer Zeile nach den aktuellen Einstellungen.
  "Unterordner nachbauen": Ausgabeordner + der Weg vom Basisordner zur
  Datei, z.B.
    Basis  D:\Musik\   Datei D:\Musik\House\2024\a.mp3
    Ausgabe E:\Stems\  ->  E:\Stems\House\2024\ }
function TfrmMain.ItemOutDir(Index: Integer): string;
var
  Item: TListItem;
  Root: string;
begin
  Item := lvFiles.Items[Index];
  if chkBeside.Checked then
    Result := ''                                  // neben der Originaldatei
  else
  begin
    Result := edtOut.Directory;
    Root := Item.SubItems[2];
    if FPrefs.KeepTree and (Result <> '') and (Root <> '') then
      Result := IncludeTrailingPathDelimiter(Result) +
        ExtractRelativePath(IncludeTrailingPathDelimiter(Root),
          ExtractFilePath(Item.SubItems[1]));
  end;
end;

{ Zielnamen ALLER Zeilen, in Listen-Reihenfolge eindeutig gemacht: Landen
  zwei Dateien auf demselben Namen (A\Intro.mp3 und B\Intro.mp3 in einem
  flachen Ausgabeordner, oder Song.mp3 + Song.wav nebeneinander), heisst
  die spätere "Intro (2).stem.mp4". Es wird immer über die ganze Liste
  gerechnet - auch über schon fertige Zeilen -, damit jede Datei nach
  Abbrechen und Fortsetzen wieder denselben Namen bekommt. }
function TfrmMain.PlannedOutFiles: TStringArray;
var
  Used: TStringList;
  I: Integer;
begin
  Result := nil;
  SetLength(Result, lvFiles.Items.Count);
  Used := NewUsedNameList;
  try
    for I := 0 to lvFiles.Items.Count - 1 do
      Result[I] := UniqueStemOutputName(lvFiles.Items[I].SubItems[1],
        ItemOutDir(I), Used);
  finally
    Used.Free;
  end;
end;

{ Fertige Stem-Datei einer Zeile merken (Spalte 4, siehe oben) }
procedure TfrmMain.SetItemOutFile(Index: Integer; const FileName: string);
var
  Item: TListItem;
begin
  if (Index < 0) or (Index >= lvFiles.Items.Count) then Exit;
  Item := lvFiles.Items[Index];
  while Item.SubItems.Count < 5 do
    Item.SubItems.Add('');
  Item.SubItems[4] := FileName;
end;

{ StemPlayer (AddOns\StemPlayer.exe) starten, auf Wunsch gleich mit einer
  Datei oder einem Ordner. StemMaker wartet NICHT auf den Player - beide
  laufen unabhängig weiter (auch während einer Umwandlung). }
procedure TfrmMain.OpenInPlayer(const StemFile: string);
var
  Exe: string;
  P: TProcessUTF8;
begin
  Exe := AppBaseDir + 'AddOns' + PathDelim + ExeName('StemPlayer');
  if not FileExists(Exe) then
  begin
    MessageDlg(Format(_('StemPlayer nicht gefunden:%s%s'), [LineEnding + LineEnding, Exe]),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := Exe;
    P.CurrentDirectory := ExtractFilePath(Exe);
    if StemFile <> '' then
      P.Parameters.Add(StemFile);  // Datei oder Ordner
    P.Options := [];               // nicht warten, keine Pipes (siehe Entwicklungslog)
    try
      P.Execute;
      if StemFile <> '' then
        LogLine('StemPlayer gestartet: ' + StemFile)
      else
        LogLine('StemPlayer gestartet (ohne Datei)');
    except
      on E: Exception do
        AddLog(Format(_('StemPlayer konnte nicht gestartet werden: %s'), [E.Message]));
    end;
  finally
    P.Free;                        // gibt nur unseren Zugriff frei, der Player läuft weiter
  end;
end;

{ Explorer öffnen und die Datei darin markieren - so kann man sie gleich
  in Traktor ziehen. Gibt es die Datei nicht, wird nur ihr Ordner geöffnet. }
procedure TfrmMain.ShowInExplorer(const FileName: string);
begin
  {$IFDEF WINDOWS}
  if FileExists(FileName) then
  begin
    { explorer.exe /select,"D:\Stems\Song.stem.mp4"
      Über ShellExecuteW (Unicode), damit Umlaute im Pfad stimmen. }
    ShellExecuteW(0, 'open', 'explorer.exe',
      PWideChar(UTF8Decode('/select,"' + FileName + '"')), nil, SW_SHOWNORMAL);
    Exit;
  end;
  {$ENDIF}
  if DirectoryExists(ExtractFilePath(FileName)) then
    OpenDocument(ExtractFilePath(FileName));
end;

{ "Ordner öffnen": Ist eine Zeile mit fertiger Stem-Datei markiert, wird
  genau diese Datei im Explorer gezeigt. Sonst der Ausgabeordner (bzw. bei
  "neben der Originaldatei" der Ordner der ersten Datei). }
procedure TfrmMain.btnOpenOutClick(Sender: TObject);
var
  F: string;
begin
  if lvFiles.Selected <> nil then
  begin
    F := ItemOutFile(lvFiles.Selected.Index);
    if FileExists(F) then
    begin
      ShowInExplorer(F);
      Exit;
    end;
  end;
  if (not chkBeside.Checked) and DirectoryExists(edtOut.Directory) then
    OpenDocument(edtOut.Directory)
  else if lvFiles.Items.Count > 0 then
    OpenDocument(ExtractFilePath(lvFiles.Items[0].SubItems[1]));
end;

{ "Anhören": StemPlayer starten, der Öffnen-Dialog zeigt gleich den Ordner
  der zuletzt umgewandelten Datei (Wunsch Speedy, 04.10.2026). Eine
  bestimmte Datei direkt öffnen: Doppelklick in der Liste.
  Welcher Ordner: zuletzt fertige Datei dieses Durchlaufs, sonst die
  unterste Zeile mit vorhandener Stem-Datei, sonst der Ausgabeordner. }
procedure TfrmMain.btnListenClick(Sender: TObject);
var
  I: Integer;
  F, Dir: string;
  Planned: TStringArray;
begin
  Dir := '';
  F := FLastOutFile;
  if not FileExists(F) then
  begin
    F := '';
    Planned := PlannedOutFiles;          // einmal für alle Zeilen rechnen
    for I := lvFiles.Items.Count - 1 downto 0 do
    begin
      if (lvFiles.Items[I].SubItems.Count > 4) and (lvFiles.Items[I].SubItems[4] <> '') then
        Planned[I] := lvFiles.Items[I].SubItems[4];
      if FileExists(Planned[I]) then
      begin
        F := Planned[I];
        Break;
      end;
    end;
  end;
  if F <> '' then
    Dir := ExtractFilePath(F)
  else if (not chkBeside.Checked) and DirectoryExists(edtOut.Directory) then
    Dir := edtOut.Directory;
  if Dir <> '' then
  begin
    { Ohne "\" am Ende übergeben: "D:\Stems\" in Anführungszeichen würde
      Windows als Zeichen " lesen. Laufwerk allein (D:\) -> "D:\." }
    if Length(ExcludeTrailingPathDelimiter(Dir)) <= 2 then
      Dir := IncludeTrailingPathDelimiter(Dir) + '.'
    else
      Dir := ExcludeTrailingPathDelimiter(Dir);
  end;
  OpenInPlayer(Dir);
end;

{ ---------------------------------------------------------------------------
  Farb-Akzente (Zeichnen selbst: uStatusDraw)
  --------------------------------------------------------------------------- }

{ Streifen in den vier Stem-Farben unter der Knopfleiste }
procedure TfrmMain.pbAccentPaint(Sender: TObject);
begin
  DrawAccentStrip(pbAccent.Canvas, pbAccent.ClientRect, FPrefs.StemColors);
end;

{ Spalte "Status" der Dateiliste selbst zeichnen (Balken, Häkchen, Farben).
  Alle anderen Spalten zeichnet Windows wie immer. }
procedure TfrmMain.lvFilesCustomDrawSubItem(Sender: TCustomListView;
  Item: TListItem; SubItem: Integer; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  R: TRect;
  Look: TStatusLook;
  Pct: Integer;
begin
  if SubItem <> 1 then Exit;       // 0 = Datei, 1 = Status, 2 = Pfad
  if Item.SubItems.Count = 0 then Exit;
  R := Item.DisplayRectSubItem(1, drBounds);
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;

  { Zustand steht im Data-Feld (nicht am Text erkennen, siehe ItemState) }
  Pct := 0;
  case ItemState(Item) of
    ST_WAIT: Look := slWait;
    ST_RUN:
      begin
        Look := slRun;
        if Item.Index = FCurIndex then Pct := FFilePct;
      end;
    ST_OK:   Look := slOK;
    ST_FAIL: Look := slFail;
  else
    Look := slOther;
  end;

  { Ausgewählte Zeilen zeichnet Windows selbst (blau hinterlegt, mit Text).
    Eigene Farbe auf dem blauen Hintergrund geht hier nicht zuverlässig:
    Windows legt die Auswahl nachträglich darüber und die Zelle wird weiss. }
  if Item.Selected and (lvFiles.Focused or not lvFiles.HideSelection) then Exit;

  Sender.Canvas.Font.Assign(lvFiles.Font);
  DrawStatusCell(Sender.Canvas, R, Look, Pct, Item.SubItems[0], FPrefs.StemColors,
    clWindow, clWindowText, False, Screen.PixelsPerInch);
  DefaultDraw := False;            // Windows soll diese Zelle nicht übermalen
end;

{ Doppelklick auf eine Zeile: fertige Stem-Datei gleich anhören }
procedure TfrmMain.lvFilesDblClick(Sender: TObject);
var
  F: string;
begin
  if lvFiles.Selected = nil then Exit;
  F := ItemOutFile(lvFiles.Selected.Index);
  if FileExists(F) then
    OpenInPlayer(F)
  else
    AddLog(Format(_('Noch keine Stem-Datei für "%s" - zuerst umwandeln.'),
      [lvFiles.Selected.Caption]));
end;

{ ---------------------------------------------------------------------------
  Start / Abbrechen / Ende
  --------------------------------------------------------------------------- }

{ Buttons und Einstellungen sperren, solange gearbeitet wird }
procedure TfrmMain.SetRunning(Running: Boolean);
begin
  btnStart.Enabled := not Running;
  btnCancel.Enabled := Running;
  btnAddFiles.Enabled := not Running;
  btnAddFolder.Enabled := not Running;
  btnRemove.Enabled := not Running;
  btnClear.Enabled := not Running;
  gbSettings.Enabled := not Running;
  if not Running then
  begin
    pbFile.Position := 0;
    lblStage.Caption := '';
  end;
end;

procedure TfrmMain.btnStartClick(Sender: TObject);
var
  S: TStemSettings;
  Job: TStemJob;
  Problems: string;
  I: Integer;
  Planned: TStringArray;
begin
  S := CurrentSettings;
  if (not chkBeside.Checked) and (Trim(edtOut.Directory) = '') then
  begin
    MessageDlg(_('Bitte einen Ausgabeordner wählen oder "neben Originaldatei" aktivieren.'),
      mtWarning, [mbOK], 0);
    Exit;
  end;

  { sind alle Werkzeuge da? Sonst das Prüffenster anbieten (mit Download) }
  Job := TStemJob.Create(S);
  try
    if not Job.CheckTools(Problems) then
    begin
      if MessageDlg(_('Es fehlen Programmteile:') + LineEnding + LineEnding + Problems +
        LineEnding + _('Jetzt prüfen und fehlende Dateien herunterladen?'),
        mtError, [mbYes, mbNo], 0) = mrYes then
      begin
        RunStartupCheck(S.Model, False);
        UpdateToolStatus;
      end;
      Exit;
    end;
  finally
    Job.Free;
  end;

  { Worker anlegen und alle noch nicht fertigen Dateien übergeben }
  FWorker := TStemWorker.Create(Self, S);
  Planned := PlannedOutFiles;            // Zielnamen, eindeutig (siehe dort)
  FTotal := 0;
  for I := 0 to lvFiles.Items.Count - 1 do
    if ItemState(lvFiles.Items[I]) <> ST_OK then   // alles ausser "fertig"
    begin
      FWorker.AddFile(lvFiles.Items[I].SubItems[1], Planned[I], I);
      SetState(lvFiles.Items[I], ST_WAIT);
      lvFiles.Items[I].SubItems[0] := _('wartet');
      Inc(FTotal);
    end;
  if FTotal = 0 then
  begin
    { alles schon erledigt (oder Liste leer) }
    if (lvFiles.Items.Count > 0) and (MessageDlg(
      _('Alle Dateien in der Liste sind bereits fertig. Nochmals konvertieren?'),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
    begin
      { "Nochmals" heisst: die vorhandenen Stem-Dateien neu erzeugen.
        Ohne "überschreiben" würde uStemJob sonst jede Datei als
        "existiert schon" überspringen. Deshalb nur für diesen Durchlauf
        mit Überschreiben einen neuen Worker anlegen (die gespeicherte
        Einstellung bleibt, wie sie ist). }
      FreeAndNil(FWorker);
      S.Overwrite := True;
      FWorker := TStemWorker.Create(Self, S);
      for I := 0 to lvFiles.Items.Count - 1 do
      begin
        FWorker.AddFile(lvFiles.Items[I].SubItems[1], Planned[I], I);
        SetState(lvFiles.Items[I], ST_WAIT);
        lvFiles.Items[I].SubItems[0] := _('wartet');
        Inc(FTotal);
      end;
    end
    else
    begin
      if lvFiles.Items.Count = 0 then
        MessageDlg(_('Die Liste ist leer - zuerst Dateien hinzufügen.'),
          mtInformation, [mbOK], 0);
      FreeAndNil(FWorker);
      Exit;
    end;
  end;

  SaveSettings;
  pbTotal.Position := 0;
  FRunSettings := S;
  LogLine(Format('=== Start: %d Datei(en), Modell %s, %d Teile ===',
    [FTotal, StemModelDisplayName(S.Model), S.Threads]));
  { Energie: Laptop auf Akku? -> nur Hinweis, ändern können wir das nicht }
  if PowerOnBattery then
    AddLog(Format(_('Hinweis: Der PC läuft auf Akku (%s). Windows ' +
      'bremst dann die CPU - am Netzteil geht es deutlich schneller.'), [PowerSourceText]));
  { Schlafsperre setzen und ggf. den Energiesparmodus aussetzen.
    Ist "PC wach halten" aus, wird nur gemessen (Standby-Erkennung). }
  FPower := PowerBeginRun(FPrefs.KeepAwake, FIniName);
  if FPower.SchemeSet then
    AddLog(Format(_('Energiesparplan "%s" vorübergehend auf "%s" ' +
      'gestellt - wird nach der Konvertierung zurückgestellt.'),
      [FPower.OldName, FPower.NewName]));
  { Stoppuhren starten }
  FRunStart := GetTickCount64;
  FFileStart := FRunStart;
  FFilePct := 0;
  FFilesDone := 0;
  FOKTimeMS := 0;
  FOKCount := 0;
  FOKAudioMS := 0;
  FCurIndex := -1;
  FUserCancelled := False;
  FLastOutFile := '';
  SaveQueueNow;
  lblFileTime.Caption := '';
  lblTotal.Caption := '';
  lblTotal.Font.Color := clDefault;     // Farbe der letzten Zusammenfassung weg
  tmrTime.Interval := 1000;
  tmrTime.Enabled := True;
  SetRunning(True);
  FWorker.OnTerminate := @WorkerDone;   // wird aufgerufen, wenn alles fertig ist
  FWorker.Start;
  FTrayNotice := False;
  UpdateTray;                          // Symbol neben der Uhr mit Fortschritt
  TrayProgress;
end;

procedure TfrmMain.btnCancelClick(Sender: TObject);
begin
  if FWorker <> nil then
  begin
    AddLog(_('Abbruch angefordert...'));
    FUserCancelled := True;
    FWorker.Cancel;
  end;
end;

{ Worker ist fertig: Zusammenfassung ins Protokoll, Buttons wieder frei }
procedure TfrmMain.WorkerDone(Sender: TObject);
var
  Total: string;
begin
  tmrTime.Enabled := False;
  Total := FormatDuration(GetTickCount64 - FRunStart);
  AddLog(Format(_('Fertig: %d erfolgreich, %d übersprungen, %d fehlgeschlagen  -  Gesamtzeit %s'),
    [FWorker.OKCount, FWorker.SkipCount, FWorker.FailCount, Total]));
  if FWorker.CancelCount > 0 then
    AddLog(Format(_('Abgebrochen: %d Datei(en)'), [FWorker.CancelCount]));
  { Meldung neben der Uhr (nur wenn nicht abgebrochen und StemMaker
    gerade nicht vorne ist) }
  if not FUserCancelled then
    TrayNotifyDone(FWorker.OKCount, FWorker.SkipCount, FWorker.FailCount, Total);
  lblFileTime.Caption := '';
  if FUserCancelled then
    lblTotal.Caption := Format(_('Fertig - Gesamtzeit %s'), [Total])
  else
  begin
    { Zusammenfassung unten: grün = alles gut, rot = mindestens ein Fehler }
    lblTotal.Caption := Format(_('Fertig: %d erfolgreich, %d übersprungen, %d fehlgeschlagen  -  Gesamtzeit %s'),
      [FWorker.OKCount, FWorker.SkipCount, FWorker.FailCount, Total]);
    if FWorker.FailCount > 0 then
      lblTotal.Font.Color := CLR_FAIL_TEXT
    else
      lblTotal.Font.Color := CLR_OK_TEXT;
  end;
  EndPower;                       // zuerst zurückstellen, dann zusammenfassen
  WriteRunSummary(FWorker);
  { Fertige Tracks zählen. Ist eine "runde" Zahl erreicht (10, 50, 100 ...),
    kommt der Spenden-Hinweis - aber nur nach einem guten Durchlauf: ohne
    Abbruch, ohne anschliessendes Herunterfahren und mit höchstens 10 %
    fehlgeschlagenen Dateien (siehe uDonate). Bei langen Listen (z. B.
    1000 MP3s) ist eine kaputte Datei normal und soll den Hinweis nicht
    verhindern. Übersprungene Dateien zählen nicht als Fehler. }
  if CountStemsForDonate(FWorker.OKCount, FOKAudioMS,
    (not FUserCancelled) and not chkShutdown.Checked and
    (FWorker.FailCount * 10 <= FWorker.OKCount + FWorker.FailCount)) then
    FDonatePending := True;
  { Wir sind hier noch IM Ende-Ereignis des Threads - ihn jetzt schon
    freizugeben würde knallen. Deshalb kurz danach über die
    Nachrichtenschlange freigeben (FreeWorker). }
  Application.QueueAsyncCall(@FreeWorker, PtrInt(FWorker));
  FWorker := nil;
  SetRunning(False);
  UpdateTray;                     // Symbol weg, wenn es nicht mehr gebraucht wird
  SaveQueueNow;

  { "Ordner nach der Umwandlung öffnen": die zuletzt fertige Stem-Datei im
    Explorer zeigen. Nicht, wenn gleich heruntergefahren wird. }
  if chkOpenWhenDone.Checked and (FLastOutFile <> '') and
    not (chkShutdown.Checked and not FUserCancelled) then
    ShowInExplorer(FLastOutFile);

  { "PC nach Abschluss herunterfahren" - nur wenn nicht abgebrochen wurde.
    Das Häkchen gilt nur für diesen einen Durchlauf.
    WICHTIG: Das Countdown-Fenster NICHT hier öffnen - wir sind noch im
    Ende-Ereignis des Threads. Ein Fenster mit eigener Warteschleife
    blockiert dort alles (gleiches Problem wie früher beim Prüffenster).
    Deshalb über die Nachrichtenschlange kurz danach (AskShutdown). }
  if chkShutdown.Checked and not FUserCancelled then
  begin
    chkShutdown.Checked := False;
    Application.QueueAsyncCall(@AskShutdown, 0);
  end
  else if FHasUpdate then
    { Update kam während der Umwandlung - jetzt anbieten }
    Application.QueueAsyncCall(@OfferUpdate, 0)
  else if FDonatePending then
    { Spenden-Hinweis: wie oben NICHT direkt hier (Ende-Ereignis des Threads) }
    Application.QueueAsyncCall(@ShowDonate, 0);
end;

{ Spenden-Hinweis zeigen - aber nur, wenn man StemMaker gerade anschaut.
  Ist das Fenster im Symbol neben der Uhr oder im Hintergrund, wartet der
  Hinweis, bis StemMaker wieder vorne ist (AppActivate). So springt nie
  ein Fenster über ein anderes Programm. }
procedure TfrmMain.ShowDonate(Data: PtrInt);
begin
  if (not FDonatePending) or (FWorker <> nil) then Exit;
  if not Application.Active or FInTray or (WindowState = wsMinimized) then Exit;
  FDonatePending := False;
  ShowDonateThanks;
end;

procedure TfrmMain.AskShutdown(Data: PtrInt);
begin
  if ShutdownCountdown then
  begin
    AddLog(_('PC wird heruntergefahren ...'));
    LogLine('Herunterfahren nach Abschluss: shutdown /s /t 15');
    with TProcessUTF8.Create(nil) do
    try
      Executable := 'shutdown.exe';
      Parameters.Add('/s');                 // herunterfahren
      Parameters.Add('/t');
      Parameters.Add('15');                 // in 15 Sekunden
      Options := [poNoConsole];
      try
        Execute;
      except
        on E: Exception do
          LogLine('shutdown.exe konnte nicht gestartet werden: ' + E.Message);
      end;
    finally
      Free;
    end;
    Close;                         // StemMaker sauber beenden (Log wird normal abgeschlossen)
  end
  else
  begin
    AddLog(_('Herunterfahren abgebrochen.'));
    { kam während der Umwandlung ein Update, jetzt anbieten }
    if FHasUpdate then
      Application.QueueAsyncCall(@OfferUpdate, 0);
  end;
end;

{ ---------------------------------------------------------------------------
  Zusammenfassung am Ende eines Durchlaufs (ins Protokoll und ins Log):
  Zeiten, Durchschnitt pro Track, Kerne, Speicher, Rechner-Infos
  --------------------------------------------------------------------------- }
procedure TfrmMain.WriteRunSummary(W: TStemWorker);
var
  RunMS: QWord;
  Fmt, Avg: string;
  Used: Integer;
  Slept: QWord;
begin
  RunMS := GetTickCount64 - FRunStart;
  if FOKCount > 0 then
    Avg := FormatDuration(FOKTimeMS div QWord(FOKCount))
  else
    Avg := '-';
  case FRunSettings.Codec of
    scALAC: Fmt := _('ALAC (verlustfrei)');
  else
    if FRunSettings.AACAuto then
      Fmt := Format(_('AAC automatisch (wie die Quelle, max. %d kbit/s) - ' +
        'Bitrate pro Datei siehe "Quelle:" oben'), [FRunSettings.AACBitrate])
    else
      Fmt := Format('AAC %d kbit/s', [FRunSettings.AACBitrate]);
  end;
  Used := FRunSettings.Threads * W.OmpPerPart;
  AddLog(_('=== Zusammenfassung ==='));
  AddLog(Format(_('  Dateien        : %d  (OK %d, übersprungen %d, Fehler %d)'),
    [FTotal, W.OKCount, W.SkipCount, W.FailCount]));
  if W.CancelCount > 0 then
    AddLog(Format(_('  Abgebrochen    : %d'), [W.CancelCount]));
  AddLog(Format(_('  Gesamtzeit     : %s'), [FormatDuration(RunMS)]));
  AddLog(Format(_('  Schnitt/Track  : %s  (nur erfolgreiche Tracks)'), [Avg]));
  { Tempo über alle fertigen Dateien: Rechenzeit pro Minute Musik.
    FOKTimeMS / FOKAudioMS = Sekunden pro Sekunde Musik -> x 60 }
  if FOKAudioMS > 0 then
    AddLog(Format(_('  Tempo          : %.1f s pro Minute Musik (Statistik: logs\statistik.csv)'),
      [FOKTimeMS / FOKAudioMS * 60]));
  AddLog(Format(_('  Modell         : %s'), [StemModelDisplayName(FRunSettings.Model)]));
  AddLog(Format(_('  Format         : %s'), [Fmt]));
  { Engine: wie viele Dateien Turbo und wie viele demucs.cpp getrennt hat }
  if W.TurboCount > 0 then
    AddLog(Format(_('  Engine         : Turbo (StemOnnx) für %d Datei(en), zuletzt auf: %s'),
      [W.TurboCount, W.TurboDev]));
  if W.ClassicCount > 0 then
  begin
    AddLog(Format(_('  Engine         : Klassisch (demucs.cpp) für %d Datei(en)'), [W.ClassicCount]));
    AddLog(Format(_('  Rechenleistung : %d Teile x %d Kerne = %d von %d echten Kernen (%d logisch), demucs-Version %s'),
      [FRunSettings.Threads, W.OmpPerPart, Used, PhysicalCoreCount, TThread.ProcessorCount,
       DemucsVariantName(DemucsExeFor(FRunSettings.DemucsDir, FRunSettings.Model))]));
  end;
  if W.MaxPeakMemMB > 0 then
    AddLog(Format(_('  RAM Trennen    : max. %d MB  (Gesamt-RAM %.1f GB)'),
      [W.MaxPeakMemMB, SysRAMTotalMB / 1024]));
  if W.TurboCount = 0 then
    AddLog(_('  Grafikkarte    : nicht genutzt (demucs.cpp rechnet nur mit der CPU)'));
  AddLog(Format(_('                   vorhanden: %s'), [SysGPUInfo]));
  AddLog(Format(_('  Energie        : %s'), [PowerSummaryText(FPower)]));
  Slept := PowerSleptMS(FPower);
  if Slept > 0 then
    AddLog(Format(_('  ACHTUNG        : Der PC war ca. %s im Ruhezustand - ' +
      'die Zeiten oben sind um diese Dauer zu lang.'), [FormatDuration(Slept)]))
  else
    AddLog(_('  Ruhezustand    : keiner während der Konvertierung'));
end;

{ Schlafsperre aufheben und Energiesparplan zurückstellen.
  Darf mehrfach aufgerufen werden - beim zweiten Mal passiert nichts. }
procedure TfrmMain.EndPower;
begin
  PowerEndRun(FPower, FIniName);
end;

{ ===========================================================================
  SAMMLUNGS-FUNKTIONEN
  - Warteschlange merken (uQueue: StemMaker_queue.txt)
  - Song-Längen im Hintergrund ermitteln (TDurationProber)
  - Zeitschätzung vor dem Start
  - Countdown vor dem Herunterfahren
  =========================================================================== }

{ Die Liste hat sich geändert (Dateien dazu/weg). Speichern, Längen
  abfragen und Schätzung neu rechnen - aber nicht für jede einzelne
  Datei, wenn gerade 500 auf einmal hinzugefügt werden: Wir melden die
  Arbeit nur EINMAL an, sie läuft, sobald das Hinzufügen fertig ist. }
procedure TfrmMain.ListChanged;
begin
  if FRestoring or FChangePending then Exit;
  FChangePending := True;
  Application.QueueAsyncCall(@AfterListChange, 0);
end;

procedure TfrmMain.AfterListChange(Data: PtrInt);
begin
  FChangePending := False;
  SaveQueueNow;
  StartProbe;
  UpdateEstimate;
end;

{ Länge einer Zeile in ms (0 = unbekannt) }
function TfrmMain.ItemDurMS(Index: Integer): Int64;
begin
  Result := 0;
  if (Index >= 0) and (Index < lvFiles.Items.Count) and
     (lvFiles.Items[Index].SubItems.Count > 3) then
    Result := StrToInt64Def(lvFiles.Items[Index].SubItems[3], 0);
  if Result < 0 then Result := 0;
end;

{ Tempo in "ms Rechenzeit pro ms Musik":
    1. was in diesem Durchlauf schon gemessen wurde (am genauesten)
    2. sonst das gelernte Tempo dieses PCs (StemMaker.ini [Speed])
    3. sonst ein grober Startwert }
function TfrmMain.RateMsPerMs: Double;
var
  M: TStemModel;
  SecPerMin: Double;
  Turbo: Boolean;
begin
  if (FWorker <> nil) and (FOKAudioMS > 0) then
    Exit(FOKTimeMS / FOKAudioMS);
  if FWorker <> nil then
  begin
    M := FRunSettings.Model;
    Turbo := TurboFor(FRunSettings);
  end
  else
  begin
    M := TStemModel(cbModel.ItemIndex);
    Turbo := TurboFor(CurrentSettings);
  end;
  SecPerMin := SpeedLoad(FIniName, M, Turbo);
  if SecPerMin <= 0 then
    SecPerMin := SpeedDefault(M, Turbo);
  Result := SecPerMin / 60;      // X s Arbeit pro 60 s Musik = X/60 ms Arbeit pro ms Musik
end;

{ ganze Liste in StemMaker_queue.txt schreiben }
procedure TfrmMain.SaveQueueNow;
var
  E: TQueueEntries;
  I: Integer;
begin
  if FRestoring then Exit;
  SetLength(E, lvFiles.Items.Count);
  for I := 0 to lvFiles.Items.Count - 1 do
  begin
    case ItemState(lvFiles.Items[I]) of
      ST_OK:     E[I].State := 'o';
      ST_SKIP:   E[I].State := 's';
      ST_FAIL:   E[I].State := 'f';
      ST_CANCEL: E[I].State := 'c';
      ST_RUN:    E[I].State := 'r';
    else
      E[I].State := 'w';
    end;
    E[I].Path := lvFiles.Items[I].SubItems[1];
    if lvFiles.Items[I].SubItems.Count > 2 then
      E[I].Root := lvFiles.Items[I].SubItems[2]
    else
      E[I].Root := '';
    E[I].DurMS := StrToInt64Def(lvFiles.Items[I].SubItems[3], 0);
  end;
  QueueSave(E);
end;

{ beim Start: gespeicherte Liste wieder einlesen }
procedure TfrmMain.RestoreQueue;
var
  E: TQueueEntries;
  I, Missing, Open, Interrupted: Integer;
  Item: TListItem;
  St: Integer;
  S: string;
begin
  E := QueueLoad;
  if Length(E) = 0 then Exit;
  Missing := 0;
  Open := 0;
  Interrupted := 0;
  FRestoring := True;
  lvFiles.BeginUpdate;
  try
    for I := 0 to High(E) do
    begin
      if not FileExists(E[I].Path) then
      begin
        Inc(Missing);              // Datei gibt es nicht mehr (verschoben/gelöscht)
        Continue;
      end;
      case E[I].State of
        'o': begin St := ST_OK;     S := 'OK'; end;
        's': begin St := ST_SKIP;   S := _('existiert schon'); end;
        'f': begin St := ST_FAIL;   S := _('Fehler'); end;
        'c': begin St := ST_CANCEL; S := _('abgebrochen'); end;
        'r': begin St := ST_WAIT;   S := _('wartet (unterbrochen)'); Inc(Interrupted); end;
      else
        begin St := ST_WAIT; S := _('wartet'); end;
      end;
      if St <> ST_OK then Inc(Open);
      Item := lvFiles.Items.Add;
      Item.Caption := ExtractFileName(E[I].Path);
      Item.SubItems.Add(S);
      Item.SubItems.Add(E[I].Path);
      Item.SubItems.Add(E[I].Root);
      if E[I].DurMS <> 0 then
        Item.SubItems.Add(IntToStr(E[I].DurMS))
      else
        Item.SubItems.Add('');
      SetState(Item, St);
    end;
  finally
    lvFiles.EndUpdate;
    FRestoring := False;
  end;
  LogLine(Format('Warteschlange wiederhergestellt: %d Dateien, %d offen, %d unterbrochen, %d fehlen',
    [lvFiles.Items.Count, Open, Interrupted, Missing]));
  if lvFiles.Items.Count > 0 then
    AddLog(Format(_('Liste vom letzten Mal wiederhergestellt: %d Dateien, davon %d noch offen.'),
      [lvFiles.Items.Count, Open]));
  if Interrupted > 0 then
    AddLog(_('Die zuletzt bearbeitete Datei wurde unterbrochen - sie wird mit "Start" neu gemacht.'));
  if Missing > 0 then
    AddLog(Format(_('%d Dateien aus der gespeicherten Liste gibt es nicht mehr - weggelassen.'),
      [Missing]));
  ListChanged;                     // speichern (ohne die fehlenden), Längen, Schätzung
end;

{ Längen-Abfrage starten für alle Zeilen ohne bekannte Länge }
procedure TfrmMain.StartProbe;
var
  L: TStringList;
  I: Integer;
begin
  if FProber <> nil then
  begin
    FProbeAgain := True;           // läuft schon -> danach nochmals
    Exit;
  end;
  if not FileExists(FToolFFmpeg) then Exit;   // ffmpeg fehlt noch
  L := TStringList.Create;
  try
    for I := 0 to lvFiles.Items.Count - 1 do
      if lvFiles.Items[I].SubItems[3] = '' then
        L.Add(lvFiles.Items[I].SubItems[1]);
    if L.Count = 0 then Exit;
    FProbeAgain := False;
    FProber := TDurationProber.Create(FToolFFmpeg, L, @DurationResult);
    FProber.OnTerminate := @ProberDone;
    FProber.Start;
  finally
    L.Free;
  end;
end;

procedure TfrmMain.ProberDone(Sender: TObject);
begin
  { wie beim Worker: nicht im eigenen Ende-Ereignis freigeben }
  Application.QueueAsyncCall(@FreeProber, PtrInt(FProber));
  FProber := nil;
  SaveQueueNow;                    // ermittelte Längen mit in die Liste schreiben
  if FProbeAgain then
    StartProbe;
end;

procedure TfrmMain.FreeProber(Data: PtrInt);
begin
  TDurationProber(Data).WaitFor;
  TDurationProber(Data).Free;
end;

{ beim Beenden: Abfrage stoppen und warten }
procedure TfrmMain.StopProbe;
begin
  if FProber = nil then Exit;
  FProber.OnTerminate := nil;
  FProber.Terminate;
  FProber.WaitFor;
  FreeAndNil(FProber);
end;

{ eine Länge ist da (läuft im Hauptthread) }
procedure TfrmMain.DurationResult(const Path: string; DurMS: Int64);
var
  I: Integer;
begin
  for I := 0 to lvFiles.Items.Count - 1 do
    if SameFileName(lvFiles.Items[I].SubItems[1], Path) then
    begin
      if DurMS > 0 then
        lvFiles.Items[I].SubItems[3] := IntToStr(DurMS)
      else
        lvFiles.Items[I].SubItems[3] := '-1';   // nicht lesbar - nicht nochmals fragen
      Break;
    end;
  UpdateEstimate;
  if (FProber = nil) or (FProber.Finished) then
    SaveQueueNow;
end;

{ Schätzung vor dem Start, unten unter dem Gesamt-Balken:
  "87 Dateien offen, 6:12:40 Musik - geschätzte Dauer ca. 11:30:00 (Tempo dieses PCs)" }
procedure TfrmMain.UpdateEstimate;
var
  I, Open, Unknown: Integer;
  Audio: Int64;
  Est: Double;
  Measured: Boolean;
  S: string;
begin
  if FWorker <> nil then Exit;     // während der Arbeit zeigt UpdateTimes die Zeiten
  lblTotal.Font.Color := clDefault;  // grün/rot gilt nur für die Zusammenfassung
  Open := 0;
  Unknown := 0;
  Audio := 0;
  for I := 0 to lvFiles.Items.Count - 1 do
    if ItemState(lvFiles.Items[I]) <> ST_OK then
    begin
      Inc(Open);
      if ItemDurMS(I) > 0 then
        Inc(Audio, ItemDurMS(I))
      else
        Inc(Unknown);
    end;
  if Open = 0 then
  begin
    if lvFiles.Items.Count > 0 then
      lblTotal.Caption := _('Alle Dateien in der Liste sind fertig.');
    Exit;
  end;
  if Unknown = Open then
  begin
    lblTotal.Caption := Format(_('%d Dateien offen - Länge wird ermittelt ...'), [Open]);
    Exit;
  end;
  Measured := SpeedLoad(FIniName, TStemModel(cbModel.ItemIndex),
    TurboFor(CurrentSettings)) > 0;
  { unbekannte Längen: wie der Schnitt der bekannten annehmen }
  Est := Audio * RateMsPerMs * Open / (Open - Unknown);
  S := Format(_('%d Dateien offen, %s Musik - Dauer ca. %s'),
    [Open, FormatDuration(Audio), FormatDuration(Round(Est))]);
  { kurzer Zusatz im Text, die Erklärung im Hinweis (Maus drüber) }
  if Measured then
  begin
    S := S + ' ' + _('(Tempo dieses PCs)');
    lblTotal.Hint := _('Geschätzt mit dem Tempo, das auf diesem PC gemessen wurde.');
  end
  else
  begin
    S := S + ' ' + _('(grob geschätzt)');
    lblTotal.Hint := _('Grobe Schätzung - nach dem ersten fertigen Track kennt StemMaker das Tempo dieses PCs.');
  end;
  if Unknown > 0 then
    S := S + Format(_(' - %d Längen noch unbekannt'), [Unknown]);
  lblTotal.ShowHint := True;
  lblTotal.Caption := S;
end;

{ ---------------------------------------------------------------------------
  Symbol neben der Uhr (Infobereich der Taskleiste)

  Eine Umwandlung dauert pro Song Minuten, ein ganzer Ordner Stunden. In
  der Zeit arbeitet man meist etwas anderes. Das Symbol hilft dabei:
    - Maus drüber: Fortschritt, z.B. "StemMaker - 45 % (Datei 3 von 12)"
    - Meldung, wenn alles fertig ist (nur wenn StemMaker nicht vorne ist,
      abschaltbar unter Einstellungen -> Programm)
    - auf Wunsch (Einstellungen -> Programm, Standard aus): beim Minimieren
      verschwindet das Fenster aus der Taskleiste, nur das Symbol bleibt
    - Klick aufs Symbol holt das Fenster zurück, Rechtsklick: Menü

  Das Symbol ist nur da, solange es etwas zu sagen hat: während einer
  Umwandlung, solange das Fenster versteckt ist, und nach der
  "fertig"-Meldung bis man StemMaker wieder anschaut.

  Minimieren bei Lazarus unter Windows: Den Eintrag in der Taskleiste hat
  nicht das Hauptfenster, sondern ein unsichtbares "Anwendungsfenster"
  (Application.Handle). Beim Minimieren versteckt Lazarus das Hauptfenster
  und minimiert dieses Anwendungsfenster. Wir verstecken danach auch das
  Anwendungsfenster -> der Eintrag in der Taskleiste verschwindet.
  Zurück: Anwendungsfenster zeigen, Application.Restore holt das
  Hauptfenster wieder hervor.

  Zweiter Start, während das Fenster versteckt ist: uSingleInstance findet
  kein sichtbares Fenster und meldet sich stattdessen über ein Signal
  (SingleInstanceShowWanted). Ein Timer fragt das alle 0,5 s ab, aber nur
  solange das Fenster versteckt ist.
  --------------------------------------------------------------------------- }
procedure TfrmMain.SetupTray;
var
  Pop: TPopupMenu;
  Item: TMenuItem;
begin
  FTray := TTrayIcon.Create(Self);
  FTray.Icon.Assign(Application.Icon);
  FTray.Hint := APP_NAME;
  FTray.OnClick := @TrayClick;

  Pop := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(Pop);
  Item.Caption := _('StemMaker anzeigen');
  Item.Default := True;                    // fett, wie bei Windows üblich
  Item.OnClick := @TrayClick;
  Pop.Items.Add(Item);
  Item := TMenuItem.Create(Pop);
  Item.Caption := _('Beenden');
  Item.OnClick := @TrayQuitClick;
  Pop.Items.Add(Item);
  FTray.PopUpMenu := Pop;

  FTrayTimer := TTimer.Create(Self);
  FTrayTimer.Enabled := False;
  FTrayTimer.Interval := 500;
  FTrayTimer.OnTimer := @TrayTimerTick;

  Application.OnMinimize := @AppMinimize;
  Application.OnActivate := @AppActivate;
  Application.OnEndSession := @AppEndSession;
  SingleInstanceShowWanted;                // Signal für den zweiten Start anlegen
end;

{ Symbol zeigen oder verstecken, je nach Lage }
procedure TfrmMain.UpdateTray;
begin
  if FTray = nil then Exit;
  if FWorker = nil then
    FTray.Hint := APP_NAME;
  FTray.Visible := (FWorker <> nil) or FInTray or FTrayNotice;
end;

{ Fortschritt in den Hinweis des Symbols (Maus drüber). Windows zeigt
  höchstens 127 Zeichen - das reicht locker. }
procedure TfrmMain.TrayProgress;
var
  S: string;
  Pct, Cur: Integer;
begin
  if (FTray = nil) or (FWorker = nil) or (FTotal <= 0) then Exit;
  Pct := Round((FFilesDone * 100 + FFilePct) / FTotal);
  Cur := FFilesDone + 1;
  if Cur > FTotal then Cur := FTotal;
  S := Format(_('%s - %d %% (Datei %d von %d)'), [APP_NAME, Pct, Cur, FTotal]);
  if S <> FTray.Hint then                  // nur bei Änderung neu setzen
    FTray.Hint := S;
end;

procedure TfrmMain.HideToTray;
begin
  FInTray := True;
  UpdateTray;
  TrayProgress;
  {$IFDEF WINDOWS}
  { Taskleisten-Eintrag weg (siehe oben: gehört dem Anwendungsfenster) }
  ShowWindow(Application.Handle, SW_HIDE);
  {$ENDIF}
  SingleInstanceShowWanted;                // altes Signal verwerfen
  FTrayTimer.Enabled := True;
end;

procedure TfrmMain.ShowFromTray;
begin
  FTrayTimer.Enabled := False;
  if FInTray then
  begin
    FInTray := False;
    {$IFDEF WINDOWS}
    ShowWindow(Application.Handle, SW_SHOW);
    {$ENDIF}
  end;
  FTrayNotice := False;
  Application.Restore;                     // war minimiert -> wiederherstellen
  if WindowState = wsMinimized then
    WindowState := wsNormal;
  Application.BringToFront;
  UpdateTray;
end;

procedure TfrmMain.TrayClick(Sender: TObject);
begin
  ShowFromTray;
end;

{ "Beenden" im Menü: erst das Fenster zeigen, damit die Frage "Umwandlung
  läuft noch - abbrechen?" (FormCloseQuery) sichtbar ist }
procedure TfrmMain.TrayQuitClick(Sender: TObject);
begin
  ShowFromTray;
  Close;
end;

{ Ein zweiter StemMaker-Start möchte, dass wir uns zeigen }
procedure TfrmMain.TrayTimerTick(Sender: TObject);
begin
  if SingleInstanceShowWanted then
    ShowFromTray;
end;

procedure TfrmMain.AppMinimize(Sender: TObject);
begin
  if FPrefs.TrayMinimize then
    HideToTray;
end;

{ StemMaker ist wieder vorne -> die "fertig"-Meldung ist gesehen }
procedure TfrmMain.AppActivate(Sender: TObject);
begin
  if FDonatePending and (FWorker = nil) then
    Application.QueueAsyncCall(@ShowDonate, 0);
  if FTrayNotice then
  begin
    FTrayNotice := False;
    UpdateTray;
  end;
end;

{ Meldung neben der Uhr, wenn alles fertig ist. Nur wenn eingeschaltet
  und StemMaker gerade nicht vorne ist (wer zuschaut, braucht sie nicht). }
procedure TfrmMain.TrayNotifyDone(OK, Skipped, Failed: Integer; const Total: string);
begin
  if (FTray = nil) or not FPrefs.TrayNotify then Exit;
  if Application.Active and not FInTray and (WindowState <> wsMinimized) then Exit;
  FTrayNotice := True;
  FTray.Hint := APP_NAME;
  FTray.Visible := True;
  FTray.BalloonTitle := _('StemMaker ist fertig');
  FTray.BalloonHint := Format(_('%d erfolgreich, %d übersprungen, %d fehlgeschlagen' +
    ' - Gesamtzeit %s'), [OK, Skipped, Failed, Total]);
  if Failed > 0 then
    FTray.BalloonFlags := bfWarning
  else
    FTray.BalloonFlags := bfInfo;
  FTray.BalloonTimeout := 10000;
  FTray.ShowBalloonHint;
end;

{ ---------------------------------------------------------------------------
  Windows wird heruntergefahren (oder der Benutzer meldet sich ab)

  Windows beendet StemMaker danach nach wenigen Sekunden hart - unser
  normales Ende (FormDestroy, LogClose in StemMaker.lpr) kommt dann nie.
  Ohne diese Funktion hiess das beim nächsten Start: Log "_ABSTURZ",
  Frage nach einem Fehlerbericht, Energiesparplan erst dann zurück.
  Darum hier schnell alles Wichtige erledigen:
    - laufende Umwandlung abbrechen (demucs/ffmpeg beenden). NICHT auf
      den Thread warten, dafür reicht die Zeit nicht. Die angefangene
      Datei steht in der Liste als "läuft" und wird beim nächsten Start
      wieder von vorne gemacht (wie nach "Abbrechen").
    - Energiesparplan/Schlafsperre zurückstellen
    - Liste und Einstellungen speichern, Symbol neben der Uhr entfernen
    - Log normal abschliessen (kein "_ABSTURZ")
  Geht auch, wenn das Fenster ins Symbol versteckt ist.
  --------------------------------------------------------------------------- }
procedure TfrmMain.AppEndSession(Sender: TObject);
begin
  LogLine('Windows wird beendet (Herunterfahren oder Abmelden)');
  if FWorker <> nil then
  begin
    LogLine('Laufende Umwandlung wird abgebrochen, die angefangene Datei ' +
      'kommt beim nächsten Start noch einmal dran');
    FWorker.OnTerminate := nil;    // WorkerDone soll nicht mehr kommen
    FWorker.Cancel;
  end;
  EndPower;
  SaveQueueNow;
  SaveSettings;
  if FTray <> nil then
    FTray.Visible := False;
  LogClose;
end;

{ ---------------------------------------------------------------------------
  Countdown vor dem Herunterfahren: 60 Sekunden mit "Abbrechen".
  Gibt True zurück, wenn heruntergefahren werden soll.
  --------------------------------------------------------------------------- }
type
  TShutdownForm = class(TForm)
  public
    Lbl: TLabel;
    Left_: Integer;
    procedure Tick(Sender: TObject);
  end;

procedure TShutdownForm.Tick(Sender: TObject);
begin
  Dec(Left_);
  Lbl.Caption := Format(_('Alle Dateien sind fertig. Der PC wird in %d Sekunden heruntergefahren.'),
    [Left_]);
  if Left_ <= 0 then
    ModalResult := mrOK;
end;

function TfrmMain.ShutdownCountdown: Boolean;
var
  F: TShutdownForm;
  Btn: TButton;
  T: TTimer;
begin
  F := TShutdownForm.CreateNew(nil);
  try
    F.Caption := APP_NAME;
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.FormStyle := fsStayOnTop;
    F.ClientWidth := 440;
    F.ClientHeight := 120;
    F.Left_ := 60;
    F.Lbl := TLabel.Create(F);
    F.Lbl.Parent := F;
    F.Lbl.SetBounds(16, 16, 408, 44);
    F.Lbl.AutoSize := False;
    F.Lbl.WordWrap := True;
    F.Lbl.Caption := Format(_('Alle Dateien sind fertig. Der PC wird in %d Sekunden heruntergefahren.'),
      [F.Left_]);
    Btn := TButton.Create(F);
    Btn.Parent := F;
    Btn.SetBounds(300, 74, 124, 32);
    Btn.Caption := _('Abbrechen');
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    T := TTimer.Create(F);
    T.Interval := 1000;
    T.OnTimer := @F.Tick;
    T.Enabled := True;
    Result := F.ShowModal = mrOK;
  finally
    F.Free;
  end;
end;

procedure TfrmMain.FreeWorker(Data: PtrInt);
var
  W: TStemWorker;
begin
  W := TStemWorker(Data);
  W.WaitFor;
  W.Free;
end;

end.
