{ ============================================================================
  designviews.pas  -  Steuerelemente für die Ansichten "CD-Player" und
                      "Plattenspieler" des Elospeed StemPlayer

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Die beiden Ansichten zeigen dieselben Funktionen wie die normale Ansicht,
  nur in einem anderen Look (siehe Design-Entwürfe 6 und 7). Die meisten
  Bedienelemente (Fader, Mute/Solo, Wellenformen, Lupe, Loop-Knöpfe) sind
  dieselben Objekte wie in der normalen Ansicht; das Hauptfenster setzt sie
  beim Umschalten nur an einen anderen Platz (playerform.PlaceCtl).
  Neu sind nur die Teile, die es vorher nicht gab:

    TStemPad     grosser Pad-Knopf in der Stemfarbe (CD-Player: Mute/Solo)
    TJogWheel    Jogwheel des CD-Players. Der blaue Ring zeigt die Restzeit,
                 der Strich dreht sich mit der Musik. Mit der Maus drehen =
                 Scrubbing (Ton wie beim Ziehen der Welle in der Lupe).
    TTurntable   Plattenteller: jeder Stem als Wellenform-Ring rund um die
                 Platte, weisser Zeiger = aktuelle Stelle, der Tonarm wandert
                 von aussen nach innen. Platte mit der Maus drehen = Scrubbing,
                 Klick auf einen Ring = an diese Stelle springen.

  Kantenglättung: Windows zeichnet Kreise und schräge Linien ohne
  Kantenglättung (treppig). Darum werden die unveränderlichen Teile (Rand,
  Ringe, Etikett) einmal in doppelter Grösse vorgezeichnet und mit
  StretchBlt im Modus HALFTONE weich verkleinert (Downsample). Bei jedem
  Bild wird nur noch dieses fertige Bild kopiert und die beweglichen Teile
  (Zeiger, Tonarm, Zeit) darüber gezeichnet.

  Wichtig (siehe Entwicklungslog StemPlayer 1.6): Die Bilder werden NICHT
  in Resize verworfen. Das LCL schickt Resize auch ohne Grössenänderung,
  z. B. wenn irgendwo ein Label seinen Text ändert. Paint vergleicht
  stattdessen die Grösse des vorgezeichneten Bildes.

  Farben: TColor ist $00BBGGRR (Blau zuerst!), nicht RGB.
  ============================================================================ }
unit designviews;

{$mode objfpc}{$H+}

interface

uses
  { Windows zuerst: sonst überdeckt Windows.TBitmap das TBitmap aus Graphics }
  Windows, Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  LazUTF8, djcontrols, wellenform;

const
  SS = 2;                 // Kantenglättung: so viel grösser wird vorgezeichnet
  FRAMES_33 = 79380;      // 33 1/3 U/min: eine Umdrehung = 1,8 s bei 44,1 kHz
  FRAMES_45 = 58800;      // 45 U/min: eine Umdrehung = 1,33 s
  CD_BLUE   = $00FF8A3D;  // Ring des Jogwheels       #3D8AFF
  CD_ORANGE = $002EA8FF;  // CUE-Knopf                #FFA82E
  DISPLAY_BG = $00110F0E; // Display des CD-Players   #0E0F11

type
  { ---------- Pad-Knopf in der Stemfarbe ---------- }
  TStemPad = class(TGraphicControl)
  private
    FStemColor: TColor;   // Farbe des Stems
    FSubText  : string;   // kleine zweite Zeile (z. B. "STUMM")
    FLit      : Boolean;  // True = leuchtet (gefüllt), False = nur Rahmen
    FDim      : Boolean;  // True = grau (Modus Original / Rest)
    FPressed  : Boolean;  // Maustaste gerade gedrückt
    procedure SetStemColor(AValue: TColor);
    procedure SetSubText(const AValue: string);
    procedure SetLit(AValue: Boolean);
    procedure SetDim(AValue: Boolean);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    property StemColor: TColor read FStemColor write SetStemColor;
    property SubText: string read FSubText write SetSubText;
    property Lit: Boolean read FLit write SetLit;
    property Dim: Boolean read FDim write SetDim;
    property Caption;
    property ShowHint;
    property OnClick;
  end;

  { ---------- Jogwheel des CD-Players ---------- }
  TJogWheel = class(TGraphicControl)
  private
    FPos      : Double;   // aktuelle Stelle in Frames
    FTotal    : Int64;    // Länge des Tracks in Frames
    FBackColor: TColor;   // Farbe der Fläche dahinter
    FCenterCaption: string;  // kleine Zeile in der Mitte ("REST")
    FCenterText: string;     // grosse Zeile in der Mitte ("-00:22")
    FBack     : TBitmap;  // vorgezeichnet: Rand, Teller, Ring
    FBuf      : TBitmap;  // Zwischenbild für flackerfreies Zeichnen
    FArcQ     : Integer;  // Länge des Rings, mit der FBack gezeichnet ist (1/2 Grad)
    FAngleQ   : Integer;  // zuletzt gezeichneter Drehwinkel (1/2 Grad)
    { Drehen mit der Maus }
    FArmed    : Boolean;  // linke Taste auf dem Rad gedrückt
    FDragging : Boolean;  // wird gerade gedreht (Scrubbing läuft)
    FLastAng  : Double;   // Mauswinkel beim letzten MouseMove (Grad)
    FAccum    : Double;   // seit Beginn gedrehte Grad (vorzeichenbehaftet)
    FDownPos  : Double;   // Stelle in Frames beim Beginn des Drehens
    FOnScrub  : TScrubEvent;
    procedure SetPos(AValue: Double);
    procedure SetTotal(AValue: Int64);
    procedure SetCenterText(const AValue: string);
    procedure SetCenterCaption(const AValue: string);
    function  ArcQuant: Integer;
    function  AngleQuant: Integer;
    procedure RenderBack;
    function  AngleAt(X, Y: Integer): Double;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Position: Double read FPos write SetPos;   // in Frames
    property Total: Int64 read FTotal write SetTotal;
    property BackColor: TColor read FBackColor write FBackColor;
    property CenterCaption: string read FCenterCaption write SetCenterCaption;
    property CenterText: string read FCenterText write SetCenterText;
    property OnScrub: TScrubEvent read FOnScrub write FOnScrub;
    property ShowHint;
  end;

  { ---------- Plattenteller mit Stem-Ringen ---------- }
  TTurntable = class(TGraphicControl)
  private
    FPeaks    : array[1..4] of TPeakData;   // Hüllkurven der 4 Stems
    FScale    : Single;                     // gemeinsamer Massstab (wie die Wellenformen)
    FColors   : array[1..4] of TColor;      // Stemfarben
    FActive   : array[1..4] of Boolean;     // hörbar (sonst grau)
    FPos      : Double;   // aktuelle Stelle in Frames
    FTotal    : Int64;    // Länge des Tracks in Frames
    FFramesPerRev: Integer;  // Frames pro Umdrehung (33 oder 45 U/min)
    FTitle    : string;   // Titel auf dem Etikett
    FTimeText : string;   // Zeit auf dem Etikett ("00:45 / 01:07")
    FLoopA    : Single;   // Loop-Punkt A als Anteil 0..1 (-1 = nicht gesetzt)
    FLoopB    : Single;   // Loop-Punkt B als Anteil 0..1 (-1 = nicht gesetzt)
    FLoopOn   : Boolean;  // Loop aktiv (kräftig grün, sonst gedämpft)
    FBackColor: TColor;
    FBack     : TBitmap;  // vorgezeichnet: Teller, Rillen, Ringe, Etikett
    FBuf      : TBitmap;
    FDirty    : Boolean;  // FBack neu zeichnen (Ringe, Farben, Titel geändert)
    FHandQ, FSpinQ, FArmQ: Integer;   // zuletzt gezeichnete Lage von Zeiger, Etikett, Tonarm
    { Drehen mit der Maus }
    FArmed    : Boolean;
    FDragging : Boolean;
    FLastAng  : Double;
    FAccum    : Double;
    FDownPos  : Double;
    FOnScrub  : TScrubEvent;
    FOnSeek   : TSeekEvent;
    procedure SetPos(AValue: Double);
    procedure SetTotal(AValue: Int64);
    procedure SetTitle(const AValue: string);
    procedure SetTimeText(const AValue: string);
    procedure SetFramesPerRev(AValue: Integer);
    procedure Geometry(out CX, CY, RPlatter, RRecord, RLabel: Double);
    procedure RingRadius(Idx: Integer; out RMid, RHalf: Double);
    function  Fraction: Double;
    procedure StylusRadius(out RS: Double);
    procedure RenderBack;
    function  AngleAt(X, Y: Integer): Double;
    function  RadiusAt(X, Y: Integer): Double;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Hüllkurve eines Stems (1..4) setzen. AScale wie bei TWaveView.SetPeaks }
    procedure SetStemPeaks(Idx: Integer; const APeaks: TPeakData; AScale: Single);
    procedure ClearPeaks;
    { Farbe und Zustand eines Rings (hörbar = Stemfarbe, sonst grau) }
    procedure SetRing(Idx: Integer; AColor: TColor; AActive: Boolean);
    { Loop als grüner Bogen am Rand der Platte. A/B als Anteil 0..1, -1 = nicht gesetzt }
    procedure SetLoop(AFrom, ATo: Single; AOn: Boolean);
    property Position: Double read FPos write SetPos;   // in Frames
    property Total: Int64 read FTotal write SetTotal;
    property FramesPerRev: Integer read FFramesPerRev write SetFramesPerRev;
    property Title: string read FTitle write SetTitle;
    property TimeText: string read FTimeText write SetTimeText;
    property BackColor: TColor read FBackColor write FBackColor;
    property OnScrub: TScrubEvent read FOnScrub write FOnScrub;
    property OnSeek: TSeekEvent read FOnSeek write FOnSeek;
    property ShowHint;
  end;

implementation

{ ============================================================================
  Hilfsfunktionen
  ============================================================================ }

{ Kreis um (CX, CY) mit Radius R (mit aktuellem Stift und Pinsel) }
procedure Circle(C: TCanvas; CX, CY, R: Double);
begin
  C.Ellipse(Round(CX - R), Round(CY - R), Round(CX + R) + 1, Round(CY + R) + 1);
end;

{ Linie vom Radius R1 bis R2 in Richtung Winkel A (Grad, 0 = oben, im Uhrzeigersinn) }
procedure RadialLine(C: TCanvas; CX, CY, A, R1, R2: Double);
var S, K: Double;
begin
  SinCos(DegToRad(A), S, K);
  C.Line(Round(CX + S * R1), Round(CY - K * R1), Round(CX + S * R2), Round(CY - K * R2));
end;

{ Punkt auf dem Kreis mit Radius R in Richtung Winkel A (wie RadialLine) }
function PolarPoint(CX, CY, A, R: Double): TPoint;
var S, K: Double;
begin
  SinCos(DegToRad(A), S, K);
  Result := Point(Round(CX + S * R), Round(CY - K * R));
end;

{ Winkel von (CX, CY) zum Punkt (X, Y): 0 = oben, im Uhrzeigersinn, 0..360 }
function PointAngle(CX, CY: Double; X, Y: Integer): Double;
begin
  Result := RadToDeg(ArcTan2(X - CX, CY - Y));
  if Result < 0 then Result := Result + 360;
end;

{ Unterschied zweier Winkel, -180..180 (über die 0 hinweg richtig) }
function AngleDiff(A, B: Double): Double;
begin
  Result := A - B;
  while Result > 180 do Result := Result - 360;
  while Result < -180 do Result := Result + 360;
end;

{ Doppelt grosses Bild weich auf die Grösse von Small verkleinern }
procedure Downsample(Big, Small: TBitmap);
var DC: HDC;
begin
  DC := Small.Canvas.Handle;
  SetStretchBltMode(DC, HALFTONE);
  SetBrushOrgEx(DC, 0, 0, nil);   // nötig nach HALFTONE (laut Windows-Doku)
  StretchBlt(DC, 0, 0, Small.Width, Small.Height,
             Big.Canvas.Handle, 0, 0, Big.Width, Big.Height, SRCCOPY);
end;

{ Text waagrecht zentriert um CX ausgeben (Oberkante Y) }
procedure DrawCentered(C: TCanvas; CX, Y: Integer; const S: string);
begin
  C.TextOut(CX - C.TextWidth(S) div 2, Y, S);
end;

{ ============================================================================
  TStemPad
  ============================================================================ }

constructor TStemPad.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { wie TDJButton: kein Doppelklick, sonst geht jeder zweite schnelle Klick verloren }
  ControlStyle := ControlStyle - [csDoubleClicks];
  FStemColor := DJ_DIM;
  SetInitialBounds(0, 0, 120, 52);
end;

procedure TStemPad.SetStemColor(AValue: TColor);
begin
  if FStemColor = AValue then Exit;
  FStemColor := AValue;
  Invalidate;
end;

procedure TStemPad.SetSubText(const AValue: string);
begin
  if FSubText = AValue then Exit;
  FSubText := AValue;
  Invalidate;
end;

procedure TStemPad.SetLit(AValue: Boolean);
begin
  if FLit = AValue then Exit;
  FLit := AValue;
  Invalidate;
end;

procedure TStemPad.SetDim(AValue: Boolean);
begin
  if FDim = AValue then Exit;
  FDim := AValue;
  Invalidate;
end;

procedure TStemPad.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TStemPad.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TStemPad.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FPressed := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TStemPad.MouseLeave;
begin
  inherited MouseLeave;
  FPressed := False;
  Invalidate;
end;

procedure TStemPad.Paint;
var
  R: TRect;
  C, Bg, Bd, Fg, Fg2: TColor;
  CX, H1, H2, Y: Integer;
begin
  R := ClientRect;
  if FDim then C := DJ_OFF else C := FStemColor;
  if FLit then
  begin
    { leuchtet: gefüllt in der Stemfarbe, dunkle Schrift }
    Bg := C;
    Bd := BlendColor(C, clWhite, 0.35);
    Fg := $00201A18;
    Fg2 := BlendColor(C, $00201A18, 0.7);
  end
  else
  begin
    { aus: dunkel, nur der Rahmen und die Schrift in der Stemfarbe }
    Bg := BlendColor(DJ_PANEL, C, 0.07);
    Bd := BlendColor(DJ_PANEL, C, 0.75);
    Fg := C;
    Fg2 := BlendColor(C, DJ_PANEL, 0.35);
  end;
  if FPressed then Bg := BlendColor(Bg, clBlack, 0.25);

  with Canvas do
  begin
    Brush.Color := Bg;
    Pen.Color := Bd;
    Pen.Width := 2;
    RoundRect(1, 1, R.Right, R.Bottom, 10, 10);
    Pen.Width := 1;
    { heller Streifen oben: wirkt wie ein gewölbter Gummi-Pad }
    if FLit then
    begin
      Pen.Color := BlendColor(C, clWhite, 0.55);
      Line(6, 3, R.Right - 6, 3);
    end;

    Brush.Style := bsClear;
    CX := Self.Width div 2;
    Font.Assign(Self.Font);
    Font.Style := [fsBold];
    Font.Size := 10;
    Font.Color := Fg;
    H1 := TextHeight('Ag');
    Font.Size := 7;
    H2 := TextHeight('Ag');
    Y := (Self.Height - H1 - H2) div 2;
    Font.Size := 10;
    DrawCentered(Canvas, CX, Y, Caption);
    Font.Size := 7;
    Font.Color := Fg2;
    DrawCentered(Canvas, CX, Y + H1, FSubText);
    Brush.Style := bsSolid;
  end;
end;

{ ============================================================================
  TJogWheel
  ============================================================================ }

constructor TJogWheel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBack := TBitmap.Create;
  FBuf := TBitmap.Create;
  FBackColor := DJ_BG;
  FArcQ := -1;
  FAngleQ := -1;
  Cursor := crHandPoint;
  SetInitialBounds(0, 0, 230, 230);
end;

destructor TJogWheel.Destroy;
begin
  FBack.Free;
  FBuf.Free;
  inherited Destroy;
end;

{ Restzeit als Länge des Rings in halben Grad (0..720) }
function TJogWheel.ArcQuant: Integer;
begin
  if FTotal <= 0 then Exit(0);
  Result := Round(EnsureRange((FTotal - FPos) / FTotal, 0, 1) * 720);
end;

{ Drehwinkel in halben Grad: eine Umdrehung pro 1,8 s wie eine Platte
  mit 33 1/3 U/min (so drehen auch die Anzeigen echter CD-Player) }
function TJogWheel.AngleQuant: Integer;
begin
  Result := Round(FPos / FRAMES_33 * 720) mod 720;
end;

procedure TJogWheel.SetPos(AValue: Double);
begin
  if FDragging then Exit;   // beim Drehen zählt die Maus, nicht die Engine
  FPos := AValue;
  if (ArcQuant <> FArcQ) or (AngleQuant <> FAngleQ) then Invalidate;
end;

procedure TJogWheel.SetTotal(AValue: Int64);
begin
  FTotal := AValue;
  Invalidate;
end;

procedure TJogWheel.SetCenterText(const AValue: string);
begin
  if FCenterText = AValue then Exit;
  FCenterText := AValue;
  Invalidate;
end;

procedure TJogWheel.SetCenterCaption(const AValue: string);
begin
  if FCenterCaption = AValue then Exit;
  FCenterCaption := AValue;
  Invalidate;
end;

{ Unveränderliche Teile + Restzeit-Ring vorzeichnen. Der Ring ändert sich
  nur alle paar Sekunden um einen halben Grad, darum gehört er hierher. }
procedure TJogWheel.RenderBack;
var
  Big: TBitmap;
  S, k: Integer;
  C, R, RRing, RPlate, RDisp, T: Double;
  Q: Integer;
begin
  S := Min(Width, Height);
  Q := ArcQuant;
  Big := TBitmap.Create;
  try
    Big.SetSize(S * SS, S * SS);
    C := S * SS / 2;
    R := C - 2 * SS;
    RRing := R - 17 * SS;
    RPlate := R - 27 * SS;
    RDisp := R * 0.47;
    with Big.Canvas do
    begin
      Brush.Color := FBackColor;
      FillRect(0, 0, Big.Width, Big.Height);
      { Rand mit Griffrillen }
      Pen.Width := SS;
      Pen.Color := $003A3634;
      Brush.Color := $00262322;
      Circle(Big.Canvas, C, C, R);
      Pen.Color := $00131211;
      for k := 0 to 119 do
        RadialLine(Big.Canvas, C, C, k * 3, R - 2 * SS, R - 11 * SS);
      { dunkle Spur des Rings }
      Brush.Style := bsClear;
      Pen.Width := 7 * SS;
      Pen.Color := $00382416;
      Circle(Big.Canvas, C, C, RRing);
      { Ring: Restzeit, beginnt oben und läuft im Uhrzeigersinn }
      if Q > 0 then
      begin
        Pen.Color := CD_BLUE;
        Arc(Round(C - RRing), Round(C - RRing), Round(C + RRing), Round(C + RRing),
            90 * 16, -Q * 8);
      end;
      Brush.Style := bsSolid;
      { Teller: von aussen hell nach innen dunkel (wie gebürstetes Metall) }
      Pen.Style := psClear;
      for k := 0 to 11 do
      begin
        T := k / 11;
        Brush.Color := BlendColor($00403B38, $00242120, T);
        Circle(Big.Canvas, C, C, RPlate - (RPlate - RDisp) * T * 0.9);
      end;
      Pen.Style := psSolid;
      { Display in der Mitte }
      Pen.Width := SS;
      Pen.Color := $00383432;
      Brush.Color := $000D0C0C;
      Circle(Big.Canvas, C, C, RDisp);
      Pen.Width := 1;
    end;
    FBack.SetSize(S, S);
    Downsample(Big, FBack);
    FArcQ := Q;
  finally
    Big.Free;
  end;
end;

procedure TJogWheel.Paint;
var
  S, OX, OY: Integer;
  C, CX, CY, R, RPlate, RDisp, A: Double;
begin
  S := Min(Width, Height);
  if S < 40 then Exit;
  if (FBack.Width <> S) or (ArcQuant <> FArcQ) then RenderBack;
  if (FBuf.Width <> Width) or (FBuf.Height <> Height) then FBuf.SetSize(Width, Height);
  OX := (Width - S) div 2;
  OY := (Height - S) div 2;
  C := S / 2;
  CX := OX + C;
  CY := OY + C;
  R := C - 2;
  RPlate := R - 27;
  RDisp := R * 0.47;
  FAngleQ := AngleQuant;
  A := FAngleQ / 2;

  with FBuf.Canvas do
  begin
    Brush.Color := FBackColor;
    FillRect(0, 0, Width, Height);
    Draw(OX, OY, FBack);
    { Markierung auf dem Teller und im Display drehen sich mit }
    Pen.Width := 3;
    Pen.Color := $00686260;
    RadialLine(FBuf.Canvas, CX, CY, A, RDisp + 5, RPlate - 4);
    Pen.Width := 2;
    Pen.Color := $00F0F0F0;
    RadialLine(FBuf.Canvas, CX, CY, A, RDisp * 0.70, RDisp * 0.88);
    Pen.Width := 1;
    { Text in der Mitte }
    Brush.Style := bsClear;
    Font.Name := 'Segoe UI';
    Font.Style := [fsBold];
    Font.Size := 7;
    Font.Color := $00D0A070;
    DrawCentered(FBuf.Canvas, Round(CX), Round(CY - RDisp * 0.48), FCenterCaption);
    Font.Name := 'Consolas';
    Font.Size := 16;
    Font.Color := $00F2F2F2;
    DrawCentered(FBuf.Canvas, Round(CX), Round(CY - TextHeight('0') / 2 + RDisp * 0.08), FCenterText);
    Brush.Style := bsSolid;
  end;
  Canvas.Draw(0, 0, FBuf);
end;

function TJogWheel.AngleAt(X, Y: Integer): Double;
begin
  Result := PointAngle(Width / 2, Height / 2, X, Y);
end;

procedure TJogWheel.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FTotal <= 0) then Exit;
  { nur auf dem Rad, nicht in den Ecken daneben }
  if Hypot(X - Width / 2, Y - Height / 2) > Min(Width, Height) / 2 then Exit;
  FArmed := True;
  FDragging := False;
  FLastAng := AngleAt(X, Y);
  FAccum := 0;
end;

procedure TJogWheel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  A, Target: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if not FArmed then Exit;
  A := AngleAt(X, Y);
  FAccum := FAccum + AngleDiff(A, FLastAng);
  FLastAng := A;
  { erst ab ein paar Grad drehen, damit ein Klick ein Klick bleibt }
  if not FDragging then
  begin
    if Abs(FAccum) < 3 then Exit;
    FDragging := True;
    FDownPos := FPos;
    FAccum := 0;
  end;
  { eine Umdrehung = 1,8 s, wie eine Platte unter der Hand }
  Target := EnsureRange(FDownPos + FAccum / 360 * FRAMES_33, 0, Max(0, FTotal - 1));
  FPos := Target;
  Invalidate;
  if Assigned(FOnScrub) then FOnScrub(Self, True, Round(Target));
end;

procedure TJogWheel.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if FDragging and Assigned(FOnScrub) then FOnScrub(Self, False, Round(FPos));
  FArmed := False;
  FDragging := False;
end;

{ ============================================================================
  TTurntable
  ============================================================================ }

const
  TT_PIVOT_X = 34;     // Drehpunkt des Tonarms: so weit vom rechten Rand
  TT_PIVOT_Y = 40;     // und so weit von oben
  TT_RINGS_GAP = 12;   // Abstand der Ringe zum Etikett

constructor TTurntable.Create(AOwner: TComponent);
var i: Integer;
begin
  inherited Create(AOwner);
  FBack := TBitmap.Create;
  FBuf := TBitmap.Create;
  FBackColor := DJ_PANEL;
  FScale := 1;
  FFramesPerRev := FRAMES_33;
  FLoopA := -1;
  FLoopB := -1;
  for i := 1 to 4 do
  begin
    FColors[i] := DJ_DIM;
    FActive[i] := True;
  end;
  FDirty := True;
  Cursor := crHandPoint;
  SetInitialBounds(0, 0, 480, 440);
end;

destructor TTurntable.Destroy;
begin
  FBack.Free;
  FBuf.Free;
  inherited Destroy;
end;

{ Lage der Platte im Steuerelement. Rechts bleibt Platz für den Tonarm. }
procedure TTurntable.Geometry(out CX, CY, RPlatter, RRecord, RLabel: Double);
begin
  RPlatter := Min(Height / 2 - 6, (Width - 70) / 2);
  CX := RPlatter + 8;
  CY := Height / 2;
  RRecord := RPlatter - 12;
  RLabel := RRecord * 0.30;
end;

{ Ring Idx (1 = aussen): Mittellinie und halbe Breite }
procedure TTurntable.RingRadius(Idx: Integer; out RMid, RHalf: Double);
var
  CX, CY, RP, RR, RL, Band: Double;
begin
  Geometry(CX, CY, RP, RR, RL);
  Band := (RR - 6 - (RL + TT_RINGS_GAP)) / 4;
  RMid := RR - 6 - (Idx - 0.5) * Band;
  RHalf := Band * 0.46;
end;

function TTurntable.Fraction: Double;
begin
  if FTotal <= 0 then Exit(0);
  Result := EnsureRange(FPos / FTotal, 0, 1);
end;

{ Abstand der Nadel zur Mitte: am Anfang am äusseren Ring, am Ende innen }
procedure TTurntable.StylusRadius(out RS: Double);
var
  RMid, RHalf, ROut, RIn: Double;
begin
  RingRadius(1, RMid, RHalf);
  ROut := RMid + RHalf;
  RingRadius(4, RMid, RHalf);
  RIn := RMid - RHalf;
  RS := ROut - Fraction * (ROut - RIn);
end;

procedure TTurntable.SetPos(AValue: Double);
var RS: Double;
begin
  if FDragging then Exit;   // beim Drehen zählt die Maus, nicht die Engine
  FPos := AValue;
  StylusRadius(RS);
  if (Round(Fraction * 1440) <> FHandQ) or
     (Round(FPos / FFramesPerRev * 360) mod 360 <> FSpinQ) or
     (Round(RS * 2) <> FArmQ) then
    Invalidate;
end;

procedure TTurntable.SetTotal(AValue: Int64);
begin
  FTotal := AValue;
  Invalidate;
end;

procedure TTurntable.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  FDirty := True;
  Invalidate;
end;

procedure TTurntable.SetTimeText(const AValue: string);
begin
  if FTimeText = AValue then Exit;
  FTimeText := AValue;
  Invalidate;
end;

procedure TTurntable.SetFramesPerRev(AValue: Integer);
begin
  if AValue <= 0 then Exit;
  FFramesPerRev := AValue;
  Invalidate;
end;

procedure TTurntable.SetStemPeaks(Idx: Integer; const APeaks: TPeakData; AScale: Single);
begin
  if (Idx < 1) or (Idx > 4) then Exit;
  FPeaks[Idx] := APeaks;   // dynamische Arrays: nur ein Verweis, keine Kopie
  FScale := AScale;
  FDirty := True;
  Invalidate;
end;

procedure TTurntable.ClearPeaks;
var i: Integer;
begin
  for i := 1 to 4 do
  begin
    FPeaks[i].Valid := False;
    SetLength(FPeaks[i].Lo, 0);
    SetLength(FPeaks[i].Hi, 0);
    SetLength(FPeaks[i].Rms, 0);
  end;
  FDirty := True;
  Invalidate;
end;

procedure TTurntable.SetRing(Idx: Integer; AColor: TColor; AActive: Boolean);
begin
  if (Idx < 1) or (Idx > 4) then Exit;
  if (FColors[Idx] = AColor) and (FActive[Idx] = AActive) then Exit;
  FColors[Idx] := AColor;
  FActive[Idx] := AActive;
  FDirty := True;
  Invalidate;
end;

procedure TTurntable.SetLoop(AFrom, ATo: Single; AOn: Boolean);
begin
  if (FLoopA = AFrom) and (FLoopB = ATo) and (FLoopOn = AOn) then Exit;
  FLoopA := AFrom;
  FLoopB := ATo;
  FLoopOn := AOn;
  Invalidate;
end;

{ Teller, Rillen, die 4 Wellenform-Ringe und das Etikett vorzeichnen.
  Jeder Ring zeigt den ganzen Track einmal rundherum: oben = Anfang,
  im Uhrzeigersinn bis zum Ende (wie der Zeiger einer Uhr). }
procedure TTurntable.RenderBack;
const
  STEPS = 1080;   // Striche pro Ring (alle 1/3 Grad)
var
  Big: TBitmap;
  CX, CY, RP, RR, RL, RMid, RHalf, R, A, P, Rm: Double;
  i, k, b, b0, b1, N, PX, PY: Integer;
  Col, ColPeak: TColor;
  S: string;
begin
  Geometry(CX, CY, RP, RR, RL);
  Big := TBitmap.Create;
  try
    Big.SetSize(Width * SS, Height * SS);
    with Big.Canvas do
    begin
      Brush.Color := FBackColor;
      FillRect(0, 0, Big.Width, Big.Height);

      { Teller mit Stroboskop-Punkten am Rand }
      Pen.Width := SS;
      Pen.Color := $00403C3A;
      Brush.Color := $002B2928;
      Circle(Big.Canvas, CX * SS, CY * SS, RP * SS);
      Pen.Style := psClear;
      Brush.Color := $00A09A96;
      for k := 0 to 89 do
      begin
        with PolarPoint(CX * SS, CY * SS, k * 4, (RP - 5) * SS) do
          Circle(Big.Canvas, X, Y, 1.3 * SS);
      end;
      Pen.Style := psSolid;

      { Platte mit feinen Rillen }
      Pen.Color := $000E0E0E;
      Brush.Color := $00121212;
      Circle(Big.Canvas, CX * SS, CY * SS, RR * SS);
      Brush.Style := bsClear;
      Pen.Width := 1;
      R := RL + 4;
      k := 0;
      while R < RR - 1 do
      begin
        if Odd(k) then Pen.Color := $001A1A1A else Pen.Color := $00161616;
        Circle(Big.Canvas, CX * SS, CY * SS, R * SS);
        R := R + 2.5;
        Inc(k);
      end;

      { Wellenform-Ringe: Spitzenwert gedämpft, Effektivwert (Rms) kräftig }
      Pen.Width := SS;
      for i := 1 to 4 do
      begin
        RingRadius(i, RMid, RHalf);
        if FActive[i] then Col := FColors[i] else Col := $00505050;
        ColPeak := BlendColor(Col, $00121212, 0.5);
        N := Length(FPeaks[i].Hi);
        if (not FPeaks[i].Valid) or (N = 0) then
        begin
          { noch keine Hüllkurve: nur eine dünne Linie }
          Pen.Color := BlendColor(Col, $00121212, 0.7);
          Circle(Big.Canvas, CX * SS, CY * SS, RMid * SS);
          Continue;
        end;
        for k := 0 to STEPS - 1 do
        begin
          b0 := Int64(k) * N div STEPS;
          b1 := Max(b0, Int64(k + 1) * N div STEPS - 1);
          P := 0;
          Rm := 0;
          for b := b0 to b1 do
          begin
            P := Max(P, Max(Abs(FPeaks[i].Lo[b]), Abs(FPeaks[i].Hi[b])));
            Rm := Max(Rm, FPeaks[i].Rms[b]);
          end;
          P := Min(1, P * FScale);
          Rm := Min(1, Rm * FScale * 1.4);
          A := (k + 0.5) / STEPS * 360;
          Pen.Color := ColPeak;
          RadialLine(Big.Canvas, CX * SS, CY * SS, A,
                     (RMid - P * RHalf) * SS, (RMid + P * RHalf + 0.6) * SS);
          if Rm > 0.02 then
          begin
            Pen.Color := Col;
            RadialLine(Big.Canvas, CX * SS, CY * SS, A,
                       (RMid - Rm * RHalf) * SS, (RMid + Rm * RHalf + 0.6) * SS);
          end;
        end;
      end;
      Brush.Style := bsSolid;

      { Etikett }
      Pen.Width := SS;
      Pen.Color := $00B8C4CC;
      Brush.Color := $00D5E2EA;
      Circle(Big.Canvas, CX * SS, CY * SS, RL * SS);
      Brush.Style := bsClear;
      Font.Name := 'Segoe UI';
      Font.Style := [fsBold];
      Font.Size := 7 * SS;
      Font.Color := $00303030;
      DrawCentered(Big.Canvas, Round(CX * SS), Round((CY - RL * 0.62) * SS), 'S T E M P L A Y E R');
      Font.Size := 8 * SS;
      Font.Color := $00202020;
      { zu langen Titel hinten kürzen (zeichenweise, UTF-8: Umlaute
        sind mehrere Bytes) }
      S := FTitle;
      if TextWidth(S) > RL * 1.7 * SS then
      begin
        repeat
          S := UTF8Copy(S, 1, UTF8Length(S) - 1);
        until (S = '') or (TextWidth(S + '…') <= RL * 1.7 * SS);
        S := S + '…';
      end;
      DrawCentered(Big.Canvas, Round(CX * SS), Round((CY + RL * 0.12) * SS), S);
      Brush.Style := bsSolid;
      { Mittelachse }
      Pen.Color := $00707070;
      Brush.Color := $00A8A8A8;
      Circle(Big.Canvas, CX * SS, CY * SS, 4 * SS);

      { Sockel des Tonarms }
      PX := (Self.Width - TT_PIVOT_X) * SS;
      PY := TT_PIVOT_Y * SS;
      Pen.Color := $00504A48;
      Brush.Color := $00353230;
      Circle(Big.Canvas, PX, PY, 25 * SS);
      Pen.Color := $00686462;
      Brush.Color := $00484442;
      Circle(Big.Canvas, PX, PY, 15 * SS);
      Pen.Width := 1;
    end;
    FBack.SetSize(Width, Height);
    Downsample(Big, FBack);
    FDirty := False;
  finally
    Big.Free;
  end;
end;

procedure TTurntable.Paint;
var
  CX, CY, RP, RR, RL, RS, D, L, AA, H, UX, UY, NX, NY, SX, SY, VX, VY: Double;
  PX, PY: Integer;
begin
  if (Width < 100) or (Height < 100) then Exit;
  if FDirty or (FBack.Width <> Width) or (FBack.Height <> Height) then RenderBack;
  if (FBuf.Width <> Width) or (FBuf.Height <> Height) then FBuf.SetSize(Width, Height);
  Geometry(CX, CY, RP, RR, RL);
  StylusRadius(RS);
  FHandQ := Round(Fraction * 1440);
  FSpinQ := Round(FPos / FFramesPerRev * 360) mod 360;
  FArmQ := Round(RS * 2);

  with FBuf.Canvas do
  begin
    Draw(0, 0, FBack);

    { weisser Zeiger: aktuelle Stelle auf den Ringen }
    Pen.Width := 2;
    Pen.Color := $00F4F4F4;
    RadialLine(FBuf.Canvas, CX, CY, FHandQ / 4, RL + 3, RR + 3);

    { Loop: grüner Bogen zwischen Platte und Stroboskop-Punkten.
      Windows misst Winkel ab 3 Uhr gegen den Uhrzeigersinn (in 1/16 Grad),
      hier zählt 0 = oben im Uhrzeigersinn -> umrechnen }
    if (FLoopA >= 0) and (FLoopB > FLoopA) then
    begin
      Pen.Width := 4;
      if FLoopOn then Pen.Color := DJ_GREEN
      else Pen.Color := BlendColor(DJ_GREEN, $002B2928, 0.55);
      Brush.Style := bsClear;
      Arc(Round(CX - RR - 4), Round(CY - RR - 4), Round(CX + RR + 4), Round(CY + RR + 4),
          Round((90 - FLoopA * 360) * 16), -Max(16, Round((FLoopB - FLoopA) * 360 * 16)));
      Brush.Style := bsSolid;
    end;

    { Punkt auf dem Etikett: dreht sich mit 33 bzw. 45 U/min }
    Pen.Width := 1;
    Pen.Color := $00606870;
    Brush.Color := $00808890;
    with PolarPoint(CX, CY, FSpinQ, RL * 0.78) do
      Circle(FBuf.Canvas, X, Y, 3);

    { Zeit auf dem Etikett }
    Brush.Style := bsClear;
    Font.Name := 'Segoe UI';
    Font.Style := [];
    Font.Size := 7;
    Font.Color := $00505050;
    DrawCentered(FBuf.Canvas, Round(CX), Round(CY + RL * 0.45), FTimeText);
    Brush.Style := bsSolid;

    { Tonarm: Drehpunkt P, Nadel S auf dem Kreis mit Radius RS um die Mitte.
      Der Arm hat die feste Länge L -> S ist der Schnittpunkt zweier Kreise. }
    PX := Self.Width - TT_PIVOT_X;
    PY := TT_PIVOT_Y;
    D := Hypot(PX - CX, PY - CY);
    if D > 1 then
    begin
      L := D * 0.92;
      UX := (PX - CX) / D;   // Richtung Mitte -> Drehpunkt
      UY := (PY - CY) / D;
      NX := -UY;             // senkrecht dazu (zeigt nach rechts unten)
      NY := UX;
      AA := (RS * RS - L * L + D * D) / (2 * D);
      H := Sqrt(Max(0, RS * RS - AA * AA));
      SX := CX + AA * UX + H * NX;
      SY := CY + AA * UY + H * NY;
      VX := (SX - PX) / L;   // Richtung Drehpunkt -> Nadel
      VY := (SY - PY) / L;
      { Gegengewicht hinter dem Drehpunkt }
      Pen.Width := 12;
      Pen.Color := $00585452;
      Line(Round(PX - VX * 8), Round(PY - VY * 8), Round(PX - VX * 30), Round(PY - VY * 30));
      { Rohr }
      Pen.Width := 5;
      Pen.Color := $00A8A8A8;
      Line(PX, PY, Round(SX - VX * 20), Round(SY - VY * 20));
      Pen.Width := 1;
      Pen.Color := $00E0E0E0;
      Line(PX - 1, PY - 1, Round(SX - VX * 20) - 1, Round(SY - VY * 20) - 1);
      { Tonkopf }
      Pen.Width := 10;
      Pen.Color := $00383634;
      Line(Round(SX - VX * 22), Round(SY - VY * 22), Round(SX + VX * 3), Round(SY + VY * 3));
      { Lager oben drauf }
      Pen.Width := 1;
      Pen.Color := $00909090;
      Brush.Color := $00C8C8C8;
      Circle(FBuf.Canvas, PX, PY, 8);
    end;
    Pen.Width := 1;
  end;
  Canvas.Draw(0, 0, FBuf);
end;

function TTurntable.AngleAt(X, Y: Integer): Double;
var CX, CY, RP, RR, RL: Double;
begin
  Geometry(CX, CY, RP, RR, RL);
  Result := PointAngle(CX, CY, X, Y);
end;

function TTurntable.RadiusAt(X, Y: Integer): Double;
var CX, CY, RP, RR, RL: Double;
begin
  Geometry(CX, CY, RP, RR, RL);
  Result := Hypot(X - CX, Y - CY);
end;

procedure TTurntable.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var CX, CY, RP, RR, RL: Double;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FTotal <= 0) then Exit;
  Geometry(CX, CY, RP, RR, RL);
  if RadiusAt(X, Y) > RR then Exit;   // nur auf der Platte
  FArmed := True;
  FDragging := False;
  FLastAng := AngleAt(X, Y);
  FAccum := 0;
end;

procedure TTurntable.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  A, Target: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if not FArmed then Exit;
  A := AngleAt(X, Y);
  FAccum := FAccum + AngleDiff(A, FLastAng);
  FLastAng := A;
  if not FDragging then
  begin
    if Abs(FAccum) < 3 then Exit;   // ein Klick bleibt ein Klick
    FDragging := True;
    FDownPos := FPos;
    FAccum := 0;
  end;
  { eine Umdrehung der Platte = 1,8 s (33) bzw. 1,33 s (45) }
  Target := EnsureRange(FDownPos + FAccum / 360 * FFramesPerRev, 0, Max(0, FTotal - 1));
  FPos := Target;
  Invalidate;
  if Assigned(FOnScrub) then FOnScrub(Self, True, Round(Target));
end;

procedure TTurntable.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var CX, CY, RP, RR, RL: Double;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if FDragging then
  begin
    if Assigned(FOnScrub) then FOnScrub(Self, False, Round(FPos));
  end
  else if FArmed then
  begin
    { nur geklickt: auf einem Ring -> an diese Stelle des Tracks springen }
    Geometry(CX, CY, RP, RR, RL);
    if (RadiusAt(X, Y) >= RL + TT_RINGS_GAP) and Assigned(FOnSeek) then
      FOnSeek(Self, AngleAt(X, Y) / 360);
  end;
  FArmed := False;
  FDragging := False;
end;

end.
