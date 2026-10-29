unit uStatusDraw;

{ ---------------------------------------------------------------------------
  Kleine Farb-Akzente im Hauptfenster

  Grundsatz: Das Hauptfenster bleibt ein normales Windows-Fenster. Nur drei
  Stellen bekommen etwas Farbe:

    1. Ein dünner Streifen in den vier Stem-Farben unter der Knopfleiste
       (Drums, Bass, Other, Vox - dieselben Farben, die Traktor anzeigt).

    2. Die Spalte "Status" der Dateiliste wird selbst gezeichnet:
         läuft   -> kleiner Fortschrittsbalken + Prozent
         fertig  -> grünes Häkchen, Text (z. B. "OK (2:41)") und
                    vier Farbpunkte = vier Stems in der Datei
         Fehler  -> roter Text
         wartet  -> grauer Text
         sonst   -> normaler Text (übersprungen, abgebrochen)

    3. Unten rechts ein kleiner Ko-fi-Knopf: abgerundet, Ko-fi-Rot,
       weisses Herz und "Kaffee spendieren". Er sitzt in einer eigenen
       schmalen Leiste unter dem Log und stört so beim Arbeiten nicht.

  Die Zeichen-Routinen hier kennen das Hauptfenster nicht. Sie bekommen
  Leinwand, Rechteck, Zustand und Farben und zeichnen nur. So lassen sie
  sich auch allein testen.

  Grössen sind für 96 dpi angegeben und werden mit PPI umgerechnet
  (125 %, 150 % ... Skalierung in Windows).
  --------------------------------------------------------------------------- }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Math, IntfGraphics, FPImage;

type
  { Wie eine Zeile aussieht. Absichtlich ein eigener Typ (nicht die ST_...
    Zahlen aus dem Hauptfenster), damit diese Unit allein steht. }
  TStatusLook = (slWait, slRun, slOK, slFail, slOther);

  TStemColorArray = array[0..3] of TColor;

const
  { Farben wie bei Windows 10/11 (TColor = $00BBGGRR, Blau zuerst!) }
  CLR_BAR_BORDER = TColor($00BCBCBC);   // Rand des Balkens
  CLR_BAR_BACK   = TColor($00E6E6E6);   // leerer Teil
  CLR_BAR_FILL   = TColor($0025B006);   // Windows-Grün  #06B025
  CLR_OK_TEXT    = TColor($00377F1A);   // dunkles Grün  #1A7F37 (gut lesbar)
  CLR_FAIL_TEXT  = TColor($001C2BC4);   // Windows-Rot   #C42B1C
  CLR_KOFI       = TColor($005E5AFF);   // Ko-fi-Rot     #FF5A5E (Herz, wie im Danke-Fenster)
  { Ko-fi-Knopf "E" (Wahl Speedy 29.10.2026): dunkle Pille, vorne das Symbol
    des jeweiligen Programms, rotes Herz, weisser Text - in allen Elospeed-Tools gleich }
  CLR_KOFI_FACE      = TColor($00262220);   // auf hellem Grund     #202226
  CLR_KOFI_FACE_DARK = TColor($00302C2A);   // auf dunklem Grund    #2A2C30
  CLR_KOFI_HOVER     = TColor($00443F3C);   // Maus darüber         #3C3F44

{ Streifen in den vier Stem-Farben, gleich breite Teile von links nach rechts }
procedure DrawAccentStrip(C: TCanvas; const R: TRect; const Colors: TStemColorArray);

{ Eine Zelle der Spalte "Status" zeichnen.
    R           Rechteck der Zelle
    Look        Zustand der Zeile
    Percent     Fortschritt 0..100 (nur bei slRun)
    Text        Text der Zelle, so wie er in der Liste steht
    BackColor   Hintergrund (normal clWindow, ausgewählt clHighlight)
    TextColor   Schrift (normal clWindowText, ausgewählt clHighlightText)
    Highlighted True = Zeile ist dunkel hinterlegt (ausgewählt). Dann kein
                Grün/Rot/Grau für den Text, das wäre schlecht lesbar.
    PPI         Bildschirm-dpi (96 = 100 %) }
procedure DrawStatusCell(C: TCanvas; const R: TRect; Look: TStatusLook;
  Percent: Integer; const Text: string; const Colors: TStemColorArray;
  BackColor, TextColor: TColor; Highlighted: Boolean; PPI: Integer);

{ Breite des Ko-fi-Knopfs für den Text (Symbol + Herz + Text + Rand), in Pixel.
  Die Schrift der Leinwand muss schon gesetzt sein (fett, siehe unten). }
function KofiButtonWidth(C: TCanvas; const Text: string; PPI: Integer): Integer;

{ Ko-fi-Knopf zeichnen: Hintergrund BackColor, darauf die dunkle Pille mit
  dem Programm-Symbol (AppIcon, meist Application.Icon; nil = ohne), rotem
  Herz und weissem Text, senkrecht mittig im Rechteck R.
  Hover = True -> Maus ist darüber, die Pille wird etwas heller. }
procedure DrawKofiButton(C: TCanvas; const R: TRect; const Text: string;
  Hover: Boolean; BackColor: TColor; PPI: Integer; AppIcon: TIcon = nil);

implementation

{ 96-dpi-Mass auf den Bildschirm umrechnen }
function ScalePx(V, PPI: Integer): Integer;
begin
  if PPI <= 0 then PPI := 96;
  Result := (V * PPI + 48) div 96;
end;

function KofiButtonWidth(C: TCanvas; const Text: string; PPI: Integer): Integer;
begin
  { 6 Rand links, 16 Symbol, 6 Abstand, 10 Herz, 6 Abstand, Text, 12 Rand rechts }
  Result := ScalePx(56, PPI) + C.TextWidth(Text);
end;

{ ist die Farbe dunkel? (für die Wahl der Pillenfarbe) }
function IsDarkColor(Col: TColor): Boolean;
var
  RGB: LongInt;
begin
  RGB := ColorToRGB(Col);
  Result := (Red(RGB) * 299 + Green(RGB) * 587 + Blue(RGB) * 114) div 1000 < 100;
end;

{ Pille und Herz geglättet zeichnen: GDI zeichnet Rundungen ohne
  Kantenglättung (treppig). Darum vierfach so gross zeichnen und dann
  je 4 x 4 Punkte zu einem mitteln.
    B      Rechteck der Pille auf C
    HeartX Mitte des Herzens (x, auf C), HeartY Oberkante der Herzkreise }
procedure DrawSmoothPill(C: TCanvas; const B: TRect; PillColor, BackColor: TColor;
  HeartX, HeartY, D: Integer);
const
  SS = 4;   // Vergrösserung beim Zeichnen
var
  Big, Small: TBitmap;
  BigImg, SmallImg: TLazIntfImage;
  W, H, X, Y, I, J, HX, HY, DD: Integer;
  R, G, Bl: Cardinal;
  Px: TFPColor;
begin
  W := B.Right - B.Left;
  H := B.Bottom - B.Top;
  if (W <= 0) or (H <= 0) then Exit;
  Big := TBitmap.Create;
  Small := TBitmap.Create;
  BigImg := nil;
  SmallImg := nil;
  try
    Big.PixelFormat := pf24bit;
    Big.SetSize(W * SS, H * SS);
    with Big.Canvas do
    begin
      { Systemfarben wie clBtnFace in echte Farben umrechnen, sonst bleibt
        der Hintergrund im Speicherbild schwarz }
      Brush.Color := ColorToRGB(BackColor);
      FillRect(0, 0, W * SS, H * SS);
      Brush.Color := PillColor;
      Pen.Color := PillColor;
      RoundRect(0, 0, W * SS, H * SS, H * SS, H * SS);
      { Herz aus zwei Kreisen und einem Dreieck (nicht jede Schrift hat ♥) }
      HX := (HeartX - B.Left) * SS;
      HY := (HeartY - B.Top) * SS;
      DD := D * SS;
      Brush.Color := CLR_KOFI;
      Pen.Color := CLR_KOFI;
      Ellipse(HX - DD, HY - DD div 2, HX + SS, HY + DD div 2 + SS);
      Ellipse(HX, HY - DD div 2, HX + DD + SS, HY + DD div 2 + SS);
      Polygon([Point(HX - DD + SS div 2, HY + SS), Point(HX + DD + SS div 2, HY + SS),
        Point(HX + SS div 2, HY + DD + SS)]);
    end;

    BigImg := Big.CreateIntfImage;
    Small.PixelFormat := pf24bit;
    Small.SetSize(W, H);
    SmallImg := Small.CreateIntfImage;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        R := 0; G := 0; Bl := 0;
        for J := 0 to SS - 1 do
          for I := 0 to SS - 1 do
          begin
            Px := BigImg.Colors[X * SS + I, Y * SS + J];
            Inc(R, Px.Red); Inc(G, Px.Green); Inc(Bl, Px.Blue);
          end;
        Px.Red := R div (SS * SS);
        Px.Green := G div (SS * SS);
        Px.Blue := Bl div (SS * SS);
        Px.Alpha := alphaOpaque;
        SmallImg.Colors[X, Y] := Px;
      end;
    Small.LoadFromIntfImage(SmallImg);
    C.Draw(B.Left, B.Top, Small);
  finally
    SmallImg.Free;
    BigImg.Free;
    Small.Free;
    Big.Free;
  end;
end;

procedure DrawKofiButton(C: TCanvas; const R: TRect; const Text: string;
  Hover: Boolean; BackColor: TColor; PPI: Integer; AppIcon: TIcon);
var
  B, IR: TRect;    // der Knopf selbst, das Symbol
  H, HX, HY, D, X, S: Integer;
  Col: TColor;
begin
  { clDefault (Panel ohne eigene Farbe) wäre in der Bitmap schwarz }
  if (BackColor = clDefault) or (BackColor = clNone) then
    BackColor := clBtnFace;
  BackColor := ColorToRGB(BackColor);
  C.Brush.Style := bsSolid;
  C.Brush.Color := BackColor;
  C.FillRect(R);

  { Pille: so hoch wie die Schrift plus etwas Luft, ganz runde Enden }
  H := Min(R.Bottom - R.Top - ScalePx(2, PPI),
    Max(C.TextHeight('Ag') + ScalePx(8, PPI), ScalePx(22, PPI)));
  B := Rect(R.Left, (R.Top + R.Bottom - H) div 2, R.Right, 0);
  B.Bottom := B.Top + H;
  if Hover then
    Col := CLR_KOFI_HOVER
  else if IsDarkColor(BackColor) then
    Col := CLR_KOFI_FACE_DARK
  else
    Col := CLR_KOFI_FACE;

  { Lage von Symbol und Herz }
  X := B.Left + ScalePx(7, PPI);
  S := ScalePx(16, PPI);
  D := ScalePx(5, PPI);
  HX := X + S + ScalePx(6, PPI) + D;
  HY := (B.Top + B.Bottom) div 2 - ScalePx(2, PPI);
  DrawSmoothPill(C, B, Col, BackColor, HX, HY, D);

  { vorne das Symbol des Programms (16 px bei 100 %) }
  if (AppIcon <> nil) and not AppIcon.Empty then
  begin
    AppIcon.Current := AppIcon.GetBestIndexForSize(Size(S, S));
    IR := Rect(X, (B.Top + B.Bottom - S) div 2, X + S, (B.Top + B.Bottom - S) div 2 + S);
    C.StretchDraw(IR, AppIcon);
  end;

  { Text weiss }
  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(HX + D + ScalePx(6, PPI), (B.Top + B.Bottom - C.TextHeight('Ag')) div 2, Text);
end;

procedure DrawAccentStrip(C: TCanvas; const R: TRect; const Colors: TStemColorArray);
var
  I, X0, X1, W: Integer;
begin
  W := R.Right - R.Left;
  C.Brush.Style := bsSolid;
  for I := 0 to 3 do
  begin
    { Teil I geht von I/4 bis (I+1)/4 der Breite - so bleibt keine Lücke,
      auch wenn die Breite nicht durch 4 teilbar ist }
    X0 := R.Left + (W * I) div 4;
    X1 := R.Left + (W * (I + 1)) div 4;
    C.Brush.Color := Colors[I];
    C.FillRect(Rect(X0, R.Top, X1, R.Bottom));
  end;
end;

procedure DrawStatusCell(C: TCanvas; const R: TRect; Look: TStatusLook;
  Percent: Integer; const Text: string; const Colors: TStemColorArray;
  BackColor, TextColor: TColor; Highlighted: Boolean; PPI: Integer);

  { 96-dpi-Mass auf den Bildschirm umrechnen }
  function S(V: Integer): Integer;
  begin
    if PPI <= 0 then PPI := 96;
    Result := (V * PPI + 48) div 96;
  end;

  { Text senkrecht mittig ab X schreiben, rechts an der Zelle abschneiden.
    Gibt das rechte Ende des Textes zurück. }
  function PutText(X: Integer; const T: string; Col: TColor): Integer;
  var
    Y: Integer;
  begin
    C.Font.Color := Col;
    C.Brush.Style := bsClear;
    Y := (R.Top + R.Bottom - C.TextHeight('Ag')) div 2;
    C.TextRect(Rect(X, R.Top, R.Right - S(2), R.Bottom), X, Y, T);
    Result := X + C.TextWidth(T);
  end;

var
  X, CY, BarW, FillW, I, D, Gap: Integer;
  Bar: TRect;
  Col: TColor;
begin
  { Hintergrund der ganzen Zelle }
  C.Brush.Style := bsSolid;
  C.Brush.Color := BackColor;
  C.FillRect(R);

  X := R.Left + S(6);
  CY := (R.Top + R.Bottom) div 2;

  case Look of
    slRun:
      begin
        Percent := EnsureRange(Percent, 0, 100);
        { Balken: höchstens 120 px, Platz für "100 %" daneben lassen }
        BarW := Min(S(120), R.Right - X - S(48));
        if BarW >= S(30) then
        begin
          Bar := Rect(X, CY - S(6), X + BarW, CY + S(6));
          C.Brush.Color := CLR_BAR_BORDER;
          C.FillRect(Bar);
          InflateRect(Bar, -1, -1);
          C.Brush.Color := CLR_BAR_BACK;
          C.FillRect(Bar);
          FillW := ((Bar.Right - Bar.Left) * Percent) div 100;
          if FillW > 0 then
          begin
            C.Brush.Color := CLR_BAR_FILL;
            C.FillRect(Rect(Bar.Left, Bar.Top, Bar.Left + FillW, Bar.Bottom));
          end;
          PutText(X + BarW + S(6), Format('%d %%', [Percent]), TextColor);
        end
        else
          PutText(X, Text, TextColor);    // Spalte zu schmal: nur der Text
      end;

    slOK:
      begin
        if Highlighted then Col := TextColor else Col := CLR_OK_TEXT;
        { Häkchen als zwei Linien (nicht als Zeichen "✓" - das fehlt in
          manchen Windows-Schriften) }
        C.Pen.Style := psSolid;
        C.Pen.Color := Col;
        C.Pen.Width := Max(1, S(2));
        C.MoveTo(X, CY);
        C.LineTo(X + S(3), CY + S(3));
        C.LineTo(X + S(9), CY - S(4));
        C.Pen.Width := 1;
        X := PutText(X + S(14), Text, Col);
        { vier Farbpunkte, nur wenn sie ganz Platz haben }
        D := S(8);
        Gap := S(3);
        X := X + S(8);
        if X + 4 * D + 3 * Gap <= R.Right - S(4) then
        begin
          C.Brush.Style := bsSolid;
          for I := 0 to 3 do
          begin
            C.Brush.Color := Colors[I];
            C.FillRect(Rect(X, CY - D div 2, X + D, CY - D div 2 + D));
            X := X + D + Gap;
          end;
        end;
      end;

    slFail:
      begin
        if Highlighted then Col := TextColor else Col := CLR_FAIL_TEXT;
        PutText(X, Text, Col);
      end;

    slWait:
      begin
        if Highlighted then Col := TextColor else Col := clGrayText;
        PutText(X, Text, Col);
      end;
  else
    PutText(X, Text, TextColor);
  end;
end;

end.
