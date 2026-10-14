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
  ============================================================================ }
unit wellenform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType, djcontrols;

const
  PEAK_BUCKETS = 4000;   // Auflösung der Hüllkurve (reicht für 4K-Breite)
  PEAK_TRACKS  = 5;      // 0 = Master, 1..4 = Stems

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
    Done : Boolean;      // vom Thread gesetzt, wenn alles fertig ist
    { RawFiles wie bei TStemEngine: [0] = Master, [1..4] = Stems }
    constructor Create(const RawFiles: array of string; TotalFrames: Int64);
  end;

  TSeekEvent = procedure(Sender: TObject; Fraction: Single) of object;

  { TWaveView }

  TWaveView = class(TGraphicControl)
  private
    FPeaks    : TPeakData;
    FScale    : Single;      // Verstärkung der Anzeige (gemeinsamer Massstab)
    FColor    : TColor;      // Farbe der Wellenform (Stemfarbe)
    FActive   : Boolean;     // False -> grau (Stem stumm / anderer Modus)
    FPosition : Single;      // Abspielkopf 0..1
    FHeadX    : Integer;     // zuletzt gezeichnete Pixel-Position des Kopfes
    FPlayed   : TBitmap;     // zwischengespeichert: gespielter Teil (hell)
    FRest     : TBitmap;     // zwischengespeichert: noch nicht gespielt (dunkel)
    FDirty    : Boolean;     // Bilder müssen neu berechnet werden
    FDragging : Boolean;
    FOnSeek   : TSeekEvent;
    procedure SetColor2(AValue: TColor);
    procedure SetActive(AValue: Boolean);
    procedure SetPosition(AValue: Single);
    procedure RenderCache;
    procedure DoSeekAt(X: Integer);
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
    property WaveColor: TColor read FColor write SetColor2;
    property Active: Boolean read FActive write SetActive;
    property Position: Single read FPosition write SetPosition;
    property OnSeek: TSeekEvent read FOnSeek write FOnSeek;
    property ShowHint;
  end;

{ Höchster Betrag (|Lo| oder |Hi|) einer Hüllkurve, für den Massstab }
function PeakMax(const P: TPeakData): Single;

implementation

const
  WAVE_BG = $00151312;   // Hintergrund der Spur  #121315 (etwas dunkler als die Zeile)

{ Mischt zwei Farben: A = 1 -> nur C1, A = 0 -> nur C2 }
function Blend(C1, C2: TColor; A: Single): TColor;
begin
  Result := RGBToColor(
    Round(Red(C1)   * A + Red(C2)   * (1 - A)),
    Round(Green(C1) * A + Green(C2) * (1 - A)),
    Round(Blue(C1)  * A + Blue(C2)  * (1 - A)));
end;

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
  SumSq: array of Double;
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
  FDirty := True;
  Invalidate;
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
  { Nur neu zeichnen, wenn sich der Kopf um mindestens ein Pixel bewegt }
  X := Round(FPosition * (Width - 1));
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
  X: Integer;
begin
  if FDirty or (FPlayed.Width <> Width) or (FPlayed.Height <> Height) then
    RenderCache;
  X := Round(FPosition * (Width - 1));
  FHeadX := X;
  { links vom Kopf: gespielt (hell), rechts: noch nicht gespielt (dunkel) }
  if X > 0 then
    Canvas.CopyRect(Rect(0, 0, X, Height), FPlayed.Canvas, Rect(0, 0, X, Height));
  Canvas.CopyRect(Rect(X, 0, Width, Height), FRest.Canvas, Rect(X, 0, Width, Height));
  { Rahmen }
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := DJ_BORDER;
  Canvas.Rectangle(0, 0, Width, Height);
  Canvas.Brush.Style := bsSolid;
  { Abspielkopf: 2 Pixel breiter roter Strich (nur wenn eine Datei geladen ist) }
  if FPeaks.Valid then
  begin
    Canvas.Brush.Color := DJ_PLAYHEAD;
    Canvas.FillRect(Max(0, X - 1), 0, Min(Width, X + 1), Height);
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
  end;
end;

procedure TWaveView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then DoSeekAt(X);
end;

procedure TWaveView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

end.
