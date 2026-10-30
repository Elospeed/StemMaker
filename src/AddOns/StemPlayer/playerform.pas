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
    Shift+1..4 Solo (nur dieser)     0           Mute/Solo zurücksetzen
    Strg+Shift+1..4  Solo dazunehmen (mehrere Solos), ebenso Strg+Klick auf S
    S / O / R  Stems / Original / Rest           Pfeil links/rechts  -/+ 5 s
    Pos1       an den Anfang         Strg+O      Datei öffnen
    W          Wellenformen aus/ein (nur in der klassischen Ansicht)
               Klick in Wellenform  dorthin springen
    A / B      Loop-Punkt A / B setzen (B schaltet den Loop gleich ein)
    L          Loop an/aus           Rücktaste / Shift+L  Loop löschen
    Rechte Maustaste in einer Wellenform ziehen: Loop-Bereich aufziehen
    Pfeil li/re        bei aktivem Loop: ganzen Loop um einen Schritt
                       verschieben (sonst -/+ 5 s springen). Der Schritt
                       wächst mit dem Zoom der Lupe (8 s: 0,1 s, ganz nah 2 ms)
    Shift+Pfeil li/re  Loop auseinanderziehen: Shift+links schiebt A nach
                       links, Shift+rechts schiebt B nach rechts
    Strg+Pfeil li/re   Loop zusammenziehen: Strg+rechts schiebt A nach
                       rechts, Strg+links schiebt B nach links
    Lupe (Streifen unter dem Original): Mausrad zoomt, Marken A/B ziehen,
    rechte Maustaste ziehen = Loop am Raster, mit Shift frei

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
    1.4  (06.10.2026)  Nur noch echte Stem-Dateien werden geladen. Vorher ging
                       per Drag & Drop (oder "Alle Dateien" im Öffnen-Dialog)
                       jede Datei durch, z.B. eine MP3: Der Player nahm dann
                       einfach 5 Spuren an, die laufende Wiedergabe brach ab und
                       ffmpeg meldete einen unverständlichen Fehler. Jetzt kommt
                       eine klare Meldung (DE/EN), der geladene Track bleibt.
    1.5  (14.10.2026)  Wellenform: unter jedem Stem seine Wellenform
                       in der Stemfarbe, oben die Wellenform des Originals statt
                       der Balkenleiste, roter Abspielkopf läuft überall mit.
                       Klick oder Ziehen in eine Wellenform springt dorthin.
                       Oben rechts Umschalter KOMPAKT / WELLENFORM (oder Taste W),
                       die Wahl wird gespeichert und beim nächsten Start
                       übernommen. Berechnung im Hintergrund (wellenform.pas).
                       Abspielkopf flüssig: eigener schneller Timer (~60 Bilder/s)
                       und eine geglättete Uhr statt der stufigen Geräteposition
                       (siehe HeadTimerTick).
                       Solo ist jetzt exklusiv: ein neues Solo löst das vorherige
                       ab (wie am DJ-Mixer). Mehrere Solos gleichzeitig nur mit
                       Strg+Klick bzw. Strg+Shift+1..4.
    1.6  (21.10.2026)  Loop A-B: einen Abschnitt endlos wiederholen, z.B. um
                       mit Mute/Solo eine Stelle genau zu prüfen. Punkte A und
                       B per Knopf oder Taste (A, B) an der aktuellen Stelle,
                       oder mit der rechten Maustaste in einer Wellenform
                       aufziehen. L schaltet den Loop an/aus, Rücktaste
                       löscht ihn. Der Rücksprung ist nahtlos (stemengine 1.2),
                       der Bereich ist in allen Wellenformen grün hinterlegt.
                       Lupe unter der Original-Wellenform: zeigt ~8 s um den
                       Abspielkopf mit Zeitraster. Darin Loop genau setzen
                       (rastet am Raster ein, Shift = frei), Marken A/B mit
                       der Maus verschieben, Mausrad zoomt (0,25 bis 60 s).
                       Tastatur: Pfeile verschieben den ganzen aktiven Loop,
                       Shift+Pfeil zieht ihn nach aussen auseinander,
                       Strg+Pfeil nach innen zusammen, je weiter hinein-
                       gezoomt, desto feiner (bis 2 ms, Zoom bis 0,25 s).
                       Lupe flüssiger: Welle wird als Bild vorgerechnet und
                       nur noch verschoben (wellenform 1.4/1.5), Abspielkopf
                       im Takt des Monitors statt mit Timer (bildtakt.pas).
                       Welle in der Lupe mit der linken Maustaste ziehen:
                       der rote Strich bleibt stehen, beim Loslassen geht es
                       an der neuen Stelle weiter (auch bei Pause).
    1.7  (21.10.2026)  Mehrsprachig (Deutsch, Englisch, Spanisch): der Player
                       übernimmt die Sprache, die in StemMaker eingestellt ist
                       (StemMaker.ini [Main] Language). Die Texte stehen in
                       denselben Sprachdateien lang\*.po wie die von StemMaker
                       (siehe LoadLanguage und src\ulang.pas).
                       Scrubbing: beim Ziehen der Welle in der Lupe hört man
                       den Ton wie bei einer Schallplatte unter der Hand,
                       schnell gezogen hoch, langsam tief, rückwärts
                       rückwärts (stemengine 1.3).
    1.8  (27.10.2026)  Neues Design CD-Player, gleiche Funktionen, anderer
                       Look. Die Ansicht wählt man jetzt in einem Ausklapp-Menü
                       (KOMPAKT / WELLENFORM / CD-PLAYER) statt mit Knöpfen,
                       damit die Fläche übersichtlich bleibt.
                       CD-Player mit Display, Jogwheel (Ring = Restzeit, Drehen
                       = Scrubbing), runden CUE/Play-Knöpfen, Stem-Pads und
                       eigener Loop-Spur (Lupe + Loop-Knöpfe). Ein Design
                       Plattenspieler ist fertig, kommt aber erst später
                       (Branch elospeed/stemplayer-plattenspieler). Die vorhandenen Bedienelemente werden dafür nur
                       umgesetzt (PlaceCtl), neu sind die Teile in designviews.pas.
                       Wahl in StemPlayer.ini [Ansicht] Design.
  ============================================================================ }
unit playerform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Buttons, LCLType, LCLIntf, Process, FileUtil,
  LazFileUtils, IniFiles, MMSystem, Menus, uLang, mp4stem, stemengine, djcontrols, wellenform,
  bildtakt, designviews;

const
  APP_TITLE = 'Elospeed StemPlayer';
  APP_VER   = '1.8.1';
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
    Wave     : TWaveView;  // Wellenform unter der Zeile
    Color    : TColor;
    Level    : Single;     // geglätteter Anzeigepegel 0..1
  end;

  { Ansicht: die beiden klassischen (mit/ohne Wellenformen) und das
    Design CD-Player (gleiche Funktionen, anderer Look) }
  TViewMode = (vmCompact, vmWave, vmCD);

  { Ursprünglicher Platz eines Bedienelements, das für ein Design an eine
    andere Stelle gesetzt wurde (siehe PlaceCtl / RestorePlacements) }
  TPlacement = record
    Ctl     : TControl;
    Parent  : TWinControl;
    Bounds  : TRect;
    Anchors : TAnchors;
  end;

  { TMainForm }

  TMainForm = class(TForm)
  private
    FScroll     : TScrollBox;  // klassische Ansicht: Flächen mit Bildlauf, falls der Bildschirm zu klein ist
    { --- Oberer Bereich --- }
    PnlTop      : TDJPanel;
    BtnOpen     : TDJButton;
    LblFile     : TLabel;
    LblFileInfo : TLabel;      // kleine Zeile unter dem Dateinamen
    BtnView       : TDJButton;  // Ansicht wählen: zeigt die aktuelle, Klick klappt das Menü auf
    MnuView       : TPopupMenu; // Menü mit den Ansichten (Kompakt, Wellenform, CD-Player)
    { --- "Deck": Transport + Modus --- }
    PnlDeck     : TDJPanel;
    BtnPlay     : TDJButton;
    BtnStop     : TDJButton;
    TrkPos      : TDJSlider;   // Positionsleiste, bis die Wellenform fertig ist
    WaveMaster  : TWaveView;   // Wellenform des Originals (ersetzt dann TrkPos)
    Zoom        : TZoomView;   // Lupe: wenige Sekunden um den Abspielkopf
    LblTime     : TLabel;      // aktuelle Position (gross)
    LblTotal    : TLabel;      // Gesamtlänge (klein, gedimmt)
    BtnModeStems: TDJButton;
    BtnModeOrig : TDJButton;
    BtnModeRest : TDJButton;
    BtnReset    : TDJButton;
    BtnLoopA    : TDJButton;   // Loop: Punkt A an der aktuellen Stelle
    BtnLoopB    : TDJButton;   // Loop: Punkt B (schaltet den Loop ein)
    BtnLoopOn   : TDJButton;   // Loop an/aus
    BtnLoopClear: TDJButton;   // Loop löschen
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
    PbKofi      : TPaintBox;   // Ko-fi-Knopf unten rechts (wie in allen Elospeed-Tools)
    FKofiHover  : Boolean;
    LblHelp     : TLabel;
    LblStatus   : TLabel;
    LblKofi     : TLabel;
    { --- Design CD-Player (designviews.pas) --- }
    PnlCD       : TDJPanel;    // ganze Fläche des Designs
    CDDisplay   : TDJPanel;    // Display oben: Titel, Zeiten, Wellenformen
    CDLoop      : TDJPanel;    // Loop-Spur: Lupe + Loop-Knöpfe
    CDPads      : TDJPanel;    // Stem-Pads + Fader
    CDSource    : TDJPanel;    // Quelle: Öffnen + Ansicht
    CDViewCap   : TLabel;      // Überschrift "ANSICHT" über dem Auswahlknopf
    CDMode      : TDJPanel;    // Hören: Stems / Original / Rest / Reset
    CDMaster    : TDJPanel;    // Master-Fader + Ausgangspegel
    Jog         : TJogWheel;
    Pads        : array[1..STEM_COUNT, 0..1] of TStemPad;  // [Stem, 0 = Mute / 1 = Solo]
    CDBars      : array[1..STEM_COUNT] of TShape;          // Farbstreifen vor den Wellen
    LblCDTime, LblCDRemain, LblCDLength, LblCDMode: TLabel;  // Zeiten im Display
    { --- Ansicht --- }
    FView       : TViewMode;   // aktuelle Ansicht
    FPlaced     : array of TPlacement;  // für das Design versetzte Elemente
    FClassicW   : Integer;     // Fenstergrösse der klassischen Ansicht in 96-dpi-Pixeln,
    FClassicH   : Integer;     // wird beim Zurückschalten wiederhergestellt
    FShown      : Boolean;     // Fenster wurde schon einmal angezeigt (FormShow)
    FFitting    : Boolean;     // Fenstergrösse wird gerade im Code angepasst
    FWaveH96    : Integer;     // zuletzt gezogene Wellenhöhe (96 dpi), 0 = Standard
    { --- Sonstiges --- }
    Timer       : TTimer;
    Takt        : TBildtakt;   // Abspielkopf im Takt des Monitors (bildtakt.pas)
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
    FPeakThread : TPeakThread; // berechnet die Wellenformen im Hintergrund
    FShowWaves  : Boolean;     // Wellenformen sichtbar (Taste W)
    FHeadPos    : Double;      // geglättete Anzeigeposition in Frames
    FHeadTime   : Double;      // Zeitpunkt (NowSeconds) dieser Position
    FHeadRunning: Boolean;     // lief die Uhr schon beim letzten Tick?
    FLoopA      : Int64;       // Loop-Punkt A in Frames (-1 = nicht gesetzt)
    FLoopB      : Int64;       // Loop-Punkt B in Frames (-1 = nicht gesetzt)
    FLoopOn     : Boolean;     // Loop aktiv

    procedure LoadLanguage;
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
    procedure ApplySolo(Idx: Integer; Additive: Boolean);
    procedure UpdateRowLook;
    procedure SetWavesVisible(AShow: Boolean);
    function  ContentHeight: Integer;
    function  FrameW: Integer;
    function  FrameH: Integer;
    function  WaveSize: Integer;
    function  ClassicMinHeight(AWaves: Boolean): Integer;
    procedure SetWaveSize(H: Integer);
    procedure FitWaves;
    procedure UpdateClassicSize;
    procedure KeepOnScreen;
    function  DesignFits: Boolean;
    procedure FormResize(Sender: TObject);
    procedure SaveViewSetting;
    procedure ViewClick(Sender: TObject);
    procedure ViewMenuClick(Sender: TObject);
    procedure ViewMenuMeasure(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
    procedure ViewMenuDraw(Sender: TObject; ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState);
    function  ViewName(V: TViewMode): string;
    { Design CD-Player }
    procedure BuildDesignUI;
    function  MakeBox(AParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer): TDJPanel;
    function  MakeCaption(AParent: TWinControl; const ACaption: string;
                          ALeft, ATop: Integer): TLabel;
    procedure PlaceCtl(Ctl: TControl; NewParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer);
    procedure RestorePlacements;
    procedure PlaceLoopButtons(AParent: TWinControl; X, Y: Integer);
    procedure LayoutCD;
    procedure SetView(V: TViewMode);
    procedure EnterDesign(V: TViewMode);
    procedure LeaveDesign;
    procedure FitDesignWindow;
    procedure UpdateViewButtons;
    procedure UpdateDesignLook;
    procedure UpdateDesignNames;
    procedure PadClick(Sender: TObject);
    procedure StopPeakThread;
    procedure ApplyPeaks;
    procedure TogglePlay;
    procedure StopPlay;
    procedure SeekRelative(Seconds: Integer);
    procedure SetMode(M: TPlayMode);
    function  CurrentFrame: Int64;
    procedure SetLoopA;
    procedure SetLoopB;
    procedure ToggleLoop;
    procedure ClearLoop;
    procedure ApplyLoop(UpdateEngine: Boolean = True);
    procedure SetLoopRange(A, B: Int64);
    procedure NudgeMarker(Marker: Integer; Frames: Int64);
    procedure MoveLoop(Frames: Int64);
    function  NudgeStep: Int64;
    procedure ZoomSeek(Sender: TObject; Frame: Int64);
    procedure ZoomScrub(Sender: TObject; IsDown: Boolean; Frame: Int64);
    procedure ZoomLoopSelect(Sender: TObject; AFrom, ATo: Int64);
    procedure ZoomMarkerMove(Sender: TObject; Marker: Integer; Frame: Int64; Final: Boolean);
    procedure LoopClick(Sender: TObject);
    procedure WaveLoopSelect(Sender: TObject; AFrom, ATo: Single);
    function  FormatTime(Frames: Int64): string;
    function  FormatTimeFine(Frames: Int64): string;
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
    procedure WaveSeek(Sender: TObject; Fraction: Single);
    procedure MeterPaint(Sender: TObject);
    procedure OutMeterPaint(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure HeadTimerTick(Data: PtrInt);
    procedure KofiClick(Sender: TObject);
    procedure KofiPaint(Sender: TObject);
    procedure KofiEnter(Sender: TObject);
    procedure KofiLeave(Sender: TObject);
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

uses
  {$IFDEF WINDOWS}UxTheme,{$ENDIF}
  uStatusDraw;   // Ko-fi-Knopf, gleich wie in StemMaker

const
  { Farben: siehe djcontrols.pas (Palette "Traktor Dark") }
  ROW_HEIGHT  = 54;   // Höhe einer Stem-Zeile (ohne Wellenform)
  WAVE_HEIGHT = 36;   // Höhe der Wellenform unter einer Stem-Zeile
  WAVE_EXTRA  = WAVE_HEIGHT + 8;   // so viel wird jede Zeile mit Wellenform höher
  ZOOM_TOP    = 52;   // Lupe: Abstand oben im Deck (unter der Original-Wellenform)
  ZOOM_HEIGHT = 56;   // Höhe der Lupe
  ROW2        = ZOOM_TOP + ZOOM_HEIGHT - 52 + 8;  // so weit rutscht die Knopfzeile nach unten
  BASE_HEIGHT = 590 + ROW2;  // Fensterhöhe ohne Wellenformen (nur Startwert)
  WAVE_MIN    = 16;   // so niedrig dürfen die Stem-Wellenformen beim Verkleinern werden
  WAVE_PAD    = 10;   // Abstand unter der Wellenform bis zum Rand der Stem-Zeile
  BOTTOM_GAP  = 8;    // Abstand unter MASTER bis zur Fusszeile
  MARGIN      = 10;   // Abstand der Flächen zum Fensterrand
  MONO_FONT   = 'Consolas';   // Zahlen mit fester Breite (springen nicht)
  MIN_LOOP    = SAMPLE_RATE div 10;   // kürzester Loop: 0,1 Sekunden
  DESIGN_W    = 1000;  // Innenbreite des Fensters im Design CD-Player
  DESIGN_H    = 634;   // Innenhöhe ohne die Fusszeile

{ ============================================================================
  Aufbau des Fensters
  ============================================================================ }

constructor TMainForm.Create(TheOwner: TComponent);
var
  Ini: TIniFile;
  ShowWaves: Boolean;
  Design: string;
begin
  { Keine .lfm-Datei -> CreateNew statt Create }
  inherited CreateNew(TheOwner);
  LoadLanguage;   // VOR allen Texten, sonst bleibt die Oberfläche deutsch
  Caption := APP_TITLE + ' ' + APP_VER + _('  -  von Elospeed');
  Width := 820;
  Height := BASE_HEIGHT;
  Constraints.MinWidth := 720;
  Constraints.MinHeight := BASE_HEIGHT;
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
  OnResize := @FormResize;

  { Standardnamen/-farben vorbelegen (leerer Dateiname -> nur Defaults) }
  ReadStemInfo('', FInfo);
  FLoopA := -1;
  FLoopB := -1;
  FLoopOn := False;
  BuildUI;
  BuildDesignUI;
  UpdateGains;
  ApplyLoop;

  { Ansicht wie beim letzten Mal (StemPlayer.ini [Ansicht] Wellenform=1/0).
    Erster Start: mit Wellenformen. Passt das grössere Fenster nicht auf den
    Bildschirm, startet er trotzdem kompakt (gespeichert wird das nicht). }
  { Design (StemPlayer.ini [Ansicht] Design=CD/Kompakt/Wellenform)
    kommt dazu. Wellenform=1/0 bleibt die Wahl für die klassische Ansicht,
    zu der man aus einem Design zurückkehrt. Passt ein Design nicht auf
    den Bildschirm, startet die klassische Ansicht. }
  FView := vmCompact;
  FShowWaves := False;
  ShowWaves := True;
  Design := '';
  try
    Ini := TIniFile.Create(IniFileName);
    try
      ShowWaves := Ini.ReadBool('Ansicht', 'Wellenform', True);
      Design := Ini.ReadString('Ansicht', 'Design', '');
    finally
      Ini.Free;
    end;
  except
    { INI nicht lesbar -> Standard }
  end;
  { Ob die Ansicht auf den Bildschirm passt, prüft erst FormShow: Lazarus
    vergrössert das Fenster nach dem Konstruktor noch auf die Windows-
    Skalierung (125/150/200 %), erst danach stimmen die echten Grössen. }
  if ShowWaves then SetView(vmWave)
  else SetView(vmCompact);
  if SameText(Design, 'CD') then SetView(vmCD);

  OpenDlg := TOpenDialog.Create(Self);
  OpenDlg.Title := _('Stem-Datei öffnen');
  OpenDlg.Filter := _('Traktor Stems (*.stem.mp4;*.mp4)|*.stem.mp4;*.mp4|Alle Dateien (*.*)|*.*');

  Timer := TTimer.Create(Self);
  Timer.Interval := 30;
  Timer.OnTimer := @TimerTick;
  Timer.Enabled := True;

  { Abspielkopf separat, einmal pro Bildschirmbild (bildtakt.pas). Ein
    Timer läuft im eigenen Takt neben dem Monitor her, die Lupe ruckelt
    dann. Die LED-Meter bleiben beim gewohnten 30-ms-Timer. }
  Takt := TBildtakt.Create(@HeadTimerTick);
  { Windows-Takt auf 1 ms (für Sleep im Ersatzbetrieb ohne Bildwechsel).
    Gilt nur für dieses Programm, wird in FormClose zurückgesetzt. }
  timeBeginPeriod(1);

  { Reste früherer Abstürze aus dem Temp-Ordner entfernen }
  CleanupOrphanTempDirs;
  CreateInstanceDir;

  FFFmpeg := FindFFmpeg;
  if FFFmpeg = '' then
    LblStatus.Caption := _('ffmpeg.exe nicht gefunden - wird beim ersten Öffnen abgefragt.')
  else
    LblStatus.Caption := 'ffmpeg: ' + FFFmpeg;
end;

{ ---------------------------------------------------------------------------
  Sprache: dieselbe wie in StemMaker. Der StemPlayer hat keine eigene
  Auswahl - er liest StemMaker.ini ([Main] Language=en) im StemMaker-Ordner
  (eine Ebene über AddOns\, siehe AppBaseDir), ersatzweise die Kopie in
  %APPDATA%\StemMaker\ (schreibgeschützter Programmordner). Steht dort
  noch nichts, nimmt er wie StemMaker die Windows-Sprache.
  Fehlt die Sprachdatei (z.B. StemPlayer allein ohne StemMaker-Ordner),
  bleibt alles deutsch - LangLoad gibt dann einfach False zurück.
  --------------------------------------------------------------------------- }
procedure TMainForm.LoadLanguage;
var
  Ini: TIniFile;
  Code, IniName: string;
  i: Integer;
begin
  Code := '';
  for i := 1 to 2 do
  begin
    if i = 1 then
      IniName := AppBaseDir + 'StemMaker.ini'
    else
      IniName := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
        'StemMaker' + PathDelim + 'StemMaker.ini';
    if not FileExists(IniName) then Continue;
    try
      Ini := TIniFile.Create(IniName);
      try
        Code := Trim(Ini.ReadString('Main', 'Language', ''));
      finally
        Ini.Free;
      end;
    except
      Code := '';   // INI nicht lesbar -> nächste versuchen
    end;
    if Code <> '' then Break;
  end;
  if Code = '' then
    Code := LangSystemDefault;
  LangLoad(Code);
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
  Result.Parent := FScroll;
  Result.Align := alTop;
  { Aufsteigender Top-Wert -> neue Fläche landet unter allen bisherigen }
  Result.Top := FScroll.ControlCount * 100;
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
  V: TViewMode;     // Schleife über die Ansichten fürs Menü
  Item: TMenuItem;  // ein Menüeintrag
begin
  W := ClientWidth - 2 * MARGIN;   // Breite der Flächen

  { Alle Flächen der klassischen Ansicht liegen in einem Bildlauf-Bereich:
    Ist der Bildschirm zu klein (z. B. 175 % auf einem Full-HD-Laptop),
    erscheint rechts eine Bildlaufleiste statt dass MASTER unten fehlt }
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.Color := DJ_BG;
  FScroll.ParentColor := False;
  FScroll.HorzScrollBar.Visible := False;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.AutoScroll := True;

  { ---------- Oben: Datei ---------- }
  PnlTop := MakeDJPanel(56, 4);
  PnlTop.Color := DJ_BG;
  PnlTop.BorderColor := clNone;    // ohne Rahmen, liegt direkt auf dem Fenster

  BtnOpen := MakeButton(PnlTop, _('ÖFFNEN'), 0, 12, 96, 32);
  BtnOpen.Hint := _('Stem-Datei öffnen (Strg+O) - oder einfach aufs Fenster ziehen');
  BtnOpen.ShowHint := True;
  BtnOpen.OnClick := @BtnOpenClick;

  LblFile := MakeLabel(PnlTop, _('Stem-Datei öffnen oder hierher ziehen (Drag & Drop)'), 110, 8, 12, True);
  LblFile.Anchors := [akLeft, akTop, akRight];
  LblFile.AutoSize := False;
  LblFile.ShowAccelChar := False;   // "&" im Dateinamen zeigen, nicht als Tastenkürzel
  LblFile.SetBounds(110, 8, W - 110 - 220, 24);

  { Ansicht wählen: ein Knopf mit der aktuellen Ansicht, darunter klappt
    ein Menü mit allen vier Ansichten auf (statt vier Knöpfen nebeneinander,
    damit auf der Fläche selbst nur das Arbeitswerkzeug bleibt) }
  BtnView := MakeButton(PnlTop, '', W - 200, 14, 200, 28);
  BtnView.Anchors := [akTop, akRight];
  BtnView.DropDown := True;
  BtnView.Hint := _('Ansicht wählen: Kompakt, Wellenform oder CD-Player (Taste W: Kompakt/Wellenform)');
  BtnView.ShowHint := True;
  BtnView.OnClick := @ViewClick;
  MnuView := TPopupMenu.Create(Self);
  MnuView.OwnerDraw := True;   // dunkel wie der Player, nicht im hellen Windows-Stil
  MnuView.OnMeasureItem := @ViewMenuMeasure;
  MnuView.OnDrawItem := @ViewMenuDraw;
  for V := Low(TViewMode) to High(TViewMode) do
  begin
    Item := TMenuItem.Create(MnuView);
    Item.Caption := ViewName(V);
    Item.Tag := Ord(V);          // Tag = Ansicht, nie über den (übersetzten) Text
    Item.OnClick := @ViewMenuClick;
    MnuView.Items.Add(Item);
  end;

  LblFileInfo := MakeLabel(PnlTop, '', 110, 32, 0, False);
  LblFileInfo.Font.Color := DJ_DIM;

  { ---------- Deck: Transport (Zeile 1) + Modus (Zeile 2) ---------- }
  PnlDeck := MakeDJPanel(96 + ROW2, 4);

  BtnPlay := MakeButton(PnlDeck, '', 12, 12, 46, 34);
  BtnPlay.Glyph := dgPlay;
  BtnPlay.LitColor := DJ_GREEN;
  BtnPlay.Enabled := False;
  BtnPlay.Hint := _('Play / Pause (Leertaste)');
  BtnPlay.ShowHint := True;
  BtnPlay.OnClick := @BtnPlayClick;

  BtnStop := MakeButton(PnlDeck, '', 64, 12, 46, 34);
  BtnStop.Glyph := dgStop;
  BtnStop.Enabled := False;
  BtnStop.Hint := _('Stop und zurück an den Anfang');
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

  { Gleicher Platz wie TrkPos. Wird erst sichtbar, wenn die Wellenform des
    Originals berechnet ist (bis dahin bleibt die alte Leiste). }
  WaveMaster := TWaveView.Create(Self);
  WaveMaster.Parent := PnlDeck;
  WaveMaster.SetBounds(120, 12, W - 120 - 172, 34);
  WaveMaster.Anchors := [akLeft, akTop, akRight];
  WaveMaster.WaveColor := $00D0D0D0;
  WaveMaster.Visible := False;
  WaveMaster.OnSeek := @WaveSeek;
  WaveMaster.OnLoopSelect := @WaveLoopSelect;
  WaveMaster.Hint := _('Original - klicken oder ziehen, um an diese Stelle zu springen.') + LineEnding +
                     _('Rechte Maustaste ziehen: Loop-Bereich aufziehen');
  WaveMaster.ShowHint := True;

  { Lupe: über die ganze Breite unter der Original-Wellenform }
  Zoom := TZoomView.Create(Self);
  Zoom.Parent := PnlDeck;
  Zoom.SetBounds(12, ZOOM_TOP, W - 24, ZOOM_HEIGHT);
  Zoom.Anchors := [akLeft, akTop, akRight];
  Zoom.OnSeek := @ZoomSeek;
  Zoom.OnScrub := @ZoomScrub;
  Zoom.OnLoopSelect := @ZoomLoopSelect;
  Zoom.OnMarkerMove := @ZoomMarkerMove;
  Zoom.Hint := _('Lupe: einige Sekunden rund um den roten Strich, zum genauen Setzen des Loops.') + LineEnding +
               _('Rechte Maustaste ziehen: Loop setzen (rastet am Raster ein, mit Shift frei).') + LineEnding +
               _('Marken A und B mit der Maus verschieben. Welle mit der linken Maustaste ziehen: Stelle anfahren, dabei hört man den Ton.') + LineEnding +
               _('Mausrad: zoomen. Klick: springen.');
  Zoom.ShowHint := True;

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

  L := MakeLabel(PnlDeck, _('HÖREN'), 12, 62 + ROW2, 8, False);
  L.Font.Color := DJ_DIM;

  { Modus-Umschaltung: drei aneinanderliegende Buttons, der aktive ist hell }
  BtnModeStems := MakeButton(PnlDeck, _('STEMS  S'), 62, 56 + ROW2, 96, 28);
  BtnModeOrig  := MakeButton(PnlDeck, _('ORIGINAL  O'), 157, 56 + ROW2, 116, 28);
  BtnModeRest  := MakeButton(PnlDeck, _('REST  R'), 272, 56 + ROW2, 90, 28);
  BtnModeStems.Down := True;
  BtnModeStems.Hint := _('Die 4 Stems gemischt - mit Mute / Solo / Lautstärke (Taste S)');
  BtnModeOrig.Hint  := _('Originalmix aus der Datei (Spur 0) zum A/B-Vergleich (Taste O)');
  BtnModeRest.Hint  := _('Rest = Original minus Summe aller Stems (Taste R):') + LineEnding +
                       _('hörbar, was bei der Trennung verloren ging oder anders') + LineEnding +
                       _('klingt (ideal: fast Stille).');
  BtnModeStems.ShowHint := True; BtnModeOrig.ShowHint := True; BtnModeRest.ShowHint := True;
  BtnModeStems.OnClick := @ModeClick;
  BtnModeOrig.OnClick := @ModeClick;
  BtnModeRest.OnClick := @ModeClick;

  { Loop A-B: rechts neben den Modus-Knöpfen. Passt auch bei der
    kleinsten Fensterbreite noch vor RESET. }
  L := MakeLabel(PnlDeck, _('LOOP'), 374, 62 + ROW2, 8, False);
  L.Font.Color := DJ_DIM;
  BtnLoopA     := MakeButton(PnlDeck, 'A', 406, 56 + ROW2, 32, 28);
  BtnLoopB     := MakeButton(PnlDeck, 'B', 437, 56 + ROW2, 32, 28);
  BtnLoopOn    := MakeButton(PnlDeck, _('AN  L'), 468, 56 + ROW2, 62, 28);
  BtnLoopClear := MakeButton(PnlDeck, '×', 529, 56 + ROW2, 28, 28);
  BtnLoopA.LitColor := DJ_GREEN;
  BtnLoopB.LitColor := DJ_GREEN;
  BtnLoopOn.LitColor := DJ_GREEN;
  BtnLoopA.Hint := _('Loop-Punkt A an der aktuellen Stelle setzen (Taste A)');
  BtnLoopB.Hint := _('Loop-Punkt B an der aktuellen Stelle setzen (Taste B).') + LineEnding +
                   _('Der Abschnitt A bis B wird dann endlos wiederholt.') + LineEnding +
                   _('Tipp: mit der rechten Maustaste in einer Wellenform ziehen');
  BtnLoopOn.Hint := _('Loop an/aus (Taste L). Einschalten springt zu A,') + LineEnding +
                    _('wenn die Wiedergabe gerade ausserhalb des Loops ist.');
  BtnLoopClear.Hint := _('Loop löschen (Rücktaste)');
  BtnLoopA.ShowHint := True; BtnLoopB.ShowHint := True;
  BtnLoopOn.ShowHint := True; BtnLoopClear.ShowHint := True;
  BtnLoopA.OnClick := @LoopClick;
  BtnLoopB.OnClick := @LoopClick;
  BtnLoopOn.OnClick := @LoopClick;
  BtnLoopClear.OnClick := @LoopClick;

  BtnReset := MakeButton(PnlDeck, _('RESET  0'), W - 112, 56 + ROW2, 100, 28);
  BtnReset.Anchors := [akTop, akRight];
  BtnReset.Hint := _('Alles zurücksetzen: Mute/Solo aus, Fader auf 100 %, Modus Stems (Taste 0)');
  BtnReset.ShowHint := True;
  BtnReset.OnClick := @BtnResetClick;

  { ---------- 4 Stem-Zeilen ---------- }
  for i := 1 to STEM_COUNT do
    BuildStemRow(i);

  { ---------- Master ---------- }
  PnlMaster := MakeDJPanel(60, 8);

  MakeLabel(PnlMaster, _('MASTER'), 14, 10, 11, True);
  L := MakeLabel(PnlMaster, _('AUSGANG L / R'), 14, 34, 8, False);
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

  BtnClip := MakeButton(PnlMaster, _('CLIP'), W - 60, 17, 48, 26);
  BtnClip.Anchors := [akTop, akRight];
  BtnClip.LitColor := DJ_RED;
  BtnClip.Indicator := True;   // nur Anzeige, kein Knopf
  BtnClip.Font.Size := 7;
  BtnClip.Hint := _('Leuchtet rot, wenn die Summe übersteuert (dann Master leiser stellen)');
  BtnClip.ShowHint := True;

  { ---------- Unten ---------- }
  PnlBottom := TDJPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 66;
  PnlBottom.Color := DJ_FOOTER;
  PnlBottom.Width := ClientWidth;

  LblHelp := MakeLabel(PnlBottom,
    _('Leertaste Play/Pause  ·  1-4 Mute  ·  Shift+1-4 Solo  ·  0 Reset  ·  ' +
    'S/O/R Modus  ·  Pfeile -/+5 s  ·  W Wellenform  ·  A/B/L Loop  ·  Shift/Strg+Pfeil Breite'), 12, 6, 0, False);
  LblHelp.Font.Color := $00999999;
  { feste Breite statt AutoSize: die Breite richtet sich nach dem Text in der
    jeweiligen Sprache, AutoSize schnitt unter Wine den letzten Buchstaben ab }
  LblHelp.AutoSize := False;
  LblHelp.Anchors := [akLeft, akTop, akRight];
  LblHelp.Width := PnlBottom.Width - 24;

  LblStatus := MakeLabel(PnlBottom, '', 12, 25, 0, False);
  LblStatus.Font.Color := DJ_DIM;
  LblStatus.Anchors := [akLeft, akTop, akRight];
  LblStatus.AutoSize := False;
  LblStatus.Width := PnlBottom.Width - 24;

  { Ko-fi-Knopf unten rechts: dunkle Pille mit dem StemPlayer-Symbol (uStatusDraw) }
  PbKofi := TPaintBox.Create(Self);
  PbKofi.Parent := PnlBottom;
  PbKofi.Canvas.Font.Style := [fsBold];
  PbKofi.Width := KofiButtonWidth(PbKofi.Canvas, _('Kaffee spendieren'), Screen.PixelsPerInch);
  PbKofi.Height := 24;
  PbKofi.Left := PnlBottom.Width - PbKofi.Width - 12;
  PbKofi.Top := 40;
  PbKofi.Anchors := [akTop, akRight];
  PbKofi.Cursor := crHandPoint;
  PbKofi.Hint := 'ko-fi.com/elospeed';
  PbKofi.ShowHint := True;
  PbKofi.OnPaint := @KofiPaint;
  PbKofi.OnClick := @KofiClick;
  PbKofi.OnMouseEnter := @KofiEnter;
  PbKofi.OnMouseLeave := @KofiLeave;
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
  R^.BtnMute.Hint := Format(_('Mute: Stem stumm schalten (Taste %d)'), [Idx]);
  R^.BtnMute.ShowHint := True;

  R^.BtnSolo := MakeButton(R^.Panel, 'S', 178, 13, 32, 28);
  R^.BtnSolo.Toggle := True;
  R^.BtnSolo.LitColor := DJ_YELLOW;
  R^.BtnSolo.Tag := 100 + Idx;
  R^.BtnSolo.OnClick := @MuteSoloClick;
  R^.BtnSolo.Hint := Format(_('Solo: nur diesen Stem hören (Shift+%d).') + LineEnding +
    _('Strg+Klick: weiteren Stem dazunehmen (mehrere Solos)'), [Idx]);
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

  { Wellenform unter der Zeile, gleiche Einrückung wie der Name.
    Unsichtbar, solange die Wellenformen ausgeblendet sind (SetWavesVisible). }
  R^.Wave := TWaveView.Create(Self);
  R^.Wave.Parent := R^.Panel;
  R^.Wave.SetBounds(20, ROW_HEIGHT - 2, W - 20 - 12, WAVE_HEIGHT);
  R^.Wave.Anchors := [akLeft, akTop, akRight];
  R^.Wave.WaveColor := R^.Color;
  R^.Wave.Visible := False;
  R^.Wave.OnSeek := @WaveSeek;
  R^.Wave.OnLoopSelect := @WaveLoopSelect;
  R^.Wave.Hint := _('Klicken oder ziehen, um an diese Stelle zu springen.') + LineEnding +
                  _('Rechte Maustaste ziehen: Loop-Bereich aufziehen');
  R^.Wave.ShowHint := True;
end;

{ Wellenformen ein- oder ausblenden. Jede Stem-Zeile wird um ihre
  Wellenform höher bzw. niedriger, das Fenster wächst bzw. schrumpft
  entsprechend (und bleibt auf dem Bildschirm). }
procedure TMainForm.SetWavesVisible(AShow: Boolean);
var
  i: Integer;
begin
  if AShow = FShowWaves then Exit;
  FShowWaves := AShow;
  FFitting := True;
  DisableAlign;
  try
    for i := 1 to STEM_COUNT do Rows[i].Wave.Visible := AShow;
    { Gezogene Wellenhöhe merken, damit sie nach Kompakt wiederkommt }
    if AShow then
    begin
      if FWaveH96 > 0 then SetWaveSize(Scale96ToForm(FWaveH96))
      else SetWaveSize(Scale96ToForm(WAVE_HEIGHT));
    end
    else
    begin
      FWaveH96 := ScaleFormTo96(WaveSize);
      for i := 1 to STEM_COUNT do Rows[i].Panel.Height := Scale96ToForm(ROW_HEIGHT);
    end;
    Constraints.MinHeight := 0;
    Constraints.MaxHeight := 0;
    Height := Height - ClientHeight + ContentHeight;
  finally
    EnableAlign;
    FFitting := False;
  end;
  UpdateClassicSize;
  KeepOnScreen;
end;

{ ----------------------------------------------------------------------------
  Fenstergrösse und Windows-Skalierung

  Lazarus baut das Fenster in 96-dpi-Pixeln auf und vergrössert danach
  alles auf die Windows-Skalierung (bei 150 % z. B. 820 -> 1230 Pixel).
  Alle Grössen, die später im Code gesetzt werden, müssen deshalb mit
  Scale96ToForm umgerechnet werden. Mit festen Pixelwerten war das Fenster
  bei 150 % höher als der Bildschirm und der CD-Player zerfiel.
  ---------------------------------------------------------------------------- }

{ Benötigte Innenhöhe der klassischen Ansicht: alle Flächen untereinander,
  Abstand unter MASTER und Fusszeile }
function TMainForm.ContentHeight: Integer;

  function Need(C: TControl): Integer;
  begin
    Result := C.Height + C.BorderSpacing.Top + C.BorderSpacing.Bottom +
              2 * C.BorderSpacing.Around;
  end;

var i: Integer;
begin
  Result := Need(PnlTop) + Need(PnlDeck) + Need(PnlMaster);
  for i := 1 to STEM_COUNT do Inc(Result, Need(Rows[i].Panel));
  Inc(Result, Scale96ToForm(BOTTOM_GAP) + PnlBottom.Height);
end;

{ Rahmen und Titelleiste von Windows (Aussenmass minus Height/Width).
  Vor dem ersten Anzeigen geschätzt. }
function TMainForm.FrameW: Integer;
var R: TRect;
begin
  if HandleAllocated and (GetWindowRect(Handle, R) <> 0) and (R.Right > R.Left) then
    Result := Max(0, (R.Right - R.Left) - Width)
  else
    Result := Scale96ToForm(16);
end;

function TMainForm.FrameH: Integer;
var R: TRect;
begin
  if HandleAllocated and (GetWindowRect(Handle, R) <> 0) and (R.Bottom > R.Top) then
    Result := Max(0, (R.Bottom - R.Top) - Height)
  else
    Result := Scale96ToForm(40);
end;

{ Aktuelle Höhe der Stem-Wellenformen }
function TMainForm.WaveSize: Integer;
begin
  Result := Rows[1].Wave.Height;
end;

{ Kleinste Fensterhöhe (Height) der klassischen Ansicht: Kompakt bzw.
  Wellenform mit ganz flachen Wellen (WAVE_MIN) }
function TMainForm.ClassicMinHeight(AWaves: Boolean): Integer;
var i: Integer;
begin
  Result := Height - ClientHeight + ContentHeight;
  for i := 1 to STEM_COUNT do
    Dec(Result, Rows[i].Panel.Height - Scale96ToForm(ROW_HEIGHT));
  if AWaves then
    Inc(Result, STEM_COUNT * (Scale96ToForm(ROW_HEIGHT - 2) + Scale96ToForm(WAVE_MIN) +
      Scale96ToForm(WAVE_PAD) - Scale96ToForm(ROW_HEIGHT)));
end;

{ Stem-Wellenformen auf Höhe H setzen, die Zeilen wachsen mit }
procedure TMainForm.SetWaveSize(H: Integer);
var i: Integer;
begin
  for i := 1 to STEM_COUNT do
  begin
    Rows[i].Wave.Height := H;
    Rows[i].Panel.Height := Rows[i].Wave.Top + H + Scale96ToForm(WAVE_PAD);
  end;
end;

{ Wellenform-Ansicht: freie oder fehlende Höhe auf die vier Stem-Wellen
  verteilen, damit die Bedienelemente der Fenstergrösse folgen }
procedure TMainForm.FitWaves;
var
  Slack, NewH: Integer;
begin
  if (FView <> vmWave) or FFitting then Exit;
  Slack := ClientHeight - ContentHeight;
  NewH := Max(Scale96ToForm(WAVE_MIN), WaveSize + Slack div STEM_COUNT);
  if NewH = WaveSize then Exit;
  FFitting := True;
  DisableAlign;
  try
    SetWaveSize(NewH);
  finally
    EnableAlign;
    FFitting := False;
  end;
end;

{ Mindestgrösse der klassischen Ansicht. Kompakt hat eine feste Höhe,
  die Wellenform-Ansicht lässt sich bis auf WAVE_MIN-hohe Wellen
  verkleinern und beliebig vergrössern. Nie grösser als der Bildschirm. }
procedure TMainForm.UpdateClassicSize;
var
  MinH, MaxAvail: Integer;
begin
  if FView = vmCD then Exit;
  MinH := ClassicMinHeight(FView = vmWave);
  MaxAvail := Screen.WorkAreaHeight - FrameH;
  MinH := Min(MinH, MaxAvail);
  FFitting := True;
  try
    Constraints.MaxHeight := 0;
    Constraints.MaxWidth := 0;
    Constraints.MinWidth := Min(Scale96ToForm(720), Screen.WorkAreaWidth - FrameW);
    { Maximieren nur in der Wellenform-Ansicht: dort wachsen die Wellen mit.
      Kompakt hat eine feste Höhe, maximiert gäbe es nur einen breiten Streifen. }
    if FView = vmWave then BorderIcons := [biSystemMenu, biMinimize, biMaximize]
    else
    begin
      if WindowState = wsMaximized then WindowState := wsNormal;
      BorderIcons := [biSystemMenu, biMinimize];
    end;
    Constraints.MinHeight := MinH;
    if FView = vmCompact then
    begin
      Constraints.MaxHeight := MinH;
      Height := MinH;
    end;
  finally
    FFitting := False;
  end;
  FitWaves;
end;

{ Fenster ganz auf dem Bildschirm halten: zu hoch/breit -> kleiner,
  ragt es unten/rechts hinaus -> verschieben }
procedure TMainForm.KeepOnScreen;
var R: TRect;
begin
  R := Screen.WorkAreaRect;
  if Height + FrameH > R.Bottom - R.Top then Height := R.Bottom - R.Top - FrameH;
  if Width + FrameW > R.Right - R.Left then Width := R.Right - R.Left - FrameW;
  if not HandleAllocated then Exit;
  if Left + Width + FrameW > R.Right then Left := Max(R.Left, R.Right - Width - FrameW);
  if Top + Height + FrameH > R.Bottom then Top := Max(R.Top, R.Bottom - Height - FrameH);
  if Left < R.Left then Left := R.Left;
  if Top < R.Top then Top := R.Top;
end;

{ Passt der CD-Player bei der aktuellen Skalierung auf den Bildschirm?
  (bei 150 % braucht er 1500 x 1050 Pixel plus Rahmen) }
function TMainForm.DesignFits: Boolean;
begin
  Result := (Scale96ToForm(DESIGN_W) + FrameW <= Screen.WorkAreaWidth) and
            (Scale96ToForm(DESIGN_H) + PnlBottom.Height + FrameH <= Screen.WorkAreaHeight);
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  FitWaves;
end;

{ ============================================================================
  Design CD-Player (Entwurf 7)

  Gleiche Funktionen, anderer Look. Die vorhandenen Bedienelemente
  (Fader, Mute/Solo, Wellenformen, Lupe, Loop- und Modus-Knöpfe, Master)
  werden NICHT doppelt angelegt, sondern beim Umschalten in die Flächen des
  Designs versetzt (PlaceCtl) und beim Zurückschalten wieder an ihren alten
  Platz gesetzt (RestorePlacements). So bleibt die ganze Logik dieselbe.
  Neu sind nur Jogwheel und Stem-Pads (designviews.pas)
  sowie ein paar Anzeigen (Zeiten, Farbstreifen).
  Die Loop-Spur (Lupe + Loop-Knöpfe) gibt es im Design als eigenen
  Streifen, in den Entwürfen war sie noch nicht eingezeichnet.
  ============================================================================ }

{ Dunkle Fläche mit Rahmen an fester Stelle (für die Designs) }
function TMainForm.MakeBox(AParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer): TDJPanel;
begin
  Result := TDJPanel.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, AHeight);
end;

{ Kleine gedimmte Überschrift (z. B. "HÖREN") }
function TMainForm.MakeCaption(AParent: TWinControl; const ACaption: string;
  ALeft, ATop: Integer): TLabel;
begin
  Result := MakeLabel(AParent, ACaption, ALeft, ATop, 7, True);
  Result.Font.Color := DJ_DIM;
end;

procedure TMainForm.BuildDesignUI;
var
  i, k: Integer;
  L: TLabel;

  { Zeit-Anzeige im Display: kleine Überschrift rechtsbündig, Wert daneben }
  function DisplayValue(const ACaption: string; CapLeft, CapWidth, ValLeft,
    ValWidth: Integer; Mono: Boolean): TLabel;
  var C: TLabel;
  begin
    C := MakeCaption(CDDisplay, ACaption, CapLeft, 15);
    C.AutoSize := False;
    C.Alignment := taRightJustify;
    C.Width := CapWidth;
    C.Font.Color := $00C09070;   // gedecktes Blau wie die Beschriftung echter CD-Player
    Result := MakeLabel(CDDisplay, '--:--', ValLeft, 8, 12, not Mono);
    if Mono then Result.Font.Name := MONO_FONT;
    Result.AutoSize := False;
    Result.SetBounds(ValLeft, 8, ValWidth, 24);
  end;

begin
  { ---------- CD-Player ---------- }
  PnlCD := TDJPanel.Create(Self);
  PnlCD.Visible := False;
  PnlCD.Parent := Self;
  PnlCD.Align := alClient;
  PnlCD.Color := DJ_BG;
  PnlCD.BorderColor := clNone;

  CDDisplay := MakeBox(PnlCD, MARGIN, 8, DESIGN_W - 2 * MARGIN, 238);
  CDDisplay.Color := DISPLAY_BG;
  LblCDTime   := DisplayValue(_('ZEIT'),   426, 56, 486, 64, True);
  LblCDRemain := DisplayValue(_('RESTZEIT'), 554, 56, 614, 72, True);
  LblCDLength := DisplayValue(_('LÄNGE'),  688, 64, 756, 64, True);
  LblCDMode   := DisplayValue(_('HÖREN'),  822, 60, 886, 88, False);
  LblCDMode.Font.Size := 11;
  for i := 1 to STEM_COUNT do
  begin
    { Farbstreifen vor jeder Stem-Welle (wie die Spuren im Entwurf) }
    CDBars[i] := TShape.Create(Self);
    CDBars[i].Parent := CDDisplay;
    CDBars[i].SetBounds(8, 40 + (i - 1) * 36, 4, 32);
    CDBars[i].Pen.Style := psClear;
    CDBars[i].Brush.Color := Rows[i].Color;
  end;

  CDLoop := MakeBox(PnlCD, MARGIN, 254, DESIGN_W - 2 * MARGIN, 72);
  MakeCaption(CDLoop, _('LOOP'), 766, 15);

  Jog := TJogWheel.Create(Self);
  Jog.Parent := PnlCD;
  Jog.SetBounds(20, 334, 228, 228);
  Jog.BackColor := DJ_BG;
  Jog.CenterCaption := _('RESTZEIT');
  Jog.CenterText := '-00:00';
  Jog.OnScrub := @ZoomScrub;   // gleiches Scrubbing wie beim Ziehen in der Lupe
  Jog.Hint := _('Jogwheel: mit gedrückter Maustaste drehen, dann hört man den Ton wie bei einer Platte unter der Hand.') + LineEnding +
              _('Der blaue Ring zeigt die Restzeit.');
  Jog.ShowHint := True;

  CDPads := MakeBox(PnlCD, 262, 334, 528, 300);
  MakeCaption(CDPads, _('STEM-PADS'), 12, 6);
  for i := 1 to STEM_COUNT do
    for k := 0 to 1 do
    begin
      Pads[i, k] := TStemPad.Create(Self);
      Pads[i, k].Parent := CDPads;
      if k = 0 then
      begin
        Pads[i, k].SetBounds(12 + (i - 1) * 128, 24, 120, 54);
        Pads[i, k].Tag := i;
        Pads[i, k].Hint := Format(_('Mute: Stem stumm schalten (Taste %d)'), [i]);
      end
      else
      begin
        Pads[i, k].SetBounds(12 + (i - 1) * 128, 86, 120, 46);
        Pads[i, k].Tag := 100 + i;
        Pads[i, k].Caption := _('SOLO');
        Pads[i, k].Hint := Format(_('Solo: nur diesen Stem hören (Shift+%d).') + LineEnding +
          _('Strg+Klick: weiteren Stem dazunehmen (mehrere Solos)'), [i]);
      end;
      Pads[i, k].ShowHint := True;
      Pads[i, k].OnClick := @PadClick;
    end;

  CDSource := MakeBox(PnlCD, 800, 334, 190, 112);
  MakeCaption(CDSource, _('QUELLE'), 10, 6);
  CDViewCap := MakeCaption(CDSource, _('ANSICHT'), 10, 60);
  CDMode := MakeBox(PnlCD, 800, 452, 190, 84);
  MakeCaption(CDMode, _('HÖREN'), 10, 6);
  CDMaster := MakeBox(PnlCD, 800, 542, 190, 92);
  MakeCaption(CDMaster, _('MASTER'), 10, 6);

end;

{ Bedienelement für ein Design an eine andere Stelle setzen und den alten
  Platz merken. Im Design ist alles fest angeordnet (nur links/oben verankert). }
procedure TMainForm.PlaceCtl(Ctl: TControl; NewParent: TWinControl;
  ALeft, ATop, AWidth, AHeight: Integer);
var n: Integer;
begin
  n := Length(FPlaced);
  SetLength(FPlaced, n + 1);
  FPlaced[n].Ctl := Ctl;
  FPlaced[n].Parent := Ctl.Parent;
  { Alter Platz in 96-dpi-Pixeln, damit er auch nach dem Hochskalieren
    beim Start (Design schon im Konstruktor gewählt) wieder stimmt }
  with Ctl.BoundsRect do
    FPlaced[n].Bounds := Rect(ScaleFormTo96(Left), ScaleFormTo96(Top),
      ScaleFormTo96(Right), ScaleFormTo96(Bottom));
  FPlaced[n].Anchors := Ctl.Anchors;
  Ctl.Anchors := [akLeft, akTop];
  Ctl.Parent := NewParent;
  { Positionen im Design sind in 96-dpi-Pixeln angegeben }
  Ctl.SetBounds(Scale96ToForm(ALeft), Scale96ToForm(ATop),
    Scale96ToForm(AWidth), Scale96ToForm(AHeight));
end;

{ Alle versetzten Elemente zurück an ihren alten Platz (rückwärts, falls
  eines zweimal versetzt wurde) }
procedure TMainForm.RestorePlacements;
var i: Integer;
begin
  for i := High(FPlaced) downto 0 do
    with FPlaced[i] do
    begin
      Ctl.Anchors := [akLeft, akTop];
      Ctl.Parent := Parent;
      Ctl.BoundsRect := Rect(Scale96ToForm(Bounds.Left), Scale96ToForm(Bounds.Top),
        Scale96ToForm(Bounds.Right), Scale96ToForm(Bounds.Bottom));
      Ctl.Anchors := Anchors;
    end;
  SetLength(FPlaced, 0);
end;

{ Loop-Knöpfe rechts neben der Lupe: oben A, B, löschen; darunter AN/AUS }
procedure TMainForm.PlaceLoopButtons(AParent: TWinControl; X, Y: Integer);
begin
  PlaceCtl(BtnLoopA, AParent, X, Y, 50, 26);
  PlaceCtl(BtnLoopB, AParent, X + 52, Y, 50, 26);
  PlaceCtl(BtnLoopClear, AParent, X + 104, Y, 54, 26);
  PlaceCtl(BtnLoopOn, AParent, X, Y + 30, 158, 26);
end;

procedure TMainForm.LayoutCD;
var
  i, Y: Integer;
begin
  { Display: Titel, 4 Stem-Wellen mit Farbstreifen, Original darunter }
  PlaceCtl(LblFile, CDDisplay, 16, 8, 400, 24);
  for i := 1 to STEM_COUNT do
  begin
    PlaceCtl(Rows[i].Wave, CDDisplay, 16, 40 + (i - 1) * 36, 956, 32);
    Rows[i].Wave.Visible := True;
  end;
  PlaceCtl(TrkPos, CDDisplay, 16, 188, 956, 40);
  PlaceCtl(WaveMaster, CDDisplay, 16, 188, 956, 40);

  { Loop-Spur }
  PlaceCtl(Zoom, CDLoop, 12, 8, 744, 56);
  PlaceLoopButtons(CDLoop, 810, 8);

  { CUE und Play/Pause als runde Knöpfe unter dem Jogwheel.
    CUE = zurück an den Anfang und anhalten (wie der Stop-Knopf). }
  PlaceCtl(BtnStop, PnlCD, 54, 570, 60, 60);
  PlaceCtl(BtnPlay, PnlCD, 154, 570, 60, 60);
  BtnStop.Glyph := dgNone;
  BtnStop.Caption := _('CUE');
  BtnStop.RoundShape := True;
  BtnStop.RingColor := CD_ORANGE;
  BtnPlay.RoundShape := True;
  BtnPlay.RingColor := DJ_GREEN;

  { Fader-Zeilen unter den Pads }
  for i := 1 to STEM_COUNT do
  begin
    Y := 144 + (i - 1) * 38;
    PlaceCtl(Rows[i].LblName, CDPads, 12, Y + 3, 100, 20);
    PlaceCtl(Rows[i].TrkVol, CDPads, 112, Y, 204, 26);
    PlaceCtl(Rows[i].LblVol, CDPads, 316, Y + 4, 42, 20);
    PlaceCtl(Rows[i].Meter, CDPads, 368, Y + 2, 148, 22);
  end;

  { Quelle: Öffnen + Ansicht }
  PlaceCtl(BtnOpen, CDSource, 10, 24, 170, 26);
  PlaceCtl(BtnView, CDSource, 10, 78, 170, 26);

  { Hören }
  PlaceCtl(BtnModeStems, CDMode, 10, 24, 84, 24);
  PlaceCtl(BtnModeOrig, CDMode, 96, 24, 84, 24);
  PlaceCtl(BtnModeRest, CDMode, 10, 52, 84, 24);
  PlaceCtl(BtnReset, CDMode, 96, 52, 84, 24);

  { Master }
  PlaceCtl(LblMasterVol, CDMaster, 130, 4, 50, 18);
  PlaceCtl(TrkMaster, CDMaster, 6, 22, 178, 26);
  PlaceCtl(MeterOut, CDMaster, 10, 56, 120, 26);
  PlaceCtl(BtnClip, CDMaster, 136, 56, 44, 26);
end;

procedure TMainForm.SetView(V: TViewMode);
begin
  { CD-Player braucht bei grosser Windows-Skalierung mehr Platz, als der
    Bildschirm hat -> klassische Ansicht bleiben, statt abgeschnitten
    (vor dem ersten Anzeigen prüft das FormShow) }
  if (V = vmCD) and (V <> FView) and FShown and not DesignFits then
  begin
    LblStatus.Caption := _('Der CD-Player passt bei dieser Windows-Skalierung nicht auf den Bildschirm.');
    V := FView;
  end;
  { Wellenformen brauchen mehr Höhe als Kompakt }
  if (V = vmWave) and (V <> FView) and FShown and
     (ClassicMinHeight(True) + FrameH > Screen.WorkAreaHeight) then
  begin
    LblStatus.Caption := _('Die Wellenformen passen bei dieser Windows-Skalierung nicht auf den Bildschirm.');
    V := FView;
  end;
  if V <> FView then
  begin
    { Maximiert geht nur die Wellenform-Ansicht -> vorher zurück auf normal,
      damit die gemerkte Fenstergrösse stimmt }
    if (V <> vmWave) and (WindowState = wsMaximized) then WindowState := wsNormal;
    if FView = vmCD then LeaveDesign;
    FView := V;
    case V of
      vmCompact: SetWavesVisible(False);
      vmWave:    SetWavesVisible(True);
    else
      EnterDesign(V);
    end;
    if V <> vmCD then
    begin
      UpdateClassicSize;
      KeepOnScreen;
    end;
    UpdateDesignLook;
  end;
  UpdateViewButtons;
end;

{ Innengrösse des Fensters auf das Design einstellen und es auf dem
  Bildschirm halten (das Design ist breiter als die klassische Ansicht) }
procedure TMainForm.FitDesignWindow;
begin
  FFitting := True;
  try
    if WindowState = wsMaximized then WindowState := wsNormal;
    Constraints.MinWidth := 0;
    Constraints.MinHeight := 0;
    Constraints.MaxWidth := 0;
    Constraints.MaxHeight := 0;
    { DESIGN_W/H sind 96-dpi-Pixel, die Fusszeile ist schon skaliert }
    ClientWidth := Scale96ToForm(DESIGN_W);
    ClientHeight := Scale96ToForm(DESIGN_H) + PnlBottom.Height;
    Constraints.MinWidth := Width;
    Constraints.MinHeight := Height;
    { Feste Grösse: die Elemente im Design sitzen an festen Plätzen und
      wachsen nicht mit, ein grösseres Fenster gäbe nur leere Fläche }
    Constraints.MaxWidth := Width;
    Constraints.MaxHeight := Height;
    BorderIcons := [biSystemMenu, biMinimize];
  finally
    FFitting := False;
  end;
  KeepOnScreen;
end;

procedure TMainForm.EnterDesign(V: TViewMode);
var i: Integer;
begin
  { Grösse der klassischen Ansicht merken (für LeaveDesign) }
  FClassicW := ScaleFormTo96(Width);
  FClassicH := ScaleFormTo96(Height);
  DisableAlign;
  try
    PnlTop.Visible := False;
    PnlDeck.Visible := False;
    for i := 1 to STEM_COUNT do Rows[i].Panel.Visible := False;
    PnlMaster.Visible := False;
    FScroll.Visible := False;
    FitDesignWindow;
    LayoutCD;
    PnlCD.Visible := True;
  finally
    EnableAlign;
  end;
end;

procedure TMainForm.LeaveDesign;
var i: Integer;
begin
  DisableAlign;
  try
    PnlCD.Visible := False;
    { Fenster zuerst auf die alte Grösse, dann passen die rechts
      verankerten Elemente wieder genau an ihren Platz }
    Constraints.MinWidth := 0;
    Constraints.MinHeight := 0;
    Constraints.MaxWidth := 0;
    Constraints.MaxHeight := 0;
    SetBounds(Left, Top, Scale96ToForm(FClassicW), Scale96ToForm(FClassicH));
    { Versteckte Flächen werden nicht ausgerichtet und behalten sonst ihre
      alte Breite (z. B. die von vor dem Hochskalieren beim Start) -> die
      rechts verankerten Elemente landeten neben dem Fenster }
    PnlTop.Width := ClientWidth - PnlTop.BorderSpacing.Left - PnlTop.BorderSpacing.Right;
    PnlDeck.Width := PnlTop.Width;
    for i := 1 to STEM_COUNT do Rows[i].Panel.Width := PnlTop.Width;
    PnlMaster.Width := PnlTop.Width;
    RestorePlacements;
    BtnStop.Glyph := dgStop;
    BtnStop.Caption := '';
    BtnStop.RoundShape := False;
    BtnPlay.RoundShape := False;
    for i := 1 to STEM_COUNT do Rows[i].Wave.Visible := FShowWaves;
    { Flächen in der alten Reihenfolge wieder einblenden }
    PnlTop.Top := 0;
    PnlDeck.Top := 100;
    for i := 1 to STEM_COUNT do Rows[i].Panel.Top := 100 + i * 100;
    PnlMaster.Top := 100 + (STEM_COUNT + 1) * 100;
    PnlTop.Visible := True;
    PnlDeck.Visible := True;
    for i := 1 to STEM_COUNT do Rows[i].Panel.Visible := True;
    PnlMaster.Visible := True;
    FScroll.Visible := True;
  finally
    EnableAlign;
  end;
end;

{ Auswahlknopf zeigt die aktuelle Ansicht, im Menü ist sie abgehakt }
procedure TMainForm.UpdateViewButtons;
var
  i: Integer;
begin
  BtnView.Caption := ViewName(FView);
  for i := 0 to MnuView.Items.Count - 1 do
    MnuView.Items[i].Checked := MnuView.Items[i].Tag = Ord(FView);
end;

{ Anzeigename einer Ansicht (Knopf und Menü) }
function TMainForm.ViewName(V: TViewMode): string;
begin
  case V of
    vmCompact: Result := _('KOMPAKT');
    vmWave:    Result := _('WELLENFORM');
  else
    Result := _('CD-PLAYER');
  end;
end;

{ Pads, Farbstreifen, Ringe und Punkte wie die Stem-Zeilen färben:
  hörbar = Stemfarbe, sonst grau (aufgerufen aus UpdateRowLook) }
procedure TMainForm.UpdateDesignLook;
var
  i: Integer;
  IsOn, StemMode: Boolean;
  C: TColor;
begin
  if Pads[1, 0] = nil then Exit;   // Designs noch nicht aufgebaut
  StemMode := BtnModeStems.Down;
  for i := 1 to STEM_COUNT do
  begin
    IsOn := (Rows[i].Panel.Tag = 1) and StemMode;
    Pads[i, 0].StemColor := Rows[i].Color;
    Pads[i, 0].Lit := IsOn;
    Pads[i, 0].Dim := not StemMode;
    Pads[i, 0].SubText := Rows[i].LblState.Caption;
    Pads[i, 1].StemColor := Rows[i].Color;
    Pads[i, 1].Lit := Rows[i].BtnSolo.Down and StemMode;
    Pads[i, 1].Dim := not StemMode;
    if IsOn then C := Rows[i].Color else C := $00444444;
    CDBars[i].Brush.Color := C;
  end;
  if BtnModeOrig.Down then LblCDMode.Caption := _('ORIGINAL')
  else if BtnModeRest.Down then LblCDMode.Caption := _('REST')
  else LblCDMode.Caption := _('STEMS');
end;

{ Stem-Namen nach dem Laden einer Datei übernehmen }
procedure TMainForm.UpdateDesignNames;
var
  i: Integer;
begin
  for i := 1 to STEM_COUNT do
  begin
    Pads[i, 0].Caption := UpperCase(FInfo.Names[i - 1]);
    Pads[i, 1].SubText := UpperCase(FInfo.Names[i - 1]);
  end;
  UpdateDesignLook;
end;

{ Pad gedrückt: wie der Knopf M bzw. S der Stem-Zeile }
procedure TMainForm.PadClick(Sender: TObject);
var i: Integer;
begin
  i := TStemPad(Sender).Tag;
  if i > 100 then
  begin
    Rows[i - 100].BtnSolo.Down := not Rows[i - 100].BtnSolo.Down;
    MuteSoloClick(Rows[i - 100].BtnSolo);
  end
  else
  begin
    Rows[i].BtnMute.Down := not Rows[i].BtnMute.Down;
    MuteSoloClick(Rows[i].BtnMute);
  end;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  { Erst jetzt kennt Windows die Rahmenbreite und das Fenster ist auf die
    Windows-Skalierung vergrössert -> Ansicht an den Bildschirm anpassen.
    Passt die gespeicherte Ansicht nicht, startet eine kleinere
    (gespeichert wird das nicht). }
  if not FShown then
  begin
    FShown := True;
    {$IFDEF WINDOWS}
    { Bildlaufleiste dunkel wie der Player (ab Windows 10 1809, sonst hell) }
    SetWindowTheme(FScroll.Handle, 'DarkMode_Explorer', nil);
    {$ENDIF}
    if (FView = vmCD) and not DesignFits then
    begin
      if FShowWaves and (ClassicMinHeight(True) + FrameH <= Screen.WorkAreaHeight) then
        SetView(vmWave)
      else
        SetView(vmCompact);
    end;
    if FView = vmCD then FitDesignWindow
    else
    begin
      { Wellenform-Ansicht passt nicht einmal mit ganz flachen Wellen -> Kompakt }
      if (FView = vmWave) and (ClassicMinHeight(True) + FrameH > Screen.WorkAreaHeight) then
        SetView(vmCompact);
      UpdateClassicSize;
      KeepOnScreen;
    end;
  end;
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

{ StemPlayer.ini neben der exe. Ist der Ordner schreibgeschützt (Setup-
  Installation unter C:\Programme), dann %APPDATA%\StemMaker\StemPlayer.ini -
  gleiches Vorgehen wie StemMaker.ini (siehe ustemjob.StemIniFileName). }
function TMainForm.IniFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
  if not DirectoryIsWritable(ExtractFilePath(Result)) then
  begin
    Result := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
      'StemMaker' + PathDelim;
    ForceDirectories(Result);
    Result := Result + ExtractFileName(ChangeFileExt(Application.ExeName, '.ini'));
  end;
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
{ Gewählte Ansicht merken, damit der nächste Start gleich so aussieht }
procedure TMainForm.SaveViewSetting;
var Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Ini.WriteBool('Ansicht', 'Wellenform', FShowWaves);
      case FView of
        vmCD:      Ini.WriteString('Ansicht', 'Design', 'CD');
        vmWave:    Ini.WriteString('Ansicht', 'Design', 'Wellenform');
      else
        Ini.WriteString('Ansicht', 'Design', 'Kompakt');
      end;
    finally
      Ini.Free;
    end;
  except
    { nicht schreibbar -> nächstes Mal eben wieder mit Standard }
  end;
end;

{ Klick auf den Auswahlknopf: Menü direkt unter dem Knopf aufklappen }
procedure TMainForm.ViewClick(Sender: TObject);
var
  P: TPoint;   // linke untere Ecke des Knopfs in Bildschirmkoordinaten
begin
  P := BtnView.ClientToScreen(Point(0, BtnView.Height));
  MnuView.PopUp(P.X, P.Y);
end;

{ Ansicht im Menü gewählt }
procedure TMainForm.ViewMenuClick(Sender: TObject);
begin
  SetView(TViewMode((Sender as TMenuItem).Tag));
  SaveViewSetting;
end;

{ Menüeinträge so breit wie der Knopf und gut klickbar hoch }
procedure TMainForm.ViewMenuMeasure(Sender: TObject; ACanvas: TCanvas;
  var AWidth, AHeight: Integer);
begin
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Style := [fsBold];
  AWidth := Math.Max(BtnView.Width - 20, ACanvas.TextWidth((Sender as TMenuItem).Caption) + Scale96ToForm(40));
  AHeight := Scale96ToForm(30);
end;

{ Menüeintrag im Player-Stil: dunkel, unter der Maus heller,
  die aktuelle Ansicht mit grünem Streifen links und heller Schrift }
procedure TMainForm.ViewMenuDraw(Sender: TObject; ACanvas: TCanvas;
  ARect: TRect; AState: TOwnerDrawState);
var
  Item: TMenuItem;   // der zu zeichnende Eintrag
  TS: TTextStyle;    // Textausrichtung
begin
  Item := Sender as TMenuItem;
  with ACanvas do
  begin
    if odSelected in AState then Brush.Color := BlendColor(DJ_BTN, clWhite, 0.10)
    else Brush.Color := DJ_PANEL;
    FillRect(ARect);
    if Item.Checked then
    begin
      Brush.Color := DJ_GREEN;
      FillRect(ARect.Left, ARect.Top + 5, ARect.Left + 4, ARect.Bottom - 5);
    end;
    Font.Assign(Self.Font);
    Font.Style := [fsBold];
    if Item.Checked or (odSelected in AState) then Font.Color := DJ_TEXT
    else Font.Color := $00B0B0B0;
    TS := TextStyle;
    TS.Layout := tlCenter;
    TS.SingleLine := True;
    Brush.Style := bsClear;
    TextRect(Rect(ARect.Left + 16, ARect.Top, ARect.Right - 8, ARect.Bottom),
      ARect.Left + 16, ARect.Top, Item.Caption, TS);
    Brush.Style := bsSolid;
  end;
end;

{ Wellenform-Berechnung abbrechen und warten, bis der Thread seine
  .raw-Dateien geschlossen hat (sonst lassen sie sich nicht löschen). }
procedure TMainForm.StopPeakThread;
begin
  if FPeakThread = nil then Exit;
  FPeakThread.Terminate;
  FPeakThread.WaitFor;
  FreeAndNil(FPeakThread);
end;

{ Thread ist fertig -> Hüllkurven an die Anzeigen übergeben.
  Alle 4 Stems bekommen den GLEICHEN Massstab (lautester Stem füllt die Höhe),
  damit ein leiser Stem auch leise aussieht. Das Original hat seinen eigenen. }
procedure TMainForm.ApplyPeaks;
var
  i: Integer;
  M: Single;
begin
  M := 0;
  for i := 1 to STEM_COUNT do
    M := Max(M, PeakMax(FPeakThread.Peaks[i]));
  if M < 0.05 then M := 0.05;   // fast stille Datei nicht riesig aufblasen
  for i := 1 to STEM_COUNT do
    if FPeakThread.Peaks[i].Valid then
      Rows[i].Wave.SetPeaks(FPeakThread.Peaks[i], 1 / M);
  if FPeakThread.Peaks[0].Valid then
  begin
    M := Max(0.05, PeakMax(FPeakThread.Peaks[0]));
    WaveMaster.SetPeaks(FPeakThread.Peaks[0], 1 / M);
    WaveMaster.Visible := True;
    TrkPos.Visible := False;
    if FPeakThread.Fine.Valid and (Engine <> nil) then
      Zoom.SetPeaks(FPeakThread.Fine, 1 / M, Engine.TotalFrames,
        FTempDir + 'track0.raw');
  end;
  FreeAndNil(FPeakThread);
end;

procedure TMainForm.UnloadFile;
var i: Integer;
begin
  StopPeakThread;
  for i := 1 to STEM_COUNT do Rows[i].Wave.ClearPeaks;
  WaveMaster.ClearPeaks;
  Zoom.ClearPeaks;
  WaveMaster.Visible := False;
  TrkPos.Visible := True;
  if Engine <> nil then
  begin
    Engine.Free;           // stoppt Thread, schliesst Audiogerät und Dateien
    Engine := nil;
  end;
  { Loop gehört zum Track -> beim nächsten Track ohne Loop beginnen }
  FLoopA := -1;
  FLoopB := -1;
  FLoopOn := False;
  ApplyLoop;
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
      LblStatus.Caption := Format(_('Dekodiere %d Spuren mit ffmpeg ... %.1f s'),
        [TrackCount, (GetTickCount64 - T0) / 1000]);
      Application.ProcessMessages;   // Fenster bleibt bedienbar
      Sleep(30);
    end;
    DrainOutput;   // Rest nach Prozessende einsammeln
    ErrText := Trim(ErrText);

    Result := (P.ExitStatus = 0) and FileExists(FTempDir + 'track0.raw');
    if (not Result) and (ErrText = '') then
      ErrText := Format(_('ffmpeg wurde mit Code %d beendet.'), [P.ExitStatus]);
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
  Msg, ErrText, Reason: string;
  Dlg: TOpenDialog;
  NewInfo: TStemInfo;
begin
  if FLoading then Exit;

  { Ordner statt Datei reingezogen? }
  if DirectoryExists(FileName) then
  begin
    MessageDlg(APP_TITLE,
      _('Bitte eine Stem-Datei (.stem.mp4) reinziehen, keinen Ordner.'),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  if not FileExists(FileName) then Exit;

  { Ist es überhaupt eine Stem-Datei? Diese Prüfung kommt VOR UnloadFile,
    damit eine falsche Datei den gerade geladenen Track nicht wegwirft.
    Sie liest nur die MP4-Struktur (Millisekunden), ffmpeg wird nicht gebraucht. }
  if not CheckStemFile(FileName, NewInfo, Reason) then
  begin
    LblStatus.Caption := _('Keine Stem-Datei: ') + ExtractFileName(FileName);
    MessageDlg(APP_TITLE, ExtractFileName(FileName) + LineEnding + LineEnding +
      Reason, mtWarning, [mbOK], 0);
    Exit;
  end;

  { ffmpeg vorhanden? Sonst einmalig fragen und merken }
  if (FFFmpeg = '') or not FileExists(FFFmpeg) then
  begin
    MessageDlg(APP_TITLE,
      _('ffmpeg.exe wurde nicht gefunden.') + LineEnding +
      _('Bitte im nächsten Dialog die ffmpeg.exe auswählen') + LineEnding +
      _('(z.B. die von Elospeed StemMaker).'), mtInformation, [mbOK], 0);
    Dlg := TOpenDialog.Create(nil);
    try
      Dlg.Title := _('ffmpeg.exe auswählen');
      Dlg.Filter := _('ffmpeg.exe|ffmpeg.exe|Programme (*.exe)|*.exe');
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

    { 1) Struktur übernehmen (oben schon von CheckStemFile gelesen, also
         mindestens 5 Audiospuren) }
    FInfo := NewInfo;
    Tracks := FInfo.AudioTracks;
    if Tracks > TRACK_MAX + 1 then Tracks := TRACK_MAX + 1;

    Msg := '';
    if not FInfo.HasStemBox then
      Msg := _('Hinweis: kein Traktor-"stem"-Block gefunden (Standardnamen werden verwendet).');

    { 2) Dekodieren }
    FTempDir := FInstanceDir + 'track_' +
                IntToStr(GetTickCount64) + PathDelim;
    ForceDirectories(FTempDir);
    LblFile.Caption := ExtractFileName(FileName);
    LblFileInfo.Caption := _('Dekodiere ...');
    Ok := DecodeTracks(FileName, Tracks, ErrText);
    if not Ok then
    begin
      UnloadFile;   // halbfertige .raw-Dateien wieder löschen
      if FCancelLoad then
      begin
        { Abbruch durch Schliessen des Fensters -> keine Fehlermeldung }
        LblStatus.Caption := _('Laden abgebrochen.');
        LblFile.Caption := '';
        LblFileInfo.Caption := '';
        Exit;
      end;
      LblFileInfo.Caption := _('Fehler beim Dekodieren');
      LblStatus.Caption := _('Fehler beim Dekodieren: ') +
        StringReplace(ErrText, LineEnding, ' | ', [rfReplaceAll]);
      MessageDlg(APP_TITLE, _('ffmpeg konnte die Datei nicht dekodieren:') + LineEnding +
        FileName + LineEnding + LineEnding + _('Meldung von ffmpeg:') + LineEnding +
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
    { Wellenformen im Hintergrund berechnen, die Musik startet trotzdem sofort }
    FPeakThread := TPeakThread.Create(Raw, Engine.TotalFrames);

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
    LblFileInfo.Caption := Format(_('%d Spuren  ·  Länge %s'), [Tracks, FormatTime(Engine.TotalFrames)]);
    LblTotal.Caption := '/ ' + FormatTime(Engine.TotalFrames);
    { Designs: Länge, Titel und Namen }
    Jog.Total := Engine.TotalFrames;
    LblCDLength.Caption := FormatTime(Engine.TotalFrames);
    UpdateDesignNames;

    if Msg <> '' then LblStatus.Caption := Msg
    else LblStatus.Caption := Format(_('%d Spuren geladen  ·  Länge %s  ·  ffmpeg: %s'),
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
      if BtnModeOrig.Down then S := _('MODUS: ORIGINAL') else S := _('MODUS: REST');
    end
    else if Rows[i].BtnSolo.Down then
    begin
      S := _('SOLO');
      StateColor := DJ_YELLOW;
    end
    else if not IsOn then
    begin
      if Rows[i].BtnMute.Down then
      begin
        S := _('STUMM');
        StateColor := DJ_RED;
      end
      else S := _('AUS (SOLO)');  // ein anderer Stem ist auf Solo
    end
    else S := _('HÖRBAR');
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
    { Wellenform: hörbar = Stemfarbe, sonst grau (wie die Pegelanzeige) }
    Rows[i].Wave.WaveColor := Rows[i].Color;
    Rows[i].Wave.Active := IsOn and StemMode;
  end;
  UpdateDesignLook;
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

{ Wie FormatTime, aber mit Millisekunden (für die Loop-Punkte, die sich
  ganz hineingezoomt in 2-ms-Schritten verschieben lassen) }
function TMainForm.FormatTimeFine(Frames: Int64): string;
var Ms: Int64;
begin
  Ms := Round(Frames * 1000 / SAMPLE_RATE);   // gerundet: 2-ms-Schritte sind 88 Frames
  Result := Format('%.2d:%.2d.%.3d', [Ms div 60000, (Ms div 1000) mod 60, Ms mod 1000]);
end;

{ ============================================================================
  Loop A-B
  Die Punkte werden hier verwaltet, die Engine wiederholt den Abschnitt
  (siehe stemengine.pas). A allein ist nur eine Marke. Sobald auch B
  gesetzt ist, läuft der Loop. Ein aktiver Loop "fängt" die Wiedergabe,
  wenn sie von vorne an B ankommt; wer hinter B springt, hört normal weiter.
  ============================================================================ }

{ Aktuelle Stelle für die Loop-Punkte: die geglättete Position des roten
  Strichs, also genau das, was man gerade sieht und hört }
function TMainForm.CurrentFrame: Int64;
begin
  Result := 0;
  if Engine = nil then Exit;
  Result := Round(FHeadPos);
  if Result < 0 then Result := 0;
  if Result >= Engine.TotalFrames then Result := Engine.TotalFrames - 1;
end;

procedure TMainForm.SetLoopA;
begin
  if Engine = nil then Exit;
  FLoopA := CurrentFrame;
  { B vor (oder zu nah an) dem neuen A ergibt keinen Loop mehr }
  if (FLoopB >= 0) and (FLoopB - FLoopA < MIN_LOOP) then
  begin
    FLoopB := -1;
    FLoopOn := False;
  end;
  ApplyLoop;
end;

procedure TMainForm.SetLoopB;
var P: Int64;
begin
  if Engine = nil then Exit;
  if FLoopA < 0 then
  begin
    LblStatus.Caption := _('Loop: zuerst Punkt A setzen (Taste A), dann B.');
    Exit;
  end;
  P := CurrentFrame;
  if P - FLoopA < MIN_LOOP then
  begin
    LblStatus.Caption := _('Loop: Punkt B muss hinter Punkt A liegen.');
    Exit;
  end;
  FLoopB := P;
  FLoopOn := True;
  ApplyLoop;
end;

procedure TMainForm.ToggleLoop;
var P: Int64;
begin
  if Engine = nil then Exit;
  if (FLoopA < 0) or (FLoopB < 0) then
  begin
    LblStatus.Caption := _('Loop: zuerst Punkt A und B setzen (Tasten A und B, ' +
                         'oder rechte Maustaste in der Wellenform ziehen).');
    Exit;
  end;
  FLoopOn := not FLoopOn;
  ApplyLoop;
  { Einschalten ausserhalb des Loops: gleich zu A springen (wie "Reloop") }
  P := CurrentFrame;
  if FLoopOn and ((P < FLoopA) or (P >= FLoopB)) then
    Engine.SeekTo := FLoopA;
end;

procedure TMainForm.ClearLoop;
begin
  FLoopA := -1;
  FLoopB := -1;
  FLoopOn := False;
  ApplyLoop;
end;

{ Loop an Engine, Wellenformen, Knöpfe und Statuszeile weitergeben.
  UpdateEngine = False: nur anzeigen (während eine Marke gezogen wird, damit
  die Engine nicht bei jeder Mausbewegung neu aufsetzt). }
procedure TMainForm.ApplyLoop(UpdateEngine: Boolean);
var
  i: Integer;
  FA, FB: Single;
begin
  if (Engine <> nil) and UpdateEngine then
  begin
    { Erst beide Punkte, dann den Zähler: so übernimmt die Engine nie
      ein A ohne das passende B }
    if FLoopOn and (FLoopA >= 0) and (FLoopB > FLoopA) then
    begin
      Engine.LoopStart := FLoopA;
      Engine.LoopEnd := FLoopB;
    end
    else
    begin
      Engine.LoopStart := -1;
      Engine.LoopEnd := -1;
    end;
    Inc(Engine.LoopSerial);
  end;

  FA := -1; FB := -1;
  if (Engine <> nil) and (Engine.TotalFrames > 0) then
  begin
    if FLoopA >= 0 then FA := FLoopA / Engine.TotalFrames;
    if FLoopB >= 0 then FB := FLoopB / Engine.TotalFrames;
  end;
  WaveMaster.SetLoop(FA, FB, FLoopOn);
  Zoom.SetLoop(FLoopA, FLoopB, FLoopOn);
  for i := 1 to STEM_COUNT do Rows[i].Wave.SetLoop(FA, FB, FLoopOn);

  BtnLoopA.Down := FLoopA >= 0;
  BtnLoopB.Down := FLoopB >= 0;
  BtnLoopOn.Down := FLoopOn;
  BtnLoopOn.Enabled := (FLoopA >= 0) and (FLoopB >= 0);
  BtnLoopClear.Enabled := FLoopA >= 0;

  if Engine = nil then Exit;
  if (FLoopA >= 0) and (FLoopB >= 0) then
  begin
    if FLoopOn then
      LblStatus.Caption := Format(_('Loop an:  %s bis %s  (%.1f s)  ·  L = aus, Rücktaste = löschen'),
        [FormatTimeFine(FLoopA), FormatTimeFine(FLoopB), (FLoopB - FLoopA) / SAMPLE_RATE])
    else
      LblStatus.Caption := Format(_('Loop aus:  %s bis %s gemerkt  ·  L = wieder an'),
        [FormatTimeFine(FLoopA), FormatTimeFine(FLoopB)]);
  end
  else if FLoopA >= 0 then
    LblStatus.Caption := Format(_('Loop: Punkt A bei %s  ·  jetzt an der Endstelle B drücken'),
      [FormatTimeFine(FLoopA)])
  else
    LblStatus.Caption := '';
end;

procedure TMainForm.LoopClick(Sender: TObject);
begin
  if Sender = BtnLoopA then SetLoopA
  else if Sender = BtnLoopB then SetLoopB
  else if Sender = BtnLoopOn then ToggleLoop
  else ClearLoop;
end;

{ Neuer Loop von A bis B (Frames), sofort aktiv. Liegt die Wiedergabe
  ausserhalb, springt sie an den Anfang des Loops. }
procedure TMainForm.SetLoopRange(A, B: Int64);
var P: Int64;
begin
  if (Engine = nil) or (Engine.TotalFrames <= 0) then Exit;
  if A < 0 then A := 0;
  if B > Engine.TotalFrames then B := Engine.TotalFrames;
  if B - A < MIN_LOOP then
  begin
    LblStatus.Caption := _('Loop: zu kurz (mindestens 0,1 Sekunden).');
    Exit;
  end;
  FLoopA := A;
  FLoopB := B;
  FLoopOn := True;
  ApplyLoop;
  P := CurrentFrame;
  if (P < A) or (P >= B) then Engine.SeekTo := A;
end;

{ Rechte Maustaste in einer Übersichts-Wellenform gezogen }
procedure TMainForm.WaveLoopSelect(Sender: TObject; AFrom, ATo: Single);
begin
  if (Engine = nil) or (Engine.TotalFrames <= 0) then Exit;
  SetLoopRange(Round(AFrom * (Engine.TotalFrames - 1)),
               Round(ATo * (Engine.TotalFrames - 1)));
end;

{ Lupe: rechte Maustaste gezogen (Frames sind schon aufs Raster gerundet) }
procedure TMainForm.ZoomLoopSelect(Sender: TObject; AFrom, ATo: Int64);
begin
  SetLoopRange(AFrom, ATo);
end;

{ Lupe: Klick daneben -> dorthin springen }
procedure TMainForm.ZoomSeek(Sender: TObject; Frame: Int64);
begin
  if Engine <> nil then Engine.SeekTo := Frame;
end;

{ Lupe: Welle wird gezogen -> Ton folgt der Maus (Scrubbing, stemengine 1.3).
  Beim Loslassen macht die Engine selbst weiter (siehe unten). }
procedure TMainForm.ZoomScrub(Sender: TObject; IsDown: Boolean; Frame: Int64);
begin
  if Engine = nil then Exit;
  Engine.ScrubTarget := Frame;
  if IsDown then
    Engine.Scrubbing := True
  else
  begin
    { Loslassen: die Engine geht selbst weiter (beim Abspielen nahtlos ab
      dem Lesekopf, bei Pause an ScrubTarget). Beim Abspielen kein SeekTo,
      das würde die Warteschlange leeren und eine Lücke machen. Bei Pause
      schadet es nicht und sichert den Fall, dass die Engine das Ziehen
      noch gar nicht bemerkt hatte. }
    if not Engine.Playing then Engine.SeekTo := Frame;
    Engine.Scrubbing := False;
  end;
end;

{ Lupe: Marke A (1) oder B (2) wird gezogen. Sie darf nicht über die andere
  hinaus (mindestens MIN_LOOP Abstand). Erst beim Loslassen bekommt die
  Engine den neuen Loop. }
procedure TMainForm.ZoomMarkerMove(Sender: TObject; Marker: Integer;
  Frame: Int64; Final: Boolean);
begin
  if Engine = nil then Exit;
  if Marker = 1 then
  begin
    if FLoopB >= 0 then Frame := Min(Frame, FLoopB - MIN_LOOP);
    FLoopA := Max(0, Frame);
  end
  else
  begin
    Frame := Max(Frame, FLoopA + MIN_LOOP);
    FLoopB := Min(Engine.TotalFrames, Frame);
  end;
  ApplyLoop(Final);
end;

{ Strg/Shift + Pfeil: Marke A (1) bzw. B (2) um Frames verschieben }
procedure TMainForm.NudgeMarker(Marker: Integer; Frames: Int64);
begin
  if Engine = nil then Exit;
  if (Marker = 1) and (FLoopA >= 0) then
    ZoomMarkerMove(nil, 1, FLoopA + Frames, True)
  else if (Marker = 2) and (FLoopB >= 0) then
    ZoomMarkerMove(nil, 2, FLoopB + Frames, True);
end;

{ Tastaturschritt für den Loop: 1/80 der Lupenbreite, runder Wert. Wer
  näher heranzoomt, verschiebt also auch feiner (bei 8 s 0,1 s, bis 2 ms). }
function TMainForm.NudgeStep: Int64;
begin
  Result := Zoom.StepFrames;
end;

{ Pfeiltaste bei aktivem Loop: ganzen Loop verschieben, Länge bleibt.
  Liegt die Wiedergabe danach ausserhalb, geht es bei A weiter. }
procedure TMainForm.MoveLoop(Frames: Int64);
var
  Len, P: Int64;
begin
  if (Engine = nil) or (FLoopA < 0) or (FLoopB < 0) then Exit;
  Len := FLoopB - FLoopA;
  FLoopA := EnsureRange(FLoopA + Frames, 0, Engine.TotalFrames - Len);
  FLoopB := FLoopA + Len;
  ApplyLoop;
  P := CurrentFrame;
  if FLoopOn and ((P < FLoopA) or (P >= FLoopB)) then Engine.SeekTo := FLoopA;
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

{ Solo-Logik wie am DJ-Mixer: Solo heisst "nur dieser Stem". Wird ein Solo
  eingeschaltet, gehen alle anderen Solos aus. Mit Additive (Strg gedrückt)
  bleiben die anderen an -> mehrere Stems gleichzeitig solo.
  Erwartet, dass Rows[Idx].BtnSolo.Down schon den neuen Zustand hat. }
procedure TMainForm.ApplySolo(Idx: Integer; Additive: Boolean);
var i: Integer;
begin
  if Rows[Idx].BtnSolo.Down and not Additive then
    for i := 1 to STEM_COUNT do
      if i <> Idx then Rows[i].BtnSolo.Down := False;
end;

procedure TMainForm.MuteSoloClick(Sender: TObject);
var BtnTag: Integer;
begin
  { Solo-Knöpfe haben Tag 100 + Stem-Nummer (siehe BuildStemRow) }
  BtnTag := TComponent(Sender).Tag;
  if BtnTag > 100 then
    ApplySolo(BtnTag - 100, GetKeyState(VK_CONTROL) < 0);
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

{ Klick/Ziehen in eine Wellenform (Stem oder Original): dorthin springen }
procedure TMainForm.WaveSeek(Sender: TObject; Fraction: Single);
begin
  if (Engine = nil) or (Engine.TotalFrames <= 0) then Exit;
  Engine.SeekTo := Round(Fraction * (Engine.TotalFrames - 1));
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
  S: string;
begin
  if Engine = nil then Exit;
  Playing := Engine.Playing;

  { Wellenformen fertig berechnet? }
  if (FPeakThread <> nil) and FPeakThread.Done then ApplyPeaks;

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
  { Zeiten in den Designs (nur bei Änderung setzen: ein neuer Text lässt das
    LCL alle Elemente neu ausrichten, siehe Version 1.6 im Entwicklungslog) }
  if FView = vmCD then
  begin
    S := '-' + FormatTime(Max(0, Engine.TotalFrames - Engine.PlayPos));
    if LblCDTime.Caption <> LblTime.Caption then LblCDTime.Caption := LblTime.Caption;
    if LblCDRemain.Caption <> S then LblCDRemain.Caption := S;
    Jog.CenterText := S;
  end;

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

{ Abspielkopf in allen Wellenformen bewegen.

  Warum nicht einfach Engine.PlayPos anzeigen? Die Position vom Audiogerät
  (waveOutGetPosition) kommt in Stufen: der Engine-Thread fragt sie nur nach
  jedem Puffer (~23 ms) ab, und viele Windows-Treiber zählen selbst nur in
  Blöcken weiter. Zusammen mit einem Timer, der auch nur ungefähr alle
  15/30 ms kommt, springt der Strich mal 1, mal 2 Stufen -> ruckelig.

  Darum läuft hier eine eigene, geglättete Uhr: Beim Abspielen wächst die
  Anzeigeposition gleichmässig mit der echten Zeit (44100 Frames pro
  Sekunde) und wird nur sanft an die Geräteposition herangezogen. Bei einem
  Sprung (Klick, Pfeiltasten, Stop) oder grosser Abweichung wird sie sofort
  übernommen. Pause: Geräteposition direkt.
  Loop: Läuft die Uhr über B hinaus, springt sie wie die Engine um die
  Loop-Länge zurück (sonst würde sie bei kurzen Loops hinterherhinken). }
procedure TMainForm.HeadTimerTick(Data: PtrInt);
var
  T, Dev, Diff, Old: Double;
  F: Single;
  i: Integer;
begin
  if (Engine = nil) or (Engine.TotalFrames <= 0) then Exit;
  T := NowSeconds;
  Dev := Engine.PlayPos;
  if Engine.Playing and not Engine.EndReached and FHeadRunning then
  begin
    Old := FHeadPos;
    FHeadPos := FHeadPos + (T - FHeadTime) * SAMPLE_RATE;
    if FLoopOn and (FLoopB > FLoopA) and (Old < FLoopB) and (FHeadPos >= FLoopB) then
      FHeadPos := FHeadPos - (FLoopB - FLoopA);
    Diff := Dev - FHeadPos;
    if Abs(Diff) > SAMPLE_RATE * 0.25 then
      FHeadPos := Dev                      // Sprung oder Aussetzer: übernehmen
    { sanft nachführen, kein Zurückspringen. Kleine Abweichungen (die Geräteposition
      kommt in ~23-ms-Stufen) nur ganz schwach, sonst schwankt das Tempo der
      Lupe sichtbar }
    else if Abs(Diff) < SAMPLE_RATE * 0.03 then
      FHeadPos := FHeadPos + Diff * 0.02
    else
      FHeadPos := FHeadPos + Diff * 0.08;
  end
  else
    FHeadPos := Dev;                       // Pause, Ende oder gerade gestartet
  FHeadRunning := Engine.Playing and not Engine.EndReached;
  FHeadTime := T;
  if FHeadPos < 0 then FHeadPos := 0;
  if FHeadPos > Engine.TotalFrames then FHeadPos := Engine.TotalFrames;

  { zeichnet nur neu, wenn sich der Strich um ein Pixel bewegt }
  F := FHeadPos / Engine.TotalFrames;
  WaveMaster.Position := F;
  for i := 1 to STEM_COUNT do Rows[i].Wave.Position := F;
  Zoom.Position := FHeadPos;
  if FView = vmCD then Jog.Position := FHeadPos;
end;

procedure TMainForm.KofiClick(Sender: TObject);
begin
  OpenURL(KOFI_URL);
end;

procedure TMainForm.KofiPaint(Sender: TObject);
begin
  PbKofi.Canvas.Font.Style := [fsBold];
  DrawKofiButton(PbKofi.Canvas, PbKofi.ClientRect, _('Kaffee spendieren'),
    FKofiHover, DJ_FOOTER, Screen.PixelsPerInch, Application.Icon);
end;

procedure TMainForm.KofiEnter(Sender: TObject);
begin
  FKofiHover := True;
  PbKofi.Invalidate;
end;

procedure TMainForm.KofiLeave(Sender: TObject);
begin
  FKofiHover := False;
  PbKofi.Invalidate;
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
        begin
          Rows[i].BtnSolo.Down := not Rows[i].BtnSolo.Down;
          ApplySolo(i, ssCtrl in Shift);   // Strg+Shift = dazunehmen
        end
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
    VK_LEFT, VK_RIGHT:
      begin
        if Key = VK_LEFT then i := -1 else i := 1;
        { Shift = auseinander: links bewegt A nach links, rechts B nach rechts.
          Strg = zusammen: rechts bewegt A nach rechts, links B nach links. }
        if ssShift in Shift then
        begin
          if i < 0 then NudgeMarker(1, -NudgeStep) else NudgeMarker(2, NudgeStep);
        end
        else if ssCtrl in Shift then
        begin
          if i > 0 then NudgeMarker(1, NudgeStep) else NudgeMarker(2, -NudgeStep);
        end
        else if FLoopOn and (FLoopA >= 0) and (FLoopB > FLoopA) then
          MoveLoop(i * NudgeStep)                                  // ganzer Loop
        else SeekRelative(i * 5);
        Key := 0;
      end;
    VK_HOME:  begin if Engine <> nil then Engine.SeekTo := 0; Key := 0; end;
    VK_W:
      begin
        { nur in der klassischen Ansicht: die Designs haben keine Umschaltung }
        if FView = vmWave then SetView(vmCompact)
        else if FView = vmCompact then SetView(vmWave);
        SaveViewSetting;
        Key := 0;
      end;
    VK_A:     begin SetLoopA; Key := 0; end;
    VK_B:     begin SetLoopB; Key := 0; end;
    VK_L:
      begin
        if ssShift in Shift then ClearLoop else ToggleLoop;
        Key := 0;
      end;
    VK_BACK:  begin ClearLoop; Key := 0; end;
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
    LblStatus.Caption := _('Breche Dekodieren ab ...');
    CanClose := False;
  end
  else
    CanClose := True;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  timeEndPeriod(1);
  Timer.Enabled := False;
  if Takt <> nil then
  begin
    Takt.Stoppen;
    FreeAndNil(Takt);
  end;
  UnloadFile;          // Thread beenden + Track-Ordner löschen
  ReleaseInstanceDir;  // Sperrdatei schliessen + Instanz-Ordner löschen
end;

end.
