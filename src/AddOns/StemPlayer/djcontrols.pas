{ ============================================================================
  djcontrols.pas  -  Selbst gezeichnete Steuerelemente für den DJ-Look

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Warum eigene Steuerelemente?
    Die Standard-Buttons und -Schieberegler von Windows (TButton, TTrackBar)
    lassen sich unter Windows nicht umfärben - sie sehen immer hell und nach
    "Büro" aus. Darum werden die Bedienelemente hier selbst auf den Canvas
    gezeichnet. Die Logik im Hauptfenster bleibt dieselbe, nur die Optik ist neu.

  Enthalten:
    TDJPanel   Fläche mit dunklem Hintergrund, 1-Pixel-Rahmen und optional
               einem farbigen Streifen links (Stemfarbe)
    TDJButton  flacher Button. Kann einrasten (Toggle) und leuchtet im
               gedrückten Zustand in seiner Farbe (LitColor). Mit
               LitColor = clNone wird er im gedrückten Zustand hell
               (für die Modus-Umschaltung Stems / Original / Rest).
               Optional mit Symbol statt Text (Play / Pause / Stop).
    TDJSlider  Schieberegler in zwei Varianten:
               dssFader    dünne Spur mit farbiger Füllung + Fader-Kappe
               dssPosition breite dunkle Leiste mit rotem Abspielkopf
    LED-Meter  werden weiter in TPaintBox im Hauptfenster gezeichnet
               (DrawLedBar unten erledigt das eigentliche Zeichnen).

  Farben: TColor ist $00BBGGRR (Blau zuerst!), nicht RGB.
  ============================================================================ }
unit djcontrols;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, ExtCtrls, LCLType;

const
  { Farbpalette "Traktor Dark" (siehe Design-Vorschlag A) }
  DJ_BG        = $001A1817;   // Fensterhintergrund   #17181A
  DJ_PANEL     = $0023201F;   // Flächen / Zeilen     #1F2023
  DJ_BORDER    = $00322E2C;   // Rahmen               #2C2E32
  DJ_BTN       = $00302C2A;   // Button-Fläche        #2A2C30
  DJ_BTNBORDER = $00423D3A;   // Button-Rahmen        #3A3D42
  DJ_TEXT      = $00E6E6E6;   // heller Text
  DJ_DIM       = $007A7A7A;   // gedimmter Text
  DJ_METERBG   = $00282523;   // unbeleuchtete LED    #232528
  DJ_TRACK     = $00111111;   // Spur der Fader
  DJ_FOOTER    = $00141211;   // Fusszeile            #111214
  DJ_RED       = $004A4AFF;   // Mute                 #FF4A4A
  DJ_YELLOW    = $0000C4FF;   // Solo                 #FFC400
  DJ_GREEN     = $0084DC3D;   // Play / Meter grün    #3DDC84
  DJ_AMBER     = $003DD2FF;   // Meter gelb           #FFD23D
  DJ_PLAYHEAD  = $003B3BFF;   // Abspielkopf          #FF3B3B
  DJ_OFF       = $00555555;   // ausgeschaltete Stems
  DJ_KOFI      = $005A9FFF;   // Ko-fi-Link           #FF9F5A

type
  TDJGlyph = (dgNone, dgPlay, dgPause, dgStop);

  { ---------- Fläche mit Rahmen und Farbstreifen ---------- }
  TDJPanel = class(TCustomPanel)
  private
    FAccentColor: TColor;
    FAccentWidth: Integer;
    FBorderColor: TColor;
    procedure SetAccentColor(AValue: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property AccentColor: TColor read FAccentColor write SetAccentColor;
    property AccentWidth: Integer read FAccentWidth write FAccentWidth;  // 0 = kein Streifen
    property BorderColor: TColor read FBorderColor write FBorderColor;   // clNone = kein Rahmen
  end;

  { ---------- Button ---------- }
  TDJButton = class(TGraphicControl)
  private
    FDown: Boolean;
    FToggle: Boolean;
    FLitColor: TColor;
    FGlyph: TDJGlyph;
    FHover: Boolean;
    FPressed: Boolean;
    procedure SetDown(AValue: Boolean);
    procedure SetLitColor(AValue: TColor);
    procedure SetGlyph(AValue: TDJGlyph);
  protected
    procedure Paint; override;
    procedure Click; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Down: Boolean read FDown write SetDown;
    { True = rastet bei jedem Klick ein/aus (Mute, Solo).
      False = Down wird nur vom Programm gesetzt (Modus-Buttons, CLIP). }
    property Toggle: Boolean read FToggle write FToggle;
    property LitColor: TColor read FLitColor write SetLitColor;
    property Glyph: TDJGlyph read FGlyph write SetGlyph;
    property Caption;
    property Font;
    property ShowHint;
    property OnClick;
  end;

  { ---------- Schieberegler ---------- }
  TDJSliderStyle = (dssFader, dssPosition);

  TDJSlider = class(TGraphicControl)
  private
    FMin, FMax, FPosition: Integer;
    FStyle: TDJSliderStyle;
    FFillColor: TColor;
    FDragging: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetPosition(AValue: Integer);
    procedure SetMax(AValue: Integer);
    procedure SetMin(AValue: Integer);
    procedure SetFillColor(AValue: TColor);
    function  PosFromX(X: Integer): Integer;
    function  TrackLeft: Integer;
    function  TrackRight: Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Min: Integer read FMin write SetMin;
    property Max: Integer read FMax write SetMax;
    { Setzen von Position löst OnChange aus (wie bei TTrackBar) }
    property Position: Integer read FPosition write SetPosition;
    property Style: TDJSliderStyle read FStyle write FStyle;
    property FillColor: TColor read FFillColor write SetFillColor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property ShowHint;
    property OnMouseDown;
    property OnMouseUp;
  end;

{ Mischt zwei Farben: T = 0 -> nur A, T = 1 -> nur B }
function BlendColor(A, B: TColor; T: Single): TColor;

{ Zeichnet eine LED-Kette (Segmente) von links nach rechts.
  Frac = 0..1 beleuchteter Anteil. Ist Zones = True, werden die Segmente wie
  am Mischpult grün / gelb (ab -6 dB) / rot (ab -1 dB) gefärbt, sonst alle
  in LitColor. Unbeleuchtete Segmente bleiben dunkel. }
procedure DrawLedBar(ACanvas: TCanvas; const R: TRect; Frac: Single;
  LitColor: TColor; Zones: Boolean);

implementation

function BlendColor(A, B: TColor; T: Single): TColor;
var
  ra, ga, ba, rb, gb, bb: Integer;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  ra := A and $FF; ga := (A shr 8) and $FF; ba := (A shr 16) and $FF;
  rb := B and $FF; gb := (B shr 8) and $FF; bb := (B shr 16) and $FF;
  Result := RGBToColor(Round(ra + (rb - ra) * T),
                       Round(ga + (gb - ga) * T),
                       Round(ba + (bb - ba) * T));
end;

procedure DrawLedBar(ACanvas: TCanvas; const R: TRect; Frac: Single;
  LitColor: TColor; Zones: Boolean);
const
  SEG_W = 10;   // Breite eines Segments
  GAP   = 3;    // Abstand dazwischen
var
  N, i, X, Lit: Integer;
  C, ZoneC: TColor;
  P: Single;
begin
  N := (R.Right - R.Left + GAP) div (SEG_W + GAP);
  if N < 1 then Exit;
  Lit := Round(Frac * N);
  X := R.Left;
  for i := 0 to N - 1 do
  begin
    { Position des Segments auf der dB-Skala (0..1, wie LevelToFrac) }
    P := (i + 0.5) / N;
    if Zones then
    begin
      if P >= 47 / 48 then ZoneC := DJ_PLAYHEAD
      else if P >= 42 / 48 then ZoneC := DJ_AMBER
      else ZoneC := DJ_GREEN;
    end
    else
      ZoneC := LitColor;
    if i < Lit then C := ZoneC
    else if Zones then C := BlendColor(DJ_METERBG, ZoneC, 0.15)  // Zone leicht angedeutet
    else C := DJ_METERBG;
    ACanvas.Brush.Color := C;
    ACanvas.FillRect(X, R.Top, X + SEG_W, R.Bottom);
    Inc(X, SEG_W + GAP);
  end;
end;

{ ============================================================================
  TDJPanel
  ============================================================================ }

constructor TDJPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Color := DJ_PANEL;
  FBorderColor := DJ_BORDER;
  FAccentColor := clNone;
  FAccentWidth := 0;
  DoubleBuffered := True;   // verhindert Flackern der Meter
  ParentBackground := False;
end;

procedure TDJPanel.SetAccentColor(AValue: TColor);
begin
  if FAccentColor = AValue then Exit;
  FAccentColor := AValue;
  Invalidate;
end;

procedure TDJPanel.Paint;
begin
  with Canvas do
  begin
    Brush.Color := Color;
    FillRect(ClientRect);
    if FBorderColor <> clNone then
    begin
      Pen.Color := FBorderColor;
      Brush.Style := bsClear;
      Rectangle(ClientRect);
      Brush.Style := bsSolid;
    end;
    if (FAccentWidth > 0) and (FAccentColor <> clNone) then
    begin
      Brush.Color := FAccentColor;
      FillRect(0, 0, FAccentWidth, Self.Height);
    end;
  end;
end;

{ ============================================================================
  TDJButton
  ============================================================================ }

constructor TDJButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { Kein Doppelklick: sonst würde schnelles Umschalten von Mute/Solo
    jeden zweiten Klick "verschlucken" }
  ControlStyle := ControlStyle - [csDoubleClicks];
  FLitColor := clNone;
  FGlyph := dgNone;
  SetInitialBounds(0, 0, 80, 30);
end;

procedure TDJButton.SetDown(AValue: Boolean);
begin
  if FDown = AValue then Exit;
  FDown := AValue;
  Invalidate;
end;

procedure TDJButton.SetLitColor(AValue: TColor);
begin
  if FLitColor = AValue then Exit;
  FLitColor := AValue;
  Invalidate;
end;

procedure TDJButton.SetGlyph(AValue: TDJGlyph);
begin
  if FGlyph = AValue then Exit;
  FGlyph := AValue;
  Invalidate;
end;

procedure TDJButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TDJButton.Click;
begin
  if FToggle then
  begin
    FDown := not FDown;
    Invalidate;
  end;
  inherited Click;   // ruft OnClick auf
end;

procedure TDJButton.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TDJButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  FPressed := False;
  Invalidate;
end;

procedure TDJButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TDJButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FPressed := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

{ Achtung: innerhalb von "with Canvas do" bedeuten Width/Height die Grösse
  des Canvas (nicht die des Buttons) - darum immer Self.Width/Self.Height. }
procedure TDJButton.Paint;
var
  R: TRect;
  Bg, Bd, Fg: TColor;
  CX, CY, S: Integer;
  TS: TTextStyle;
begin
  R := ClientRect;

  { Farben je nach Zustand }
  if not IsEnabled then
  begin
    Bg := BlendColor(DJ_BTN, DJ_BG, 0.5);
    Bd := DJ_BORDER;
    Fg := BlendColor(DJ_DIM, DJ_BG, 0.4);
  end
  else if FDown and (FLitColor = clNone) then
  begin
    { Modus-Button aktiv: hell mit dunkler Schrift }
    Bg := DJ_TEXT;
    Bd := DJ_TEXT;
    Fg := DJ_BG;
  end
  else if FDown then
  begin
    { leuchtet in seiner Farbe }
    Bg := BlendColor(DJ_BTN, FLitColor, 0.28);
    Bd := FLitColor;
    Fg := BlendColor(FLitColor, clWhite, 0.25);
  end
  else
  begin
    Bg := DJ_BTN;
    if FHover then Bg := BlendColor(DJ_BTN, clWhite, 0.07);
    Bd := DJ_BTNBORDER;
    Fg := $00B0B0B0;
    if FHover then Fg := DJ_TEXT;
  end;
  if FPressed and IsEnabled then Bg := BlendColor(Bg, clBlack, 0.2);

  with Canvas do
  begin
    Brush.Color := Bg;
    FillRect(R);
    Pen.Color := Bd;
    Brush.Style := bsClear;
    Rectangle(R);
    { "Glühen": zweiter, halbtransparent wirkender Rahmen innen }
    if FDown and (FLitColor <> clNone) and IsEnabled then
    begin
      Pen.Color := BlendColor(Bg, FLitColor, 0.45);
      Rectangle(R.Left + 1, R.Top + 1, R.Right - 1, R.Bottom - 1);
    end;
    Brush.Style := bsSolid;

    CX := (R.Left + R.Right) div 2;
    CY := (R.Top + R.Bottom) div 2;
    S := Math.Min(Self.Width, Self.Height) div 4;   // halbe Symbolgrösse
    Brush.Color := Fg;
    Pen.Color := Fg;
    case FGlyph of
      dgPlay:
        Polygon([Point(CX - S + 1, CY - S), Point(CX + S + 1, CY), Point(CX - S + 1, CY + S)]);
      dgPause:
        begin
          FillRect(CX - S, CY - S, CX - S div 3, CY + S + 1);
          FillRect(CX + S div 3 + 1, CY - S, CX + S + 1, CY + S + 1);
        end;
      dgStop:
        FillRect(CX - S + 1, CY - S + 1, CX + S, CY + S);
    else
      begin
        Font.Assign(Self.Font);
        Font.Color := Fg;
        Font.Style := [fsBold];
        TS := TextStyle;
        TS.Alignment := taCenter;
        TS.Layout := tlCenter;
        TS.SingleLine := True;
        TS.Clipping := True;
        Brush.Style := bsClear;
        TextRect(R, 0, 0, Caption, TS);
        Brush.Style := bsSolid;
      end;
    end;
  end;
end;

{ ============================================================================
  TDJSlider
  ============================================================================ }

const
  CAP_W = 14;   // Breite der Fader-Kappe
  CAP_H = 22;   // Höhe der Fader-Kappe

constructor TDJSlider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csDoubleClicks];
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FStyle := dssFader;
  FFillColor := DJ_TEXT;
  SetInitialBounds(0, 0, 200, 26);
end;

procedure TDJSlider.SetPosition(AValue: Integer);
begin
  AValue := EnsureRange(AValue, FMin, Math.Max(FMin, FMax));
  if FPosition = AValue then Exit;
  FPosition := AValue;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TDJSlider.SetMax(AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := Math.Max(FMin, FMax);
  Invalidate;
end;

procedure TDJSlider.SetMin(AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TDJSlider.SetFillColor(AValue: TColor);
begin
  if FFillColor = AValue then Exit;
  FFillColor := AValue;
  Invalidate;
end;

{ Bereich, in dem sich der Wert abbildet. Beim Fader wird links und rechts
  eine halbe Kappenbreite frei gelassen, damit die Kappe nie abgeschnitten wird. }
function TDJSlider.TrackLeft: Integer;
begin
  if FStyle = dssFader then Result := CAP_W div 2 else Result := 1;
end;

function TDJSlider.TrackRight: Integer;
begin
  if FStyle = dssFader then Result := Width - CAP_W div 2 - 1 else Result := Width - 2;
end;

function TDJSlider.PosFromX(X: Integer): Integer;
var
  L, W: Integer;
begin
  L := TrackLeft;
  W := TrackRight - L;
  if W <= 0 then Exit(FMin);
  Result := FMin + Round((X - L) / W * (FMax - FMin));
end;

procedure TDJSlider.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);   // OnMouseDown für das Hauptfenster
  if (Button = mbLeft) and IsEnabled then
  begin
    FDragging := True;
    Position := PosFromX(X);
  end;
end;

procedure TDJSlider.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then Position := PosFromX(X);
end;

procedure TDJSlider.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TDJSlider.Paint;
var
  L, Rt, X, CY, i: Integer;
  F: Single;
  Fill: TColor;
begin
  L := TrackLeft;
  Rt := TrackRight;
  if FMax > FMin then F := (FPosition - FMin) / (FMax - FMin) else F := 0;
  X := L + Round(F * (Rt - L));
  if IsEnabled then Fill := FFillColor else Fill := DJ_OFF;

  with Canvas do
  begin
    if FStyle = dssFader then
    begin
      { Hintergrund wie die Fläche dahinter }
      Brush.Color := Parent.Color;
      FillRect(ClientRect);
      CY := Self.Height div 2;
      { Spur + farbige Füllung bis zur Kappe }
      Brush.Color := DJ_TRACK;
      FillRect(L, CY - 2, Rt, CY + 2);
      Brush.Color := Fill;
      FillRect(L, CY - 2, X, CY + 2);
      { Fader-Kappe mit Verlauf und weisser Mittellinie }
      GradientFill(Rect(X - CAP_W div 2, CY - CAP_H div 2, X + CAP_W div 2, CY + CAP_H div 2),
                   $00635D5A, $00403C3A, gdVertical);
      Pen.Color := $00736D6A;
      Brush.Style := bsClear;
      Rectangle(X - CAP_W div 2, CY - CAP_H div 2, X + CAP_W div 2, CY + CAP_H div 2);
      Brush.Style := bsSolid;
      Pen.Color := $00DDDDDD;
      Line(X - CAP_W div 2 + 3, CY, X + CAP_W div 2 - 3, CY);
    end
    else
    begin
      { Positionsleiste: dunkel, gespielter Teil etwas heller, Raster, Abspielkopf }
      Brush.Color := $00151312;
      FillRect(ClientRect);
      if IsEnabled and (X > 1) then
      begin
        GradientFill(Rect(1, 1, X, Self.Height - 1), $002A2624, $00373230, gdHorizontal);
      end;
      Pen.Color := $00302C2A;
      i := 40;
      while i < Self.Width - 1 do
      begin
        Line(i, 1, i, Self.Height - 1);
        Inc(i, 40);
      end;
      Pen.Color := DJ_BORDER;
      Brush.Style := bsClear;
      Rectangle(ClientRect);
      Brush.Style := bsSolid;
      if IsEnabled then
      begin
        { Abspielkopf: 2 Pixel rot + dezenter Schein daneben }
        Brush.Color := BlendColor($00151312, DJ_PLAYHEAD, 0.3);
        FillRect(X - 2, 1, X + 4, Self.Height - 1);
        Brush.Color := DJ_PLAYHEAD;
        FillRect(X, 1, X + 2, Self.Height - 1);
      end;
    end;
  end;
end;

end.
