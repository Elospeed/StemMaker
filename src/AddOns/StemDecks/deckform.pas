{ ============================================================================
  deckform.pas  -  Hauptfenster des Elospeed StemDecks-Tests

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Zweck (Machbarkeitstest, KEIN fertiges Produkt):
    Ein 5.1-Mitschnitt (z.B. Konzert-Video) hat sechs Kanäle. Traktor kann
    pro Deck genau 4 Stems abspielen - mit allen 4 Decks also 16 Spuren.
    Idee: 5.1 in vier Stereo-Teile zerlegen (Front, Center, Surround, LFE),
    jeden Teil wie einen Song in 4 Stems trennen und die vier Stem-Dateien
    auf Deck A..D gleichzeitig abspielen.

    Dieses Programm macht beides:
      1. "5.1 ZERLEGEN": prüft die Datei mit ffmpeg, schreibt
         A_/B_/C_/D_<Name>.wav und wandelt sie auf Wunsch gleich mit
         StemCLI (ohne Club-Pegel) in A_/B_/C_/D_<Name>.stem.mp4 um.
      2. Vierfach-StemPlayer im Traktor-Stil (ohne Wellenform):
         Deck A..D mit je 4 Stems (Mute, Fader, LED-Meter), Deck-Fader und
         EIN gemeinsames Play/Stop - alle Decks laufen sampelgenau synchron.
         Wer eine A_-Datei lädt, bekommt B_/C_/D_ aus demselben Ordner
         automatisch dazu.

  Aufbau wie im StemPlayer: Fenster komplett im Code (keine .lfm),
  Optik aus djcontrols.pas, Stem-Prüfung aus mp4stem.pas (beide aus
  ..\StemPlayer\ mitbenutzt), Audio in deckengine.pas.

  Temp-Dateien: wie StemPlayer ein eigener Ordner pro Instanz
      %TEMP%\ElospeedStemDecks_<PID>_<Startzeit>\   (mit instance.lock)
  darin pro Deck ein Unterordner mit den dekodierten Stems
  (16 Bit / 44.1 kHz / Stereo, ca. 10 MB pro Stem und Minute -> 4 volle
  Decks mit 5 Minuten = ca. 800 MB). Beim Schliessen wird alles gelöscht,
  Reste nach einem Absturz beim nächsten Start.

  Tastatur:
    Leertaste  Play / Pause (alle Decks)    Pos1   an den Anfang
    1..4       Deck A..D stumm an/aus       Pfeile -/+ 5 s
    Strg+O     Decks laden                  Strg+5 5.1 zerlegen
  Parameter / Drag & Drop: Stem-Datei -> laden, andere Datei -> 5.1 zerlegen.

  Versionen:
    0.1  (10.10.2026)  Erste Testversion (Machbarkeit 5.1 auf vier Decks)
  ============================================================================ }
unit deckform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, LCLType, LCLIntf, Process, FileUtil, LazFileUtils, IniFiles,
  mp4stem, deckengine, djcontrols, surround51;

const
  APP_TITLE   = 'Elospeed StemDecks';
  APP_VER     = '0.1 Test';
  TEMP_PREFIX = 'ElospeedStemDecks_';   // Präfix der Temp-Ordner
  LOCK_NAME   = 'instance.lock';        // Sperrdatei im Instanz-Ordner
  TEST_SECONDS= 180;                    // "nur Anfang" beim Zerlegen

type
  { Eine Stem-Zeile innerhalb eines Decks }
  TStemCtl = record
    LblName : TLabel;
    BtnMute : TDJButton;
    TrkVol  : TDJSlider;
    Meter   : TPaintBox;
    Color   : TColor;
    Level   : Single;      // geglätteter Anzeigepegel 0..1
  end;

  { Ein Deck (A..D) }
  TDeck = record
    Panel    : TDJPanel;
    LblLetter: TLabel;     // grosser Buchstabe A..D
    LblName  : TLabel;     // Dateiname
    LblInfo  : TLabel;     // Länge / 5.1-Teil
    BtnLoad  : TDJButton;
    BtnMute  : TDJButton;  // ganzes Deck stumm
    TrkVol   : TDJSlider;  // Deck-Lautstärke
    LblVol   : TLabel;
    Stems    : array[0..STEMS_PER_DECK-1] of TStemCtl;
    FileName : string;
    RawDir   : string;     // Temp-Unterordner mit stem0..3.raw ('' = leer)
    OldRawDir: string;     // vorheriger Ordner, wird nach dem Engine-Neustart gelöscht
    Frames   : Int64;      // Länge in Frames
    Info     : TStemInfo;
  end;

  { TMainForm }

  TMainForm = class(TForm)
  private
    { --- Oben --- }
    PnlTop     : TDJPanel;
    BtnSplit   : TDJButton;
    BtnLoadAll : TDJButton;
    LblHint    : TLabel;
    BtnPlay    : TDJButton;
    BtnStop    : TDJButton;
    TrkPos     : TDJSlider;
    LblTime    : TLabel;
    LblTotal   : TLabel;
    { --- Decks --- }
    PnlDecks   : TPanel;
    Decks      : array[0..DECK_COUNT-1] of TDeck;
    { --- Master + Fusszeile --- }
    PnlMaster  : TDJPanel;
    TrkMaster  : TDJSlider;
    LblMasterVol: TLabel;
    MeterOut   : TPaintBox;
    BtnClip    : TDJButton;
    PnlBottom  : TDJPanel;
    LblHelp    : TLabel;
    LblStatus  : TLabel;
    { --- Sonstiges --- }
    Timer      : TTimer;
    OpenDlg    : TOpenDialog;
    SplitDlg   : TOpenDialog;

    Engine      : TDeckEngine;
    FInstanceDir: string;
    FLockFile   : TFileStream;
    FFFmpeg     : string;
    FBusy       : Boolean;     // ffmpeg / StemCLI läuft
    FCancel     : Boolean;     // Abbruchwunsch (Fenster wird geschlossen)
    FCloseAfter : Boolean;
    FUpdatingPos: Boolean;
    FDraggingPos: Boolean;
    FOutLevel   : array[0..1] of Single;
    FLastClip   : Integer;
    FClipTicks  : Integer;

    { Aufbau }
    procedure BuildUI;
    procedure BuildDeck(d: Integer);
    procedure LayoutDecks(Sender: TObject);
    function  MakeButton(AParent: TWinControl; const ACaption: string;
                         ALeft, ATop, AWidth, AHeight: Integer): TDJButton;
    function  MakeFader(AParent: TWinControl; ALeft, ATop, AWidth: Integer;
                        AFill: TColor): TDJSlider;
    function  MakeLabel(AParent: TWinControl; const ACaption: string;
                        ALeft, ATop: Integer; ASize: Integer; ABold: Boolean): TLabel;

    { Werkzeuge / Temp }
    function  IniFileName: string;
    function  ReadIniPath(const Key: string): string;
    procedure WriteIniPath(const Key, Value: string);
    function  AskForExe(const ExeName, Why, IniKey: string): string;
    function  FindFFmpeg: string;
    function  FindStemCLI: string;
    function  EnsureFFmpeg: Boolean;
    function  RunTool(const Exe: string; Args: TStrings; const What: string;
                      out OutText: string): Integer;
    procedure CreateInstanceDir;
    procedure ReleaseInstanceDir;
    procedure CleanupOrphanTempDirs;
    procedure DeferredClose(Data: PtrInt);
    procedure SetBusy(B: Boolean);

    { Laden / Abspielen }
    function  DecodeDeck(d: Integer; const FileName: string): Boolean;
    procedure RebuildEngine;
    procedure LoadIntoDeck(d: Integer; const FileName: string);
    procedure LoadSet(const FileName: string);
    procedure ClearDeck(d: Integer);
    procedure UpdateGains;
    procedure UpdateDeckLook(d: Integer);
    procedure TogglePlay;
    procedure SeekRelative(Seconds: Integer);
    function  FormatTime(Frames: Int64): string;
    function  LevelToFrac(L: Single): Single;

    { 5.1 zerlegen }
    procedure Split51(const FileName: string);
    function  ConvertWithStemCLI(const Wavs: array of string): Boolean;

    { Ereignisse }
    procedure BtnSplitClick(Sender: TObject);
    procedure BtnLoadAllClick(Sender: TObject);
    procedure BtnDeckLoadClick(Sender: TObject);
    procedure BtnPlayClick(Sender: TObject);
    procedure BtnStopClick(Sender: TObject);
    procedure MuteClick(Sender: TObject);
    procedure VolChange(Sender: TObject);
    procedure MasterChange(Sender: TObject);
    procedure PosChange(Sender: TObject);
    procedure PosMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PosMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MeterPaint(Sender: TObject);
    procedure OutMeterPaint(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure OpenParamLater(Data: PtrInt);
    procedure OpenAny(const FileName: string);
  public
    constructor Create(TheOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

const
  MARGIN    = 10;
  MONO_FONT = 'Consolas';
  STEM_ROW  = 40;      // Höhe einer Stem-Zeile im Deck
  { Deck-Farben ähnlich Traktor: A/B blau, C/D grau-weiss  (TColor = $BBGGRR) }
  DECK_COLORS: array[0..DECK_COUNT-1] of TColor =
    ($00E8A03C, $00E8A03C, $00C8C8C8, $00C8C8C8);

{ ============================================================================
  Aufbau des Fensters
  ============================================================================ }

constructor TMainForm.Create(TheOwner: TComponent);
var d: Integer;
begin
  inherited CreateNew(TheOwner);    // keine .lfm-Datei
  Caption := APP_TITLE + ' ' + APP_VER + '  -  vier Decks, 16 Stems  -  von Elospeed';
  Width := 1180;
  Height := 820;
  Constraints.MinWidth := 1000;
  Constraints.MinHeight := 760;
  Position := poScreenCenter;
  Color := DJ_BG;
  Font.Name := 'Segoe UI';
  Font.Color := DJ_TEXT;
  DoubleBuffered := True;
  KeyPreview := True;
  AllowDropFiles := True;
  OnKeyDown := @FormKeyDown;
  OnDropFiles := @FormDropFiles;
  OnClose := @FormClose;
  OnCloseQuery := @FormCloseQuery;
  OnShow := @FormShow;

  for d := 0 to DECK_COUNT - 1 do
    ReadStemInfo('', Decks[d].Info);   // Standardnamen/-farben
  BuildUI;

  OpenDlg := TOpenDialog.Create(Self);
  OpenDlg.Title := 'Stem-Datei laden (A_-Datei lädt B_/C_/D_ automatisch mit)';
  OpenDlg.Filter := 'Traktor Stems (*.stem.mp4;*.mp4)|*.stem.mp4;*.mp4|Alle Dateien (*.*)|*.*';

  SplitDlg := TOpenDialog.Create(Self);
  SplitDlg.Title := '5.1-Datei zum Zerlegen wählen';
  SplitDlg.Filter :=
    '5.1-Ton (Video/Audio)|*.mkv;*.mka;*.mp4;*.m4v;*.m4a;*.mov;*.ac3;*.eac3;*.dts;*.thd;*.wav;*.flac;*.vob;*.ts;*.m2ts;*.avi;*.webm;*.ogg;*.opus|' +
    'Alle Dateien (*.*)|*.*';

  Timer := TTimer.Create(Self);
  Timer.Interval := 30;
  Timer.OnTimer := @TimerTick;
  Timer.Enabled := True;

  CleanupOrphanTempDirs;
  CreateInstanceDir;

  FFFmpeg := FindFFmpeg;
  if FFFmpeg = '' then
    LblStatus.Caption := 'ffmpeg.exe nicht gefunden - wird beim ersten Laden abgefragt.'
  else
    LblStatus.Caption := 'ffmpeg: ' + FFFmpeg;
  UpdateGains;
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

function TMainForm.MakeButton(AParent: TWinControl; const ACaption: string;
  ALeft, ATop, AWidth, AHeight: Integer): TDJButton;
begin
  Result := TDJButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, AHeight);
  Result.Caption := ACaption;
end;

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

procedure TMainForm.BuildUI;
var
  W, d: Integer;
  L: TLabel;
begin
  W := ClientWidth - 2 * MARGIN;

  { ---------- Oben: Werkzeuge + gemeinsamer Transport ---------- }
  PnlTop := TDJPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 104;
  PnlTop.BorderSpacing.Around := MARGIN;
  PnlTop.Width := W;

  BtnSplit := MakeButton(PnlTop, '5.1 ZERLEGEN', 12, 10, 140, 32);
  BtnSplit.Hint := '5.1-Datei (z.B. Konzert-Video) in A_/B_/C_/D_-Dateien zerlegen' + LineEnding +
                   'und auf Wunsch gleich in Stems umwandeln (Strg+5)';
  BtnSplit.ShowHint := True;
  BtnSplit.OnClick := @BtnSplitClick;

  BtnLoadAll := MakeButton(PnlTop, 'DECKS LADEN', 160, 10, 140, 32);
  BtnLoadAll.Hint := 'Eine A_-Stem-Datei wählen: B_/C_/D_ aus demselben Ordner' + LineEnding +
                     'werden automatisch auf Deck B..D geladen (Strg+O)';
  BtnLoadAll.ShowHint := True;
  BtnLoadAll.OnClick := @BtnLoadAllClick;

  LblHint := MakeLabel(PnlTop,
    'Machbarkeitstest: 5.1 -> 4 Decks x 4 Stems.  A = Front  ·  B = Center  ·  C = Surround  ·  D = LFE',
    316, 18, 0, False);
  LblHint.Font.Color := DJ_DIM;

  BtnPlay := MakeButton(PnlTop, '', 12, 56, 46, 36);
  BtnPlay.Glyph := dgPlay;
  BtnPlay.LitColor := DJ_GREEN;
  BtnPlay.Enabled := False;
  BtnPlay.Hint := 'Play / Pause - alle Decks gleichzeitig (Leertaste)';
  BtnPlay.ShowHint := True;
  BtnPlay.OnClick := @BtnPlayClick;

  BtnStop := MakeButton(PnlTop, '', 64, 56, 46, 36);
  BtnStop.Glyph := dgStop;
  BtnStop.Enabled := False;
  BtnStop.Hint := 'Stop und zurück an den Anfang';
  BtnStop.ShowHint := True;
  BtnStop.OnClick := @BtnStopClick;

  TrkPos := TDJSlider.Create(Self);
  TrkPos.Parent := PnlTop;
  TrkPos.Style := dssPosition;
  TrkPos.SetBounds(120, 56, W - 120 - 172, 36);
  TrkPos.Anchors := [akLeft, akTop, akRight];
  TrkPos.Min := 0;
  TrkPos.Max := 1000;
  TrkPos.Enabled := False;
  TrkPos.OnChange := @PosChange;
  TrkPos.OnMouseDown := @PosMouseDown;
  TrkPos.OnMouseUp := @PosMouseUp;

  LblTime := MakeLabel(PnlTop, '00:00', 0, 58, 18, True);
  LblTime.Font.Name := MONO_FONT;
  LblTime.AutoSize := False;
  LblTime.Alignment := taRightJustify;
  LblTime.SetBounds(W - 168, 58, 88, 32);
  LblTime.Anchors := [akTop, akRight];

  LblTotal := MakeLabel(PnlTop, '/ 00:00', 0, 68, 10, False);
  LblTotal.Font.Name := MONO_FONT;
  LblTotal.Font.Color := DJ_DIM;
  LblTotal.AutoSize := False;
  LblTotal.SetBounds(W - 76, 68, 70, 20);
  LblTotal.Anchors := [akTop, akRight];

  { ---------- Unten: Fusszeile, darüber Master ---------- }
  PnlBottom := TDJPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 48;
  PnlBottom.Color := DJ_FOOTER;
  PnlBottom.Width := ClientWidth;
  PnlBottom.Top := 10000;           // ganz unten

  LblHelp := MakeLabel(PnlBottom,
    'Leertaste Play/Pause  ·  1-4 Deck A-D stumm  ·  Pfeile -/+5 s  ·  Pos1 Anfang  ·  ' +
    'Strg+O Decks laden  ·  Strg+5 5.1 zerlegen  ·  Dateien aufs Fenster ziehen', 12, 6, 0, False);
  LblHelp.Font.Color := $00999999;

  LblStatus := MakeLabel(PnlBottom, '', 12, 25, 0, False);
  LblStatus.Font.Color := DJ_DIM;
  LblStatus.Anchors := [akLeft, akTop, akRight];
  LblStatus.AutoSize := False;
  LblStatus.Width := PnlBottom.Width - 24;

  PnlMaster := TDJPanel.Create(Self);
  PnlMaster.Parent := Self;
  PnlMaster.Align := alBottom;
  PnlMaster.Height := 56;
  PnlMaster.BorderSpacing.Left := MARGIN;
  PnlMaster.BorderSpacing.Right := MARGIN;
  PnlMaster.BorderSpacing.Bottom := MARGIN;
  PnlMaster.Width := W;
  PnlMaster.Top := 9000;            // über der Fusszeile

  MakeLabel(PnlMaster, 'MASTER', 14, 8, 11, True);
  L := MakeLabel(PnlMaster, 'SUMME ALLER DECKS', 14, 32, 7, False);
  L.Font.Color := DJ_DIM;

  TrkMaster := MakeFader(PnlMaster, 180, 15, 200, DJ_TEXT);
  TrkMaster.Position := 60;   // 16 Spuren addieren sich -> etwas leiser starten
  TrkMaster.OnChange := @MasterChange;
  LblMasterVol := MakeLabel(PnlMaster, '60%', 0, 19, 0, False);
  LblMasterVol.Font.Name := MONO_FONT;
  LblMasterVol.Font.Color := $00AAAAAA;
  LblMasterVol.AutoSize := False;
  LblMasterVol.Alignment := taRightJustify;
  LblMasterVol.SetBounds(384, 19, 46, 20);

  MeterOut := TPaintBox.Create(Self);
  MeterOut.Parent := PnlMaster;
  MeterOut.SetBounds(442, 14, W - 442 - 72, 28);
  MeterOut.Anchors := [akLeft, akTop, akRight];
  MeterOut.OnPaint := @OutMeterPaint;

  BtnClip := MakeButton(PnlMaster, 'CLIP', W - 60, 15, 48, 26);
  BtnClip.Anchors := [akTop, akRight];
  BtnClip.LitColor := DJ_RED;
  BtnClip.Font.Size := 7;
  BtnClip.Hint := 'Leuchtet rot, wenn die Summe übersteuert (dann Master leiser stellen)';
  BtnClip.ShowHint := True;

  { ---------- Mitte: 4 Decks im 2x2-Raster wie in Traktor ---------- }
  PnlDecks := TPanel.Create(Self);
  PnlDecks.Parent := Self;
  PnlDecks.Align := alClient;
  PnlDecks.BevelOuter := bvNone;
  PnlDecks.Color := DJ_BG;
  PnlDecks.BorderSpacing.Left := MARGIN;
  PnlDecks.BorderSpacing.Right := MARGIN;
  PnlDecks.OnResize := @LayoutDecks;
  { Grösse vorab ausrechnen, damit die Decks beim Aufbau richtig breit sind }
  PnlDecks.SetBounds(MARGIN, PnlTop.Height + 2 * MARGIN, W,
    ClientHeight - PnlTop.Height - 3 * MARGIN - PnlMaster.Height - MARGIN - PnlBottom.Height);

  for d := 0 to DECK_COUNT - 1 do
    BuildDeck(d);
  LayoutDecks(nil);
end;

{ Ein Deck:  Kopf (Buchstabe, Name, LADEN) | Deck-Zeile (M, Fader) | 4 Stems }
procedure TMainForm.BuildDeck(d: Integer);
var
  Dk: ^TDeck;
  W, s, Y: Integer;
  L: TLabel;
begin
  Dk := @Decks[d];
  Dk^.Panel := TDJPanel.Create(Self);
  Dk^.Panel.Parent := PnlDecks;
  Dk^.Panel.AccentWidth := 4;
  Dk^.Panel.AccentColor := DECK_COLORS[d];
  W := (PnlDecks.Width - MARGIN) div 2;
  Dk^.Panel.SetBounds(0, 0, W, 300);

  Dk^.LblLetter := MakeLabel(Dk^.Panel, DECK_LETTERS[d], 14, 4, 24, True);
  Dk^.LblLetter.Font.Color := DECK_COLORS[d];

  Dk^.LblName := MakeLabel(Dk^.Panel, '(leer)', 52, 8, 11, True);
  Dk^.LblName.AutoSize := False;
  Dk^.LblName.SetBounds(52, 8, W - 52 - 96, 22);
  Dk^.LblName.Anchors := [akLeft, akTop, akRight];
  Dk^.LblName.Font.Color := DJ_DIM;

  Dk^.LblInfo := MakeLabel(Dk^.Panel, 'Stem-Datei laden', 52, 30, 8, False);
  Dk^.LblInfo.Font.Color := DJ_DIM;

  Dk^.BtnLoad := MakeButton(Dk^.Panel, 'LADEN', W - 88, 10, 76, 28);
  Dk^.BtnLoad.Anchors := [akTop, akRight];
  Dk^.BtnLoad.Tag := d;
  Dk^.BtnLoad.Hint := Format('Stem-Datei auf Deck %s laden', [DECK_LETTERS[d]]);
  Dk^.BtnLoad.ShowHint := True;
  Dk^.BtnLoad.OnClick := @BtnDeckLoadClick;

  { Deck-Zeile: ganzes Deck stumm + Deck-Lautstärke }
  Y := 58;
  L := MakeLabel(Dk^.Panel, 'DECK', 14, Y + 6, 8, True);
  L.Font.Color := DJ_DIM;
  Dk^.BtnMute := MakeButton(Dk^.Panel, 'M', 100, Y, 32, 28);
  Dk^.BtnMute.Toggle := True;
  Dk^.BtnMute.LitColor := DJ_RED;
  Dk^.BtnMute.Tag := 1000 + d;
  Dk^.BtnMute.OnClick := @MuteClick;
  Dk^.BtnMute.Hint := Format('Ganzes Deck %s stumm (Taste %d)', [DECK_LETTERS[d], d + 1]);
  Dk^.BtnMute.ShowHint := True;
  Dk^.TrkVol := MakeFader(Dk^.Panel, 140, Y + 1, 160, DECK_COLORS[d]);
  Dk^.TrkVol.Position := 100;
  Dk^.TrkVol.Tag := 1000 + d;
  Dk^.TrkVol.OnChange := @VolChange;
  Dk^.LblVol := MakeLabel(Dk^.Panel, '100%', 304, Y + 5, 0, False);
  Dk^.LblVol.Font.Name := MONO_FONT;
  Dk^.LblVol.Font.Color := $00AAAAAA;

  { 4 Stem-Zeilen }
  for s := 0 to STEMS_PER_DECK - 1 do
  begin
    Y := 98 + s * STEM_ROW;
    Dk^.Stems[s].Color := Dk^.Info.Colors[s];
    Dk^.Stems[s].Level := 0;

    Dk^.Stems[s].LblName := MakeLabel(Dk^.Panel, UpperCase(Dk^.Info.Names[s]), 14, Y + 5, 9, True);
    Dk^.Stems[s].LblName.AutoSize := False;
    Dk^.Stems[s].LblName.SetBounds(14, Y + 5, 82, 20);
    Dk^.Stems[s].LblName.Font.Color := Dk^.Stems[s].Color;

    Dk^.Stems[s].BtnMute := MakeButton(Dk^.Panel, 'M', 100, Y, 32, 28);
    Dk^.Stems[s].BtnMute.Toggle := True;
    Dk^.Stems[s].BtnMute.LitColor := DJ_RED;
    Dk^.Stems[s].BtnMute.Tag := d * STEMS_PER_DECK + s;
    Dk^.Stems[s].BtnMute.OnClick := @MuteClick;

    Dk^.Stems[s].TrkVol := MakeFader(Dk^.Panel, 140, Y + 1, 160, Dk^.Stems[s].Color);
    Dk^.Stems[s].TrkVol.Position := 100;
    Dk^.Stems[s].TrkVol.Tag := d * STEMS_PER_DECK + s;
    Dk^.Stems[s].TrkVol.OnChange := @VolChange;

    Dk^.Stems[s].Meter := TPaintBox.Create(Self);
    Dk^.Stems[s].Meter.Parent := Dk^.Panel;
    Dk^.Stems[s].Meter.SetBounds(350, Y + 4, W - 350 - 12, 20);
    Dk^.Stems[s].Meter.Anchors := [akLeft, akTop, akRight];
    Dk^.Stems[s].Meter.Tag := d * STEMS_PER_DECK + s;
    Dk^.Stems[s].Meter.OnPaint := @MeterPaint;
  end;
  UpdateDeckLook(d);
end;

{ Ordnet die 4 Decks im 2x2-Raster an:  A B / C D  (wie in Traktor) }
procedure TMainForm.LayoutDecks(Sender: TObject);
var
  d, W, H: Integer;
begin
  if Decks[DECK_COUNT - 1].Panel = nil then Exit;   // noch im Aufbau
  W := (PnlDecks.ClientWidth - MARGIN) div 2;
  H := (PnlDecks.ClientHeight - MARGIN) div 2;
  for d := 0 to DECK_COUNT - 1 do
    Decks[d].Panel.SetBounds((d mod 2) * (W + MARGIN), (d div 2) * (H + MARGIN), W, H);
end;

{ ============================================================================
  Werkzeuge finden, Temp-Ordner
  ============================================================================ }

function TMainForm.IniFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

function TMainForm.ReadIniPath(const Key: string): string;
var Ini: TIniFile;
begin
  Result := '';
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Result := Ini.ReadString('Pfade', Key, '');
    finally
      Ini.Free;
    end;
  except
    { ini nicht lesbar -> ignorieren }
  end;
end;

procedure TMainForm.WriteIniPath(const Key, Value: string);
var Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Ini.WriteString('Pfade', Key, Value);
    finally
      Ini.Free;
    end;
  except
    { schreibgeschützt -> nächstes Mal wieder fragen }
  end;
end;

{ Fragt einmalig nach einer exe und merkt sich den Pfad in der .ini }
function TMainForm.AskForExe(const ExeName, Why, IniKey: string): string;
var Dlg: TOpenDialog;
begin
  Result := '';
  MessageDlg(APP_TITLE, ExeName + ' wurde nicht gefunden.' + LineEnding + Why,
    mtInformation, [mbOK], 0);
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := ExeName + ' auswählen';
    Dlg.Filter := ExeName + '|' + ExeName + '|Programme (*.exe)|*.exe';
    if Dlg.Execute then Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  if Result <> '' then WriteIniPath(IniKey, Result);
end;

function TMainForm.FindFFmpeg: string;
const
  { Typische Orte relativ zur exe (StemDecks liegt in StemMaker\AddOns\) }
  Candidates: array[0..9] of string = (
    'ffmpeg.exe', 'tools\ffmpeg.exe', 'bin\ffmpeg.exe', 'ffmpeg\bin\ffmpeg.exe',
    '..\ffmpeg.exe', '..\tools\ffmpeg.exe', '..\bin\ffmpeg.exe',
    '..\ffmpeg\bin\ffmpeg.exe', '..\..\tools\ffmpeg.exe', '..\..\ffmpeg.exe');
var
  Base, S: string;
  i: Integer;
begin
  S := ReadIniPath('ffmpeg');
  if (S <> '') and FileExists(S) then Exit(S);
  Base := ExtractFilePath(Application.ExeName);
  for i := Low(Candidates) to High(Candidates) do
  begin
    S := ExpandFileName(Base + Candidates[i]);
    if FileExists(S) then Exit(S);
  end;
  Result := FindDefaultExecutablePath('ffmpeg.exe');
end;

function TMainForm.FindStemCLI: string;
const
  Candidates: array[0..2] of string = ('StemCLI.exe', '..\StemCLI.exe', '..\..\StemCLI.exe');
var
  Base, S: string;
  i: Integer;
begin
  S := ReadIniPath('stemcli');
  if (S <> '') and FileExists(S) then Exit(S);
  Base := ExtractFilePath(Application.ExeName);
  for i := Low(Candidates) to High(Candidates) do
  begin
    S := ExpandFileName(Base + Candidates[i]);
    if FileExists(S) then Exit(S);
  end;
  Result := '';
end;

function TMainForm.EnsureFFmpeg: Boolean;
begin
  if (FFFmpeg = '') or not FileExists(FFFmpeg) then
    FFFmpeg := AskForExe('ffmpeg.exe',
      'Bitte im nächsten Dialog die ffmpeg.exe auswählen (z.B. die von StemMaker im Ordner tools\).',
      'ffmpeg');
  Result := FFFmpeg <> '';
end;

{ Startet ein Werkzeug (ffmpeg oder StemCLI) ohne Konsolenfenster, liest
  seine Ausgabe laufend mit (sonst läuft die Pipe voll und es bleibt hängen)
  und hält das Fenster bedienbar. Die letzte Ausgabezeile erscheint in der
  Statuszeile. Rückgabe: Exit-Code, -1 bei Abbruch (Fenster geschlossen). }
function TMainForm.RunTool(const Exe: string; Args: TStrings; const What: string;
  out OutText: string): Integer;
var
  P: TProcess;
  Buf: array[0..4095] of Char;
  Chunk, LastLine: string;
  n: LongInt;
  T0: QWord;

  procedure Drain;
  var k: Integer;
  begin
    while P.Output.NumBytesAvailable > 0 do
    begin
      n := P.Output.Read(Buf, SizeOf(Buf));
      if n <= 0 then Break;
      SetString(Chunk, PChar(@Buf[0]), n);
      OutText := OutText + Chunk;
      if Length(OutText) > 60000 then
        OutText := Copy(OutText, Length(OutText) - 30000, MaxInt);
    end;
    { Letzte nicht-leere Zeile (StemCLI überschreibt Fortschritt mit #13) }
    LastLine := StringReplace(OutText, #13, #10, [rfReplaceAll]);
    k := Length(LastLine);
    while (k > 0) and (LastLine[k] = #10) do Dec(k);
    SetLength(LastLine, k);
    k := LastDelimiter(#10, LastLine);
    LastLine := Trim(Copy(LastLine, k + 1, 200));
  end;

begin
  Result := -1;
  OutText := '';
  LastLine := '';
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Parameters.Assign(Args);
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHIDE;
    P.Execute;
    T0 := GetTickCount64;
    while P.Running do
    begin
      Drain;
      if FCancel then
      begin
        P.Terminate(1);
        P.WaitOnExit;     // warten, bis die Dateien freigegeben sind
        Exit(-1);
      end;
      LblStatus.Caption := Format('%s ... %d s   %s',
        [What, (GetTickCount64 - T0) div 1000, LastLine]);
      Application.ProcessMessages;
      Sleep(40);
    end;
    Drain;
    Result := P.ExitStatus;
  finally
    P.Free;
  end;
end;

procedure TMainForm.CreateInstanceDir;
begin
  FInstanceDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
                  TEMP_PREFIX + IntToStr(GetProcessID) + '_' +
                  IntToStr(GetTickCount64) + PathDelim;
  ForceDirectories(FInstanceDir);
  try
    FLockFile := TFileStream.Create(FInstanceDir + LOCK_NAME, fmCreate or fmShareExclusive);
  except
    FLockFile := nil;
  end;
end;

procedure TMainForm.ReleaseInstanceDir;
begin
  FreeAndNil(FLockFile);
  if (FInstanceDir <> '') and DirectoryExists(FInstanceDir) then
    DeleteDirectory(FInstanceDir, False);
  FInstanceDir := '';
end;

{ Reste früherer Abstürze löschen (gleiches Prinzip wie im StemPlayer:
  lässt sich instance.lock löschen, läuft die Instanz nicht mehr). }
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
        Continue;
      DeleteDirectory(Dir, False);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure TMainForm.DeferredClose(Data: PtrInt);
begin
  Close;
end;

procedure TMainForm.SetBusy(B: Boolean);
var d: Integer;
begin
  FBusy := B;
  if B then Screen.Cursor := crHourGlass else Screen.Cursor := crDefault;
  BtnSplit.Enabled := not B;
  BtnLoadAll.Enabled := not B;
  for d := 0 to DECK_COUNT - 1 do Decks[d].BtnLoad.Enabled := not B;
end;

{ ============================================================================
  Decks laden
  ============================================================================ }

{ Dekodiert die 4 Stems (Spur 1..4, ohne Master) einer Stem-Datei in einen
  neuen Temp-Unterordner. Das Deck wird erst umgestellt, wenn alles
  geklappt hat - bis dahin spielt der alte Inhalt weiter. }
function TMainForm.DecodeDeck(d: Integer; const FileName: string): Boolean;
var
  NewInfo: TStemInfo;
  Reason, Dir, OutText: string;
  Args: TStringList;
  s, Code: Integer;
  F: TFileStream;
begin
  Result := False;
  if not CheckStemFile(FileName, NewInfo, Reason) then
  begin
    MessageDlg(APP_TITLE, ExtractFileName(FileName) + LineEnding + LineEnding + Reason,
      mtWarning, [mbOK], 0);
    Exit;
  end;
  if not EnsureFFmpeg then Exit;

  Dir := FInstanceDir + 'deck' + DECK_LETTERS[d] + '_' + IntToStr(GetTickCount64) + PathDelim;
  ForceDirectories(Dir);
  Args := TStringList.Create;
  try
    Args.Add('-hide_banner');
    Args.Add('-nostdin');
    Args.Add('-loglevel'); Args.Add('error');
    Args.Add('-y');
    Args.Add('-i'); Args.Add(FileName);
    { Nur die 4 Stems (Spur 1..4). Den Master braucht der Test nicht. }
    for s := 0 to STEMS_PER_DECK - 1 do
    begin
      Args.Add('-map'); Args.Add('0:a:' + IntToStr(s + 1));
      Args.Add('-ac'); Args.Add('2');
      Args.Add('-ar'); Args.Add(IntToStr(SAMPLE_RATE));
      Args.Add('-c:a'); Args.Add('pcm_s16le');
      Args.Add('-f'); Args.Add('s16le');
      Args.Add(Dir + 'stem' + IntToStr(s) + '.raw');
    end;
    Code := RunTool(FFFmpeg, Args,
      Format('Deck %s: dekodiere %s', [DECK_LETTERS[d], ExtractFileName(FileName)]), OutText);
  finally
    Args.Free;
  end;
  if Code <> 0 then
  begin
    DeleteDirectory(Dir, False);
    if Code > 0 then
      MessageDlg(APP_TITLE, 'ffmpeg konnte die Datei nicht dekodieren:' + LineEnding +
        FileName + LineEnding + LineEnding + Trim(OutText), mtError, [mbOK], 0);
    Exit;
  end;

  { Erfolgreich: alten Inhalt merken zum Löschen, neuen übernehmen.
    Der alte Ordner wird erst in RebuildEngine gelöscht, wenn die Engine
    ihre Dateien geschlossen hat. }
  if Decks[d].OldRawDir = '' then
    Decks[d].OldRawDir := Decks[d].RawDir;
  Decks[d].RawDir := Dir;
  Decks[d].FileName := FileName;
  Decks[d].Info := NewInfo;
  Decks[d].Frames := 0;
  try
    F := TFileStream.Create(Dir + 'stem0.raw', fmOpenRead or fmShareDenyNone);
    try
      Decks[d].Frames := F.Size div BYTES_PER_FRM;
    finally
      F.Free;
    end;
  except
  end;
  Result := True;
end;

{ Baut die Engine mit dem aktuellen Inhalt aller Decks neu auf und spielt an
  derselben Stelle weiter (falls sie vorher lief). Alte Deck-Ordner werden
  danach gelöscht. }
procedure TMainForm.RebuildEngine;
var
  Raw: array[0..TRACK_COUNT-1] of string;
  d, s: Integer;
  WasPlaying: Boolean;
  Pos: Int64;
  AnyLoaded: Boolean;
begin
  WasPlaying := False;
  Pos := 0;
  if Engine <> nil then
  begin
    WasPlaying := Engine.Playing and not Engine.EndReached;
    Pos := Engine.PlayPos;
    FreeAndNil(Engine);    // schliesst Audiogerät und alle .raw-Dateien
  end;
  { Jetzt sind die alten Ordner frei -> löschen }
  for d := 0 to DECK_COUNT - 1 do
    if Decks[d].OldRawDir <> '' then
    begin
      if DirectoryExists(Decks[d].OldRawDir) then
        DeleteDirectory(Decks[d].OldRawDir, False);
      Decks[d].OldRawDir := '';
    end;

  AnyLoaded := False;
  for d := 0 to DECK_COUNT - 1 do
    for s := 0 to STEMS_PER_DECK - 1 do
      if Decks[d].RawDir <> '' then
      begin
        Raw[d * STEMS_PER_DECK + s] := Decks[d].RawDir + 'stem' + IntToStr(s) + '.raw';
        AnyLoaded := True;
      end
      else
        Raw[d * STEMS_PER_DECK + s] := '';

  if AnyLoaded then
  begin
    Engine := TDeckEngine.Create(Raw, Pos);
    if Engine.OpenError <> '' then
      MessageDlg(APP_TITLE, Engine.OpenError, mtError, [mbOK], 0);
    FUpdatingPos := True;
    TrkPos.Max := Max(1, Engine.TotalFrames div (SAMPLE_RATE div 10));   // 1/10 s
    FUpdatingPos := False;
    LblTotal.Caption := '/ ' + FormatTime(Engine.TotalFrames);
    FLastClip := 0;
    FClipTicks := 0;
    UpdateGains;
    Engine.Playing := WasPlaying;
  end;
  TrkPos.Enabled := AnyLoaded;
  BtnPlay.Enabled := AnyLoaded;
  BtnStop.Enabled := AnyLoaded;
  for d := 0 to DECK_COUNT - 1 do UpdateDeckLook(d);
end;

procedure TMainForm.LoadIntoDeck(d: Integer; const FileName: string);
begin
  if FBusy then Exit;
  SetBusy(True);
  try
    if DecodeDeck(d, FileName) then RebuildEngine;
    if not FCancel then
      LblStatus.Caption := Format('Deck %s geladen: %s', [DECK_LETTERS[d], FileName]);
  finally
    SetBusy(False);
    if FCloseAfter then Application.QueueAsyncCall(@DeferredClose, 0);
  end;
end;

{ Lädt eine Datei. Heisst sie "A_Name..." (oder B_/C_/D_), werden alle
  vorhandenen Geschwister A_..D_ aus demselben Ordner auf ihre Decks geladen.
  Sonst landet die Datei auf dem ersten leeren Deck (bzw. Deck A). }
procedure TMainForm.LoadSet(const FileName: string);
var
  d, Target, NLoaded: Integer;
  Base, Dir, F: string;
begin
  if FBusy or not FileExists(FileName) then Exit;
  if DeckFromFileName(FileName, Base) < 0 then
  begin
    Target := 0;
    for d := DECK_COUNT - 1 downto 0 do
      if Decks[d].RawDir = '' then Target := d;
    LoadIntoDeck(Target, FileName);
    Exit;
  end;

  Dir := ExtractFilePath(FileName);
  SetBusy(True);
  NLoaded := 0;
  try
    for d := 0 to DECK_COUNT - 1 do
    begin
      if FCancel then Break;
      F := Dir + DECK_LETTERS[d] + '_' + Base;
      if not FileExists(F) then
        F := Dir + LowerCase(DECK_LETTERS[d]) + '_' + Base;
      if FileExists(F) and DecodeDeck(d, F) then Inc(NLoaded);
    end;
    if (NLoaded > 0) and not FCancel then
    begin
      RebuildEngine;
      LblStatus.Caption := Format('%d Decks geladen (%s)  ·  Länge %s',
        [NLoaded, Base, FormatTime(Engine.TotalFrames)]);
    end;
  finally
    SetBusy(False);
    if FCloseAfter then Application.QueueAsyncCall(@DeferredClose, 0);
  end;
end;

procedure TMainForm.ClearDeck(d: Integer);
begin
  Decks[d].FileName := '';
  Decks[d].RawDir := '';
  Decks[d].Frames := 0;
end;

{ ============================================================================
  Steuerung
  ============================================================================ }

{ Gain jeder der 16 Spuren = Deck (Mute + Fader) x Stem (Mute + Fader) }
procedure TMainForm.UpdateGains;
var
  d, s: Integer;
  GD, GS: Single;
begin
  for d := 0 to DECK_COUNT - 1 do
  begin
    if Decks[d].BtnMute.Down then GD := 0
    else GD := Decks[d].TrkVol.Position / 100;
    for s := 0 to STEMS_PER_DECK - 1 do
    begin
      if Decks[d].Stems[s].BtnMute.Down then GS := 0
      else GS := Decks[d].Stems[s].TrkVol.Position / 100;
      if Engine <> nil then Engine.Gain[d * STEMS_PER_DECK + s] := GD * GS;
    end;
    UpdateDeckLook(d);
  end;
  if Engine <> nil then Engine.MasterVol := TrkMaster.Position / 100;
end;

{ Namen, Farben und Abdunkelung eines Decks an den Zustand anpassen }
procedure TMainForm.UpdateDeckLook(d: Integer);
var
  s, Part: Integer;
  Base: string;
  IsOn, DeckOn: Boolean;
begin
  with Decks[d] do
  begin
    DeckOn := (RawDir <> '') and not BtnMute.Down;
    if RawDir = '' then
    begin
      LblName.Caption := '(leer)';
      LblName.Font.Color := DJ_DIM;
      LblInfo.Caption := 'Stem-Datei laden';
    end
    else
    begin
      LblName.Caption := ExtractFileName(FileName);
      LblName.Font.Color := DJ_TEXT;
      Part := DeckFromFileName(FileName, Base);
      if Part >= 0 then
        LblInfo.Caption := Format('5.1-Teil: %s  ·  %s', [DECK_PARTS[Part], FormatTime(Frames)])
      else
        LblInfo.Caption := 'Länge ' + FormatTime(Frames);
    end;
    if DeckOn then
    begin
      LblLetter.Font.Color := DECK_COLORS[d];
      Panel.AccentColor := DECK_COLORS[d];
      TrkVol.FillColor := DECK_COLORS[d];
    end
    else
    begin
      LblLetter.Font.Color := $00505050;
      Panel.AccentColor := $00444444;
      TrkVol.FillColor := DJ_OFF;
    end;
    for s := 0 to STEMS_PER_DECK - 1 do
    begin
      Stems[s].Color := Info.Colors[s];
      Stems[s].LblName.Caption := UpperCase(Info.Names[s]);
      IsOn := DeckOn and not Stems[s].BtnMute.Down;
      if IsOn then
      begin
        Stems[s].LblName.Font.Color := Stems[s].Color;
        Stems[s].TrkVol.FillColor := Stems[s].Color;
      end
      else
      begin
        Stems[s].LblName.Font.Color := $00707070;
        Stems[s].TrkVol.FillColor := DJ_OFF;
      end;
      Stems[s].Meter.Invalidate;
    end;
  end;
end;

procedure TMainForm.TogglePlay;
begin
  if Engine = nil then Exit;
  if Engine.EndReached then Engine.SeekTo := 0;
  Engine.Playing := not Engine.Playing;
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
  5.1 zerlegen
  ============================================================================ }

procedure TMainForm.Split51(const FileName: string);
var
  Args: TStringList;
  OutText, AudioLine, Layout, OutDir: string;
  Wavs: array[0..3] of string;
  Code, MaxSec, d: Integer;
  R: TModalResult;
  StemFiles: Boolean;
begin
  if FBusy or not EnsureFFmpeg then Exit;
  StemFiles := False;
  SetBusy(True);
  Args := TStringList.Create;
  try
    { 1) Kanal-Layout ermitteln: "ffmpeg -i Datei" ohne Ausgabe listet die
         Spuren auf (Exit-Code ist dabei immer 1, das ist normal). }
    Args.Add('-hide_banner');
    Args.Add('-nostdin');
    Args.Add('-i'); Args.Add(FileName);
    Code := RunTool(FFFmpeg, Args, 'Prüfe Tonspur', OutText);
    if Code < 0 then Exit;
    Layout := ParseAudioLayout(OutText, AudioLine);
    if AudioLine = '' then
    begin
      MessageDlg(APP_TITLE, 'In dieser Datei wurde keine Tonspur gefunden:' + LineEnding +
        FileName, mtWarning, [mbOK], 0);
      Exit;
    end;
    if not IsSupported51(Layout) then
    begin
      MessageDlg(APP_TITLE, 'Die erste Tonspur ist kein 5.1-Ton, sondern "' + Layout + '".' +
        LineEnding + LineEnding + AudioLine + LineEnding + LineEnding +
        'Dieser Test kann nur 5.1 bzw. 5.1(side) zerlegen.', mtWarning, [mbOK], 0);
      Exit;
    end;

    { 2) Ganze Datei oder nur den Anfang? Lange Konzerte brauchen beim
         Trennen viel Zeit - für den Test reicht oft ein Ausschnitt. }
    R := QuestionDlg(APP_TITLE,
      '5.1-Ton gefunden:' + LineEnding + AudioLine + LineEnding + LineEnding +
      'Es entstehen 4 WAV-Dateien im selben Ordner:' + LineEnding +
      '  A_ = Front L/R,  B_ = Center,  C_ = Surround L/R,  D_ = LFE' + LineEnding + LineEnding +
      'Ganze Datei zerlegen oder nur die ersten ' + IntToStr(TEST_SECONDS div 60) +
      ' Minuten (schneller zum Testen)?',
      mtConfirmation,
      [mrYes, Format('Nur %d Minuten', [TEST_SECONDS div 60]), mrNo, 'Ganze Datei',
       mrCancel, 'Abbrechen'], 0);
    if R = mrYes then MaxSec := TEST_SECONDS
    else if R = mrNo then MaxSec := 0
    else Exit;

    { 3) Zerlegen }
    OutDir := ExtractFilePath(FileName);
    BuildSplitArgs(FileName, OutDir, Layout, MaxSec, Args);
    Code := RunTool(FFFmpeg, Args, 'Zerlege 5.1 in A_/B_/C_/D_', OutText);
    if Code < 0 then Exit;
    for d := 0 to 3 do Wavs[d] := DeckWavName(FileName, OutDir, d);
    if (Code <> 0) or not FileExists(Wavs[0]) then
    begin
      MessageDlg(APP_TITLE, 'ffmpeg konnte die Datei nicht zerlegen:' + LineEnding +
        Trim(OutText), mtError, [mbOK], 0);
      Exit;
    end;
    LblStatus.Caption := 'Zerlegt: ' + ExtractFileName(Wavs[0]) + ' ... ' +
                         ExtractFileName(Wavs[3]);

    { 4) Gleich in Stems umwandeln? }
    R := QuestionDlg(APP_TITLE,
      'Fertig zerlegt:' + LineEnding +
      '  ' + ExtractFileName(Wavs[0]) + LineEnding +
      '  ' + ExtractFileName(Wavs[1]) + LineEnding +
      '  ' + ExtractFileName(Wavs[2]) + LineEnding +
      '  ' + ExtractFileName(Wavs[3]) + LineEnding + LineEnding +
      'Jetzt mit StemCLI in Stem-Dateien umwandeln?' + LineEnding +
      '(ohne Club-Pegel, damit die Decks im richtigen Verhältnis bleiben;' + LineEnding +
      'dauert etwa viermal so lange wie ein Song dieser Länge)' + LineEnding + LineEnding +
      'Alternativ: die 4 WAV-Dateien in StemMaker umwandeln (Club-Pegel AUS).',
      mtConfirmation, [mrYes, 'Jetzt umwandeln', mrNo, 'Später'], 0);
    if R <> mrYes then Exit;
    StemFiles := ConvertWithStemCLI(Wavs);
  finally
    Args.Free;
    SetBusy(False);
    if FCloseAfter then Application.QueueAsyncCall(@DeferredClose, 0);
  end;

  { 5) Ergebnis gleich auf die vier Decks laden }
  if StemFiles and not FCancel then
    LoadSet(ChangeFileExt(Wavs[0], '.stem.mp4'));
end;

{ Wandelt die vier WAV-Dateien mit StemCLI um (Ausgabe neben den WAVs:
  A_<Name>.stem.mp4 usw.). --no-normalize: kein Club-Pegel, sonst würde
  jedes Deck einzeln auf Club-Lautstärke gezogen und z.B. der leise
  Surround-Teil wäre plötzlich so laut wie die Front. }
function TMainForm.ConvertWithStemCLI(const Wavs: array of string): Boolean;
var
  Cli, OutText: string;
  Args: TStringList;
  Code, d: Integer;
begin
  Result := False;
  Cli := FindStemCLI;
  if Cli = '' then
    Cli := AskForExe('StemCLI.exe',
      'StemCLI.exe liegt im StemMaker-Ordner (neben StemMaker.exe).', 'stemcli');
  if Cli = '' then Exit;

  Args := TStringList.Create;
  try
    for d := 0 to High(Wavs) do Args.Add(Wavs[d]);
    Args.Add('--no-normalize');
    Args.Add('--overwrite');
    Code := RunTool(Cli, Args, 'StemCLI trennt 4 Dateien in Stems', OutText);
  finally
    Args.Free;
  end;
  if Code < 0 then Exit;
  if Code = 3 then
  begin
    MessageDlg(APP_TITLE, 'StemCLI ist auf diesem PC noch nicht freigegeben.' + LineEnding +
      'Bitte StemMaker.exe einmal starten und den Hinweis bestätigen,' + LineEnding +
      'danach "5.1 ZERLEGEN" nochmals ausführen.', mtWarning, [mbOK], 0);
    Exit;
  end;
  for d := 0 to High(Wavs) do
    if not FileExists(ChangeFileExt(Wavs[d], '.stem.mp4')) then
    begin
      MessageDlg(APP_TITLE, Format('StemCLI ist fehlgeschlagen (Code %d).', [Code]) +
        LineEnding + LineEnding + Copy(Trim(OutText), Max(1, Length(Trim(OutText)) - 1500), 1500),
        mtError, [mbOK], 0);
      Exit;
    end;
  Result := True;
end;

{ ============================================================================
  Ereignisse
  ============================================================================ }

procedure TMainForm.BtnSplitClick(Sender: TObject);
begin
  if FBusy then Exit;
  if SplitDlg.Execute then Split51(SplitDlg.FileName);
end;

procedure TMainForm.BtnLoadAllClick(Sender: TObject);
begin
  if FBusy then Exit;
  if OpenDlg.Execute then LoadSet(OpenDlg.FileName);
end;

procedure TMainForm.BtnDeckLoadClick(Sender: TObject);
var d: Integer;
begin
  if FBusy then Exit;
  d := TDJButton(Sender).Tag;
  OpenDlg.Title := Format('Stem-Datei auf Deck %s laden', [DECK_LETTERS[d]]);
  try
    if OpenDlg.Execute then LoadIntoDeck(d, OpenDlg.FileName);
  finally
    OpenDlg.Title := 'Stem-Datei laden (A_-Datei lädt B_/C_/D_ automatisch mit)';
  end;
end;

procedure TMainForm.BtnPlayClick(Sender: TObject);
begin
  TogglePlay;
end;

procedure TMainForm.BtnStopClick(Sender: TObject);
begin
  if Engine = nil then Exit;
  Engine.Playing := False;
  Engine.SeekTo := 0;
end;

procedure TMainForm.MuteClick(Sender: TObject);
begin
  UpdateGains;
end;

procedure TMainForm.VolChange(Sender: TObject);
var t: Integer;
begin
  t := TDJSlider(Sender).Tag;
  if t >= 1000 then
    Decks[t - 1000].LblVol.Caption := IntToStr(Decks[t - 1000].TrkVol.Position) + '%';
  UpdateGains;
end;

procedure TMainForm.MasterChange(Sender: TObject);
begin
  LblMasterVol.Caption := IntToStr(TrkMaster.Position) + '%';
  UpdateGains;
end;

procedure TMainForm.PosChange(Sender: TObject);
begin
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
  t, d, s: Integer;
  C: TColor;
begin
  PB := TPaintBox(Sender);
  t := PB.Tag;
  d := t div STEMS_PER_DECK;
  s := t mod STEMS_PER_DECK;
  PB.Canvas.Brush.Color := DJ_PANEL;
  PB.Canvas.FillRect(0, 0, PB.Width, PB.Height);
  if (Engine <> nil) and (Engine.Gain[t] > 0) then C := Decks[d].Stems[s].Color
  else C := DJ_OFF;
  DrawLedBar(PB.Canvas, Rect(0, 0, PB.Width, PB.Height),
             LevelToFrac(Decks[d].Stems[s].Level), C, False);
end;

procedure TMainForm.OutMeterPaint(Sender: TObject);
var ch, H, Y: Integer;
begin
  MeterOut.Canvas.Brush.Color := DJ_PANEL;
  MeterOut.Canvas.FillRect(0, 0, MeterOut.Width, MeterOut.Height);
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
  d, s: Integer;
  L: Single;
  Playing: Boolean;
begin
  if Engine = nil then Exit;
  Playing := Engine.Playing;

  if Engine.EndReached and Playing then
  begin
    Engine.Playing := False;
    Engine.SeekTo := 0;
    Playing := False;
  end;

  BtnPlay.Down := Playing;
  if Playing then BtnPlay.Glyph := dgPause else BtnPlay.Glyph := dgPlay;

  if not FDraggingPos then
  begin
    FUpdatingPos := True;
    TrkPos.Position := Engine.PlayPos div (SAMPLE_RATE div 10);
    FUpdatingPos := False;
  end;
  LblTime.Caption := FormatTime(Engine.PlayPos);

  { Pegel: schnell hoch, langsam runter }
  for d := 0 to DECK_COUNT - 1 do
    for s := 0 to STEMS_PER_DECK - 1 do
    begin
      if Playing then L := Engine.Peak[d * STEMS_PER_DECK + s] else L := 0;
      with Decks[d].Stems[s] do
      begin
        if L > Level then Level := L else Level := Level * 0.82;
        Meter.Invalidate;
      end;
    end;
  for s := 0 to 1 do
  begin
    if Playing then L := Engine.OutPeak[s] else L := 0;
    if L > FOutLevel[s] then FOutLevel[s] := L
    else FOutLevel[s] := FOutLevel[s] * 0.82;
  end;
  MeterOut.Invalidate;

  if Engine.ClipCount <> FLastClip then
  begin
    FLastClip := Engine.ClipCount;
    FClipTicks := 33;
  end;
  if FClipTicks > 0 then Dec(FClipTicks);
  BtnClip.Down := FClipTicks > 0;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var d: Integer;
begin
  if FBusy then Exit;
  case Key of
    VK_SPACE: begin TogglePlay; Key := 0; end;
    VK_1..VK_4:
      begin
        d := Key - VK_1;
        if ssCtrl in Shift then Exit;
        Decks[d].BtnMute.Down := not Decks[d].BtnMute.Down;
        UpdateGains;
        Key := 0;
      end;
    VK_5:
      if ssCtrl in Shift then begin BtnSplitClick(nil); Key := 0; end;
    VK_O:
      if ssCtrl in Shift then begin BtnLoadAllClick(nil); Key := 0; end;
    VK_LEFT:  begin SeekRelative(-5); Key := 0; end;
    VK_RIGHT: begin SeekRelative(5); Key := 0; end;
    VK_HOME:  begin if Engine <> nil then Engine.SeekTo := 0; Key := 0; end;
  end;
end;

{ Stem-Datei -> auf die Decks laden, alles andere -> als 5.1-Quelle zerlegen }
procedure TMainForm.OpenAny(const FileName: string);
var Base: string;
begin
  if FBusy or not FileExists(FileName) then Exit;
  if (Pos('.stem.mp4', LowerCase(FileName)) > 0) or
     ((DeckFromFileName(FileName, Base) >= 0) and
      SameText(ExtractFileExt(FileName), '.mp4')) then
    LoadSet(FileName)
  else
    Split51(FileName);
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) > 0 then OpenAny(FileNames[0]);
end;

{ Datei als Parameter ("Öffnen mit" oder Verknüpfung) - erst wenn das
  Fenster sichtbar ist, über die Nachrichtenschlange }
procedure TMainForm.FormShow(Sender: TObject);
begin
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then
    Application.QueueAsyncCall(@OpenParamLater, 0);
end;

procedure TMainForm.OpenParamLater(Data: PtrInt);
begin
  OpenAny(ParamStr(1));
end;

{ Läuft gerade ffmpeg oder StemCLI, darf das Fenster noch nicht zu:
  Abbruch anfordern, das Werkzeug wird beendet und danach geschlossen. }
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FBusy then
  begin
    FCancel := True;
    FCloseAfter := True;
    LblStatus.Caption := 'Breche ab ...';
    CanClose := False;
  end
  else
    CanClose := True;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var d: Integer;
begin
  Timer.Enabled := False;
  FreeAndNil(Engine);
  for d := 0 to DECK_COUNT - 1 do ClearDeck(d);
  ReleaseInstanceDir;
end;

end.
