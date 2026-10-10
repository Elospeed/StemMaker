{ ============================================================================
  deckform.pas  -  Hauptfenster von Elospeed StemDecks

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Zweck:
    Ein 5.1-Mitschnitt (z.B. Konzert-DVD) hat sechs Kanäle. Daraus macht
    das Programm vier Stereo-"Teile": Front L/R, Center, LFE (Sub) und
    Surround L/R. Welcher Teil wohin kommt, ist einstellbar
    (EINSTELLUNGEN). Standard nach dem Wunsch eines Nutzers auf r/Traktor:
        Deck A / Slot 1 = Front L/R
        Deck B / Slot 2 = LFE  (B wie Bass, auf 0 dB angehoben)
        Deck C / Slot 3 = Center
        Deck D / Slot 4 = Surround L/R

    Drei Funktionen:
      1. "5.1 -> 1 STEM": die vier Teile direkt als Stems in EINE
         Stem-Datei (<Name>.stem.mp4) - ohne KI, sehr schnell.
         Master = Kopie von Slot 1 oder still (einstellbar).
      2. "5.1 -> 4 DECKS": schreibt A_/B_/C_/D_<Name>.wav und trennt
         jede davon mit StemCLI (KI, ohne Club-Pegel) in 4 Stems
         -> A_/B_/C_/D_<Name>.stem.mp4 = 16 Stems auf 4 Decks.
      3. Vierfach-StemPlayer im Traktor-Stil (ohne Wellenform):
         Deck A..D mit je 4 Stems (Mute, Fader, LED-Meter), Deck-Fader und
         EIN gemeinsames Play/Pause - alle Decks laufen sampelgenau synchron.
         Wer eine A_-Datei lädt, bekommt B_/C_/D_ aus demselben Ordner
         automatisch dazu.

    Hat die Quelle mehrere Tonspuren (DVD: oft Stereo + AC3 5.1 + DTS 5.1),
    wird gefragt, welche 5.1-Spur verwendet werden soll.

    Alles, was passiert (auch die komplette Ausgabe von ffmpeg/StemCLI),
    steht im Protokoll logs\StemDecks.log (Knopf LOG). Bei Problemen
    schickt der Nutzer diese Datei.

  Aufbau wie im StemPlayer: Fenster komplett im Code (keine .lfm),
  Optik aus djcontrols.pas, Stem-Prüfung aus mp4stem.pas (beide aus
  ..\StemPlayer\ mitbenutzt), Stem-Block aus ..\..\ustemmp4.pas (StemMaker),
  Audio in deckengine.pas, Sprache und Protokoll in decklog.pas.

  Temp-Dateien: wie StemPlayer ein eigener Ordner pro Instanz
      %TEMP%\ElospeedStemDecks_<PID>_<Startzeit>\   (mit instance.lock)
  darin pro Deck ein Unterordner mit den dekodierten Stems
  (16 Bit / 44.1 kHz / Stereo, ca. 10 MB pro Stem und Minute). Beim
  Schliessen wird alles gelöscht, Reste nach einem Absturz beim nächsten
  Start.

  Einstellungen in StemDecks.ini neben der exe:
      [Zuordnung] DeckA..DeckD = 0 Front, 1 Center, 2 LFE, 3 Surround
                  LfeAuf0dB = 1/0, MasterStill = 1/0
      [Allgemein] Sprache = (leer = automatisch) / de / en
      [Pfade]     ffmpeg, stemcli

  Tastatur:
    Leertaste / P  Play / Pause (alle Decks)   Pos1   an den Anfang
    1..4           Deck A..D stumm an/aus      Pfeile -/+ 5 s
    Strg+O         Decks laden
  Parameter / Drag & Drop: Stem-Datei -> laden, andere Datei -> fragen,
  ob 1 Stem-Datei oder 4 Decks.

  Versionen:
    0.1  (10.10.2026)  Erste Testversion (Machbarkeit 5.1 auf vier Decks)
    0.2  (10.10.2026)  Zuordnung einstellbar (Standard A Front, B LFE,
                       C Center, D Surround), "5.1 -> 1 STEM" ohne KI,
                       Auswahl der Tonspur, LFE auf 0 dB, Protokoll mit
                       Log-Fenster, Deutsch/Englisch, Taste P
  ============================================================================ }
unit deckform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, LCLType, LCLIntf, Process, FileUtil, LazFileUtils, IniFiles,
  uStemMP4, mp4stem, deckengine, djcontrols, surround51, decklog;

const
  APP_TITLE   = 'Elospeed StemDecks';
  APP_VER     = '0.2';
  TEMP_PREFIX = 'ElospeedStemDecks_';   // Präfix der Temp-Ordner
  LOCK_NAME   = 'instance.lock';        // Sperrdatei im Instanz-Ordner
  TEST_SECONDS= 180;                    // "nur Anfang" beim Umwandeln

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
    Info     : mp4stem.TStemInfo;
  end;

  { TMainForm }

  TMainForm = class(TForm)
  private
    { --- Oben --- }
    PnlTop     : TDJPanel;
    BtnPack    : TDJButton;
    BtnSplit   : TDJButton;
    BtnLoadAll : TDJButton;
    BtnSettings: TDJButton;
    BtnLog     : TDJButton;
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
    SrcDlg     : TOpenDialog;

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
    { Einstellungen }
    FParts      : TDeckParts;  // welcher 5.1-Teil auf Deck/Slot A..D
    FLfeNorm    : Boolean;     // LFE auf 0 dB Spitzenpegel anheben
    FMasterSilent: Boolean;    // Master der Stem-Datei still statt = Slot 1
    FIniLang    : string;      // '' / 'de' / 'en'
    { Bedienelemente im Fenster EINSTELLUNGEN (nur solange es offen ist) }
    FSetCb      : array[0..3] of TComboBox;
    FSetLfe     : TCheckBox;
    FSetMaster  : TComboBox;

    { Aufbau }
    procedure BuildUI;
    procedure BuildDeck(d: Integer);
    procedure LayoutDecks(Sender: TObject);
    procedure UpdateHint;
    function  MakeButton(AParent: TWinControl; const ACaption: string;
                         ALeft, ATop, AWidth, AHeight: Integer): TDJButton;
    function  MakeFader(AParent: TWinControl; ALeft, ATop, AWidth: Integer;
                        AFill: TColor): TDJSlider;
    function  MakeLabel(AParent: TWinControl; const ACaption: string;
                        ALeft, ATop: Integer; ASize: Integer; ABold: Boolean): TLabel;

    { Einstellungen }
    function  IniFileName: string;
    procedure LoadSettings;
    procedure SaveSettings;
    function  ShowSettings: Boolean;
    procedure SettingsDefaultClick(Sender: TObject);
    procedure SettingsCloseQuery(Sender: TObject; var CanClose: Boolean);
    function  PartsText: string;

    { Werkzeuge / Temp }
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

    { 5.1 umwandeln }
    function  ProbeSource(const FileName: string; out Track: Integer;
                          out Layout, AudioLine: string): Boolean;
    function  ChooseTrack(const Tracks: TAudioTracks; out Idx: Integer): Boolean;
    function  AskLength(const AudioLine, Extra: string): Integer;
    function  MeasureLfeGain(const FileName, Layout: string; Track, MaxSec: Integer): Double;
    procedure Pack51(const FileName: string);
    procedure Split51(const FileName: string);
    function  ConvertWithStemCLI(const Wavs: array of string): Boolean;

    { Ereignisse }
    procedure BtnPackClick(Sender: TObject);
    procedure BtnSplitClick(Sender: TObject);
    procedure BtnLoadAllClick(Sender: TObject);
    procedure BtnSettingsClick(Sender: TObject);
    procedure BtnLogClick(Sender: TObject);
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
  { Stem-Farben in der verpackten Datei, je 5.1-Teil (Front, Center, LFE, Surround) }
  PART_COLORS: array[0..3] of string = ('#56B4E9', '#CC79A7', '#D55E00', '#009E73');
  { Dateitypen, in denen 5.1-Ton stecken kann }
  SRC_FILTER_EXT =
    '*.mkv;*.mka;*.mp4;*.m4v;*.m4a;*.mov;*.ac3;*.eac3;*.dts;*.thd;*.wav;*.flac;' +
    '*.vob;*.ts;*.m2ts;*.mts;*.avi;*.webm;*.ogg;*.opus';

{ ============================================================================
  Aufbau des Fensters
  ============================================================================ }

constructor TMainForm.Create(TheOwner: TComponent);
var d: Integer;
begin
  inherited CreateNew(TheOwner);    // keine .lfm-Datei
  { Erst Einstellungen (darin steht die Sprache), dann Protokoll, dann Fenster }
  LoadSettings;
  InitLanguage(FIniLang);
  LogInit(APP_TITLE, APP_VER);
  Log('Zuordnung / mapping: ' + PartsText);

  Caption := APP_TITLE + ' ' + APP_VER +
    T('  -  5.1 auf Stems und vier Decks  -  von Elospeed',
      '  -  5.1 to stems and four decks  -  by Elospeed');
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
  UpdateHint;

  OpenDlg := TOpenDialog.Create(Self);
  OpenDlg.Title := T('Stem-Datei laden (A_-Datei lädt B_/C_/D_ automatisch mit)',
                     'Load stem file (an A_ file also loads B_/C_/D_)');
  OpenDlg.Filter := T('Traktor Stems', 'Traktor stems') +
    ' (*.stem.mp4;*.mp4)|*.stem.mp4;*.mp4|' + T('Alle Dateien', 'All files') + ' (*.*)|*.*';

  SrcDlg := TOpenDialog.Create(Self);
  SrcDlg.Filter := T('5.1-Ton (Video/Audio)', '5.1 audio (video/audio)') + '|' +
    SRC_FILTER_EXT + '|' + T('Alle Dateien', 'All files') + ' (*.*)|*.*';

  Timer := TTimer.Create(Self);
  Timer.Interval := 30;
  Timer.OnTimer := @TimerTick;
  Timer.Enabled := True;

  CleanupOrphanTempDirs;
  CreateInstanceDir;

  FFFmpeg := FindFFmpeg;
  Log('ffmpeg : ' + FFFmpeg);
  Log('StemCLI: ' + FindStemCLI);
  if FFFmpeg = '' then
    LblStatus.Caption := T('ffmpeg.exe nicht gefunden - wird beim ersten Gebrauch abgefragt.',
                           'ffmpeg.exe not found - you will be asked for it on first use.')
  else
    LblStatus.Caption := 'ffmpeg: ' + FFFmpeg + '    ·    Log: ' + LogFileName;
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

  BtnPack := MakeButton(PnlTop, '5.1 -> 1 STEM', 12, 10, 136, 32);
  BtnPack.Hint := T('5.1-Datei direkt in EINE Stem-Datei verpacken (ohne KI):' + LineEnding +
                    'die vier 5.1-Teile werden Stem 1..4 (Zuordnung unter EINSTELLUNGEN)',
                    'Pack a 5.1 file into ONE stem file (no AI):' + LineEnding +
                    'the four 5.1 parts become stems 1..4 (mapping under SETTINGS)');
  BtnPack.ShowHint := True;
  BtnPack.OnClick := @BtnPackClick;

  BtnSplit := MakeButton(PnlTop, '5.1 -> 4 DECKS', 156, 10, 136, 32);
  BtnSplit.Hint := T('5.1-Datei in A_/B_/C_/D_-Dateien aufteilen und jede mit KI' + LineEnding +
                     'in 4 Stems trennen (16 Stems auf 4 Decks, braucht StemMaker)',
                     'Split a 5.1 file into A_/B_/C_/D_ files and separate each' + LineEnding +
                     'into 4 stems with AI (16 stems on 4 decks, needs StemMaker)');
  BtnSplit.ShowHint := True;
  BtnSplit.OnClick := @BtnSplitClick;

  BtnLoadAll := MakeButton(PnlTop, T('DECKS LADEN', 'LOAD DECKS'), 300, 10, 120, 32);
  BtnLoadAll.Hint := T('Eine A_-Stem-Datei wählen: B_/C_/D_ aus demselben Ordner' + LineEnding +
                       'werden automatisch auf Deck B..D geladen (Strg+O)',
                       'Pick an A_ stem file: B_/C_/D_ from the same folder' + LineEnding +
                       'are loaded onto decks B..D automatically (Ctrl+O)');
  BtnLoadAll.ShowHint := True;
  BtnLoadAll.OnClick := @BtnLoadAllClick;

  BtnSettings := MakeButton(PnlTop, T('EINSTELLUNGEN', 'SETTINGS'), 428, 10, 120, 32);
  BtnSettings.Hint := T('Welcher 5.1-Teil auf welchem Deck / Slot, LFE, Master, Sprache',
                        'Which 5.1 part goes to which deck / slot, LFE, master, language');
  BtnSettings.ShowHint := True;
  BtnSettings.OnClick := @BtnSettingsClick;

  BtnLog := MakeButton(PnlTop, 'LOG', 556, 10, 60, 32);
  BtnLog.Hint := T('Protokoll anzeigen (bei Problemen bitte die Datei schicken)',
                   'Show the log (if something goes wrong, please send us this file)');
  BtnLog.ShowHint := True;
  BtnLog.OnClick := @BtnLogClick;

  LblHint := MakeLabel(PnlTop, '', 630, 18, 0, False);
  LblHint.Font.Color := DJ_DIM;

  BtnPlay := MakeButton(PnlTop, '', 12, 56, 46, 36);
  BtnPlay.Glyph := dgPlay;
  BtnPlay.LitColor := DJ_GREEN;
  BtnPlay.Enabled := False;
  BtnPlay.Hint := T('Play / Pause - alle Decks gleichzeitig (Leertaste oder P)',
                    'Play / pause - all decks together (space or P)');
  BtnPlay.ShowHint := True;
  BtnPlay.OnClick := @BtnPlayClick;

  BtnStop := MakeButton(PnlTop, '', 64, 56, 46, 36);
  BtnStop.Glyph := dgStop;
  BtnStop.Enabled := False;
  BtnStop.Hint := T('Stop und zurück an den Anfang', 'Stop and back to the start');
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
    T('Leertaste / P  Play/Pause  ·  1-4 Deck A-D stumm  ·  Pfeile -/+5 s  ·  Pos1 Anfang  ·  ' +
      'Strg+O Decks laden  ·  Dateien aufs Fenster ziehen',
      'Space / P  play/pause  ·  1-4 mute deck A-D  ·  arrows -/+5 s  ·  Home start  ·  ' +
      'Ctrl+O load decks  ·  drop files onto the window'), 12, 6, 0, False);
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
  L := MakeLabel(PnlMaster, T('SUMME ALLER DECKS', 'SUM OF ALL DECKS'), 14, 32, 7, False);
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
  BtnClip.Hint := T('Leuchtet rot, wenn die Summe übersteuert (dann Master leiser stellen)',
                    'Lights red when the sum clips (turn the master down)');
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

  Dk^.LblName := MakeLabel(Dk^.Panel, '', 52, 8, 11, True);
  Dk^.LblName.AutoSize := False;
  Dk^.LblName.SetBounds(52, 8, W - 52 - 96, 22);
  Dk^.LblName.Anchors := [akLeft, akTop, akRight];
  Dk^.LblName.Font.Color := DJ_DIM;

  Dk^.LblInfo := MakeLabel(Dk^.Panel, '', 52, 30, 8, False);
  Dk^.LblInfo.Font.Color := DJ_DIM;

  Dk^.BtnLoad := MakeButton(Dk^.Panel, T('LADEN', 'LOAD'), W - 88, 10, 76, 28);
  Dk^.BtnLoad.Anchors := [akTop, akRight];
  Dk^.BtnLoad.Tag := d;
  Dk^.BtnLoad.Hint := Format(T('Stem-Datei auf Deck %s laden', 'Load a stem file onto deck %s'),
                             [DECK_LETTERS[d]]);
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
  Dk^.BtnMute.Hint := Format(T('Ganzes Deck %s stumm (Taste %d)', 'Mute whole deck %s (key %d)'),
                             [DECK_LETTERS[d], d + 1]);
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

{ "A = FRONT L/R  ·  B = LFE (SUB)  ·  ..." }
function TMainForm.PartsText: string;
var d: Integer;
begin
  Result := '';
  for d := 0 to 3 do
  begin
    if d > 0 then Result := Result + '  ·  ';
    Result := Result + DECK_LETTERS[d] + ' = ' + PART_NAMES[FParts[d]];
  end;
end;

procedure TMainForm.UpdateHint;
begin
  LblHint.Caption := PartsText;
end;

{ ============================================================================
  Einstellungen
  ============================================================================ }

function TMainForm.IniFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TMainForm.LoadSettings;
var
  Ini: TIniFile;
  d: Integer;
begin
  FParts := DEFAULT_PARTS;
  FLfeNorm := True;
  FMasterSilent := False;
  FIniLang := '';
  try
    Ini := TIniFile.Create(IniFileName);
    try
      for d := 0 to 3 do
        FParts[d] := Ini.ReadInteger('Zuordnung', 'Deck' + DECK_LETTERS[d], DEFAULT_PARTS[d]);
      FLfeNorm := Ini.ReadBool('Zuordnung', 'LfeAuf0dB', True);
      FMasterSilent := Ini.ReadBool('Zuordnung', 'MasterStill', False);
      FIniLang := Trim(Ini.ReadString('Allgemein', 'Sprache', ''));
    finally
      Ini.Free;
    end;
  except
    { ini nicht lesbar -> Standard }
  end;
  if not PartsValid(FParts) then FParts := DEFAULT_PARTS;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
  d: Integer;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      for d := 0 to 3 do
        Ini.WriteInteger('Zuordnung', 'Deck' + DECK_LETTERS[d], FParts[d]);
      Ini.WriteBool('Zuordnung', 'LfeAuf0dB', FLfeNorm);
      Ini.WriteBool('Zuordnung', 'MasterStill', FMasterSilent);
      Ini.WriteString('Allgemein', 'Sprache', FIniLang);
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      Log('Einstellungen nicht gespeichert / settings not saved: ' + E.Message);
  end;
end;

{ Fenster EINSTELLUNGEN. True = übernommen }
function TMainForm.ShowSettings: Boolean;
var
  F: TForm;
  Cb: array[0..3] of TComboBox;
  CbMaster, CbLang: TComboBox;
  ChkLfe: TCheckBox;
  L: TLabel;
  B: TButton;
  P: TDeckParts;
  d, k, Y: Integer;
  R: TModalResult;
  OldLang: string;

  function AddLabel(const S: string; X, AY: Integer): TLabel;
  begin
    Result := TLabel.Create(F);
    Result.Parent := F;
    Result.Left := X;
    Result.Top := AY;
    Result.Caption := S;
  end;

  function AddCombo(X, AY, AW: Integer): TComboBox;
  begin
    Result := TComboBox.Create(F);
    Result.Parent := F;
    Result.Style := csDropDownList;
    Result.SetBounds(X, AY, AW, 26);
  end;

  function AddButton(const S: string; X: Integer; MR: TModalResult): TButton;
  begin
    Result := TButton.Create(F);
    Result.Parent := F;
    Result.SetBounds(X, F.ClientHeight - 44, 130, 30);
    Result.Caption := S;
    Result.ModalResult := MR;
  end;

begin
  Result := False;
  F := TForm.CreateNew(nil);
  try
    F.Caption := APP_TITLE + ' - ' + T('Einstellungen', 'Settings');
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.ClientWidth := 580;
    F.ClientHeight := 400;

    L := AddLabel(T('Welcher 5.1-Teil kommt auf welches Deck (5.1 -> 4 DECKS)' + LineEnding +
                    'bzw. in welchen Stem-Slot (5.1 -> 1 STEM)?',
                    'Which 5.1 part goes to which deck (5.1 -> 4 DECKS)' + LineEnding +
                    'or into which stem slot (5.1 -> 1 STEM)?'), 16, 12);
    L.Font.Style := [fsBold];

    for d := 0 to 3 do
    begin
      Y := 60 + d * 34;
      AddLabel(Format(T('Deck %s  /  Slot %d', 'Deck %s  /  slot %d'), [DECK_LETTERS[d], d + 1]),
               16, Y + 4);
      Cb[d] := AddCombo(190, Y, 220);
      for k := 0 to 3 do Cb[d].Items.Add(PART_NAMES[k]);
      Cb[d].ItemIndex := FParts[d];
    end;

    ChkLfe := TCheckBox.Create(F);
    ChkLfe.Parent := F;
    ChkLfe.SetBounds(16, 206, 550, 24);
    ChkLfe.Caption := T('LFE (Sub) auf 0 dB Spitzenpegel anheben (ist auf DVDs meist sehr leise)',
                        'Raise LFE (sub) to 0 dB peak (usually very quiet on DVDs)');
    ChkLfe.Checked := FLfeNorm;

    AddLabel(T('Master-Spur der Stem-Datei:', 'Master track of the stem file:'), 16, 248);
    CbMaster := AddCombo(250, 244, 220);
    CbMaster.Items.Add(T('gleich wie Slot 1', 'same as slot 1'));
    CbMaster.Items.Add(T('still (leer)', 'silent (empty)'));
    if FMasterSilent then CbMaster.ItemIndex := 1 else CbMaster.ItemIndex := 0;

    AddLabel('Sprache / Language:', 16, 290);
    CbLang := AddCombo(250, 286, 220);
    CbLang.Items.Add('Automatisch / Automatic');
    CbLang.Items.Add('Deutsch');
    CbLang.Items.Add('English');
    if SameText(FIniLang, 'de') then CbLang.ItemIndex := 1
    else if SameText(FIniLang, 'en') then CbLang.ItemIndex := 2
    else CbLang.ItemIndex := 0;
    L := AddLabel(T('(gilt nach einem Neustart)', '(takes effect after a restart)'), 250, 316);
    L.Font.Color := clGrayText;

    B := AddButton(T('Standard', 'Default'), 16, mrNone);
    B.OnClick := @SettingsDefaultClick;
    B := AddButton('OK', F.ClientWidth - 2 * 138, mrOK);
    B.Default := True;
    B := AddButton(T('Abbrechen', 'Cancel'), F.ClientWidth - 138, mrCancel);
    B.Cancel := True;

    { Für "Standard" und die Prüfung beim Schliessen merken }
    for d := 0 to 3 do FSetCb[d] := Cb[d];
    FSetLfe := ChkLfe;
    FSetMaster := CbMaster;
    F.OnCloseQuery := @SettingsCloseQuery;
    R := F.ShowModal;
    FSetLfe := nil;
    FSetMaster := nil;
    if R <> mrOK then Exit;
    for d := 0 to 3 do P[d] := Cb[d].ItemIndex;

    FParts := P;
    FLfeNorm := ChkLfe.Checked;
    FMasterSilent := CbMaster.ItemIndex = 1;
    OldLang := FIniLang;
    case CbLang.ItemIndex of
      1: FIniLang := 'de';
      2: FIniLang := 'en';
    else
      FIniLang := '';
    end;
    SaveSettings;
    UpdateHint;
    for d := 0 to DECK_COUNT - 1 do UpdateDeckLook(d);
    Log(Format('Einstellungen / settings: %s  ·  LFE 0 dB=%s  ·  master silent=%s  ·  lang=%s',
      [PartsText, BoolToStr(FLfeNorm, True), BoolToStr(FMasterSilent, True), FIniLang]));
    if not SameText(OldLang, FIniLang) then
      MessageDlg(APP_TITLE, T('Die Sprache wird beim nächsten Start umgestellt.',
                              'The language changes at the next start.'), mtInformation, [mbOK], 0);
    Result := True;
  finally
    F.Free;
  end;
end;

{ Knopf "Standard": Zuordnung A Front, B LFE, C Center, D Surround }
procedure TMainForm.SettingsDefaultClick(Sender: TObject);
var d: Integer;
begin
  for d := 0 to 3 do FSetCb[d].ItemIndex := DEFAULT_PARTS[d];
  FSetLfe.Checked := True;
  FSetMaster.ItemIndex := 0;
end;

{ Bei OK prüfen, ob jeder Teil genau einmal vorkommt - sonst bleibt das
  Fenster offen }
procedure TMainForm.SettingsCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  P: TDeckParts;
  d: Integer;
begin
  if TForm(Sender).ModalResult <> mrOK then Exit;
  for d := 0 to 3 do P[d] := FSetCb[d].ItemIndex;
  CanClose := PartsValid(P);
  if not CanClose then
    MessageDlg(APP_TITLE, T('Jeder 5.1-Teil darf nur einmal vorkommen.',
                            'Each 5.1 part may be used only once.'), mtWarning, [mbOK], 0);
end;

{ ============================================================================
  Werkzeuge finden, Temp-Ordner
  ============================================================================ }

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
  Log(ExeName + ' nicht gefunden / not found - frage Nutzer / asking user');
  MessageDlg(APP_TITLE, ExeName + T(' wurde nicht gefunden.', ' was not found.') +
    LineEnding + Why, mtInformation, [mbOK], 0);
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := ExeName + T(' auswählen', ' - please select');
    Dlg.Filter := ExeName + '|' + ExeName + '|' + T('Programme', 'Programs') + ' (*.exe)|*.exe';
    if Dlg.Execute then Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  Log(ExeName + ' = ' + Result);
  if Result <> '' then WriteIniPath(IniKey, Result);
end;

function TMainForm.FindFFmpeg: string;
const
  { Typische Orte relativ zur exe (StemDecks liegt allein oder in StemMaker\AddOns\) }
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
      T('Bitte im nächsten Dialog die ffmpeg.exe auswählen' + LineEnding +
        '(z.B. die von StemMaker im Ordner tools\, oder von ffmpeg.org).',
        'Please select ffmpeg.exe in the next dialog' + LineEnding +
        '(e.g. the one in StemMaker''s tools\ folder, or from ffmpeg.org).'),
      'ffmpeg');
  Result := FFFmpeg <> '';
end;

{ Startet ein Werkzeug (ffmpeg oder StemCLI) ohne Konsolenfenster, liest
  seine Ausgabe laufend mit (sonst läuft die Pipe voll und es bleibt hängen)
  und hält das Fenster bedienbar. Die letzte Ausgabezeile erscheint in der
  Statuszeile. Aufruf, Exit-Code, Dauer und Ausgabe kommen ins Protokoll.
  Rückgabe: Exit-Code, -1 bei Abbruch (Fenster geschlossen) oder wenn das
  Programm nicht startet. }
function TMainForm.RunTool(const Exe: string; Args: TStrings; const What: string;
  out OutText: string): Integer;
var
  P: TProcess;
  Buf: array[0..4095] of Char;
  Chunk, LastLine, Cmd: string;
  n: LongInt;
  i: Integer;
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
  { Aufruf ins Protokoll (Parameter mit Leerzeichen in Anführungszeichen) }
  Cmd := '"' + Exe + '"';
  for i := 0 to Args.Count - 1 do
    if Pos(' ', Args[i]) > 0 then Cmd := Cmd + ' "' + Args[i] + '"'
    else Cmd := Cmd + ' ' + Args[i];
  Log(What);
  Log('  > ' + Cmd);
  T0 := GetTickCount64;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Parameters.Assign(Args);
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHIDE;
    try
      P.Execute;
    except
      on E: Exception do
      begin
        Log('  ! Start fehlgeschlagen / failed to start: ' + E.Message);
        OutText := E.Message;
        Exit(-1);
      end;
    end;
    while P.Running do
    begin
      Drain;
      if FCancel then
      begin
        P.Terminate(1);
        P.WaitOnExit;     // warten, bis die Dateien freigegeben sind
        Log('  ! abgebrochen / cancelled');
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
  Log(Format('  < Exit-Code %d nach / after %.1f s', [Result, (GetTickCount64 - T0) / 1000]));
  { Ausgabe ins Protokoll (bei sehr langer Ausgabe nur das Ende) }
  if Length(OutText) > 12000 then
    LogBlock('[...]' + LineEnding + Copy(OutText, Length(OutText) - 12000, MaxInt))
  else
    LogBlock(StringReplace(OutText, #13#10, #10, [rfReplaceAll]));
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
  BtnPack.Enabled := not B;
  BtnSplit.Enabled := not B;
  BtnLoadAll.Enabled := not B;
  BtnSettings.Enabled := not B;
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
  NewInfo: mp4stem.TStemInfo;
  Reason, Dir, OutText: string;
  Args: TStringList;
  s, Code: Integer;
  F: TFileStream;
begin
  Result := False;
  if not CheckStemFile(FileName, NewInfo, Reason) then
  begin
    Log('Keine Stem-Datei / not a stem file: ' + FileName + ' - ' + Reason);
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
    { Nur die 4 Stems (Spur 1..4). Den Master braucht der Player nicht. }
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
      Format(T('Deck %s: dekodiere %s', 'Deck %s: decoding %s'),
        [DECK_LETTERS[d], ExtractFileName(FileName)]), OutText);
  finally
    Args.Free;
  end;
  if Code <> 0 then
  begin
    DeleteDirectory(Dir, False);
    if Code > 0 then
      MessageDlg(APP_TITLE, T('ffmpeg konnte die Datei nicht dekodieren:',
        'ffmpeg could not decode the file:') + LineEnding +
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
  Log(Format('Deck %s: %s (%s)', [DECK_LETTERS[d], FileName, FormatTime(Decks[d].Frames)]));
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
    begin
      Log('Audio-Fehler / audio error: ' + Engine.OpenError);
      MessageDlg(APP_TITLE, Engine.OpenError, mtError, [mbOK], 0);
    end;
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
      LblStatus.Caption := Format(T('Deck %s geladen: %s', 'Deck %s loaded: %s'),
                                  [DECK_LETTERS[d], FileName]);
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
      LblStatus.Caption := Format(T('%d Decks geladen (%s)  ·  Länge %s',
                                    '%d decks loaded (%s)  ·  length %s'),
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
  s, DeckOfFile: Integer;
  Base: string;
  IsOn, DeckOn: Boolean;
begin
  with Decks[d] do
  begin
    DeckOn := (RawDir <> '') and not BtnMute.Down;
    if RawDir = '' then
    begin
      LblName.Caption := T('(leer)', '(empty)');
      LblName.Font.Color := DJ_DIM;
      LblInfo.Caption := T('Stem-Datei laden', 'load a stem file');
    end
    else
    begin
      LblName.Caption := ExtractFileName(FileName);
      LblName.Font.Color := DJ_TEXT;
      DeckOfFile := DeckFromFileName(FileName, Base);
      if DeckOfFile >= 0 then
        LblInfo.Caption := Format(T('5.1-Teil: %s  ·  %s', '5.1 part: %s  ·  %s'),
          [PART_NAMES[FParts[DeckOfFile]], FormatTime(Frames)])
      else
        LblInfo.Caption := T('Länge ', 'length ') + FormatTime(Frames);
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
  5.1 umwandeln
  ============================================================================ }

{ Liest die Tonspuren der Quelle und wählt eine 5.1-Spur (bei mehreren
  fragt ein Fenster). False = keine passende Spur oder abgebrochen. }
function TMainForm.ProbeSource(const FileName: string; out Track: Integer;
  out Layout, AudioLine: string): Boolean;
var
  Args: TStringList;
  OutText, AllLines: string;
  Tracks, Usable: TAudioTracks;
  i, n, Idx, Code: Integer;
begin
  Result := False;
  Track := -1;
  Layout := '';
  AudioLine := '';
  Log('Quelle / source: ' + FileName);
  Args := TStringList.Create;
  try
    { "ffmpeg -i Datei" ohne Ausgabe listet die Spuren auf (Exit-Code ist
      dabei immer 1, das ist normal) }
    Args.Add('-hide_banner');
    Args.Add('-nostdin');
    Args.Add('-probesize'); Args.Add('100M');
    Args.Add('-analyzeduration'); Args.Add('100M');
    Args.Add('-i'); Args.Add(FileName);
    Code := RunTool(FFFmpeg, Args, T('Prüfe Tonspuren', 'Checking audio tracks'), OutText);
  finally
    Args.Free;
  end;
  if Code < 0 then Exit;

  Tracks := ParseAudioTracks(OutText);
  Usable := nil;
  n := 0;
  AllLines := '';
  for i := 0 to High(Tracks) do
  begin
    AllLines := AllLines + '  ' + Tracks[i].Line + LineEnding;
    if IsSupported51(Tracks[i].Layout) then
    begin
      SetLength(Usable, n + 1);
      Usable[n] := Tracks[i];
      Inc(n);
    end;
  end;
  Log(Format('%d Tonspur(en) / audio track(s), davon 5.1 / of which 5.1: %d', [Length(Tracks), n]));

  if Length(Tracks) = 0 then
  begin
    MessageDlg(APP_TITLE, T('In dieser Datei wurde keine Tonspur gefunden:',
      'No audio track was found in this file:') + LineEnding + FileName + LineEnding + LineEnding +
      T('Bei DVDs: die grossen VOB-Dateien des Films nehmen (z.B. VTS_01_1.VOB),' + LineEnding +
        'nicht VIDEO_TS.VOB. Kopiergeschützte DVDs kann ffmpeg nicht lesen.',
        'For DVDs: use the big VOB files of the movie (e.g. VTS_01_1.VOB),' + LineEnding +
        'not VIDEO_TS.VOB. ffmpeg cannot read copy-protected DVDs.'),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  if n = 0 then
  begin
    MessageDlg(APP_TITLE, T('Keine 5.1-Tonspur gefunden. Vorhandene Tonspuren:',
      'No 5.1 audio track found. Audio tracks in this file:') + LineEnding + LineEnding +
      AllLines + LineEnding +
      T('Unterstützt wird 5.1 bzw. 5.1(side) (6 Kanäle).',
        'Supported: 5.1 or 5.1(side) (6 channels).'), mtWarning, [mbOK], 0);
    Exit;
  end;

  Idx := 0;
  if n > 1 then
    if not ChooseTrack(Usable, Idx) then Exit;
  Track := Usable[Idx].Index;
  Layout := Usable[Idx].Layout;
  AudioLine := Usable[Idx].Line;
  Log(Format('Gewählt / selected: Tonspur / audio track %d (%s)  %s', [Track + 1, Layout, AudioLine]));
  Result := True;
end;

{ Auswahlfenster, wenn die Quelle mehrere 5.1-Spuren hat (DVD: AC3 + DTS) }
function TMainForm.ChooseTrack(const Tracks: TAudioTracks; out Idx: Integer): Boolean;
var
  F: TForm;
  LB: TListBox;
  L: TLabel;
  B: TButton;
  i: Integer;
begin
  Result := False;
  Idx := 0;
  F := TForm.CreateNew(nil);
  try
    F.Caption := APP_TITLE + ' - ' + T('Tonspur wählen', 'Choose audio track');
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.ClientWidth := 760;
    F.ClientHeight := 260;

    L := TLabel.Create(F);
    L.Parent := F;
    L.SetBounds(12, 12, 730, 20);
    L.Caption := T('Diese Datei hat mehrere 5.1-Tonspuren. Welche soll verwendet werden?',
                   'This file has several 5.1 audio tracks. Which one should be used?');

    LB := TListBox.Create(F);
    LB.Parent := F;
    LB.SetBounds(12, 40, 736, 160);
    for i := 0 to High(Tracks) do
      LB.Items.Add(Format(T('Tonspur %d:  %s', 'Audio track %d:  %s'),
        [Tracks[i].Index + 1, Tracks[i].Line]));
    LB.ItemIndex := 0;

    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(F.ClientWidth - 2 * 128, 214, 116, 30);
    B.Caption := 'OK';
    B.ModalResult := mrOK;
    B.Default := True;

    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(F.ClientWidth - 128, 214, 116, 30);
    B.Caption := T('Abbrechen', 'Cancel');
    B.ModalResult := mrCancel;
    B.Cancel := True;

    if (F.ShowModal = mrOK) and (LB.ItemIndex >= 0) then
    begin
      Idx := LB.ItemIndex;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

{ Ganze Datei oder nur der Anfang? Rückgabe: Sekunden (0 = ganz), -1 = Abbruch }
function TMainForm.AskLength(const AudioLine, Extra: string): Integer;
var R: TModalResult;
begin
  R := QuestionDlg(APP_TITLE,
    T('5.1-Ton gefunden:', '5.1 audio found:') + LineEnding + AudioLine + LineEnding + LineEnding +
    Extra + LineEnding + LineEnding +
    Format(T('Ganze Datei oder nur die ersten %d Minuten (schneller zum Testen)?',
             'Whole file or only the first %d minutes (quicker for testing)?'), [TEST_SECONDS div 60]),
    mtConfirmation,
    [mrYes, Format(T('Nur %d Minuten', 'Only %d minutes'), [TEST_SECONDS div 60]),
     mrAll, T('Ganze Datei', 'Whole file'),
     mrCancel, T('Abbrechen', 'Cancel')], 0);
  if R = mrYes then Result := TEST_SECONDS
  else if R = mrAll then Result := 0
  else Result := -1;
  Log(Format('Länge / length: %d s (0 = ganz / whole, -1 = Abbruch / cancel)', [Result]));
end;

{ Misst den Spitzenpegel des LFE und liefert die Anhebung auf 0 dB.
  0 = keine Anhebung (ausgeschaltet, Kanal stumm oder Messung fehlgeschlagen) }
function TMainForm.MeasureLfeGain(const FileName, Layout: string; Track, MaxSec: Integer): Double;
var
  Args: TStringList;
  OutText: string;
  Peak: Double;
  Code: Integer;
begin
  Result := 0;
  if not FLfeNorm then Exit;
  Args := TStringList.Create;
  try
    BuildLfePeakArgs(FileName, Layout, Track, MaxSec, Args);
    Code := RunTool(FFFmpeg, Args, T('Messe LFE-Pegel', 'Measuring LFE level'), OutText);
  finally
    Args.Free;
  end;
  if Code <> 0 then Exit;
  if not ParseMaxVolume(OutText, Peak) then
  begin
    Log('LFE: kein max_volume gefunden / not found');
    Exit;
  end;
  if Peak < -80 then
  begin
    Log(Format('LFE ist praktisch stumm / practically silent (%.1f dB) - keine Anhebung / no gain', [Peak]));
    Exit;
  end;
  Result := EnsureRange(-Peak, 0, 40);
  Log(Format('LFE Spitze / peak %.1f dB -> Anhebung / gain +%.1f dB', [Peak, Result]));
end;

{ 5.1 -> EINE Stem-Datei (ohne KI): Slot 1..4 = Teile gemäss Zuordnung }
procedure TMainForm.Pack51(const FileName: string);
var
  Args: TStringList;
  OutText, AudioLine, Layout, OutFile, TmpFile, Err, Desc: string;
  Track, MaxSec, Code, s: Integer;
  Gain: Double;
  Stems: TStemInfoArray;
  LoadNow: Boolean;
begin
  if FBusy or not EnsureFFmpeg then Exit;
  LoadNow := False;
  OutFile := '';
  SetBusy(True);
  Args := TStringList.Create;
  try
    Log('--- 5.1 -> 1 STEM ---');
    if not ProbeSource(FileName, Track, Layout, AudioLine) then Exit;

    Desc := T('Es entsteht EINE Stem-Datei (ohne KI):', 'This creates ONE stem file (no AI):') + LineEnding;
    for s := 0 to 3 do
      Desc := Desc + Format('  Slot %d = %s', [s + 1, PART_NAMES[FParts[s]]]) + LineEnding;
    if FMasterSilent then Desc := Desc + T('  Master = still', '  Master = silent')
    else Desc := Desc + T('  Master = gleich wie Slot 1', '  Master = same as slot 1');
    MaxSec := AskLength(AudioLine, Desc);
    if MaxSec < 0 then Exit;

    Gain := MeasureLfeGain(FileName, Layout, Track, MaxSec);
    if FCancel then Exit;

    OutFile := ExtractFilePath(FileName) + ExtractFileNameOnly(FileName) + '.stem.mp4';
    TmpFile := ExtractFilePath(FileName) + ExtractFileNameOnly(FileName) + '.stemdecks.tmp.mp4';
    if FileExists(OutFile) then
      if MessageDlg(APP_TITLE, ExtractFileName(OutFile) +
           T(' gibt es schon. Überschreiben?', ' already exists. Overwrite?'),
           mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      begin
        OutFile := '';
        Exit;
      end;

    BuildPackArgs(FileName, TmpFile, Layout, Track, MaxSec, FParts, Gain, FMasterSilent, Args);
    Code := RunTool(FFFmpeg, Args, T('Verpacke 5.1 in eine Stem-Datei', 'Packing 5.1 into a stem file'),
                    OutText);
    if Code < 0 then
    begin
      DeleteFile(TmpFile);
      OutFile := '';
      Exit;
    end;
    if (Code <> 0) or not FileExists(TmpFile) then
    begin
      DeleteFile(TmpFile);
      MessageDlg(APP_TITLE, T('ffmpeg konnte die Stem-Datei nicht erstellen:',
        'ffmpeg could not create the stem file:') + LineEnding + LineEnding +
        Copy(Trim(OutText), 1, 1500) + LineEnding + LineEnding +
        T('Details im Log (Knopf LOG).', 'Details in the log (LOG button).'), mtError, [mbOK], 0);
      OutFile := '';
      Exit;
    end;

    { Stem-Block (Namen + Farben für Traktor) wie in StemMaker }
    for s := 0 to 3 do
    begin
      Stems[s].Name := PART_STEM_NAMES[FParts[s]];
      Stems[s].Color := PART_COLORS[FParts[s]];
    end;
    if not InjectStemMetadata(TmpFile, BuildStemJSON(Stems), nil, Err) then
    begin
      Log('Stem-Block fehlgeschlagen / stem block failed: ' + Err);
      DeleteFile(TmpFile);
      MessageDlg(APP_TITLE, T('Stem-Block konnte nicht geschrieben werden:',
        'Could not write the stem block:') + LineEnding + Err, mtError, [mbOK], 0);
      OutFile := '';
      Exit;
    end;
    if FileExists(OutFile) then DeleteFile(OutFile);
    if not RenameFile(TmpFile, OutFile) then
    begin
      Log('Umbenennen fehlgeschlagen / rename failed: ' + TmpFile + ' -> ' + OutFile);
      MessageDlg(APP_TITLE, T('Konnte die Datei nicht umbenennen:', 'Could not rename the file:') +
        LineEnding + TmpFile, mtError, [mbOK], 0);
      OutFile := '';
      Exit;
    end;
    Log('Fertig / done: ' + OutFile);
    LblStatus.Caption := T('Fertig: ', 'Done: ') + OutFile;

    LoadNow := QuestionDlg(APP_TITLE,
      T('Fertig:', 'Done:') + LineEnding + OutFile + LineEnding + LineEnding +
      T('Die Datei kann direkt in Traktor geladen werden.' + LineEnding +
        'Jetzt hier auf Deck A anhören?',
        'The file can be loaded straight into Traktor.' + LineEnding +
        'Listen to it here on deck A now?'),
      mtInformation, [mrYes, T('Auf Deck A laden', 'Load onto deck A'), mrOK, 'OK'], 0) = mrYes;
  finally
    Args.Free;
    SetBusy(False);
    if FCloseAfter then Application.QueueAsyncCall(@DeferredClose, 0);
  end;
  if LoadNow and (OutFile <> '') and not FCancel then
    LoadIntoDeck(0, OutFile);
end;

{ 5.1 -> A_/B_/C_/D_.wav -> (StemCLI) -> A_/B_/C_/D_.stem.mp4 -> 4 Decks }
procedure TMainForm.Split51(const FileName: string);
var
  Args: TStringList;
  OutText, AudioLine, Layout, OutDir, Desc: string;
  Wavs: array[0..3] of string;
  Track, Code, MaxSec, d: Integer;
  Gain: Double;
  R: TModalResult;
  StemFiles: Boolean;
begin
  if FBusy or not EnsureFFmpeg then Exit;
  StemFiles := False;
  SetBusy(True);
  Args := TStringList.Create;
  try
    Log('--- 5.1 -> 4 DECKS ---');
    if not ProbeSource(FileName, Track, Layout, AudioLine) then Exit;

    Desc := T('Es entstehen 4 WAV-Dateien im selben Ordner:',
              'This creates 4 WAV files in the same folder:') + LineEnding;
    for d := 0 to 3 do
      Desc := Desc + Format('  %s_ = %s', [DECK_LETTERS[d], PART_NAMES[FParts[d]]]) + LineEnding;
    MaxSec := AskLength(AudioLine, TrimRight(Desc));
    if MaxSec < 0 then Exit;

    Gain := MeasureLfeGain(FileName, Layout, Track, MaxSec);
    if FCancel then Exit;

    OutDir := ExtractFilePath(FileName);
    BuildSplitArgs(FileName, OutDir, Layout, Track, MaxSec, FParts, Gain, Args);
    Code := RunTool(FFFmpeg, Args, T('Teile 5.1 in A_/B_/C_/D_', 'Splitting 5.1 into A_/B_/C_/D_'),
                    OutText);
    if Code < 0 then Exit;
    for d := 0 to 3 do Wavs[d] := DeckWavName(FileName, OutDir, d);
    if (Code <> 0) or not FileExists(Wavs[0]) then
    begin
      MessageDlg(APP_TITLE, T('ffmpeg konnte die Datei nicht aufteilen:',
        'ffmpeg could not split the file:') + LineEnding + Copy(Trim(OutText), 1, 1500) +
        LineEnding + LineEnding + T('Details im Log (Knopf LOG).', 'Details in the log (LOG button).'),
        mtError, [mbOK], 0);
      Exit;
    end;
    LblStatus.Caption := T('Aufgeteilt: ', 'Split: ') + ExtractFileName(Wavs[0]) + ' ... ' +
                         ExtractFileName(Wavs[3]);

    { Gleich in Stems umwandeln? }
    R := QuestionDlg(APP_TITLE,
      T('Fertig aufgeteilt:', 'Split done:') + LineEnding +
      '  ' + ExtractFileName(Wavs[0]) + LineEnding +
      '  ' + ExtractFileName(Wavs[1]) + LineEnding +
      '  ' + ExtractFileName(Wavs[2]) + LineEnding +
      '  ' + ExtractFileName(Wavs[3]) + LineEnding + LineEnding +
      T('Jetzt jede Datei mit StemCLI (KI) in 4 Stems trennen?' + LineEnding +
        '(ohne Club-Pegel, damit die Decks im richtigen Verhältnis bleiben;' + LineEnding +
        'dauert etwa viermal so lange wie ein Song dieser Länge)' + LineEnding + LineEnding +
        'Alternativ: die 4 WAV-Dateien in StemMaker umwandeln (Club-Pegel AUS).',
        'Separate each file into 4 stems with StemCLI (AI) now?' + LineEnding +
        '(without club level, so the decks keep their balance;' + LineEnding +
        'takes about four times as long as one song of this length)' + LineEnding + LineEnding +
        'Alternative: convert the 4 WAV files in StemMaker (club level OFF).'),
      mtConfirmation, [mrYes, T('Jetzt trennen', 'Separate now'), mrNo, T('Später', 'Later')], 0);
    if R <> mrYes then Exit;
    StemFiles := ConvertWithStemCLI(Wavs);
  finally
    Args.Free;
    SetBusy(False);
    if FCloseAfter then Application.QueueAsyncCall(@DeferredClose, 0);
  end;

  { Ergebnis gleich auf die vier Decks laden }
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
      T('StemCLI.exe liegt im StemMaker-Ordner (neben StemMaker.exe).' + LineEnding +
        'StemMaker gibt es kostenlos auf github.com/Elospeed/StemMaker',
        'StemCLI.exe is in the StemMaker folder (next to StemMaker.exe).' + LineEnding +
        'StemMaker is free at github.com/Elospeed/StemMaker'), 'stemcli');
  if Cli = '' then Exit;

  Args := TStringList.Create;
  try
    for d := 0 to High(Wavs) do Args.Add(Wavs[d]);
    Args.Add('--no-normalize');
    Args.Add('--overwrite');
    Code := RunTool(Cli, Args, T('StemCLI trennt 4 Dateien in Stems',
                                 'StemCLI is separating 4 files into stems'), OutText);
  finally
    Args.Free;
  end;
  if Code < 0 then Exit;
  if Code = 3 then
  begin
    MessageDlg(APP_TITLE, T('StemCLI ist auf diesem PC noch nicht freigegeben.' + LineEnding +
      'Bitte StemMaker.exe einmal starten und den Hinweis bestätigen,' + LineEnding +
      'danach "5.1 -> 4 DECKS" nochmals ausführen.',
      'StemCLI is not enabled on this PC yet.' + LineEnding +
      'Please start StemMaker.exe once and confirm the notice,' + LineEnding +
      'then run "5.1 -> 4 DECKS" again.'), mtWarning, [mbOK], 0);
    Exit;
  end;
  for d := 0 to High(Wavs) do
    if not FileExists(ChangeFileExt(Wavs[d], '.stem.mp4')) then
    begin
      MessageDlg(APP_TITLE, Format(T('StemCLI ist fehlgeschlagen (Code %d).',
        'StemCLI failed (code %d).'), [Code]) +
        LineEnding + LineEnding + Copy(Trim(OutText), Max(1, Length(Trim(OutText)) - 1500), 1500),
        mtError, [mbOK], 0);
      Exit;
    end;
  Result := True;
end;

{ ============================================================================
  Ereignisse
  ============================================================================ }

procedure TMainForm.BtnPackClick(Sender: TObject);
begin
  if FBusy then Exit;
  SrcDlg.Title := T('5.1-Datei in eine Stem-Datei verpacken', '5.1 file to pack into one stem file');
  if SrcDlg.Execute then Pack51(SrcDlg.FileName);
end;

procedure TMainForm.BtnSplitClick(Sender: TObject);
begin
  if FBusy then Exit;
  SrcDlg.Title := T('5.1-Datei auf vier Decks aufteilen', '5.1 file to split onto four decks');
  if SrcDlg.Execute then Split51(SrcDlg.FileName);
end;

procedure TMainForm.BtnLoadAllClick(Sender: TObject);
begin
  if FBusy then Exit;
  if OpenDlg.Execute then LoadSet(OpenDlg.FileName);
end;

procedure TMainForm.BtnSettingsClick(Sender: TObject);
begin
  if FBusy then Exit;
  ShowSettings;
end;

procedure TMainForm.BtnLogClick(Sender: TObject);
begin
  ShowLogWindow;
end;

procedure TMainForm.BtnDeckLoadClick(Sender: TObject);
var
  d: Integer;
  OldTitle: string;
begin
  if FBusy then Exit;
  d := TDJButton(Sender).Tag;
  OldTitle := OpenDlg.Title;
  OpenDlg.Title := Format(T('Stem-Datei auf Deck %s laden', 'Load a stem file onto deck %s'),
                          [DECK_LETTERS[d]]);
  try
    if OpenDlg.Execute then LoadIntoDeck(d, OpenDlg.FileName);
  finally
    OpenDlg.Title := OldTitle;
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
var Idx: Integer;
begin
  Idx := TDJSlider(Sender).Tag;
  if Idx >= 1000 then
    Decks[Idx - 1000].LblVol.Caption := IntToStr(Decks[Idx - 1000].TrkVol.Position) + '%';
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
  Idx, d, s: Integer;
  C: TColor;
begin
  PB := TPaintBox(Sender);
  Idx := PB.Tag;
  d := Idx div STEMS_PER_DECK;
  s := Idx mod STEMS_PER_DECK;
  PB.Canvas.Brush.Color := DJ_PANEL;
  PB.Canvas.FillRect(0, 0, PB.Width, PB.Height);
  if (Engine <> nil) and (Engine.Gain[Idx] > 0) then C := Decks[d].Stems[s].Color
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
    { P wie im Wunsch des Nutzers: alle vier Decks gleichzeitig starten/pausieren }
    VK_SPACE, VK_P: begin TogglePlay; Key := 0; end;
    VK_1..VK_4:
      begin
        d := Key - VK_1;
        if ssCtrl in Shift then Exit;
        Decks[d].BtnMute.Down := not Decks[d].BtnMute.Down;
        UpdateGains;
        Key := 0;
      end;
    VK_O:
      if ssCtrl in Shift then begin BtnLoadAllClick(nil); Key := 0; end;
    VK_LEFT:  begin SeekRelative(-5); Key := 0; end;
    VK_RIGHT: begin SeekRelative(5); Key := 0; end;
    VK_HOME:  begin if Engine <> nil then Engine.SeekTo := 0; Key := 0; end;
  end;
end;

{ Stem-Datei -> auf die Decks laden, alles andere -> fragen: 1 Stem oder 4 Decks }
procedure TMainForm.OpenAny(const FileName: string);
var
  Base: string;
  R: TModalResult;
begin
  if FBusy or not FileExists(FileName) then Exit;
  if (Pos('.stem.mp4', LowerCase(FileName)) > 0) or
     ((DeckFromFileName(FileName, Base) >= 0) and
      SameText(ExtractFileExt(FileName), '.mp4')) then
    LoadSet(FileName)
  else
  begin
    R := QuestionDlg(APP_TITLE, ExtractFileName(FileName) + LineEnding + LineEnding +
      T('Was soll mit dieser 5.1-Datei passieren?', 'What should be done with this 5.1 file?'),
      mtConfirmation,
      [mrYes, '5.1 -> 1 STEM', mrAll, '5.1 -> 4 DECKS', mrCancel, T('Abbrechen', 'Cancel')], 0);
    if R = mrYes then Pack51(FileName)
    else if R = mrAll then Split51(FileName);
  end;
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
    LblStatus.Caption := T('Breche ab ...', 'Cancelling ...');
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
  Log('Beendet / closed');
end;

end.
