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
    1.2  (03.10.2026)  Neues Design "Traktor Dark": selbst gezeichnete Buttons,
                       Fader, Positionsleiste und LED-Meter (djcontrols.pas).
                       Bedienung und Funktion unverändert.
    1.3  (04.10.2026)  Ordner als Parameter: der Öffnen-Dialog startet gleich
                       in diesem Ordner (Knopf "Anhören" in StemMaker).
  ============================================================================ }
unit playerform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Buttons, LCLType, LCLIntf, Process, FileUtil,
  LazFileUtils, IniFiles, mp4stem, stemengine, djcontrols;

const
  APP_TITLE = 'Elospeed StemPlayer';
  APP_VER   = '1.3';
  TEMP_PREFIX = 'ElospeedStemPlayer_';  // Präfix der Temp-Ordner (siehe oben)
  LOCK_NAME   = 'instance.lock';        // Sperrdatei im Instanz-Ordner
  KOFI_URL  = 'https://ko-fi.com/elospeed';

type
  { Eine Zeile pro Stem }
  TStemRow = record
    Panel    : TDJPanel;   // Zeile mit farbigem Streifen links (Stemfarbe)
    LblName  : TLabel;
    LblState : TLabel;
    BtnMute  : TDJButton;
    BtnSolo  : TDJButton;
    TrkVol   : TDJSlider;
    LblVol   : TLabel;
    Meter    : TPaintBox;
    Color    : TColor;
    Level    : Single;     // geglätteter Anzeigepegel 0..1
  end;

  { TMainForm }

  TMainForm = class(TForm)
  private
    { --- Oberer Bereich --- }
    PnlTop      : TDJPanel;
    BtnOpen     : TDJButton;
    LblFile     : TLabel;
    LblFileInfo : TLabel;      // kleine Zeile unter dem Dateinamen
    { --- "Deck": Transport + Modus --- }
    PnlDeck     : TDJPanel;
    BtnPlay     : TDJButton;
    BtnStop     : TDJButton;
    TrkPos      : TDJSlider;
    LblTime     : TLabel;      // aktuelle Position (gross)
    LblTotal    : TLabel;      // Gesamtlänge (klein, gedimmt)
    BtnModeStems: TDJButton;
    BtnModeOrig : TDJButton;
    BtnModeRest : TDJButton;
    BtnReset    : TDJButton;
    { --- Stems --- }
    Rows        : array[1..STEM_COUNT] of TStemRow;
    { --- Master --- }
    PnlMaster   : TDJPanel;
    TrkMaster   : TDJSlider;
    LblMasterVol: TLabel;
    MeterOut    : TPaintBox;
    BtnClip     : TDJButton;   // reine Anzeige, leuchtet bei Übersteuerung
    { --- Unten --- }
    PnlBottom   : TDJPanel;
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
    procedure BuildStemRow(Idx: Integer);
    function  MakeButton(AParent: TWinControl; const ACaption: string;
                         ALeft, ATop, AWidth, AHeight: Integer): TDJButton;
    function  MakeFader(AParent: TWinControl; ALeft, ATop, AWidth: Integer;
                        AFill: TColor): TDJSlider;
    function  MakeDJPanel(AHeight, ASpaceTop: Integer): TDJPanel;
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
    procedure OpenDialogLater(Data: PtrInt);
  public
    constructor Create(TheOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

const
  { Farben: siehe djcontrols.pas (Palette "Traktor Dark") }
  ROW_HEIGHT  = 54;   // Höhe einer Stem-Zeile
  MARGIN      = 10;   // Abstand der Flächen zum Fensterrand
  MONO_FONT   = 'Consolas';   // Zahlen mit fester Breite (springen nicht)

{ ============================================================================
  Aufbau des Fensters
  ============================================================================ }

constructor TMainForm.Create(TheOwner: TComponent);
begin
  { Keine .lfm-Datei -> CreateNew statt Create }
  inherited CreateNew(TheOwner);
  Caption := APP_TITLE + ' ' + APP_VER + '  -  von Elospeed';
  Width := 820;
  Height := 590;
  Constraints.MinWidth := 720;
  Constraints.MinHeight := 590;
  Position := poScreenCenter;
  Color := DJ_BG;
  Font.Name := 'Segoe UI';
  Font.Color := DJ_TEXT;
  DoubleBuffered := True;   // weniger Flackern bei den Pegelanzeigen
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
  Result.Font.Color := DJ_TEXT;
  if ASize > 0 then Result.Font.Size := ASize;
  if ABold then Result.Font.Style := [fsBold];
end;

{ Flacher DJ-Button (siehe djcontrols.pas) }
function TMainForm.MakeButton(AParent: TWinControl; const ACaption: string;
  ALeft, ATop, AWidth, AHeight: Integer): TDJButton;
begin
  Result := TDJButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, AHeight);
  Result.Caption := ACaption;
end;

{ Lautstärke-Fader 0..100 % mit farbiger Füllung }
function TMainForm.MakeFader(AParent: TWinControl; ALeft, ATop, AWidth: Integer;
  AFill: TColor): TDJSlider;
begin
  Result := TDJSlider.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 26);
  Result.Style := dssFader;
  Result.Min := 0;
  Result.Max := 100;
  Result.FillColor := AFill;
end;

{ Dunkle Fläche mit Rahmen, oben angedockt, links/rechts mit Abstand zum Rand.
  Die Reihenfolge der oben angedockten Flächen ergibt sich aus der
  Reihenfolge der Aufrufe (jede neue Fläche kommt unter die vorige). }
function TMainForm.MakeDJPanel(AHeight, ASpaceTop: Integer): TDJPanel;
begin
  Result := TDJPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  { Aufsteigender Top-Wert -> neue Fläche landet unter allen bisherigen }
  Result.Top := ControlCount * 100;
  Result.Height := AHeight;
  Result.BorderSpacing.Top := ASpaceTop;
  Result.BorderSpacing.Left := MARGIN;
  Result.BorderSpacing.Right := MARGIN;
  { Breite vorab setzen, damit die rechts verankerten Elemente stimmen }
  Result.Width := ClientWidth - 2 * MARGIN;
end;

procedure TMainForm.BuildUI;
var
  i, W: Integer;
  L: TLabel;
begin
  W := ClientWidth - 2 * MARGIN;   // Breite der Flächen

  { ---------- Oben: Datei ---------- }
  PnlTop := MakeDJPanel(56, 4);
  PnlTop.Color := DJ_BG;
  PnlTop.BorderColor := clNone;    // ohne Rahmen, liegt direkt auf dem Fenster

  BtnOpen := MakeButton(PnlTop, 'ÖFFNEN', 0, 12, 96, 32);
  BtnOpen.Hint := 'Stem-Datei öffnen (Strg+O) - oder einfach aufs Fenster ziehen';
  BtnOpen.ShowHint := True;
  BtnOpen.OnClick := @BtnOpenClick;

  LblFile := MakeLabel(PnlTop, 'Stem-Datei öffnen oder hierher ziehen (Drag & Drop)', 110, 8, 12, True);
  LblFile.Anchors := [akLeft, akTop, akRight];
  LblFile.AutoSize := False;
  LblFile.SetBounds(110, 8, W - 110, 24);

  LblFileInfo := MakeLabel(PnlTop, '', 110, 32, 0, False);
  LblFileInfo.Font.Color := DJ_DIM;

  { ---------- Deck: Transport (Zeile 1) + Modus (Zeile 2) ---------- }
  PnlDeck := MakeDJPanel(96, 4);

  BtnPlay := MakeButton(PnlDeck, '', 12, 12, 46, 34);
  BtnPlay.Glyph := dgPlay;
  BtnPlay.LitColor := DJ_GREEN;
  BtnPlay.Enabled := False;
  BtnPlay.Hint := 'Play / Pause (Leertaste)';
  BtnPlay.ShowHint := True;
  BtnPlay.OnClick := @BtnPlayClick;

  BtnStop := MakeButton(PnlDeck, '', 64, 12, 46, 34);
  BtnStop.Glyph := dgStop;
  BtnStop.Enabled := False;
  BtnStop.Hint := 'Stop und zurück an den Anfang';
  BtnStop.ShowHint := True;
  BtnStop.OnClick := @BtnStopClick;

  TrkPos := TDJSlider.Create(Self);
  TrkPos.Parent := PnlDeck;
  TrkPos.Style := dssPosition;
  TrkPos.SetBounds(120, 12, W - 120 - 172, 34);
  TrkPos.Anchors := [akLeft, akTop, akRight];
  TrkPos.Min := 0;
  TrkPos.Max := 1000;
  TrkPos.Enabled := False;
  TrkPos.OnChange := @PosChange;
  TrkPos.OnMouseDown := @PosMouseDown;
  TrkPos.OnMouseUp := @PosMouseUp;

  { Zeit: aktuelle Position gross, Gesamtlänge klein daneben }
  LblTime := MakeLabel(PnlDeck, '00:00', 0, 12, 18, True);
  LblTime.Font.Name := MONO_FONT;
  LblTime.AutoSize := False;
  LblTime.Alignment := taRightJustify;
  LblTime.SetBounds(W - 168, 12, 88, 32);
  LblTime.Anchors := [akTop, akRight];

  LblTotal := MakeLabel(PnlDeck, '/ 00:00', 0, 22, 10, False);
  LblTotal.Font.Name := MONO_FONT;
  LblTotal.Font.Color := DJ_DIM;
  LblTotal.AutoSize := False;
  LblTotal.SetBounds(W - 76, 22, 70, 20);
  LblTotal.Anchors := [akTop, akRight];

  L := MakeLabel(PnlDeck, 'HÖREN', 12, 62, 8, False);
  L.Font.Color := DJ_DIM;

  { Modus-Umschaltung: drei aneinanderliegende Buttons, der aktive ist hell }
  BtnModeStems := MakeButton(PnlDeck, 'STEMS  S', 62, 56, 96, 28);
  BtnModeOrig  := MakeButton(PnlDeck, 'ORIGINAL  O', 157, 56, 116, 28);
  BtnModeRest  := MakeButton(PnlDeck, 'REST  R', 272, 56, 90, 28);
  BtnModeStems.Down := True;
  BtnModeStems.Hint := 'Die 4 Stems gemischt - mit Mute / Solo / Lautstärke (Taste S)';
  BtnModeOrig.Hint  := 'Originalmix aus der Datei (Spur 0) zum A/B-Vergleich (Taste O)';
  BtnModeRest.Hint  := 'Rest = Original minus Summe aller Stems (Taste R):' + LineEnding +
                       'hörbar, was bei der Trennung verloren ging oder anders' + LineEnding +
                       'klingt (ideal: fast Stille).';
  BtnModeStems.ShowHint := True; BtnModeOrig.ShowHint := True; BtnModeRest.ShowHint := True;
  BtnModeStems.OnClick := @ModeClick;
  BtnModeOrig.OnClick := @ModeClick;
  BtnModeRest.OnClick := @ModeClick;

  BtnReset := MakeButton(PnlDeck, 'RESET  0', W - 112, 56, 100, 28);
  BtnReset.Anchors := [akTop, akRight];
  BtnReset.Hint := 'Alles zurücksetzen: Mute/Solo aus, Fader auf 100 %, Modus Stems (Taste 0)';
  BtnReset.ShowHint := True;
  BtnReset.OnClick := @BtnResetClick;

  { ---------- 4 Stem-Zeilen ---------- }
  for i := 1 to STEM_COUNT do
    BuildStemRow(i);

  { ---------- Master ---------- }
  PnlMaster := MakeDJPanel(60, 8);

  MakeLabel(PnlMaster, 'MASTER', 14, 10, 11, True);
  L := MakeLabel(PnlMaster, 'AUSGANG L / R', 14, 34, 8, False);
  L.Font.Color := DJ_DIM;

  TrkMaster := MakeFader(PnlMaster, 224, 17, 200, DJ_TEXT);
  TrkMaster.Position := 80;
  TrkMaster.OnChange := @MasterChange;
  LblMasterVol := MakeLabel(PnlMaster, '80%', 0, 21, 0, False);
  LblMasterVol.Font.Name := MONO_FONT;
  LblMasterVol.Font.Color := $00AAAAAA;
  LblMasterVol.AutoSize := False;
  LblMasterVol.Alignment := taRightJustify;
  LblMasterVol.SetBounds(428, 21, 46, 20);

  MeterOut := TPaintBox.Create(Self);
  MeterOut.Parent := PnlMaster;
  MeterOut.SetBounds(486, 16, W - 486 - 72, 28);
  MeterOut.Anchors := [akLeft, akTop, akRight];
  MeterOut.OnPaint := @OutMeterPaint;

  BtnClip := MakeButton(PnlMaster, 'CLIP', W - 60, 17, 48, 26);
  BtnClip.Anchors := [akTop, akRight];
  BtnClip.LitColor := DJ_RED;
  BtnClip.Font.Size := 7;
  BtnClip.Hint := 'Leuchtet rot, wenn die Summe übersteuert (dann Master leiser stellen)';
  BtnClip.ShowHint := True;

  { ---------- Unten ---------- }
  PnlBottom := TDJPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 66;
  PnlBottom.Color := DJ_FOOTER;
  PnlBottom.Width := ClientWidth;

  LblHelp := MakeLabel(PnlBottom,
    'Leertaste Play/Pause  ·  1-4 Mute  ·  Shift+1-4 Solo  ·  0 zurücksetzen  ·  ' +
    'S/O/R Modus  ·  Pfeile -/+5 s  ·  Pos1 Anfang', 12, 6, 0, False);
  LblHelp.Font.Color := $00999999;

  LblStatus := MakeLabel(PnlBottom, '', 12, 25, 0, False);
  LblStatus.Font.Color := DJ_DIM;
  LblStatus.Anchors := [akLeft, akTop, akRight];
  LblStatus.AutoSize := False;
  LblStatus.Width := PnlBottom.Width - 24;

  LblKofi := MakeLabel(PnlBottom, 'Gefällt dir das Tool? Unterstütze Elospeed auf ko-fi.com/elospeed', 12, 44, 0, False);
  LblKofi.Font.Color := DJ_KOFI;
  LblKofi.Cursor := crHandPoint;
  LblKofi.OnClick := @KofiClick;
end;

{ Eine Stem-Zeile:  Name/Zustand | M S | Fader | % | LED-Meter }
procedure TMainForm.BuildStemRow(Idx: Integer);
var
  R: ^TStemRow;
  W: Integer;
begin
  R := @Rows[Idx];
  R^.Color := FInfo.Colors[Idx - 1];
  R^.Level := 0;

  R^.Panel := MakeDJPanel(ROW_HEIGHT, 6);
  R^.Panel.AccentWidth := 6;
  R^.Panel.AccentColor := R^.Color;
  W := R^.Panel.Width;

  R^.LblName := MakeLabel(R^.Panel, Format('%d  %s', [Idx, UpperCase(FInfo.Names[Idx - 1])]), 20, 7, 11, True);
  R^.LblName.Font.Color := R^.Color;
  R^.LblState := MakeLabel(R^.Panel, '', 20, 31, 8, False);
  R^.LblState.Font.Color := DJ_DIM;

  R^.BtnMute := MakeButton(R^.Panel, 'M', 140, 13, 32, 28);
  R^.BtnMute.Toggle := True;
  R^.BtnMute.LitColor := DJ_RED;
  R^.BtnMute.Tag := Idx;
  R^.BtnMute.OnClick := @MuteSoloClick;
  R^.BtnMute.Hint := Format('Mute: Stem stumm schalten (Taste %d)', [Idx]);
  R^.BtnMute.ShowHint := True;

  R^.BtnSolo := MakeButton(R^.Panel, 'S', 178, 13, 32, 28);
  R^.BtnSolo.Toggle := True;
  R^.BtnSolo.LitColor := DJ_YELLOW;
  R^.BtnSolo.Tag := 100 + Idx;
  R^.BtnSolo.OnClick := @MuteSoloClick;
  R^.BtnSolo.Hint := Format('Solo: nur Solo-Stems hören - mehrere möglich (Shift+%d)', [Idx]);
  R^.BtnSolo.ShowHint := True;

  R^.TrkVol := MakeFader(R^.Panel, 224, 14, 200, R^.Color);
  R^.TrkVol.Position := 100;
  R^.TrkVol.Tag := Idx;
  R^.TrkVol.OnChange := @VolChange;

  R^.LblVol := MakeLabel(R^.Panel, '100%', 0, 18, 0, False);
  R^.LblVol.Font.Name := MONO_FONT;
  R^.LblVol.Font.Color := $00AAAAAA;
  R^.LblVol.AutoSize := False;
  R^.LblVol.Alignment := taRightJustify;
  R^.LblVol.SetBounds(428, 18, 46, 20);

  R^.Meter := TPaintBox.Create(Self);
  R^.Meter.Parent := R^.Panel;
  R^.Meter.SetBounds(486, 16, W - 486 - 12, 22);
  R^.Meter.Anchors := [akLeft, akTop, akRight];
  R^.Meter.Tag := Idx;
  R^.Meter.OnPaint := @MeterPaint;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  { Datei als Kommandozeilen-Parameter? (z.B. aus StemMaker oder "Öffnen mit") }
  if (ParamCount >= 1) and FileExists(ParamStr(1)) and (FFileName = '') then
    LoadFile(ParamStr(1))
  { Ordner als Parameter? (Knopf "Anhören" in StemMaker: Ordner der zuletzt
    umgewandelten Datei) -> Öffnen-Dialog gleich dort zeigen. Erst kurz
    danach über die Nachrichtenschlange, damit das Fenster schon sichtbar ist. }
  else if (ParamCount >= 1) and DirectoryExists(ParamStr(1)) and (FFileName = '') then
  begin
    OpenDlg.InitialDir := ParamStr(1);
    Application.QueueAsyncCall(@OpenDialogLater, 0);
  end;
end;

procedure TMainForm.OpenDialogLater(Data: PtrInt);
begin
  BtnOpenClick(nil);
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
    LblFileInfo.Caption := 'Dekodiere ...';
    Ok := DecodeTracks(FileName, Tracks, ErrText);
    if not Ok then
    begin
      UnloadFile;   // halbfertige .raw-Dateien wieder löschen
      if FCancelLoad then
      begin
        { Abbruch durch Schliessen des Fensters -> keine Fehlermeldung }
        LblStatus.Caption := 'Laden abgebrochen.';
        LblFile.Caption := '';
        LblFileInfo.Caption := '';
        Exit;
      end;
      LblFileInfo.Caption := 'Fehler beim Dekodieren';
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
      Rows[i].LblName.Caption := Format('%d  %s', [i, UpperCase(FInfo.Names[i - 1])]);
      Rows[i].Color := FInfo.Colors[i - 1];
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
    LblFileInfo.Caption := Format('%d Spuren  ·  Länge %s', [Tracks, FormatTime(Engine.TotalFrames)]);
    LblTotal.Caption := '/ ' + FormatTime(Engine.TotalFrames);

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

{ Zeigt den Zustand jeder Zeile an (Text, Farben, abgedunkelt).
  Die Buttons zeichnen ihren gedrückten Zustand selbst (Mute rot, Solo gelb). }
procedure TMainForm.UpdateRowLook;
var
  i: Integer;
  S: string;
  IsOn, StemMode: Boolean;
  StateColor: TColor;
begin
  StemMode := BtnModeStems.Down;
  for i := 1 to STEM_COUNT do
  begin
    IsOn := Rows[i].Panel.Tag = 1;
    StateColor := DJ_DIM;
    if not StemMode then
    begin
      if BtnModeOrig.Down then S := 'MODUS: ORIGINAL' else S := 'MODUS: REST';
    end
    else if Rows[i].BtnSolo.Down then
    begin
      S := 'SOLO';
      StateColor := DJ_YELLOW;
    end
    else if not IsOn then
    begin
      if Rows[i].BtnMute.Down then
      begin
        S := 'STUMM';
        StateColor := DJ_RED;
      end
      else S := 'AUS (SOLO)';  // ein anderer Stem ist auf Solo
    end
    else S := 'HÖRBAR';
    Rows[i].LblState.Caption := S;
    Rows[i].LblState.Font.Color := StateColor;
    { Hörbare Stems in ihrer Farbe, alle anderen grau }
    if IsOn and StemMode then
    begin
      Rows[i].LblName.Font.Color := Rows[i].Color;
      Rows[i].Panel.AccentColor := Rows[i].Color;
      Rows[i].TrkVol.FillColor := Rows[i].Color;
    end
    else
    begin
      Rows[i].LblName.Font.Color := $00707070;
      Rows[i].Panel.AccentColor := $00444444;
      Rows[i].TrkVol.FillColor := DJ_OFF;
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
  { Genau einer der drei Modus-Buttons ist gedrückt }
  BtnModeStems.Down := M = pmStems;
  BtnModeOrig.Down  := M = pmMaster;
  BtnModeRest.Down  := M = pmResidual;
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
  i := TDJSlider(Sender).Tag;
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
  i: Integer;
  IsOn: Boolean;
  C: TColor;
begin
  PB := TPaintBox(Sender);
  i := PB.Tag;
  IsOn := (Rows[i].Panel.Tag = 1) and BtnModeStems.Down;
  { Hintergrund wie die Zeile, damit die Lücken zwischen den LEDs passen }
  PB.Canvas.Brush.Color := DJ_PANEL;
  PB.Canvas.FillRect(0, 0, PB.Width, PB.Height);
  { Aktive Stems in ihrer Farbe, stumme grau (Pegel wird trotzdem angezeigt,
    damit man sieht, ob in dieser Spur überhaupt etwas los ist) }
  if IsOn then C := Rows[i].Color else C := DJ_OFF;
  DrawLedBar(PB.Canvas, Rect(0, 0, PB.Width, PB.Height),
             LevelToFrac(Rows[i].Level), C, False);
end;

procedure TMainForm.OutMeterPaint(Sender: TObject);
var
  ch, H, Y: Integer;
begin
  MeterOut.Canvas.Brush.Color := DJ_PANEL;
  MeterOut.Canvas.FillRect(0, 0, MeterOut.Width, MeterOut.Height);
  { Zwei LED-Ketten (L oben, R unten): grün bis -6 dB, gelb bis -1 dB, rot darüber }
  H := (MeterOut.Height - 4) div 2;
  for ch := 0 to 1 do
  begin
    Y := ch * (H + 4);
    DrawLedBar(MeterOut.Canvas, Rect(0, Y, MeterOut.Width, Y + H),
               LevelToFrac(FOutLevel[ch]), DJ_GREEN, True);
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

  { Play-Button: leuchtet grün und zeigt das Pause-Symbol, solange es läuft }
  BtnPlay.Down := Playing;
  if Playing then BtnPlay.Glyph := dgPause else BtnPlay.Glyph := dgPlay;

  { Position anzeigen (nicht während der Benutzer den Regler zieht) }
  if not FDraggingPos then
  begin
    FUpdatingPos := True;
    TrkPos.Position := Engine.PlayPos div (SAMPLE_RATE div 10);
    FUpdatingPos := False;
  end;
  LblTime.Caption := FormatTime(Engine.PlayPos);

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
  if FClipTicks > 0 then Dec(FClipTicks);
  BtnClip.Down := FClipTicks > 0;
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
        Key := 0;  // Taste ist verarbeitet
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
