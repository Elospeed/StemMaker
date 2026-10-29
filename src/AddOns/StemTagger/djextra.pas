unit djextra;

{ Zusätzliche dunkle Steuerelemente für den StemTagger, passend zu
  djcontrols.pas (StemPlayer):

    TDJCombo     Eingabefeld mit eigener dunkler Auswahlliste. Die Windows-
                 ComboBox lässt sich nicht ganz dunkel färben (Rahmen, Pfeil
                 und aufgeklappte Liste bleiben weiss).
    TDJLedSwitch Schalter mit LED davor: rot = aus, grün = an.

  Alles selbst gezeichnet, keine fremden Komponenten. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, ExtCtrls, Forms, LCLType,
  LMessages, LazUTF8, IntfGraphics, FPImage, djcontrols;

type
  TDJCombo = class;

  { aufgeklappte Liste: liegt direkt auf dem Formular über allem anderen }
  TDJDropList = class(TCustomControl)
  private
    FCombo: TDJCombo;      // gehört zu diesem Feld
    FTop: Integer;         // erster sichtbarer Eintrag
    FIndex: Integer;       // hervorgehobener Eintrag, -1 = keiner
    FRowH: Integer;        // Zeilenhöhe in Pixeln
    FRows: Integer;        // Anzahl sichtbarer Zeilen
    function ItemAt(Y: Integer): Integer;
    procedure ClampTop;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure MakeVisible(I: Integer);
  end;

  TDJCombo = class(TDJPanel)
  private
    FEdit: TEdit;          // Eingabe (frei tippen geht immer)
    FArrow: TPaintBox;     // Pfeil rechts, Klick klappt die Liste auf
    FArrowHover: Boolean;
    FItems: TStringList;   // Einträge der Liste
    FDrop: TDJDropList;    // nil, solange zugeklappt
    FAutoComplete: Boolean;
    FOnChange: TNotifyEvent;
    FOnSelect: TNotifyEvent;
    function GetText: string;
    procedure SetText(const AValue: string);
    function GetTextHint: string;
    procedure SetTextHint(const AValue: string);
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    procedure ArrowPaint(Sender: TObject);
    procedure ArrowClick(Sender: TObject);
    procedure ArrowEnter(Sender: TObject);
    procedure ArrowLeave(Sender: TObject);
    procedure UserInput(Sender: TObject; Msg: Cardinal);
    procedure CloseUpAsync(Data: PtrInt);
    procedure PickAsync(Data: PtrInt);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Resize; override;
    procedure SetColor(Value: TColor); override;
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure DropDown;
    procedure CloseUp;
    procedure Pick(I: Integer);
    function DroppedDown: Boolean;
    property Edit: TEdit read FEdit;
    property Items: TStringList read FItems;
    property Text: string read GetText write SetText;
    property TextHint: string read GetTextHint write SetTextHint;
    property AutoComplete: Boolean read FAutoComplete write FAutoComplete;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
  end;

  TDJLedSwitch = class(TGraphicControl)
  private
    FDown: Boolean;        // eingeschaltet
    FHover: Boolean;
    procedure SetDown(AValue: Boolean);
  protected
    procedure Paint; override;
    procedure Click; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    function NeededWidth: Integer;
    property Down: Boolean read FDown write SetDown;
  published
    property Caption;
    property OnClick;
  end;

const
  DJ_LED_OFF = $003A3ADC;   // LED aus: Rot  #DC3A3A

{ Kreis geglättet zeichnen (vierfach gross zeichnen, dann mitteln) }
procedure DrawSmoothDot(C: TCanvas; CX, CY, R: Integer; Col, Glow, Back: TColor);

implementation

const
  MAX_ROWS = 14;   // so viele Einträge sieht man aufgeklappt auf einmal
  SCROLL_W = 4;    // Breite der Bildlaufanzeige rechts

{ ============================================================================
  Hilfsfunktion
  ============================================================================ }

procedure DrawSmoothDot(C: TCanvas; CX, CY, R: Integer; Col, Glow, Back: TColor);
const
  SS = 4;   // Vergrösserung beim Zeichnen
var
  Big, Small: TBitmap;
  BigImg, SmallImg: TLazIntfImage;
  W, X, Y, I, J, M: Integer;
  Rs, Gs, Bs: Cardinal;
  Px: TFPColor;
begin
  W := 2 * R + 6;   // Platz für den Schein rundherum
  Big := TBitmap.Create;
  Small := TBitmap.Create;
  BigImg := nil;
  SmallImg := nil;
  try
    Big.PixelFormat := pf24bit;
    Big.SetSize(W * SS, W * SS);
    M := W * SS div 2;
    with Big.Canvas do
    begin
      Brush.Color := ColorToRGB(Back);
      FillRect(0, 0, W * SS, W * SS);
      if Glow <> clNone then
      begin
        Brush.Color := ColorToRGB(Glow);
        Pen.Color := Brush.Color;
        Ellipse(M - (R + 3) * SS, M - (R + 3) * SS, M + (R + 3) * SS, M + (R + 3) * SS);
      end;
      Brush.Color := ColorToRGB(Col);
      Pen.Color := Brush.Color;
      Ellipse(M - R * SS, M - R * SS, M + R * SS, M + R * SS);
    end;
    BigImg := Big.CreateIntfImage;
    Small.PixelFormat := pf24bit;
    Small.SetSize(W, W);
    SmallImg := Small.CreateIntfImage;
    for Y := 0 to W - 1 do
      for X := 0 to W - 1 do
      begin
        Rs := 0; Gs := 0; Bs := 0;
        for J := 0 to SS - 1 do
          for I := 0 to SS - 1 do
          begin
            Px := BigImg.Colors[X * SS + I, Y * SS + J];
            Inc(Rs, Px.Red); Inc(Gs, Px.Green); Inc(Bs, Px.Blue);
          end;
        Px.Red := Rs div (SS * SS);
        Px.Green := Gs div (SS * SS);
        Px.Blue := Bs div (SS * SS);
        Px.Alpha := alphaOpaque;
        SmallImg.Colors[X, Y] := Px;
      end;
    Small.LoadFromIntfImage(SmallImg);
    C.Draw(CX - W div 2, CY - W div 2, Small);
  finally
    SmallImg.Free;
    BigImg.Free;
    Small.Free;
    Big.Free;
  end;
end;

{ Farbe A zu Anteil P (0..100) mit Farbe B mischen }
function MixColor(A, B: TColor; P: Integer): TColor;
var
  CA, CB: LongInt;
begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(
    (Red(CA) * P + Red(CB) * (100 - P)) div 100,
    (Green(CA) * P + Green(CB) * (100 - P)) div 100,
    (Blue(CA) * P + Blue(CB) * (100 - P)) div 100);
end;

{ ============================================================================
  TDJDropList
  ============================================================================ }

constructor TDJDropList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := False;
  FIndex := -1;
end;

function TDJDropList.ItemAt(Y: Integer): Integer;
begin
  Result := FTop + (Y - 1) div FRowH;
  if (Y < 1) or (Result < 0) or (Result >= FCombo.Items.Count) then
    Result := -1;
end;

procedure TDJDropList.ClampTop;
begin
  if FTop > FCombo.Items.Count - FRows then FTop := FCombo.Items.Count - FRows;
  if FTop < 0 then FTop := 0;
end;

{ Eintrag I in den sichtbaren Bereich holen und hervorheben }
procedure TDJDropList.MakeVisible(I: Integer);
begin
  FIndex := I;
  if I >= 0 then
  begin
    if I < FTop then FTop := I;
    if I >= FTop + FRows then FTop := I - FRows + 1;
  end;
  ClampTop;
  Invalidate;
end;

procedure TDJDropList.Paint;
var
  I, Y, TH, Total, ThumbH, ThumbY: Integer;
  R: TRect;
begin
  with Canvas do
  begin
    Brush.Color := DJ_PANEL;
    FillRect(ClientRect);
    Font := FCombo.Edit.Font;
    TH := TextHeight('Ag');
    for I := FTop to FTop + FRows - 1 do
    begin
      if I >= FCombo.Items.Count then Break;
      Y := 1 + (I - FTop) * FRowH;
      R := Rect(1, Y, Self.Width - 1 - SCROLL_W - 2, Y + FRowH);
      if I = FIndex then
      begin
        Brush.Color := DJ_BTNBORDER;
        FillRect(R);
        Brush.Color := DJ_GREEN;      // grüner Streifen links wie im StemPlayer
        FillRect(Rect(1, Y, 4, Y + FRowH));
        Font.Color := clWhite;
      end
      else
        Font.Color := DJ_TEXT;
      Brush.Style := bsClear;
      TextOut(8, Y + (FRowH - TH) div 2, FCombo.Items[I]);
      Brush.Style := bsSolid;
    end;
    { Bildlaufanzeige rechts, nur wenn nicht alles Platz hat }
    Total := FCombo.Items.Count;
    if Total > FRows then
    begin
      ThumbH := (Self.Height - 2) * FRows div Total;
      if ThumbH < 12 then ThumbH := 12;
      ThumbY := 1 + (Self.Height - 2 - ThumbH) * FTop div (Total - FRows);
      Brush.Color := DJ_BG;
      FillRect(Rect(Self.Width - 1 - SCROLL_W - 1, 1, Self.Width - 1, Self.Height - 1));
      Brush.Color := DJ_DIM;
      FillRect(Rect(Self.Width - 1 - SCROLL_W, ThumbY, Self.Width - 2, ThumbY + ThumbH));
    end;
    Pen.Color := DJ_BTNBORDER;
    Brush.Style := bsClear;
    Rectangle(ClientRect);
    Brush.Style := bsSolid;
  end;
end;

procedure TDJDropList.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I, Total: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  Total := FCombo.Items.Count;
  { Bildlaufanzeige ziehen }
  if (ssLeft in Shift) and (X >= Width - SCROLL_W - 6) and (Total > FRows) then
  begin
    FTop := (Y * Total) div Height - FRows div 2;
    ClampTop;
    Invalidate;
    Exit;
  end;
  I := ItemAt(Y);
  if (I <> FIndex) and (I >= 0) then
  begin
    FIndex := I;
    Invalidate;
  end;
end;

procedure TDJDropList.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, Total: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  Total := FCombo.Items.Count;
  if (X >= Width - SCROLL_W - 6) and (Total > FRows) then
  begin
    { Klick auf die Bildlaufanzeige: dorthin springen }
    FTop := (Y * Total) div Height - FRows div 2;
    ClampTop;
    Invalidate;
    Exit;
  end;
  I := ItemAt(Y);
  { erst nach dem Ereignis übernehmen: Pick gibt diese Liste frei }
  if I >= 0 then
    Application.QueueAsyncCall(@FCombo.PickAsync, I);
end;

function TDJDropList.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then Dec(FTop, 3) else Inc(FTop, 3);
  ClampTop;
  Invalidate;
  Result := True;
end;

{ ============================================================================
  TDJCombo
  ============================================================================ }

constructor TDJCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := DJ_BG;
  BorderColor := DJ_BORDER;
  FItems := TStringList.Create;

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.BorderStyle := bsNone;
  FEdit.Color := DJ_BG;
  FEdit.Font.Color := DJ_TEXT;
  FEdit.ParentShowHint := True;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;
  FEdit.OnKeyUp := @EditKeyUp;
  FEdit.OnExit := @EditExit;

  FArrow := TPaintBox.Create(Self);
  FArrow.Parent := Self;
  FArrow.Align := alRight;
  FArrow.BorderSpacing.Around := 1;
  FArrow.Cursor := crHandPoint;
  FArrow.ParentShowHint := True;
  FArrow.OnPaint := @ArrowPaint;
  FArrow.OnClick := @ArrowClick;
  FArrow.OnMouseEnter := @ArrowEnter;
  FArrow.OnMouseLeave := @ArrowLeave;
end;

destructor TDJCombo.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  CloseUp;
  FItems.Free;
  inherited Destroy;
end;

procedure TDJCombo.Resize;
begin
  inherited Resize;
  if FArrow = nil then Exit;
  FArrow.Width := Height - 2;
  FEdit.SetBounds(6, (Height - FEdit.Height) div 2,
    Width - 6 - FArrow.Width - 4, FEdit.Height);
end;

procedure TDJCombo.SetColor(Value: TColor);
begin
  inherited SetColor(Value);
  if FEdit <> nil then FEdit.Color := Value;
end;

procedure TDJCombo.CMEnabledChanged(var Message: TLMessage);
begin
  inherited;
  if not Enabled then CloseUp;
  if FArrow <> nil then FArrow.Invalidate;
end;

function TDJCombo.GetText: string;
begin
  Result := FEdit.Text;
end;

procedure TDJCombo.SetText(const AValue: string);
begin
  FEdit.Text := AValue;
end;

function TDJCombo.GetTextHint: string;
begin
  Result := FEdit.TextHint;
end;

procedure TDJCombo.SetTextHint(const AValue: string);
begin
  FEdit.TextHint := AValue;
end;

procedure TDJCombo.EditChange(Sender: TObject);
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

{ Pfeiltasten, Enter und Escape steuern die Liste, der Fokus bleibt im Feld }
procedure TDJCombo.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  I: Integer;
begin
  if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
  begin
    if DroppedDown then CloseUp else DropDown;
    Key := 0;
    Exit;
  end;
  if not DroppedDown then
  begin
    if Key = VK_DOWN then
    begin
      DropDown;
      Key := 0;
    end;
    Exit;
  end;
  case Key of
    VK_DOWN, VK_UP:
      begin
        I := FDrop.FIndex;
        if Key = VK_DOWN then Inc(I) else Dec(I);
        if I < 0 then I := 0;
        if I >= FItems.Count then I := FItems.Count - 1;
        FDrop.MakeVisible(I);
        Key := 0;
      end;
    VK_RETURN:
      begin
        if FDrop.FIndex >= 0 then Pick(FDrop.FIndex) else CloseUp;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        CloseUp;
        Key := 0;
      end;
  end;
end;

{ Ergänzen beim Tippen: "Tech H" -> "Tech House", der ergänzte Teil ist
  markiert und wird beim Weitertippen überschrieben }
procedure TDJCombo.EditKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  S: string;
  I, N: Integer;
begin
  if not FAutoComplete then Exit;
  if Key in [VK_BACK, VK_DELETE, VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_HOME,
    VK_END, VK_RETURN, VK_ESCAPE, VK_TAB, VK_SHIFT, VK_CONTROL, VK_MENU] then Exit;
  S := FEdit.Text;
  N := Length(S);
  if (N = 0) or (FEdit.SelStart <> N) then Exit;
  for I := 0 to FItems.Count - 1 do
    if (Length(FItems[I]) > N) and
       (UTF8LowerCase(Copy(FItems[I], 1, N)) = UTF8LowerCase(S)) then
    begin
      FEdit.Text := FItems[I];   // Schreibweise aus der Liste ("tech h" -> "Tech House")
      FEdit.SelStart := N;
      FEdit.SelLength := Length(FItems[I]) - N;
      Exit;
    end;
end;

procedure TDJCombo.EditExit(Sender: TObject);
begin
  CloseUp;
end;

procedure TDJCombo.ArrowPaint(Sender: TObject);
var
  CX, CY, D: Integer;
begin
  with FArrow.Canvas do
  begin
    Brush.Color := Color;
    FillRect(FArrow.ClientRect);
    { kleines Dreieck nach unten }
    if not Enabled then Brush.Color := DJ_BORDER
    else if FArrowHover or DroppedDown then Brush.Color := DJ_TEXT
    else Brush.Color := DJ_DIM;
    Pen.Color := Brush.Color;
    CX := FArrow.Width div 2;
    CY := FArrow.Height div 2;
    D := FArrow.Height div 7;
    if D < 3 then D := 3;
    Polygon([Point(CX - D, CY - D div 2), Point(CX + D, CY - D div 2), Point(CX, CY + D div 2 + 1)]);
  end;
end;

procedure TDJCombo.ArrowClick(Sender: TObject);
begin
  if not Enabled then Exit;
  if DroppedDown then CloseUp
  else
  begin
    if FEdit.CanFocus then FEdit.SetFocus;
    DropDown;
  end;
end;

procedure TDJCombo.ArrowEnter(Sender: TObject);
begin
  FArrowHover := True;
  FArrow.Invalidate;
end;

procedure TDJCombo.ArrowLeave(Sender: TObject);
begin
  FArrowHover := False;
  FArrow.Invalidate;
end;

function TDJCombo.DroppedDown: Boolean;
begin
  Result := FDrop <> nil;
end;

{ Liste aufklappen: unter dem Feld, wenn dort Platz ist, sonst darüber }
procedure TDJCombo.DropDown;
var
  Frm: TCustomForm;
  P: TPoint;
  H, I: Integer;
begin
  if DroppedDown or (FItems.Count = 0) then Exit;
  Frm := GetParentForm(Self);
  if Frm = nil then Exit;
  FDrop := TDJDropList.Create(Self);
  FDrop.FCombo := Self;
  { Zeilenhöhe mit der Schrift des Felds messen (die Liste hat noch kein Fenster) }
  Canvas.Font := FEdit.Font;
  FDrop.FRowH := Canvas.TextHeight('Ag') + Scale96ToForm(5);
  FDrop.FRows := FItems.Count;
  if FDrop.FRows > MAX_ROWS then FDrop.FRows := MAX_ROWS;
  H := FDrop.FRows * FDrop.FRowH + 2;
  P := ClientToParent(Point(0, 0), Frm);
  { nicht über den Rand des Fensters hinaus }
  while (P.Y + Height + H > Frm.ClientHeight) and (P.Y - H < 0) and (FDrop.FRows > 3) do
  begin
    Dec(FDrop.FRows);
    H := FDrop.FRows * FDrop.FRowH + 2;
  end;
  if P.Y + Height + H <= Frm.ClientHeight then
    FDrop.SetBounds(P.X, P.Y + Height - 1, Width, H)
  else
    FDrop.SetBounds(P.X, P.Y - H + 1, Width, H);
  FDrop.Parent := Frm;
  FDrop.BringToFront;
  { aktuellen Wert hervorheben }
  I := FItems.IndexOf(FEdit.Text);
  if I < 0 then
    for I := 0 to FItems.Count - 1 do
      if UTF8LowerCase(FItems[I]) = UTF8LowerCase(Trim(FEdit.Text)) then Break;
  if (I >= FItems.Count) then I := -1;
  FDrop.MakeVisible(I);
  if I >= 0 then
  begin
    { gewählten Eintrag etwa in die Mitte }
    FDrop.FTop := I - FDrop.FRows div 2;
    FDrop.ClampTop;
  end;
  Application.AddOnUserInputHandler(@UserInput);
  FArrow.Invalidate;
end;

procedure TDJCombo.CloseUp;
begin
  if FDrop = nil then Exit;
  Application.RemoveOnUserInputHandler(@UserInput);
  FDrop.Free;
  FDrop := nil;
  if FArrow <> nil then FArrow.Invalidate;
end;

procedure TDJCombo.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  { Liste wurde mit dem Formular freigegeben }
  if (Operation = opRemove) and (AComponent = FDrop) then
  begin
    Application.RemoveOnUserInputHandler(@UserInput);
    FDrop := nil;
  end;
end;

procedure TDJCombo.CloseUpAsync(Data: PtrInt);
begin
  CloseUp;
end;

procedure TDJCombo.PickAsync(Data: PtrInt);
begin
  if DroppedDown then Pick(Data);
end;

{ Eintrag I übernehmen und zuklappen }
procedure TDJCombo.Pick(I: Integer);
begin
  CloseUp;
  if (I < 0) or (I >= FItems.Count) then Exit;
  FEdit.Text := FItems[I];      // löst OnChange aus
  FEdit.SelectAll;
  if Assigned(FOnSelect) then FOnSelect(Self);
end;

{ Klick irgendwo ausserhalb von Feld und Liste klappt die Liste zu }
procedure TDJCombo.UserInput(Sender: TObject; Msg: Cardinal);
var
  P: TPoint;
  Inside: Boolean;
begin
  if FDrop = nil then Exit;
  case Msg of
    LM_LBUTTONDOWN, LM_RBUTTONDOWN, LM_MBUTTONDOWN,
    LM_NCLBUTTONDOWN:
      begin
        P := Mouse.CursorPos;
        Inside := PtInRect(Rect(0, 0, FDrop.Width, FDrop.Height), FDrop.ScreenToClient(P)) or
                  PtInRect(Rect(0, 0, Width, Height), ScreenToClient(P));
        if not Inside then
          Application.QueueAsyncCall(@CloseUpAsync, 0);
      end;
  end;
end;

{ ============================================================================
  TDJLedSwitch
  ============================================================================ }

constructor TDJLedSwitch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Cursor := crHandPoint;
  Width := 160;
  Height := 22;
end;

procedure TDJLedSwitch.SetDown(AValue: Boolean);
begin
  if FDown = AValue then Exit;
  FDown := AValue;
  Invalidate;
end;

{ Breite für LED + Text }
function TDJLedSwitch.NeededWidth: Integer;
begin
  Canvas.Font := Font;
  Result := Scale96ToForm(22) + Canvas.TextWidth(Caption) + Scale96ToForm(4);
end;

procedure TDJLedSwitch.Paint;
var
  R, CX, CY: Integer;
  Col, Back: TColor;
begin
  Back := Parent.Color;
  if (Back = clDefault) or (Back = clNone) then Back := clBtnFace;
  with Canvas do
  begin
    Brush.Color := Back;
    FillRect(ClientRect);
    R := Scale96ToForm(4);
    CX := Scale96ToForm(8);
    CY := Self.Height div 2;
    if FDown then Col := DJ_GREEN else Col := DJ_LED_OFF;
    { leuchtende LED mit schwachem Schein, aus = rot ohne Schein }
    if FDown then
      DrawSmoothDot(Canvas, CX, CY, R, Col, MixColor(Col, Back, 30), Back)
    else
      DrawSmoothDot(Canvas, CX, CY, R, Col, clNone, Back);
    Font := Self.Font;
    if FHover then Font.Color := clWhite
    else if FDown then Font.Color := DJ_TEXT
    else Font.Color := DJ_DIM;
    Brush.Style := bsClear;
    TextOut(Scale96ToForm(20), (Self.Height - TextHeight('Ag')) div 2, Caption);
    Brush.Style := bsSolid;
  end;
end;

procedure TDJLedSwitch.Click;
begin
  FDown := not FDown;
  Invalidate;
  inherited Click;
end;

procedure TDJLedSwitch.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TDJLedSwitch.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

end.
