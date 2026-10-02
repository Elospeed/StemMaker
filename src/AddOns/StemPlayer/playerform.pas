{ ============================================================================
  playerform.pas  -  Hauptfenster des Elospeed StemPlayer

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Zweck:
    Die von Elospeed StemMaker erzeugten Traktor-Stem-Dateien (.stem.mp4)
    abspielen und die 4 Stems einzeln stummschalten / solo hören / in der
    Lautstärke ändern - um die Qualität der Trennung zu prüfen.

  Das Fenster wird komplett im Code aufgebaut (keine .lfm-Datei nötig),
  damit das Projekt einfach zu kompilieren und anzupassen ist.

  Ablauf beim Öffnen einer Datei:
    1. mp4stem liest Spuranzahl, Stem-Namen und -Farben direkt aus der MP4.
    2. ffmpeg dekodiert alle Spuren in EINEM Aufruf als rohes PCM in einen
       Temp-Ordner (16 Bit / 44.1 kHz / Stereo, ca. 10 MB pro Spur und Minute).
    3. stemengine mischt live und spielt über Windows-waveOut ab.

  Temp-Dateien:
    Jede laufende Instanz hat einen eigenen Ordner
        %TEMP%\ElospeedStemPlayer_<PID>_<Startzeit>\
    mit einer Sperrdatei "instance.lock", die exklusiv geöffnet bleibt,
    solange das Programm läuft. Die dekodierten Spuren eines Tracks liegen
    darin in einem Unterordner "track_<Zeit>\".
    - Laden der nächsten Datei  -> Track-Unterordner wird gelöscht (UnloadFile)
    - Programm schliessen       -> ganzer Instanz-Ordner wird gelöscht
                                   (FormClose / ReleaseInstanceDir)
    - Schliessen WÄHREND ffmpeg dekodiert -> ffmpeg wird abgebrochen, danach
      aufgeräumt und erst dann geschlossen (FormCloseQuery / FCancelLoad)
    - Absturz / "Task beenden"  -> Ordner bleibt liegen; er wird beim
      nächsten Programmstart entfernt (CleanupOrphanTempDirs).
      Woran erkennt man "verwaist"? Die Sperrdatei lässt sich löschen.
      Bei einer noch laufenden Instanz ist sie gesperrt -> Ordner bleibt.
      (Das ist zuverlässiger als die Prozess-ID, die Windows wiederverwendet.)

  Bewusst KEIN Echtzeit-Log (anders als StemMaker): Der Player macht nur
  einen kurzen ffmpeg-Aufruf. Schlägt dieser fehl, wird die Fehlermeldung
  von ffmpeg direkt im Fehlerdialog und in der Statuszeile angezeigt.

  Tastatur:
    Leertaste  Play / Pause          1..4        Stem stumm an/aus
    Shift+1..4 Solo an/aus           0           Mute/Solo zurücksetzen
    S / O / R  Stems / Original / Rest           Pfeil links/rechts  -/+ 5 s
    Pos1       an den Anfang         Strg+O      Datei öffnen

  Versionen:
    1.0  (01.10.2026)  Erste Version: Mute/Solo/Fader, Modi Stems/Original/Rest
    1.1  (02.10.2026)  Verwaiste Temp-Ordner werden beim Start gelöscht,
                       Schliessen während des Dekodierens bricht ffmpeg sauber ab,
                       ffmpeg-Fehlermeldung wird im Fehlerfall angezeigt
  ============================================================================ }
unit playerform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Buttons, LCLType, LCLIntf, Process, FileUtil,
  LazFileUtils, IniFiles, mp4stem, stemengine;

const
  APP_TITLE = 'Elospeed StemPlayer';
  APP_VER   = '1.1';
  TEMP_PREFIX = 'ElospeedStemPlayer_';  // Präfix der Temp-Ordner (siehe oben)
  LOCK_NAME   = 'instance.lock';        // Sperrdatei im Instanz-Ordner
  KOFI_URL  = 'https://ko-fi.com/elospeed';

type
  { Eine Zeile pro Stem }
  TStemRow = record
    Panel    : TPanel;
    ColorBar : TShape;
    LblName  : TLabel;
    LblState : TLabel;
    BtnMute  : TSpeedButton;
    BtnSolo  : TSpeedButton;
    TrkVol   : TTrackBar;
    LblVol   : TLabel;
    Meter    : TPaintBox;
    Color    : TColor;
    Level    : Single;     // geglätteter Anzeigepegel 0..1
  end;

  { TMainForm }

  TMainForm = class(TForm)
  private
    { --- Oberer Bereich --- }
    PnlTop      : TPanel;
    BtnOpen     : TButton;
    LblFile     : TLabel;
    { --- Transport --- }
    PnlTransport: TPanel;
    BtnPlay     : TButton;
    BtnStop     : TButton;
    TrkPos      : TTrackBar;
    LblTime     : TLabel;
    { --- Modus --- }
    PnlMode     : TPanel;
    BtnModeStems: TSpeedButton;
    BtnModeOrig : TSpeedButton;
    BtnModeRest : TSpeedButton;
    BtnReset    : TButton;
    { --- Stems --- }
    Rows        : array[1..STEM_COUNT] of TStemRow;
    { --- Master --- }
    PnlMaster   : TPanel;
    TrkMaster   : TTrackBar;
    LblMasterVol: TLabel;
    MeterOut    : TPaintBox;
    LblClip     : TLabel;
    { --- Unten --- }
    PnlBottom   : TPanel;
    LblHelp     : TLabel;
    LblStatus   : TLabel;
    LblKofi     : TLabel;
    { --- Sonstiges --- }
    Timer       : TTimer;
    OpenDlg     : TOpenDialog;

    Engine      : TStemEngine;
    FInfo       : TStemInfo;
    FFileName   : string;
    FInstanceDir: string;      // Temp-Ordner dieser Programminstanz
    FLockFile   : TFileStream; // exklusiv offene Sperrdatei im Instanz-Ordner
    FTempDir    : string;      // Unterordner mit den .raw-Dateien des Tracks
    FFFmpeg     : string;
    FLoading    : Boolean;     // True, solange LoadFile läuft (ffmpeg dekodiert)
    FCancelLoad : Boolean;     // Abbruchwunsch für das laufende Dekodieren
    FCloseAfterLoad: Boolean;  // Fenster nach dem Abbruch automatisch schliessen
    FUpdatingPos: Boolean;
    FDraggingPos: Boolean;
    FOutLevel   : array[0..1] of Single;
    FLastClip   : Integer;
    FClipTicks  : Integer;

    procedure BuildUI;
    procedure BuildStemRow(Idx: Integer; ATop: Integer);
    function  MakeSpeed(AParent: TWinControl; const ACaption: string;
                        ALeft, ATop, AWidth: Integer; AGroup: Integer): TSpeedButton;
    function  MakeLabel(AParent: TWinControl; const ACaption: string;
                        ALeft, ATop: Integer; ASize: Integer; ABold: Boolean): TLabel;

    { Datei / ffmpeg }
    function  IniFileName: string;
    function  FindFFmpeg: string;
    procedure LoadFile(const FileName: string);
    procedure UnloadFile;
    function  DecodeTracks(const FileName: string; TrackCount: Integer;
                           out ErrText: string): Boolean;
    procedure CleanupOrphanTempDirs;
    procedure CreateInstanceDir;
    procedure ReleaseInstanceDir;
    procedure DeferredClose(Data: PtrInt);

    { Steuerung }
    procedure UpdateGains;
    procedure UpdateRowLook;
    procedure TogglePlay;
    procedure StopPlay;
    procedure SeekRelative(Seconds: Integer);
    procedure SetMode(M: TPlayMode);
    function  FormatTime(Frames: Int64): string;
    function  LevelToFrac(L: Single): Single;

    { Ereignisse }
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnPlayClick(Sender: TObject);
    procedure BtnStopClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure ModeClick(Sender: TObject);
    procedure MuteSoloClick(Sender: TObject);
    procedure VolChange(Sender: TObject);
    procedure MasterChange(Sender: TObject);
    procedure PosChange(Sender: TObject);
    procedure PosMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PosMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MeterPaint(Sender: TObject);
    procedure OutMeterPaint(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure KofiClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormShow(Sender: TObject);
  public
    constructor Create(TheOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

const
  { Farben für das dunkle "DJ-Look"-Layout }
  CLR_BG      = $00202020;
  CLR_PANEL   = $002C2C2C;
  CLR_TEXT    = $00F0F0F0;
  CLR_DIM     = $00808080;
  CLR_METERBG = $00141414;
  ROW_HEIGHT  = 60;

{ ============================================================================
  Aufbau des Fensters
  ============================================================================ }

constructor TMainForm.Create(TheOwner: TComponent);
begin
  { Keine .lfm-Datei -> CreateNew statt Create }
  inherited CreateNew(TheOwner);
  Caption := APP_TITLE + ' ' + APP_VER + '  -  von Elospeed';
  Width := 800;
  Height := 560;
  Constraints.MinWidth := 700;
  Constraints.MinHeight := 560;
  Position := poScreenCenter;
  Color := CLR_BG;
  Font.Color := CLR_TEXT;
  KeyPreview := True;
  AllowDropFiles := True;
  OnKeyDown := @FormKeyDown;
  OnDropFiles := @FormDropFiles;
  OnClose := @FormClose;
  OnCloseQuery := @FormCloseQuery;
  OnShow := @FormShow;

  { Standardnamen/-farben vorbelegen (leerer Dateiname -> nur Defaults) }
  ReadStemInfo('', FInfo);
  BuildUI;
  UpdateGains;

  OpenDlg := TOpenDialog.Create(Self);
  OpenDlg.Title := 'Stem-Datei öffnen';
  OpenDlg.Filter := 'Traktor Stems (*.stem.mp4;*.mp4)|*.stem.mp4;*.mp4|Alle Dateien (*.*)|*.*';

  Timer := TTimer.Create(Self);
  Timer.Interval := 30;
  Timer.OnTimer := @TimerTick;
  Timer.Enabled := True;

  { Reste früherer Abstürze aus dem Temp-Ordner entfernen }
  CleanupOrphanTempDirs;
  CreateInstanceDir;

  FFFmpeg := FindFFmpeg;
  if FFFmpeg = '' then
    LblStatus.Caption := 'ffmpeg.exe nicht gefunden - wird beim ersten Öffnen abgefragt.'
  else
    LblStatus.Caption := 'ffmpeg: ' + FFFmpeg;
end;

function TMainForm.MakeLabel(AParent: TWinControl; const ACaption: string;
  ALeft, ATop: Integer; ASize: Integer; ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Caption := ACaption;
  Result.Font.Color := CLR_TEXT;
  if ASize > 0 then Result.Font.Size := ASize;
  if ABold then Result.Font.Style := [fsBold];
end;

function TMainForm.MakeSpeed(AParent: TWinControl; const ACaption: string;
  ALeft, ATop, AWidth: Integer; AGroup: Integer): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 32);
  Result.Caption := ACaption;
  Result.GroupIndex := AGroup;   // GroupIndex <> 0 -> Button rastet ein
  Result.Font.Color := clBlack;  // Buttons sind hell -> dunkle Schrift
end;

procedure TMainForm.BuildUI;
var
  i: Integer;
begin
  { ---------- Oben: Datei ---------- }
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 50;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := CLR_BG;
  PnlTop.Width := ClientWidth;   // Breite vorab setzen, damit Anker stimmen

  BtnOpen := TButton.Create(Self);
  BtnOpen.Parent := PnlTop;
  BtnOpen.SetBounds(10, 10, 110, 30);
  BtnOpen.Caption := 'Öffnen...';
  BtnOpen.OnClick := @BtnOpenClick;

  LblFile := MakeLabel(PnlTop, 'Stem-Datei öffnen oder hierher ziehen (Drag & Drop)', 132, 16, 10, True);
  LblFile.Anchors := [akLeft, akTop, akRight];
  LblFile.AutoSize := False;
  LblFile.Width := PnlTop.Width - 142;

  { ---------- Transport ---------- }
  PnlTransport := TPanel.Create(Self);
  PnlTransport.Parent := Self;
  PnlTransport.Align := alTop;
  PnlTransport.Top := 100;
  PnlTransport.Height := 50;
  PnlTransport.BevelOuter := bvNone;
  PnlTransport.Color := CLR_BG;
  PnlTransport.Width := ClientWidth;

  BtnPlay := TButton.Create(Self);
  BtnPlay.Parent := PnlTransport;
  BtnPlay.SetBounds(10, 8, 90, 32);
  BtnPlay.Caption := 'Play';
  BtnPlay.Enabled := False;
  BtnPlay.OnClick := @BtnPlayClick;

  BtnStop := TButton.Create(Self);
  BtnStop.Parent := PnlTransport;
  BtnStop.SetBounds(104, 8, 70, 32);
  BtnStop.Caption := 'Stop';
  BtnStop.Enabled := False;
  BtnStop.OnClick := @BtnStopClick;

  TrkPos := TTrackBar.Create(Self);
  TrkPos.Parent := PnlTransport;
  TrkPos.SetBounds(182, 8, PnlTransport.Width - 182 - 150, 32);
  TrkPos.Anchors := [akLeft, akTop, akRight];
  TrkPos.Min := 0;
  TrkPos.Max := 1000;
  TrkPos.TickStyle := tsNone;
  TrkPos.PageSize := 50;
  TrkPos.Enabled := False;
  TrkPos.OnChange := @PosChange;
  TrkPos.OnMouseDown := @PosMouseDown;
  TrkPos.OnMouseUp := @PosMouseUp;

  LblTime := MakeLabel(PnlTransport, '00:00 / 00:00', 0, 14, 11, True);
  LblTime.AutoSize := False;
  LblTime.Alignment := taRightJustify;
  LblTime.SetBounds(PnlTransport.Width - 150, 14, 138, 24);
  LblTime.Anchors := [akTop, akRight];

  { ---------- Modus ---------- }
  PnlMode := TPanel.Create(Self);
  PnlMode.Parent := Self;
  PnlMode.Align := alTop;
  PnlMode.Top := 200;
  PnlMode.Height := 46;
  PnlMode.BevelOuter := bvNone;
  PnlMode.Color := CLR_BG;
  PnlMode.Width := ClientWidth;

  MakeLabel(PnlMode, 'Hören:', 10, 14, 0, False);
  BtnModeStems := MakeSpeed(PnlMode, 'Stems (S)', 60, 6, 110, 1);
  BtnModeOrig  := MakeSpeed(PnlMode, 'Original (O)', 172, 6, 110, 1);
  BtnModeRest  := MakeSpeed(PnlMode, 'Rest = Original - Stems (R)', 284, 6, 190, 1);
  BtnModeStems.Down := True;
  BtnModeStems.Hint := 'Die 4 Stems gemischt - mit Mute / Solo / Lautstärke';
  BtnModeOrig.Hint  := 'Originalmix aus der Datei (Spur 0) zum A/B-Vergleich';
  BtnModeRest.Hint  := 'Original minus Summe aller Stems: hörbar, was bei der Trennung' + LineEnding +
                       'verloren ging oder anders klingt (ideal: fast Stille).';
  BtnModeStems.ShowHint := True; BtnModeOrig.ShowHint := True; BtnModeRest.ShowHint := True;
  BtnModeStems.OnClick := @ModeClick;
  BtnModeOrig.OnClick := @ModeClick;
  BtnModeRest.OnClick := @ModeClick;

  BtnReset := TButton.Create(Self);
  BtnReset.Parent := PnlMode;
  BtnReset.SetBounds(PnlMode.Width - 170, 6, 160, 32);
  BtnReset.Anchors := [akTop, akRight];
  BtnReset.Caption := 'Alles zurücksetzen (0)';
  BtnReset.OnClick := @BtnResetClick;

  { ---------- 4 Stem-Zeilen ---------- }
  for i := 1 to STEM_COUNT do
    BuildStemRow(i, 300 + i * ROW_HEIGHT);

  { ---------- Master ---------- }
  PnlMaster := TPanel.Create(Self);
  PnlMaster.Parent := Self;
  PnlMaster.Align := alTop;
  PnlMaster.Top := 900;
  PnlMaster.Height := 56;
  PnlMaster.BevelOuter := bvNone;
  PnlMaster.Color := CLR_BG;
  PnlMaster.BorderSpacing.Top := 6;
  PnlMaster.Width := ClientWidth;

  MakeLabel(PnlMaster, 'Master', 14, 16, 12, True);
  TrkMaster := TTrackBar.Create(Self);
  TrkMaster.Parent := PnlMaster;
  TrkMaster.SetBounds(295, 10, 170, 32);
  TrkMaster.Min := 0;
  TrkMaster.Max := 100;
  TrkMaster.Position := 80;
  TrkMaster.Frequency := 10;
  TrkMaster.TickStyle := tsNone;
  TrkMaster.OnChange := @MasterChange;
  LblMasterVol := MakeLabel(PnlMaster, '80%', 470, 18, 0, False);

  MeterOut := TPaintBox.Create(Self);
  MeterOut.Parent := PnlMaster;
  MeterOut.SetBounds(520, 12, PnlMaster.Width - 520 - 80, 30);
  MeterOut.Anchors := [akLeft, akTop, akRight];
  MeterOut.OnPaint := @OutMeterPaint;

  LblClip := MakeLabel(PnlMaster, 'CLIP', 0, 18, 0, True);
  LblClip.AutoSize := False;
  LblClip.Alignment := taCenter;
  LblClip.SetBounds(PnlMaster.Width - 72, 18, 60, 20);
  LblClip.Anchors := [akTop, akRight];
  LblClip.Font.Color := CLR_DIM;
  LblClip.Hint := 'Leuchtet rot, wenn die Summe übersteuert (dann Master leiser stellen)';
  LblClip.ShowHint := True;

  { ---------- Unten ---------- }
  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 66;
  PnlBottom.BevelOuter := bvNone;
  PnlBottom.Color := CLR_PANEL;
  PnlBottom.Width := ClientWidth;

  LblHelp := MakeLabel(PnlBottom,
    'Leertaste Play/Pause  ·  1-4 Mute  ·  Shift+1-4 Solo  ·  0 zurücksetzen  ·  ' +
    'S/O/R Modus  ·  Pfeile -/+5 s  ·  Pos1 Anfang', 10, 6, 0, False);
  LblHelp.Font.Color := CLR_DIM;

  LblStatus := MakeLabel(PnlBottom, '', 10, 26, 0, False);
  LblStatus.Font.Color := CLR_DIM;
  LblStatus.Anchors := [akLeft, akTop, akRight];
  LblStatus.AutoSize := False;
  LblStatus.Width := PnlBottom.Width - 20;

  LblKofi := MakeLabel(PnlBottom, 'Gefällt dir das Tool? Unterstütze Elospeed auf ko-fi.com/elospeed', 10, 45, 0, False);
  LblKofi.Font.Color := $00FFB050;
  LblKofi.Font.Style := [fsUnderline];
  LblKofi.Cursor := crHandPoint;
  LblKofi.OnClick := @KofiClick;
end;

procedure TMainForm.BuildStemRow(Idx: Integer; ATop: Integer);
var
  R: ^TStemRow;
begin
  R := @Rows[Idx];
  R^.Color := FInfo.Colors[Idx - 1];
  R^.Level := 0;

  R^.Panel := TPanel.Create(Self);
  R^.Panel.Parent := Self;
  R^.Panel.Align := alTop;
  R^.Panel.Top := ATop;
  R^.Panel.Height := ROW_HEIGHT - 4;
  R^.Panel.BorderSpacing.Top := 4;
  R^.Panel.BorderSpacing.Left := 8;
  R^.Panel.BorderSpacing.Right := 8;
  R^.Panel.BevelOuter := bvNone;
  R^.Panel.Color := CLR_PANEL;
  R^.Panel.Width := ClientWidth - 16;

  R^.ColorBar := TShape.Create(Self);
  R^.ColorBar.Parent := R^.Panel;
  R^.ColorBar.Align := alLeft;
  R^.ColorBar.Width := 8;
  R^.ColorBar.Pen.Style := psClear;
  R^.ColorBar.Brush.Color := R^.Color;

  R^.LblName := MakeLabel(R^.Panel, Format('%d  %s', [Idx, FInfo.Names[Idx - 1]]), 18, 6, 12, True);
  R^.LblState := MakeLabel(R^.Panel, '', 18, 32, 0, False);
  R^.LblState.Font.Color := CLR_DIM;

  R^.BtnMute := MakeSpeed(R^.Panel, 'Mute', 140, 12, 66, 10 + Idx);
  R^.BtnMute.AllowAllUp := True;
  R^.BtnMute.Tag := Idx;
  R^.BtnMute.OnClick := @MuteSoloClick;
  R^.BtnMute.Hint := Format('Stem stumm schalten (Taste %d)', [Idx]);
  R^.BtnMute.ShowHint := True;

  R^.BtnSolo := MakeSpeed(R^.Panel, 'Solo', 210, 12, 66, 20 + Idx);
  R^.BtnSolo.AllowAllUp := True;
  R^.BtnSolo.Tag := 100 + Idx;
  R^.BtnSolo.OnClick := @MuteSoloClick;
  R^.BtnSolo.Hint := Format('Nur Solo-Stems hören - mehrere möglich (Shift+%d)', [Idx]);
  R^.BtnSolo.ShowHint := True;

  R^.TrkVol := TTrackBar.Create(Self);
  R^.TrkVol.Parent := R^.Panel;
  R^.TrkVol.SetBounds(287, 10, 170, 32);
  R^.TrkVol.Min := 0;
  R^.TrkVol.Max := 100;
  R^.TrkVol.Position := 100;
  R^.TrkVol.TickStyle := tsNone;
  R^.TrkVol.Tag := Idx;
  R^.TrkVol.OnChange := @VolChange;

  R^.LblVol := MakeLabel(R^.Panel, '100%', 462, 18, 0, False);

  R^.Meter := TPaintBox.Create(Self);
  R^.Meter.Parent := R^.Panel;
  R^.Meter.SetBounds(512, 14, R^.Panel.Width - 512 - 10, 28);
  R^.Meter.Anchors := [akLeft, akTop, akRight];
  R^.Meter.Tag := Idx;
  R^.Meter.OnPaint := @MeterPaint;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  { Datei als Kommandozeilen-Parameter? (z.B. aus StemMaker oder "Öffnen mit") }
  if (ParamCount >= 1) and FileExists(ParamStr(1)) and (FFileName = '') then
    LoadFile(ParamStr(1));
end;

{ ============================================================================
  ffmpeg finden
  ============================================================================ }

function TMainForm.IniFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

function TMainForm.FindFFmpeg: string;
const
  { Typische Orte relativ zur exe (StemMaker-Ordner, USB-Stick-Layout usw.) }
  Candidates: array[0..9] of string = (
    'ffmpeg.exe',
    'tools\ffmpeg.exe',
    'bin\ffmpeg.exe',
    'ffmpeg\ffmpeg.exe',
    'ffmpeg\bin\ffmpeg.exe',
    'tools\ffmpeg\bin\ffmpeg.exe',
    '..\ffmpeg.exe',
    '..\tools\ffmpeg.exe',
    '..\bin\ffmpeg.exe',
    '..\ffmpeg\bin\ffmpeg.exe');
var
  Base, S: string;
  i: Integer;
  Ini: TIniFile;
begin
  Result := '';
  { 1) Gespeicherter Pfad aus der .ini }
  try
    Ini := TIniFile.Create(IniFileName);
    try
      S := Ini.ReadString('Pfade', 'ffmpeg', '');
    finally
      Ini.Free;
    end;
    if (S <> '') and FileExists(S) then Exit(S);
  except
    { ini nicht lesbar -> ignorieren }
  end;
  { 2) Neben / unterhalb der exe }
  Base := ExtractFilePath(Application.ExeName);
  for i := Low(Candidates) to High(Candidates) do
  begin
    S := ExpandFileName(Base + Candidates[i]);
    if FileExists(S) then Exit(S);
  end;
  { 3) Im PATH (z.B. per winget installiert) }
  S := FindDefaultExecutablePath('ffmpeg.exe');
  if S <> '' then Exit(S);
end;

{ ============================================================================
  Datei laden
  ============================================================================ }

{ Gibt die aktuelle Datei frei und löscht ihren Temp-Ordner.
  Reihenfolge ist wichtig: zuerst den Audio-Thread beenden (er schliesst
  dabei seine .raw-Dateien), erst dann löschen - unter Windows lassen sich
  geöffnete Dateien nicht löschen. }
procedure TMainForm.UnloadFile;
begin
  if Engine <> nil then
  begin
    Engine.Free;           // stoppt Thread, schliesst Audiogerät und Dateien
    Engine := nil;
  end;
  if (FTempDir <> '') and DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);   // False = Ordner selbst auch löschen
  FTempDir := '';
  FFileName := '';
end;

{ Legt den Temp-Ordner dieser Instanz an und öffnet die Sperrdatei exklusiv.
  Solange die Datei offen ist, kann keine andere Instanz sie löschen - daran
  erkennt CleanupOrphanTempDirs, dass dieser Ordner noch in Gebrauch ist. }
procedure TMainForm.CreateInstanceDir;
begin
  FInstanceDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
                  TEMP_PREFIX + IntToStr(GetProcessID) + '_' +
                  IntToStr(GetTickCount64) + PathDelim;
  ForceDirectories(FInstanceDir);
  try
    FLockFile := TFileStream.Create(FInstanceDir + LOCK_NAME,
                                    fmCreate or fmShareExclusive);
  except
    FLockFile := nil;   // ohne Sperre läuft der Player trotzdem
  end;
end;

{ Schliesst die Sperrdatei und löscht den ganzen Instanz-Ordner
  (inkl. evtl. noch vorhandener Track-Unterordner). }
procedure TMainForm.ReleaseInstanceDir;
begin
  FreeAndNil(FLockFile);
  if (FInstanceDir <> '') and DirectoryExists(FInstanceDir) then
    DeleteDirectory(FInstanceDir, False);
  FInstanceDir := '';
end;

{ Löscht Temp-Ordner früherer Instanzen, die nach einem Absturz oder
  "Task beenden" liegen geblieben sind.
  Regel: Lässt sich die Sperrdatei "instance.lock" löschen, läuft die
  zugehörige Instanz nicht mehr -> Ordner weg. Ist sie gesperrt, gehört der
  Ordner einer noch laufenden StemPlayer-Instanz -> nicht anfassen.
  Ordner ohne Sperrdatei (z.B. ein Absturz direkt beim Anlegen) werden
  ebenfalls gelöscht. Es werden nur Ordner mit unserem Präfix angefasst. }
procedure TMainForm.CleanupOrphanTempDirs;
var
  TempRoot, Dir: string;
  SR: TSearchRec;
begin
  TempRoot := IncludeTrailingPathDelimiter(GetTempDir(False));
  if FindFirst(TempRoot + TEMP_PREFIX + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then Continue;
      Dir := TempRoot + SR.Name + PathDelim;
      if FileExists(Dir + LOCK_NAME) and not DeleteFile(Dir + LOCK_NAME) then
        Continue;                         // gesperrt -> Instanz läuft noch
      DeleteDirectory(Dir, False);        // verwaist -> komplett löschen
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Ruft ffmpeg auf und dekodiert alle Spuren nach FTempDir\trackN.raw.
  Rückgabe False bei Fehler oder Abbruch; ErrText enthält dann die
  Fehlermeldung von ffmpeg (leer bei Abbruch durch den Benutzer). }
function TMainForm.DecodeTracks(const FileName: string; TrackCount: Integer;
  out ErrText: string): Boolean;
var
  P: TProcess;
  t: Integer;
  T0: QWord;
  Buf: array[0..1023] of Char;
  Chunk: string;
  n: LongInt;

  { Liest alles, was ffmpeg bisher ausgegeben hat. Muss laufend aufgerufen
    werden, sonst läuft die Pipe voll und ffmpeg bleibt hängen. Wegen
    "-loglevel error" kommt hier normalerweise nichts oder nur wenig Text. }
  procedure DrainOutput;
  begin
    while P.Output.NumBytesAvailable > 0 do
    begin
      n := P.Output.Read(Buf, SizeOf(Buf));
      if n <= 0 then Break;
      SetString(Chunk, PChar(@Buf[0]), n);   // genau n Bytes übernehmen
      ErrText := ErrText + Chunk;
      { Nur das Ende behalten - die letzte Meldung ist die aussagekräftige }
      if Length(ErrText) > 4000 then
        ErrText := Copy(ErrText, Length(ErrText) - 2000, MaxInt);
    end;
  end;

begin
  Result := False;
  ErrText := '';
  FCancelLoad := False;
  P := TProcess.Create(nil);
  try
    P.Executable := FFFmpeg;
    P.Parameters.Add('-hide_banner');
    P.Parameters.Add('-nostdin');          // nie auf Tastatureingaben warten
    P.Parameters.Add('-loglevel');
    P.Parameters.Add('error');             // nur echte Fehler ausgeben
    P.Parameters.Add('-y');                // vorhandene Dateien überschreiben
    P.Parameters.Add('-i');
    P.Parameters.Add(FileName);
    { Ein Aufruf, mehrere Ausgaben: jede Audiospur in eine eigene .raw-Datei.
      "0:a:N" = N-te Audiospur der Eingabe (0 = Master, 1..4 = Stems). }
    for t := 0 to TrackCount - 1 do
    begin
      P.Parameters.Add('-map');
      P.Parameters.Add('0:a:' + IntToStr(t));
      P.Parameters.Add('-ac');
      P.Parameters.Add('2');                     // Stereo
      P.Parameters.Add('-ar');
      P.Parameters.Add(IntToStr(SAMPLE_RATE));   // 44.1 kHz
      P.Parameters.Add('-c:a');
      P.Parameters.Add('pcm_s16le');             // 16 Bit signed, little endian
      P.Parameters.Add('-f');
      P.Parameters.Add('s16le');                 // rohe Daten ohne WAV-Header
      P.Parameters.Add(FTempDir + 'track' + IntToStr(t) + '.raw');
    end;
    { Fehlerausgabe (stderr) über eine Pipe mitlesen, kein Konsolenfenster }
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHIDE;
    P.Execute;

    T0 := GetTickCount64;
    while P.Running do
    begin
      DrainOutput;
      { Benutzer hat das Fenster geschlossen -> ffmpeg abbrechen }
      if FCancelLoad then
      begin
        P.Terminate(1);
        P.WaitOnExit;          // warten, bis ffmpeg seine Dateien freigegeben hat
        ErrText := '';
        Exit(False);
      end;
      LblStatus.Caption := Format('Dekodiere %d Spuren mit ffmpeg ... %.1f s',
        [TrackCount, (GetTickCount64 - T0) / 1000]);
      Application.ProcessMessages;   // Fenster bleibt bedienbar
      Sleep(30);
    end;
    DrainOutput;   // Rest nach Prozessende einsammeln
    ErrText := Trim(ErrText);

    Result := (P.ExitStatus = 0) and FileExists(FTempDir + 'track0.raw');
    if (not Result) and (ErrText = '') then
      ErrText := Format('ffmpeg wurde mit Code %d beendet.', [P.ExitStatus]);
  finally
    P.Free;
  end;
end;

{ Schliesst das Fenster, nachdem ein abgebrochener Ladevorgang aufgeräumt
  ist. Wird per QueueAsyncCall aufgerufen, also erst wenn LoadFile komplett
  zurückgekehrt ist - nie mitten aus LoadFile heraus. }
procedure TMainForm.DeferredClose(Data: PtrInt);
begin
  Close;
end;

procedure TMainForm.LoadFile(const FileName: string);
var
  Tracks, i: Integer;
  Raw: array[0..TRACK_MAX] of string;
  Ok: Boolean;
  Ini: TIniFile;
  Msg, ErrText: string;
  Dlg: TOpenDialog;
begin
  if FLoading then Exit;
  if not FileExists(FileName) then Exit;

  { ffmpeg vorhanden? Sonst einmalig fragen und merken }
  if (FFFmpeg = '') or not FileExists(FFFmpeg) then
  begin
    MessageDlg(APP_TITLE,
      'ffmpeg.exe wurde nicht gefunden.' + LineEnding +
      'Bitte im nächsten Dialog die ffmpeg.exe auswählen' + LineEnding +
      '(z.B. die von Elospeed StemMaker).', mtInformation, [mbOK], 0);
    Dlg := TOpenDialog.Create(nil);
    try
      Dlg.Title := 'ffmpeg.exe auswählen';
      Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|Programme (*.exe)|*.exe';
      if not Dlg.Execute then Exit;
      FFFmpeg := Dlg.FileName;
    finally
      Dlg.Free;
    end;
    try
      Ini := TIniFile.Create(IniFileName);
      try
        Ini.WriteString('Pfade', 'ffmpeg', FFFmpeg);
      finally
        Ini.Free;
      end;
    except
      { z.B. schreibgeschützter Ordner -> dann eben nächstes Mal wieder fragen }
    end;
  end;

  FLoading := True;
  Screen.Cursor := crHourGlass;
  BtnOpen.Enabled := False;
  try
    UnloadFile;

    { 1) Struktur lesen }
    ReadStemInfo(FileName, FInfo);
    Tracks := FInfo.AudioTracks;
    if Tracks = 0 then Tracks := 5;            // nicht lesbar -> Standard annehmen
    if Tracks > TRACK_MAX + 1 then Tracks := TRACK_MAX + 1;

    Msg := '';
    if FInfo.AudioTracks < 5 then
      Msg := Format('Achtung: Datei hat nur %d Audiospur(en) - eine Traktor-Stem-Datei hat 5.', [FInfo.AudioTracks])
    else if not FInfo.HasStemBox then
      Msg := 'Hinweis: kein Traktor-"stem"-Block gefunden (Standardnamen werden verwendet).';

    { 2) Dekodieren }
    FTempDir := FInstanceDir + 'track_' +
                IntToStr(GetTickCount64) + PathDelim;
    ForceDirectories(FTempDir);
    LblFile.Caption := ExtractFileName(FileName);
    Ok := DecodeTracks(FileName, Tracks, ErrText);
    if not Ok then
    begin
      UnloadFile;   // halbfertige .raw-Dateien wieder löschen
      if FCancelLoad then
      begin
        { Abbruch durch Schliessen des Fensters -> keine Fehlermeldung }
        LblStatus.Caption := 'Laden abgebrochen.';
        LblFile.Caption := '';
        Exit;
      end;
      LblStatus.Caption := 'Fehler beim Dekodieren: ' +
        StringReplace(ErrText, LineEnding, ' | ', [rfReplaceAll]);
      MessageDlg(APP_TITLE, 'ffmpeg konnte die Datei nicht dekodieren:' + LineEnding +
        FileName + LineEnding + LineEnding + 'Meldung von ffmpeg:' + LineEnding +
        ErrText, mtError, [mbOK], 0);
      Exit;
    end;

    { 3) Engine starten }
    for i := 0 to TRACK_MAX do
      if i < Tracks then Raw[i] := FTempDir + 'track' + IntToStr(i) + '.raw'
      else Raw[i] := '';
    Engine := TStemEngine.Create(Raw);
    if Engine.OpenError <> '' then
      MessageDlg(APP_TITLE, Engine.OpenError, mtError, [mbOK], 0);
    FFileName := FileName;

    { 4) Oberfläche anpassen }
    for i := 1 to STEM_COUNT do
    begin
      Rows[i].LblName.Caption := Format('%d  %s', [i, FInfo.Names[i - 1]]);
      Rows[i].Color := FInfo.Colors[i - 1];
      Rows[i].ColorBar.Brush.Color := Rows[i].Color;
      Rows[i].Panel.Enabled := i < Tracks;     // fehlende Spuren deaktivieren
    end;
    FUpdatingPos := True;
    TrkPos.Max := Max(1, Engine.TotalFrames div (SAMPLE_RATE div 10)); // 1/10 s Schritte
    TrkPos.Position := 0;
    FUpdatingPos := False;
    TrkPos.Enabled := True;
    BtnPlay.Enabled := True;
    BtnStop.Enabled := True;
    FLastClip := 0;
    FClipTicks := 0;
    Caption := ExtractFileName(FileName) + '  -  ' + APP_TITLE;

    if Msg <> '' then LblStatus.Caption := Msg
    else LblStatus.Caption := Format('%d Spuren geladen  ·  Länge %s  ·  ffmpeg: %s',
      [Tracks, FormatTime(Engine.TotalFrames), FFFmpeg]);

    UpdateGains;
    { Direkt losspielen - zum schnellen Testen }
    Engine.Playing := True;
  finally
    Screen.Cursor := crDefault;
    BtnOpen.Enabled := True;
    FLoading := False;
    { Wurde während des Ladens "Schliessen" gedrückt? Jetzt, wo alles
      aufgeräumt ist, das Fenster wirklich schliessen. }
    if FCloseAfterLoad then
      Application.QueueAsyncCall(@DeferredClose, 0);
  end;
end;

{ ============================================================================
  Steuerung
  ============================================================================ }

{ Berechnet aus Mute / Solo / Fader den effektiven Gain jeder Spur. }
procedure TMainForm.UpdateGains;
var
  i: Integer;
  AnySolo, IsOn: Boolean;
begin
  AnySolo := False;
  for i := 1 to STEM_COUNT do
    if Rows[i].BtnSolo.Down then AnySolo := True;

  for i := 1 to STEM_COUNT do
  begin
    { Solo hat Vorrang vor Mute: ein Solo-Stem ist immer hörbar }
    if AnySolo then
      IsOn := Rows[i].BtnSolo.Down
    else
      IsOn := not Rows[i].BtnMute.Down;
    if Engine <> nil then
    begin
      if IsOn then Engine.Gain[i] := Rows[i].TrkVol.Position / 100
      else Engine.Gain[i] := 0;
    end;
    Rows[i].Panel.Tag := Ord(IsOn);   // für die Darstellung merken
  end;
  if Engine <> nil then
    Engine.MasterVol := TrkMaster.Position / 100;
  UpdateRowLook;
end;

{ Zeigt den Zustand jeder Zeile an (Text + abgedunkelt). }
procedure TMainForm.UpdateRowLook;
var
  i: Integer;
  S: string;
  IsOn, StemMode: Boolean;
begin
  StemMode := BtnModeStems.Down;
  { aktiven Modus-Button fett darstellen }
  if BtnModeStems.Down then BtnModeStems.Font.Style := [fsBold] else BtnModeStems.Font.Style := [];
  if BtnModeOrig.Down then BtnModeOrig.Font.Style := [fsBold] else BtnModeOrig.Font.Style := [];
  if BtnModeRest.Down then BtnModeRest.Font.Style := [fsBold] else BtnModeRest.Font.Style := [];
  for i := 1 to STEM_COUNT do
  begin
    IsOn := Rows[i].Panel.Tag = 1;
    if not StemMode then
    begin
      if BtnModeOrig.Down then S := '(Modus: Original)' else S := '(Modus: Rest)';
    end
    else if Rows[i].BtnSolo.Down then S := 'SOLO'
    else if not IsOn then
    begin
      if Rows[i].BtnMute.Down then S := 'STUMM' else S := 'aus (anderes Solo aktiv)';
    end
    else S := 'hörbar';
    Rows[i].LblState.Caption := S;
    { Gedrückte Mute/Solo-Buttons zusätzlich farbig + fett hervorheben }
    if Rows[i].BtnMute.Down then
    begin
      Rows[i].BtnMute.Font.Color := clRed;
      Rows[i].BtnMute.Font.Style := [fsBold];
    end
    else
    begin
      Rows[i].BtnMute.Font.Color := clBlack;
      Rows[i].BtnMute.Font.Style := [];
    end;
    if Rows[i].BtnSolo.Down then
    begin
      Rows[i].BtnSolo.Font.Color := $00008000;  // dunkelgrün
      Rows[i].BtnSolo.Font.Style := [fsBold];
    end
    else
    begin
      Rows[i].BtnSolo.Font.Color := clBlack;
      Rows[i].BtnSolo.Font.Style := [];
    end;
    if IsOn and StemMode then
    begin
      Rows[i].LblName.Font.Color := CLR_TEXT;
      Rows[i].ColorBar.Brush.Color := Rows[i].Color;
    end
    else
    begin
      Rows[i].LblName.Font.Color := CLR_DIM;
      Rows[i].ColorBar.Brush.Color := CLR_DIM;
    end;
    Rows[i].Meter.Invalidate;
  end;
end;

procedure TMainForm.TogglePlay;
begin
  if Engine = nil then Exit;
  if Engine.EndReached then Engine.SeekTo := 0;
  Engine.Playing := not Engine.Playing;
end;

procedure TMainForm.StopPlay;
begin
  if Engine = nil then Exit;
  Engine.Playing := False;
  Engine.SeekTo := 0;
end;

procedure TMainForm.SeekRelative(Seconds: Integer);
var P: Int64;
begin
  if Engine = nil then Exit;
  P := Engine.PlayPos + Int64(Seconds) * SAMPLE_RATE;
  if P < 0 then P := 0;
  if P >= Engine.TotalFrames then P := Engine.TotalFrames - 1;
  Engine.SeekTo := P;
end;

procedure TMainForm.SetMode(M: TPlayMode);
begin
  case M of
    pmStems   : BtnModeStems.Down := True;
    pmMaster  : BtnModeOrig.Down := True;
    pmResidual: BtnModeRest.Down := True;
  end;
  if Engine <> nil then Engine.Mode := M;
  UpdateRowLook;
end;

function TMainForm.FormatTime(Frames: Int64): string;
var Sec: Int64;
begin
  Sec := Frames div SAMPLE_RATE;
  Result := Format('%.2d:%.2d', [Sec div 60, Sec mod 60]);
end;

{ Pegel (0..1 linear) -> Balkenlänge (0..1) auf einer dB-Skala von -48..0 dB }
function TMainForm.LevelToFrac(L: Single): Single;
var dB: Single;
begin
  if L <= 0.0001 then Exit(0);
  dB := 20 * Log10(L);
  Result := (dB + 48) / 48;
  if Result < 0 then Result := 0;
  if Result > 1 then Result := 1;
end;

{ ============================================================================
  Ereignisse
  ============================================================================ }

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  if OpenDlg.Execute then LoadFile(OpenDlg.FileName);
end;

procedure TMainForm.BtnPlayClick(Sender: TObject);
begin
  TogglePlay;
end;

procedure TMainForm.BtnStopClick(Sender: TObject);
begin
  StopPlay;
end;

procedure TMainForm.BtnResetClick(Sender: TObject);
var i: Integer;
begin
  for i := 1 to STEM_COUNT do
  begin
    Rows[i].BtnMute.Down := False;
    Rows[i].BtnSolo.Down := False;
    Rows[i].TrkVol.Position := 100;
  end;
  SetMode(pmStems);
  UpdateGains;
end;

procedure TMainForm.ModeClick(Sender: TObject);
begin
  if Sender = BtnModeOrig then SetMode(pmMaster)
  else if Sender = BtnModeRest then SetMode(pmResidual)
  else SetMode(pmStems);
end;

procedure TMainForm.MuteSoloClick(Sender: TObject);
begin
  { Wer Mute/Solo drückt, will Stems hören -> Modus automatisch auf Stems }
  if not BtnModeStems.Down then SetMode(pmStems);
  UpdateGains;
end;

procedure TMainForm.VolChange(Sender: TObject);
var i: Integer;
begin
  i := TTrackBar(Sender).Tag;
  if (i >= 1) and (i <= STEM_COUNT) then
    Rows[i].LblVol.Caption := IntToStr(Rows[i].TrkVol.Position) + '%';
  UpdateGains;
end;

procedure TMainForm.MasterChange(Sender: TObject);
begin
  LblMasterVol.Caption := IntToStr(TrkMaster.Position) + '%';
  UpdateGains;
end;

procedure TMainForm.PosChange(Sender: TObject);
begin
  { Nur auf Benutzeraktionen reagieren, nicht auf Updates aus dem Timer }
  if FUpdatingPos or (Engine = nil) then Exit;
  Engine.SeekTo := Int64(TrkPos.Position) * (SAMPLE_RATE div 10);
end;

procedure TMainForm.PosMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDraggingPos := True;
end;

procedure TMainForm.PosMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDraggingPos := False;
end;

procedure TMainForm.MeterPaint(Sender: TObject);
var
  PB: TPaintBox;
  i, W: Integer;
  IsOn: Boolean;
  C: TColor;
begin
  PB := TPaintBox(Sender);
  i := PB.Tag;
  IsOn := (Rows[i].Panel.Tag = 1) and BtnModeStems.Down;
  with PB.Canvas do
  begin
    Brush.Color := CLR_METERBG;
    FillRect(0, 0, PB.Width, PB.Height);
    W := Round(LevelToFrac(Rows[i].Level) * PB.Width);
    { Aktive Stems in ihrer Farbe, stumme grau (Pegel wird trotzdem angezeigt,
      damit man sieht, ob in dieser Spur überhaupt etwas los ist) }
    if IsOn then C := Rows[i].Color else C := $00505050;
    Brush.Color := C;
    if W > 0 then FillRect(0, 4, W, PB.Height - 4);
    { Skalenstriche bei -36, -24, -12, -6 dB }
    Pen.Color := $00606060;
    Line(Round(PB.Width * 12 / 48), 0, Round(PB.Width * 12 / 48), 3);
    Line(Round(PB.Width * 24 / 48), 0, Round(PB.Width * 24 / 48), 3);
    Line(Round(PB.Width * 36 / 48), 0, Round(PB.Width * 36 / 48), 3);
    Line(Round(PB.Width * 42 / 48), 0, Round(PB.Width * 42 / 48), 3);
  end;
end;

procedure TMainForm.OutMeterPaint(Sender: TObject);
var
  ch, W, H, Y: Integer;
  F: Single;
begin
  with MeterOut.Canvas do
  begin
    Brush.Color := CLR_METERBG;
    FillRect(0, 0, MeterOut.Width, MeterOut.Height);
    H := (MeterOut.Height - 6) div 2;
    for ch := 0 to 1 do
    begin
      Y := 2 + ch * (H + 2);
      F := LevelToFrac(FOutLevel[ch]);
      W := Round(F * MeterOut.Width);
      { grün bis -6 dB, gelb bis -1 dB, rot darüber }
      Brush.Color := $0050C850;
      FillRect(0, Y, Min(W, Round(MeterOut.Width * 42 / 48)), Y + H);
      if W > Round(MeterOut.Width * 42 / 48) then
      begin
        Brush.Color := $0000D0F0;
        FillRect(Round(MeterOut.Width * 42 / 48), Y, Min(W, Round(MeterOut.Width * 47 / 48)), Y + H);
      end;
      if W > Round(MeterOut.Width * 47 / 48) then
      begin
        Brush.Color := $003030F0;
        FillRect(Round(MeterOut.Width * 47 / 48), Y, W, Y + H);
      end;
    end;
  end;
end;

procedure TMainForm.TimerTick(Sender: TObject);
var
  i: Integer;
  L: Single;
  Playing: Boolean;
begin
  if Engine = nil then Exit;
  Playing := Engine.Playing;

  { Ende erreicht -> anhalten und an den Anfang }
  if Engine.EndReached and Playing then
  begin
    Engine.Playing := False;
    Engine.SeekTo := 0;
    Playing := False;
  end;

  if Playing then BtnPlay.Caption := 'Pause' else BtnPlay.Caption := 'Play';

  { Position anzeigen (nicht während der Benutzer den Regler zieht) }
  if not FDraggingPos then
  begin
    FUpdatingPos := True;
    TrkPos.Position := Engine.PlayPos div (SAMPLE_RATE div 10);
    FUpdatingPos := False;
  end;
  LblTime.Caption := FormatTime(Engine.PlayPos) + ' / ' + FormatTime(Engine.TotalFrames);

  { Pegel: schnell hoch, langsam runter (klassisches Peak-Meter-Verhalten) }
  for i := 1 to STEM_COUNT do
  begin
    if Playing then L := Engine.Peak[i] else L := 0;
    if L > Rows[i].Level then Rows[i].Level := L
    else Rows[i].Level := Rows[i].Level * 0.82;
    Rows[i].Meter.Invalidate;
  end;
  for i := 0 to 1 do
  begin
    if Playing then L := Engine.OutPeak[i] else L := 0;
    if L > FOutLevel[i] then FOutLevel[i] := L
    else FOutLevel[i] := FOutLevel[i] * 0.82;
  end;
  MeterOut.Invalidate;

  { Clip-Anzeige ~1 s nachleuchten lassen }
  if Engine.ClipCount <> FLastClip then
  begin
    FLastClip := Engine.ClipCount;
    FClipTicks := 33;
  end;
  if FClipTicks > 0 then
  begin
    Dec(FClipTicks);
    LblClip.Font.Color := $003030FF;
  end
  else
    LblClip.Font.Color := CLR_DIM;
end;

procedure TMainForm.KofiClick(Sender: TObject);
begin
  OpenURL(KOFI_URL);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  i: Integer;
begin
  case Key of
    VK_SPACE:
      begin
        TogglePlay;
        Key := 0;  // verhindert, dass der fokussierte Button die Taste auch bekommt
      end;
    VK_1..VK_4:
      begin
        i := Key - VK_1 + 1;
        if ssShift in Shift then
          Rows[i].BtnSolo.Down := not Rows[i].BtnSolo.Down
        else
          Rows[i].BtnMute.Down := not Rows[i].BtnMute.Down;
        if not BtnModeStems.Down then SetMode(pmStems);
        UpdateGains;
        Key := 0;
      end;
    VK_NUMPAD1..VK_NUMPAD4:
      begin
        i := Key - VK_NUMPAD1 + 1;
        Rows[i].BtnMute.Down := not Rows[i].BtnMute.Down;
        if not BtnModeStems.Down then SetMode(pmStems);
        UpdateGains;
        Key := 0;
      end;
    VK_0, VK_NUMPAD0:
      begin
        BtnResetClick(nil);
        Key := 0;
      end;
    VK_S: begin SetMode(pmStems); Key := 0; end;
    VK_O:
      begin
        if ssCtrl in Shift then BtnOpenClick(nil) else SetMode(pmMaster);
        Key := 0;
      end;
    VK_R: begin SetMode(pmResidual); Key := 0; end;
    VK_LEFT:  begin SeekRelative(-5); Key := 0; end;
    VK_RIGHT: begin SeekRelative(5); Key := 0; end;
    VK_HOME:  begin if Engine <> nil then Engine.SeekTo := 0; Key := 0; end;
  end;
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) > 0 then LoadFile(FileNames[0]);
end;

{ Wird vor dem Schliessen gefragt. Läuft gerade ffmpeg, darf das Fenster
  noch nicht zu: ffmpeg hält seine Ausgabedateien offen und würde sonst
  weiter in den (dann gelöschten) Temp-Ordner schreiben. Stattdessen wird
  der Abbruch angefordert; LoadFile räumt auf und schliesst danach selbst. }
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FLoading then
  begin
    FCancelLoad := True;
    FCloseAfterLoad := True;
    LblStatus.Caption := 'Breche Dekodieren ab ...';
    CanClose := False;
  end
  else
    CanClose := True;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  Timer.Enabled := False;
  UnloadFile;          // Thread beenden + Track-Ordner löschen
  ReleaseInstanceDir;  // Sperrdatei schliessen + Instanz-Ordner löschen
end;

end.
