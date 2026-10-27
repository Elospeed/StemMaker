{ ============================================================================
  designviews.pas  -  Steuerelemente für die Ansicht "CD-Player" des
                      Elospeed StemPlayer

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Die Ansicht zeigt dieselben Funktionen wie die normale Ansicht,
  nur in einem anderen Look (siehe Design-Entwurf 7). Ein Design
  Plattenspieler (TTurntable) ist fertig, kommt aber erst später; es liegt
  auf dem Branch elospeed/stemplayer-plattenspieler. Die meisten
  Bedienelemente (Fader, Mute/Solo, Wellenformen, Lupe, Loop-Knöpfe) sind
  dieselben Objekte wie in der normalen Ansicht; das Hauptfenster setzt sie
  beim Umschalten nur an einen anderen Platz (playerform.PlaceCtl).
  Neu sind nur die Teile, die es vorher nicht gab:

    TStemPad     grosser Pad-Knopf in der Stemfarbe (CD-Player: Mute/Solo)
    TJogWheel    Jogwheel des CD-Players. Der blaue Ring zeigt die Restzeit,
                 der Strich dreht sich mit der Musik. Mit der Maus drehen =
                 Scrubbing (Ton wie beim Ziehen der Welle in der Lupe).
  Kantenglättung: Windows zeichnet Kreise und schräge Linien ohne
  Kantenglättung (treppig). Darum werden die unveränderlichen Teile (Rand,
  Ringe) einmal in doppelter Grösse vorgezeichnet und mit
  StretchBlt im Modus HALFTONE weich verkleinert (Downsample). Bei jedem
  Bild wird nur noch dieses fertige Bild kopiert und die beweglichen Teile
  (Strich, Zeit) darüber gezeichnet.

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
  djcontrols, wellenform;

const
  SS = 2;                 // Kantenglättung: so viel grösser wird vorgezeichnet
  FRAMES_33 = 79380;      // Jogwheel wie 33 1/3 U/min: eine Umdrehung = 1,8 s bei 44,1 kHz
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

end.
