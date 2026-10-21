{ ============================================================================
  wellenform.pas  -  Wellenform-Anzeige für den Elospeed StemPlayer

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Enthalten:
    TPeakThread  berechnet im Hintergrund aus den dekodierten .raw-Dateien
                 (16 Bit / Stereo, siehe stemengine.pas) eine verkleinerte
                 Hüllkurve: pro "Eimer" (Bucket) Minimum, Maximum und
                 mittlere Lautstärke (RMS). PEAK_BUCKETS Eimer pro Spur,
                 unabhängig von der Länge des Tracks.
    TWaveView    zeichnet diese Hüllkurve als Wellenform mit rotem
                 Abspielkopf. Klick oder Ziehen in die Wellenform meldet die
                 gewünschte Position über OnSeek (0..1) ans Hauptfenster.
                 Mit der rechten Maustaste zieht man einen Loop-Bereich auf
                 (OnLoopSelect). Ein gesetzter Loop wird grün hinterlegt.
    TZoomView    "Lupe": zeigt nur wenige Sekunden rund um den Abspielkopf
                 (der rote Strich steht in der Mitte, die Welle läuft durch),
                 mit Zeitraster. Darin lässt sich der Loop genau setzen:
                 rechte Maustaste ziehen (rastet am Raster ein, Shift =
                 frei), Marken A und B mit der linken Maustaste verschieben,
                 Mausrad zoomt. Grundlage ist eine feine Hüllkurve des
                 Originals (FINE_FRAMES Frames pro Eimer, ca. 3 ms).

  Warum ein eigener Thread?
    Ein 5-Minuten-Track hat pro Spur ca. 50 MB PCM. Alle 5 Spuren zu lesen
    dauert je nach Festplatte bis zu ca. 1 Sekunde. Im Thread kann die Musik
    sofort loslaufen, die Wellenformen erscheinen, sobald sie fertig sind.
    Das Hauptfenster fragt im Timer nach, ob der Thread fertig ist (Done).
    So braucht es weder Synchronize noch OnTerminate (keine Hänger beim
    Schliessen, wenn gleichzeitig auf den Thread gewartet wird).

  Warum schnell beim Zeichnen?
    Die Wellenform wird nur neu berechnet, wenn sich Grösse, Farbe oder
    Zustand ändern, und dann in zwei Bildern zwischengespeichert:
    "schon gespielt" (hell) und "noch nicht gespielt" (dunkel). Beim
    Abspielen wird nur noch links vom Abspielkopf das helle und rechts das
    dunkle Bild hineinkopiert und der Strich darübergezeichnet. Neu
    gezeichnet wird nur, wenn der Abspielkopf wirklich ein Pixel weiter ist.

  Farben: TColor ist $00BBGGRR (Blau zuerst!), nicht RGB.

  Versionen:
    1.0  (14.10.2026)  Erste Version (Testversion StemPlayer 1.5)
    1.1  (14.10.2026)  Flüssiger Abspielkopf: NowSeconds (genaue Uhr) und
                       Strich mit Kantenglättung in 1/4-Pixel-Schritten
    1.2  (21.10.2026)  Loop A-B: Bereich grün hinterlegt, Marken bei A und B,
                       Loop mit rechter Maustaste aufziehen (StemPlayer 1.6)
    1.3  (21.10.2026)  Lupe TZoomView mit Raster und verschiebbaren Marken,
                       feine Hüllkurve des Originals (TPeakThread.Fine)
  ============================================================================ }
unit wellenform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, djcontrols;

const
  PEAK_BUCKETS = 4000;   // Auflösung der Hüllkurve (reicht für 4K-Breite)
  PEAK_TRACKS  = 5;      // 0 = Master, 1..4 = Stems
  FINE_FRAMES  = 128;    // Frames pro Eimer der feinen Hüllkurve (~2,9 ms)
  WAVE_RATE    = 44100;  // Abtastrate der .raw-Dateien (wie stemengine)

type
  { Hüllkurve einer Spur. Werte -1..1 (bzw. 0..1 für Rms). }
  TPeakData = record
    Lo, Hi, Rms: array of Single;
    Valid: Boolean;
  end;

  { TPeakThread }

  TPeakThread = class(TThread)
  private
    FFiles: array[0..PEAK_TRACKS-1] of string;
    FTotalFrames: Int64;
    procedure CalcTrack(Idx: Integer);
  protected
    procedure Execute; override;
  public
    Peaks: array[0..PEAK_TRACKS-1] of TPeakData;
    Fine : TPeakData;    // feine Hüllkurve des Originals für die Lupe
    Done : Boolean;      // vom Thread gesetzt, wenn alles fertig ist
    { RawFiles wie bei TStemEngine: [0] = Master, [1..4] = Stems }
    constructor Create(const RawFiles: array of string; TotalFrames: Int64);
  end;

  TSeekEvent = procedure(Sender: TObject; Fraction: Single) of object;
  TLoopSelectEvent = procedure(Sender: TObject; AFrom, ATo: Single) of object;

  { TWaveView }

  TWaveView = class(TGraphicControl)
  private
    FPeaks    : TPeakData;
    FScale    : Single;      // Verstärkung der Anzeige (gemeinsamer Massstab)
    FColor    : TColor;      // Farbe der Wellenform (Stemfarbe)
    FActive   : Boolean;     // False -> grau (Stem stumm / anderer Modus)
    FPosition : Single;      // Abspielkopf 0..1
    FHeadX    : Integer;     // zuletzt gezeichnete Position des Kopfes in 1/4 Pixel
    FPlayed   : TBitmap;     // zwischengespeichert: gespielter Teil (hell)
    FRest     : TBitmap;     // zwischengespeichert: noch nicht gespielt (dunkel)
    FDirty    : Boolean;     // Bilder müssen neu berechnet werden
    FDragging : Boolean;
    FOnSeek   : TSeekEvent;
    FLoopA    : Single;      // Punkt A 0..1 (-1 = nicht gesetzt)
    FLoopB    : Single;      // Punkt B 0..1 (-1 = nicht gesetzt)
    FLoopOn   : Boolean;     // Loop aktiv (kräftiger hinterlegt)
    FSelecting: Boolean;     // rechte Maustaste: Loop-Bereich wird aufgezogen
    FSelFrom  : Integer;     // Pixel, an dem das Aufziehen begann
    FSelTo    : Integer;     // aktuelles Pixel beim Aufziehen
    FOnLoopSelect: TLoopSelectEvent;
    procedure SetColor2(AValue: TColor);
    procedure SetActive(AValue: Boolean);
    procedure SetPosition(AValue: Single);
    procedure RenderCache;
    procedure DoSeekAt(X: Integer);
    function  FracToX(F: Single): Integer;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Neue Hüllkurve setzen. AScale: Faktor, mit dem die Werte für die
      Anzeige multipliziert werden (1 / lautester Wert aller Stems). }
    procedure SetPeaks(const APeaks: TPeakData; AScale: Single);
    procedure ClearPeaks;
    { Loop anzeigen. A/B als Anteil 0..1, -1 = nicht gesetzt. }
    procedure SetLoop(AFrom, ATo: Single; AOn: Boolean);
    property WaveColor: TColor read FColor write SetColor2;
    property Active: Boolean read FActive write SetActive;
    property Position: Single read FPosition write SetPosition;
    property OnSeek: TSeekEvent read FOnSeek write FOnSeek;
    { rechte Maustaste gezogen: neuer Loop von AFrom bis ATo (0..1) }
    property OnLoopSelect: TLoopSelectEvent read FOnLoopSelect write FOnLoopSelect;
    property ShowHint;
  end;

  TFrameEvent = procedure(Sender: TObject; Frame: Int64) of object;
  TFrameRangeEvent = procedure(Sender: TObject; AFrom, ATo: Int64) of object;
  { Marke verschoben: Marker = 1 (A) oder 2 (B), Final = Maustaste losgelassen }
  TMarkerMoveEvent = procedure(Sender: TObject; Marker: Integer; Frame: Int64;
                               Final: Boolean) of object;

  { TZoomView - die Lupe }

  TZoomView = class(TGraphicControl)
  private
    FPeaks    : TPeakData;   // feine Hüllkurve (FINE_FRAMES pro Eimer)
    FScale    : Single;
    FTotal    : Int64;       // Länge des Tracks in Frames
    FPos      : Double;      // Abspielkopf in Frames (steht in der Mitte)
    FSpan     : Double;      // sichtbare Breite in Sekunden (Mausrad)
    FLoopA    : Int64;       // -1 = nicht gesetzt
    FLoopB    : Int64;
    FLoopOn   : Boolean;
    FDragMarker: Integer;    // 0 = nichts, 1 = A, 2 = B wird gezogen
    FDragFrame: Int64;       // zuletzt gemeldete Stelle der gezogenen Marke
    FSelecting: Boolean;     // rechte Maustaste: neuer Loop wird aufgezogen
    FSelFrom  : Int64;       // in Frames, weil die Welle beim Ziehen weiterläuft
    FSelTo    : Int64;
    FLastPx   : Integer;     // zuletzt gezeichnete Kopfposition (1/4 Pixel-Raster)
    FOnSeek   : TFrameEvent;
    FOnLoopSelect: TFrameRangeEvent;
    FOnMarkerMove: TMarkerMoveEvent;
    procedure SetPos(AValue: Double);
    function  FramesPerPx: Double;
    function  XToFrame(X: Integer): Double;
    function  FrameToX(F: Double): Integer;
    function  GridStep(out Major: Double): Double;
    function  SnapFrame(F: Double; Shift: TShiftState): Int64;
    function  MarkerAt(X: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function  DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
                           MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetPeaks(const APeaks: TPeakData; AScale: Single; ATotal: Int64);
    procedure ClearPeaks;
    procedure SetLoop(AFrom, ATo: Int64; AOn: Boolean);
    property Position: Double read FPos write SetPos;   // in Frames
    property Span: Double read FSpan;
    property OnSeek: TFrameEvent read FOnSeek write FOnSeek;
    property OnLoopSelect: TFrameRangeEvent read FOnLoopSelect write FOnLoopSelect;
    property OnMarkerMove: TMarkerMoveEvent read FOnMarkerMove write FOnMarkerMove;
    property ShowHint;
  end;

{ Höchster Betrag (|Lo| oder |Hi|) einer Hüllkurve, für den Massstab }
function PeakMax(const P: TPeakData): Single;

{ Genaue Uhr in Sekunden (Windows-Leistungszähler, Auflösung < 1 µs).
  GetTickCount wäre zu grob: es springt unter Windows in 15,6-ms-Stufen. }
function NowSeconds: Double;

implementation

const
  WAVE_BG = $00151312;   // Hintergrund der Spur  #121315 (etwas dunkler als die Zeile)
  LOOP_COLOR = DJ_GREEN; // Loop wie in Traktor grün

{ Mischt zwei Farben: A = 1 -> nur C1, A = 0 -> nur C2 }
function Blend(C1, C2: TColor; A: Single): TColor;
begin
  Result := RGBToColor(
    Round(Red(C1)   * A + Red(C2)   * (1 - A)),
    Round(Green(C1) * A + Green(C2) * (1 - A)),
    Round(Blue(C1)  * A + Blue(C2)  * (1 - A)));
end;

{$IFDEF WINDOWS}
function QueryPerformanceCounter(out Count: Int64): LongBool; stdcall;
  external 'kernel32.dll' name 'QueryPerformanceCounter';
function QueryPerformanceFrequency(out Freq: Int64): LongBool; stdcall;
  external 'kernel32.dll' name 'QueryPerformanceFrequency';
{$ENDIF}

function NowSeconds: Double;
{$IFDEF WINDOWS}
var C, F: Int64;
begin
  if QueryPerformanceFrequency(F) and (F > 0) and QueryPerformanceCounter(C) then
    Result := C / F
  else
    Result := GetTickCount64 / 1000;
end;
{$ELSE}
begin
  Result := GetTickCount64 / 1000;
end;
{$ENDIF}

function PeakMax(const P: TPeakData): Single;
var i: Integer;
begin
  Result := 0;
  if not P.Valid then Exit;
  for i := 0 to High(P.Lo) do
  begin
    if -P.Lo[i] > Result then Result := -P.Lo[i];
    if  P.Hi[i] > Result then Result :=  P.Hi[i];
  end;
end;

{ ============================================================================
  TPeakThread
  ============================================================================ }

constructor TPeakThread.Create(const RawFiles: array of string; TotalFrames: Int64);
var i: Integer;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FTotalFrames := TotalFrames;
  for i := 0 to PEAK_TRACKS - 1 do
  begin
    if i <= High(RawFiles) then FFiles[i] := RawFiles[i] else FFiles[i] := '';
    Peaks[i].Valid := False;
  end;
  Fine.Valid := False;
  Done := False;
  Start;
end;

{ Liest eine .raw-Datei einmal komplett durch und füllt die Eimer.
  Links und rechts werden zu Mono gemittelt (für die Anzeige reicht das). }
procedure TPeakThread.CalcTrack(Idx: Integer);
const
  CHUNK_FRAMES = 65536;          // 256 KB pro Lesevorgang
var
  F: TFileStream;
  Buf: array of SmallInt;
  SumSq, FineSq: array of Double;
  FineN, fb: Integer;
  Cnt: array of Integer;
  Got, n, k, b: Integer;
  Frame: Int64;
  V: Single;
  P: ^TPeakData;
begin
  P := @Peaks[Idx];
  if (FFiles[Idx] = '') or not FileExists(FFiles[Idx]) or (FTotalFrames <= 0) then Exit;
  SetLength(P^.Lo, PEAK_BUCKETS);
  SetLength(P^.Hi, PEAK_BUCKETS);
  SetLength(P^.Rms, PEAK_BUCKETS);
  SetLength(SumSq, PEAK_BUCKETS);
  SetLength(Cnt, PEAK_BUCKETS);
  for b := 0 to PEAK_BUCKETS - 1 do
  begin
    P^.Lo[b] := 0; P^.Hi[b] := 0; SumSq[b] := 0; Cnt[b] := 0;
  end;
  SetLength(Buf, CHUNK_FRAMES * 2);
  { Für das Original zusätzlich die feine Hüllkurve (Lupe) }
  FineN := 0;
  if Idx = 0 then
  begin
    FineN := (FTotalFrames + FINE_FRAMES - 1) div FINE_FRAMES;
    SetLength(Fine.Lo, FineN);
    SetLength(Fine.Hi, FineN);
    SetLength(Fine.Rms, FineN);
    SetLength(FineSq, FineN);
    for b := 0 to FineN - 1 do
    begin
      Fine.Lo[b] := 0; Fine.Hi[b] := 0; FineSq[b] := 0;
    end;
  end;

  { fmShareDenyNone: die Engine hat dieselbe Datei gleichzeitig offen }
  F := TFileStream.Create(FFiles[Idx], fmOpenRead or fmShareDenyNone);
  try
    Frame := 0;
    while (Frame < FTotalFrames) and not Terminated do
    begin
      Got := F.Read(Buf[0], CHUNK_FRAMES * 4) div 4;   // 4 Byte pro Frame
      if Got <= 0 then Break;
      for n := 0 to Got - 1 do
      begin
        if Frame >= FTotalFrames then Break;
        V := (Buf[n * 2] + Buf[n * 2 + 1]) / 65536;     // Mono, -1..1
        b := (Frame * PEAK_BUCKETS) div FTotalFrames;
        if V < P^.Lo[b] then P^.Lo[b] := V;
        if V > P^.Hi[b] then P^.Hi[b] := V;
        SumSq[b] := SumSq[b] + V * V;
        Inc(Cnt[b]);
        if FineN > 0 then
        begin
          fb := Frame div FINE_FRAMES;
          if V < Fine.Lo[fb] then Fine.Lo[fb] := V;
          if V > Fine.Hi[fb] then Fine.Hi[fb] := V;
          FineSq[fb] := FineSq[fb] + V * V;
        end;
        Inc(Frame);
      end;
    end;
  finally
    F.Free;
  end;
  if Terminated then Exit;
  for k := 0 to PEAK_BUCKETS - 1 do
    if Cnt[k] > 0 then P^.Rms[k] := Sqrt(SumSq[k] / Cnt[k])
    else P^.Rms[k] := 0;
  P^.Valid := True;
  if FineN > 0 then
  begin
    for k := 0 to FineN - 1 do
      Fine.Rms[k] := Sqrt(FineSq[k] / FINE_FRAMES);
    Fine.Valid := True;
  end;
end;

procedure TPeakThread.Execute;
var i: Integer;
begin
  { Stems zuerst (die sieht man am meisten), Master am Schluss }
  for i := 1 to PEAK_TRACKS - 1 do
  begin
    if Terminated then Break;
    try
      CalcTrack(i);
    except
      Peaks[i].Valid := False;   // z.B. Datei weg -> diese Spur ohne Wellenform
    end;
  end;
  if not Terminated then
  try
    CalcTrack(0);
  except
    Peaks[0].Valid := False;
  end;
  Done := True;
end;

{ ============================================================================
  TWaveView
  ============================================================================ }

constructor TWaveView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPlayed := TBitmap.Create;
  FRest := TBitmap.Create;
  FColor := DJ_TEXT;
  FActive := True;
  FScale := 1;
  FPosition := 0;
  FHeadX := -1;
  FLoopA := -1;
  FLoopB := -1;
  FDirty := True;
  Cursor := crHandPoint;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TWaveView.Destroy;
begin
  FPlayed.Free;
  FRest.Free;
  inherited Destroy;
end;

procedure TWaveView.SetPeaks(const APeaks: TPeakData; AScale: Single);
begin
  FPeaks := APeaks;
  FScale := AScale;
  FDirty := True;
  Invalidate;
end;

procedure TWaveView.ClearPeaks;
begin
  FPeaks.Valid := False;
  SetLength(FPeaks.Lo, 0);
  SetLength(FPeaks.Hi, 0);
  SetLength(FPeaks.Rms, 0);
  FPosition := 0;
  FLoopA := -1;
  FLoopB := -1;
  FLoopOn := False;
  FDirty := True;
  Invalidate;
end;

procedure TWaveView.SetLoop(AFrom, ATo: Single; AOn: Boolean);
begin
  if (AFrom = FLoopA) and (ATo = FLoopB) and (AOn = FLoopOn) then Exit;
  FLoopA := AFrom;
  FLoopB := ATo;
  FLoopOn := AOn;
  FDirty := True;    // der Hintergrund des Loop-Bereichs steckt in den Bildern
  Invalidate;
end;

function TWaveView.FracToX(F: Single): Integer;
begin
  Result := Round(F * (Width - 1));
end;

procedure TWaveView.SetColor2(AValue: TColor);
begin
  if FColor = AValue then Exit;
  FColor := AValue;
  FDirty := True;
  Invalidate;
end;

procedure TWaveView.SetActive(AValue: Boolean);
begin
  if FActive = AValue then Exit;
  FActive := AValue;
  FDirty := True;
  Invalidate;
end;

procedure TWaveView.SetPosition(AValue: Single);
var X: Integer;
begin
  if AValue < 0 then AValue := 0;
  if AValue > 1 then AValue := 1;
  FPosition := AValue;
  { Nur neu zeichnen, wenn sich der Kopf um mindestens 1/4 Pixel bewegt
    (der Strich wird mit Zwischenstufen gezeichnet, siehe Paint) }
  X := Round(FPosition * (Width - 1) * 4);
  if X <> FHeadX then Invalidate;
end;

procedure TWaveView.Resize;
begin
  inherited Resize;
  FDirty := True;
end;

{ Zeichnet beide Bilder (gespielt / nicht gespielt) neu.
  Pro Pixelspalte: dünner Strich Min..Max (Spitzen, etwas blasser) und
  darüber ein kräftigerer Strich für die mittlere Lautstärke (RMS). So sieht
  man Kick-Schläge und Gesangsphrasen deutlich, wie bei Traktor/Serato. }
procedure TWaveView.RenderCache;
var
  W, H, Mid, x, b, b0, b1: Integer;
  Lo, Hi, R, Amp: Single;
  CPeakOn, CRmsOn, CPeakOff, CRmsOff, Base: TColor;

  procedure Prepare(Bmp: TBitmap);
  begin
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := WAVE_BG;
    Bmp.Canvas.FillRect(0, 0, W, H);
    { Loop-Bereich grünlich hinterlegen: aktiv deutlich, ausgeschaltet nur
      angedeutet (man sieht, wo der gemerkte Loop liegt) }
    if (FLoopA >= 0) and (FLoopB > FLoopA) then
    begin
      if FLoopOn then Bmp.Canvas.Brush.Color := Blend(LOOP_COLOR, WAVE_BG, 0.16)
      else Bmp.Canvas.Brush.Color := Blend(LOOP_COLOR, WAVE_BG, 0.06);
      Bmp.Canvas.FillRect(FracToX(FLoopA), 0, FracToX(FLoopB) + 1, H);
    end;
    { feine Mittellinie, damit auch eine stille Spur als Spur erkennbar ist }
    Bmp.Canvas.Pen.Color := DJ_BORDER;
    Bmp.Canvas.Line(0, Mid, W, Mid);
  end;

  procedure VLine(Bmp: TBitmap; C: TColor; X, Y1, Y2: Integer);
  begin
    if Y2 < Y1 then Y2 := Y1;
    Bmp.Canvas.Pen.Color := C;
    Bmp.Canvas.Line(X, Y1, X, Y2 + 1);
  end;

begin
  FDirty := False;
  W := Max(1, Width);
  H := Max(1, Height);
  Mid := H div 2;
  Prepare(FPlayed);
  Prepare(FRest);
  if not FPeaks.Valid then Exit;

  if FActive then Base := FColor else Base := DJ_OFF;
  CPeakOn  := Blend(Base, WAVE_BG, 0.55);
  CRmsOn   := Base;
  CPeakOff := Blend(Base, WAVE_BG, 0.22);
  CRmsOff  := Blend(Base, WAVE_BG, 0.38);
  Amp := (H / 2 - 1) * FScale;

  for x := 0 to W - 1 do
  begin
    { Welche Eimer gehören zu dieser Pixelspalte? }
    b0 := (Int64(x) * PEAK_BUCKETS) div W;
    b1 := (Int64(x + 1) * PEAK_BUCKETS) div W;
    if b1 <= b0 then b1 := b0 + 1;
    if b1 > PEAK_BUCKETS then b1 := PEAK_BUCKETS;
    Lo := 0; Hi := 0; R := 0;
    for b := b0 to b1 - 1 do
    begin
      if FPeaks.Lo[b] < Lo then Lo := FPeaks.Lo[b];
      if FPeaks.Hi[b] > Hi then Hi := FPeaks.Hi[b];
      if FPeaks.Rms[b] > R then R := FPeaks.Rms[b];
    end;
    { RMS etwas angehoben, damit der "Körper" der Welle gut sichtbar ist }
    R := Min(R * 1.4, Max(Hi, -Lo));
    VLine(FPlayed, CPeakOn,  x, Mid - Round(Hi * Amp), Mid - Round(Lo * Amp));
    VLine(FPlayed, CRmsOn,   x, Mid - Round(R * Amp),  Mid + Round(R * Amp));
    VLine(FRest,   CPeakOff, x, Mid - Round(Hi * Amp), Mid - Round(Lo * Amp));
    VLine(FRest,   CRmsOff,  x, Mid - Round(R * Amp),  Mid + Round(R * Amp));
  end;
end;

procedure TWaveView.Paint;
var
  X, C: Integer;
  Xf, Fr: Single;
  LC: TColor;
begin
  if FDirty or (FPlayed.Width <> Width) or (FPlayed.Height <> Height) then
    RenderCache;
  Xf := FPosition * (Width - 1);
  FHeadX := Round(Xf * 4);
  X := Round(Xf);
  { links vom Kopf: gespielt (hell), rechts: noch nicht gespielt (dunkel) }
  if X > 0 then
    Canvas.CopyRect(Rect(0, 0, X, Height), FPlayed.Canvas, Rect(0, 0, X, Height));
  Canvas.CopyRect(Rect(X, 0, Width, Height), FRest.Canvas, Rect(X, 0, Width, Height));
  { Rahmen }
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := DJ_BORDER;
  Canvas.Rectangle(0, 0, Width, Height);
  Canvas.Brush.Style := bsSolid;
  { Loop: Marken bei A und B, bei aktivem Loop oben ein grüner Balken.
    Beim Aufziehen mit der rechten Maustaste wird der neue Bereich gezeigt. }
  if FSelecting then
  begin
    Canvas.Brush.Color := LOOP_COLOR;
    Canvas.FillRect(Min(FSelFrom, FSelTo), 0, Max(FSelFrom, FSelTo) + 1, 3);
    Canvas.FillRect(FSelFrom, 0, FSelFrom + 1, Height);
    Canvas.FillRect(FSelTo, 0, FSelTo + 1, Height);
  end
  else if FPeaks.Valid then
  begin
    if FLoopOn then LC := LOOP_COLOR else LC := Blend(LOOP_COLOR, WAVE_BG, 0.5);
    Canvas.Brush.Color := LC;
    if (FLoopA >= 0) and (FLoopB > FLoopA) and FLoopOn then
      Canvas.FillRect(FracToX(FLoopA), 0, FracToX(FLoopB) + 1, 3);
    if FLoopA >= 0 then
      Canvas.FillRect(FracToX(FLoopA), 0, FracToX(FLoopA) + 1, Height);
    if FLoopB >= 0 then
      Canvas.FillRect(FracToX(FLoopB), 0, FracToX(FLoopB) + 1, Height);
  end;
  { Abspielkopf: 2 Pixel breiter roter Strich (nur wenn eine Datei geladen ist).
    Er steht genau bei Xf-1 .. Xf+1, also meist zwischen zwei Pixeln. Die
    beiden Randspalten bekommen darum nur so viel Rot, wie der Strich sie
    bedeckt (Kantenglättung). So wandert er auch bei langen Tracks, wo er nur
    alle paar hundert Millisekunden ein ganzes Pixel weiterkommt, gleitend
    statt in sichtbaren Sprüngen. }
  if FPeaks.Valid then
  begin
    C := Trunc(Xf - 1);          // erste (teilweise) bedeckte Spalte
    Fr := (Xf - 1) - C;          // 0..1: wie weit der Strich in sie hineinragt
    if (C >= 0) and (C < Width) then
    begin
      Canvas.Brush.Color := Blend(DJ_PLAYHEAD, WAVE_BG, 1 - Fr);
      Canvas.FillRect(C, 0, C + 1, Height);
    end;
    if (C + 1 >= 0) and (C + 1 < Width) then
    begin
      Canvas.Brush.Color := DJ_PLAYHEAD;
      Canvas.FillRect(C + 1, 0, C + 2, Height);
    end;
    if (Fr > 0.02) and (C + 2 >= 0) and (C + 2 < Width) then
    begin
      Canvas.Brush.Color := Blend(DJ_PLAYHEAD, WAVE_BG, Fr);
      Canvas.FillRect(C + 2, 0, C + 3, Height);
    end;
  end;
end;

procedure TWaveView.DoSeekAt(X: Integer);
begin
  if not FPeaks.Valid or (Width < 2) then Exit;
  if X < 0 then X := 0;
  if X > Width - 1 then X := Width - 1;
  FPosition := X / (Width - 1);
  Invalidate;
  if Assigned(FOnSeek) then FOnSeek(Self, FPosition);
end;

procedure TWaveView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    DoSeekAt(X);
  end
  else if (Button = mbRight) and FPeaks.Valid and (Width >= 2) then
  begin
    FSelecting := True;
    FSelFrom := EnsureRange(X, 0, Width - 1);
    FSelTo := FSelFrom;
    Invalidate;
  end;
end;

procedure TWaveView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then DoSeekAt(X);
  if FSelecting then
  begin
    FSelTo := EnsureRange(X, 0, Width - 1);
    Invalidate;
  end;
end;

procedure TWaveView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then FDragging := False;
  if (Button = mbRight) and FSelecting then
  begin
    FSelecting := False;
    FSelTo := EnsureRange(X, 0, Width - 1);
    Invalidate;
    { Nur ein Klick ohne Ziehen (weniger als 3 Pixel) setzt keinen Loop }
    if (Abs(FSelTo - FSelFrom) >= 3) and Assigned(FOnLoopSelect) then
      FOnLoopSelect(Self, Min(FSelFrom, FSelTo) / (Width - 1),
                          Max(FSelFrom, FSelTo) / (Width - 1));
  end;
end;

{ ============================================================================
  TZoomView - Lupe
  ============================================================================ }

const
  ZOOM_MIN_SPAN = 1;     // stärkste Vergrösserung: 1 Sekunde über die ganze Breite
  ZOOM_MAX_SPAN = 60;    // schwächste: 1 Minute
  ZOOM_DEF_SPAN = 8;     // Start: 8 Sekunden
  MARKER_GRAB   = 5;     // so nah (Pixel) muss man eine Marke treffen
  { Raster-Paare (fein, grob) in Sekunden. Gewählt wird das feinste, bei dem
    die feinen Linien noch mindestens 8 Pixel auseinander liegen. }
  GRID_FINE  : array[0..5] of Double = (0.01, 0.05, 0.1, 0.5, 1, 5);
  GRID_MAJOR : array[0..5] of Double = (0.1,  0.5,  1,   5,   10, 30);

{ Zeit für die Rasterbeschriftung, z.B. 1:30.5 oder 1:30.25 }
function ZoomTimeText(Sec: Double; Fine: Boolean): string;
var
  M: Integer;
  S: Double;
begin
  if Sec < 0 then Sec := 0;
  M := Trunc(Sec) div 60;
  S := Sec - M * 60;
  if Fine then Result := Format('%.2f', [S]) else Result := Format('%.1f', [S]);
  if S < 10 then Result := '0' + Result;      // 1:05.3 statt 1:5.3
  Result := IntToStr(M) + ':' + StringReplace(Result, ',', '.', []);
end;

constructor TZoomView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSpan := ZOOM_DEF_SPAN;
  FScale := 1;
  FLoopA := -1;
  FLoopB := -1;
  FLastPx := MaxInt;
  Cursor := crHandPoint;
  ControlStyle := ControlStyle + [csOpaque];
end;

procedure TZoomView.SetPeaks(const APeaks: TPeakData; AScale: Single; ATotal: Int64);
begin
  FPeaks := APeaks;
  FScale := AScale;
  FTotal := ATotal;
  Invalidate;
end;

procedure TZoomView.ClearPeaks;
begin
  FPeaks.Valid := False;
  SetLength(FPeaks.Lo, 0);
  SetLength(FPeaks.Hi, 0);
  SetLength(FPeaks.Rms, 0);
  FTotal := 0;
  FPos := 0;
  FLoopA := -1;
  FLoopB := -1;
  FLoopOn := False;
  FDragMarker := 0;
  FSelecting := False;
  Invalidate;
end;

procedure TZoomView.SetLoop(AFrom, ATo: Int64; AOn: Boolean);
begin
  if (AFrom = FLoopA) and (ATo = FLoopB) and (AOn = FLoopOn) then Exit;
  FLoopA := AFrom;
  FLoopB := ATo;
  FLoopOn := AOn;
  Invalidate;
end;

procedure TZoomView.SetPos(AValue: Double);
var Px: Integer;
begin
  FPos := AValue;
  { Neu zeichnen, sobald sich die Welle um 1/4 Pixel verschoben hat }
  Px := Round(FPos / FramesPerPx * 4);
  if Px <> FLastPx then
  begin
    FLastPx := Px;
    Invalidate;
  end;
end;

function TZoomView.FramesPerPx: Double;
begin
  Result := FSpan * WAVE_RATE / Max(1, Width);
end;

function TZoomView.XToFrame(X: Integer): Double;
begin
  Result := FPos + (X - Width / 2) * FramesPerPx;
end;

function TZoomView.FrameToX(F: Double): Integer;
begin
  Result := Round(Width / 2 + (F - FPos) / FramesPerPx);
end;

{ Rasterabstand (fein) in Sekunden, Major = grobes Raster mit Beschriftung }
function TZoomView.GridStep(out Major: Double): Double;
var
  i: Integer;
  PxPerSec: Double;
begin
  PxPerSec := WAVE_RATE / FramesPerPx;
  for i := 0 to High(GRID_FINE) do
    if GRID_FINE[i] * PxPerSec >= 8 then
    begin
      Major := GRID_MAJOR[i];
      Exit(GRID_FINE[i]);
    end;
  Major := GRID_MAJOR[High(GRID_MAJOR)];
  Result := GRID_FINE[High(GRID_FINE)];
end;

{ Frame auf das feine Raster runden. Mit Shift: frei (auf den Frame genau). }
function TZoomView.SnapFrame(F: Double; Shift: TShiftState): Int64;
var
  Step, Major: Double;
begin
  if ssShift in Shift then
    Result := Round(F)
  else
  begin
    Step := GridStep(Major) * WAVE_RATE;
    Result := Round(Round(F / Step) * Step);
  end;
  if Result < 0 then Result := 0;
  if (FTotal > 0) and (Result > FTotal) then Result := FTotal;
end;

{ Welche Marke liegt unter X? 1 = A, 2 = B, 0 = keine }
function TZoomView.MarkerAt(X: Integer): Integer;
begin
  Result := 0;
  if (FLoopB >= 0) and (Abs(X - FrameToX(FLoopB)) <= MARKER_GRAB) then Result := 2
  else if (FLoopA >= 0) and (Abs(X - FrameToX(FLoopA)) <= MARKER_GRAB) then Result := 1;
end;

procedure TZoomView.Paint;
var
  W, H, Mid, x, b, b0, b1, xa, xb, X0, Tw: Integer;
  Lo, Hi, R, Amp, Fpp, Step, Major, T, T0, T1, Fr: Double;
  F0, F1: Double;
  CWave, CRms, CWaveOff, CRmsOff, LC: TColor;
  Played: Boolean;
  Txt: string;

  procedure Flag(XPos: Integer; const Letter: string);
  begin
    if (XPos < -12) or (XPos > W + 12) then Exit;
    Canvas.Brush.Color := LC;
    Canvas.FillRect(XPos - 1, 0, XPos + 1, H);
    Canvas.FillRect(XPos - 1, 0, XPos + 12, 13);
    Canvas.Font.Color := WAVE_BG;
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(XPos + 2, 0, Letter);
    Canvas.Brush.Style := bsSolid;
    Canvas.Font.Style := [];
  end;

begin
  W := Width;
  H := Height;
  Mid := H div 2;
  Fpp := FramesPerPx;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 7;

  { Hintergrund, Loop-Bereich grünlich }
  Canvas.Brush.Color := WAVE_BG;
  Canvas.FillRect(0, 0, W, H);
  if (FLoopA >= 0) and (FLoopB > FLoopA) then
  begin
    if FLoopOn then Canvas.Brush.Color := Blend(LOOP_COLOR, WAVE_BG, 0.16)
    else Canvas.Brush.Color := Blend(LOOP_COLOR, WAVE_BG, 0.06);
    xa := Max(0, FrameToX(FLoopA));
    xb := Min(W, FrameToX(FLoopB));
    if xb > xa then Canvas.FillRect(xa, 0, xb, H);
  end;
  if not FPeaks.Valid or (FTotal <= 0) then
  begin
    Canvas.Pen.Color := DJ_BORDER;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(0, 0, W, H);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;

  { Raster: feine Linien dunkel, grobe heller mit Zeit }
  Step := GridStep(Major);
  T0 := XToFrame(0) / WAVE_RATE;
  T1 := XToFrame(W) / WAVE_RATE;
  T := Floor(T0 / Step) * Step;
  while T <= T1 do
  begin
    if (T >= 0) and (T * WAVE_RATE <= FTotal) then
    begin
      x := FrameToX(T * WAVE_RATE);
      { grobe Linie, wenn T ein Vielfaches von Major ist (mit Rundungstoleranz) }
      Fr := T / Major;
      if Abs(Fr - Round(Fr)) < 0.001 then
      begin
        Canvas.Brush.Color := $00403A36;
        Canvas.FillRect(x, 0, x + 1, H);
        Txt := ZoomTimeText(T, Major < 1);
        Canvas.Font.Color := DJ_DIM;
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(x + 3, H - 13, Txt);
        Canvas.Brush.Style := bsSolid;
      end
      else
      begin
        Canvas.Brush.Color := $00262321;
        Canvas.FillRect(x, 0, x + 1, H);
      end;
    end;
    T := T + Step;
  end;

  { Welle: gespielter Teil (links von der Mitte) hell, Rest gedämpft }
  CWave := Blend($00D0D0D0, WAVE_BG, 0.55);
  CRms := $00D0D0D0;
  CWaveOff := Blend($00D0D0D0, WAVE_BG, 0.22);
  CRmsOff := Blend($00D0D0D0, WAVE_BG, 0.40);
  Amp := (H / 2 - 2) * FScale;
  X0 := W div 2;
  for x := 0 to W - 1 do
  begin
    F0 := XToFrame(x);
    F1 := F0 + Fpp;
    if (F1 <= 0) or (F0 >= FTotal) then Continue;
    b0 := Floor(F0 / FINE_FRAMES);
    b1 := Floor(F1 / FINE_FRAMES);
    if b1 <= b0 then b1 := b0 + 1;
    if b0 < 0 then b0 := 0;
    if b1 > Length(FPeaks.Lo) then b1 := Length(FPeaks.Lo);
    Lo := 0; Hi := 0; R := 0;
    for b := b0 to b1 - 1 do
    begin
      if FPeaks.Lo[b] < Lo then Lo := FPeaks.Lo[b];
      if FPeaks.Hi[b] > Hi then Hi := FPeaks.Hi[b];
      if FPeaks.Rms[b] > R then R := FPeaks.Rms[b];
    end;
    R := Min(R * 1.4, Max(Hi, -Lo));
    Played := x < X0;
    if Played then Canvas.Pen.Color := CWave else Canvas.Pen.Color := CWaveOff;
    Canvas.Line(x, Mid - Round(Hi * Amp), x, Mid - Round(Lo * Amp) + 1);
    if Played then Canvas.Pen.Color := CRms else Canvas.Pen.Color := CRmsOff;
    Canvas.Line(x, Mid - Round(R * Amp), x, Mid + Round(R * Amp) + 1);
  end;

  { Neuer Loop beim Aufziehen mit der rechten Maustaste }
  LC := LOOP_COLOR;
  if FSelecting then
  begin
    xa := FrameToX(Min(FSelFrom, FSelTo));
    xb := FrameToX(Max(FSelFrom, FSelTo));
    Canvas.Brush.Color := LC;
    Canvas.FillRect(xa, 0, xb + 1, 3);
    Flag(xa, 'A');
    Flag(xb, 'B');
    { Länge anzeigen }
    Txt := Format('%.2f s', [Abs(FSelTo - FSelFrom) / WAVE_RATE]);
    Canvas.Font.Color := LC;
    Canvas.Brush.Style := bsClear;
    Tw := Canvas.TextWidth(Txt);
    Canvas.TextOut(Max(2, Min(W - Tw - 2, (xa + xb - Tw) div 2)), 4, Txt);
    Canvas.Brush.Style := bsSolid;
  end
  else
  begin
    if not FLoopOn then LC := Blend(LOOP_COLOR, WAVE_BG, 0.6);
    if (FLoopA >= 0) and (FLoopB > FLoopA) and FLoopOn then
    begin
      Canvas.Brush.Color := LC;
      Canvas.FillRect(Max(0, FrameToX(FLoopA)), 0, Min(W, FrameToX(FLoopB) + 1), 3);
    end;
    if FLoopA >= 0 then Flag(FrameToX(FLoopA), 'A');
    if FLoopB >= 0 then Flag(FrameToX(FLoopB), 'B');
  end;

  { Abspielkopf in der Mitte }
  Canvas.Brush.Color := DJ_PLAYHEAD;
  Canvas.FillRect(X0 - 1, 0, X0 + 1, H);

  { Rahmen }
  Canvas.Pen.Color := DJ_BORDER;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, W, H);
  Canvas.Brush.Style := bsSolid;
end;

procedure TZoomView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var F: Double;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if not FPeaks.Valid or (FTotal <= 0) then Exit;
  if Button = mbLeft then
  begin
    { Marke getroffen -> ziehen, sonst an diese Stelle springen }
    FDragMarker := MarkerAt(X);
    if FDragMarker = 1 then FDragFrame := FLoopA
    else if FDragMarker = 2 then FDragFrame := FLoopB
    else
    begin
      F := XToFrame(X);
      if F < 0 then F := 0;
      if F > FTotal - 1 then F := FTotal - 1;
      if Assigned(FOnSeek) then FOnSeek(Self, Round(F));
    end;
  end
  else if Button = mbRight then
  begin
    FSelecting := True;
    FSelFrom := SnapFrame(XToFrame(X), Shift);
    FSelTo := FSelFrom;
    Invalidate;
  end;
end;

procedure TZoomView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragMarker <> 0 then
  begin
    FDragFrame := SnapFrame(XToFrame(X), Shift);
    if Assigned(FOnMarkerMove) then
      FOnMarkerMove(Self, FDragMarker, FDragFrame, False);
  end
  else if FSelecting then
  begin
    FSelTo := SnapFrame(XToFrame(X), Shift);
    Invalidate;
  end
  else if MarkerAt(X) <> 0 then
    Cursor := crSizeWE          // zeigt: diese Marke lässt sich verschieben
  else
    Cursor := crHandPoint;
end;

procedure TZoomView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var M: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  { Beim Loslassen gilt die zuletzt angezeigte Stelle. Neu rechnen wäre
    falsch: beim Abspielen läuft die Welle unter der stillen Maus weiter. }
  if (Button = mbLeft) and (FDragMarker <> 0) then
  begin
    M := FDragMarker;
    FDragMarker := 0;
    if Assigned(FOnMarkerMove) then
      FOnMarkerMove(Self, M, FDragFrame, True);
  end;
  if (Button = mbRight) and FSelecting then
  begin
    FSelecting := False;
    Invalidate;
    if (FSelTo <> FSelFrom) and Assigned(FOnLoopSelect) then
      FOnLoopSelect(Self, Min(FSelFrom, FSelTo), Max(FSelFrom, FSelTo));
  end;
end;

{ Mausrad: nach oben = näher heran (weniger Sekunden), nach unten = weiter weg }
function TZoomView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then FSpan := FSpan / 1.5
  else if WheelDelta < 0 then FSpan := FSpan * 1.5;
  if FSpan < ZOOM_MIN_SPAN then FSpan := ZOOM_MIN_SPAN;
  if FSpan > ZOOM_MAX_SPAN then FSpan := ZOOM_MAX_SPAN;
  FLastPx := MaxInt;
  Invalidate;
end;

end.
