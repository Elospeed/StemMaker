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
  Classes, SysUtils, Graphics, Types, Math;

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
  CLR_KOFI       = TColor($005E5AFF);   // Ko-fi-Rot     #FF5A5E (wie im Danke-Fenster)
  CLR_KOFI_HOVER = TColor($004D48E5);   // etwas dunkler #E5484D (Maus darüber)

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

{ Breite des Ko-fi-Knopfs für den Text (Herz + Text + Rand), in Pixel.
  Die Schrift der Leinwand muss schon gesetzt sein (fett, siehe unten). }
function KofiButtonWidth(C: TCanvas; const Text: string; PPI: Integer): Integer;

{ Ko-fi-Knopf zeichnen: Hintergrund BackColor, darauf der rote Knopf mit
  weissem Herz und Text, senkrecht mittig im Rechteck R.
  Hover = True -> Maus ist darüber, der Knopf wird etwas dunkler. }
procedure DrawKofiButton(C: TCanvas; const R: TRect; const Text: string;
  Hover: Boolean; BackColor: TColor; PPI: Integer);

implementation

{ 96-dpi-Mass auf den Bildschirm umrechnen }
function ScalePx(V, PPI: Integer): Integer;
begin
  if PPI <= 0 then PPI := 96;
  Result := (V * PPI + 48) div 96;
end;

function KofiButtonWidth(C: TCanvas; const Text: string; PPI: Integer): Integer;
begin
  { 10 Rand links, 9 Herz, 6 Abstand, Text, 10 Rand rechts }
  Result := ScalePx(35, PPI) + C.TextWidth(Text);
end;

procedure DrawKofiButton(C: TCanvas; const R: TRect; const Text: string;
  Hover: Boolean; BackColor: TColor; PPI: Integer);
var
  B: TRect;        // der Knopf selbst
  H, HX, HY, D: Integer;
  Col: TColor;
begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := BackColor;
  C.FillRect(R);

  { Knopf: so hoch wie die Schrift plus etwas Luft, rechts bündig }
  H := Min(R.Bottom - R.Top - ScalePx(4, PPI), C.TextHeight('Ag') + ScalePx(6, PPI));
  B := Rect(R.Left, (R.Top + R.Bottom - H) div 2, R.Right, 0);
  B.Bottom := B.Top + H;
  if Hover then Col := CLR_KOFI_HOVER else Col := CLR_KOFI;
  C.Brush.Color := Col;
  C.Pen.Color := Col;
  C.RoundRect(B, H, H);   // ganz runde Enden

  { Herz aus zwei Kreisen und einem Dreieck (nicht jede Schrift hat ♥) }
  D := ScalePx(5, PPI);
  HX := B.Left + ScalePx(14, PPI);
  HY := (B.Top + B.Bottom) div 2 - ScalePx(2, PPI);
  C.Brush.Color := clWhite;
  C.Pen.Color := clWhite;
  C.Ellipse(HX - D, HY - D div 2, HX + 1, HY + D div 2 + 1);
  C.Ellipse(HX, HY - D div 2, HX + D + 1, HY + D div 2 + 1);
  C.Polygon([Point(HX - D, HY + 1), Point(HX + D, HY + 1), Point(HX, HY + D + ScalePx(1, PPI))]);

  { Text weiss auf Rot }
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
