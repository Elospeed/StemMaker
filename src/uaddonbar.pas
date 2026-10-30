{ ============================================================================
  uaddonbar.pas  -  Seitenleiste mit den AddOns im Hauptfenster

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Rechts neben der Dateiliste steht eine schmale Leiste mit einem Knopf
  pro AddOn (StemPlayer, StemTagger ...): Symbol und Name darunter. Das
  Symbol kommt direkt aus der Exe des AddOns (AddOns\<Name>.exe), so muss
  StemMaker selbst keine Bilder mitbringen und ein neues AddOn bekommt
  automatisch sein eigenes Symbol. Fehlt die Exe, wird der Knopf nicht
  angezeigt.

  Ist die Leiste niedriger als alle Knöpfe (kleines Fenster, grosse
  Anzeigeskalierung, Log hochgezogen), werden die Knöpfe kleiner statt
  unten verdeckt: erst ohne Namen, dann kleinere Symbole, zuletzt zwei
  nebeneinander. Der Name steht dann im Tooltip.

  Versionen:
    1.0  (27.10.2026)  Erste Version (Wunsch Speedy: Leiste statt "Anhören")
    1.1  (30.10.2026)  Knöpfe werden kleiner, statt bei kleinem Fenster
                       verdeckt zu werden (Meldung Speedy)
  ============================================================================ }
unit uaddonbar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Graphics, Forms
  {$IFDEF WINDOWS}, Windows{$ENDIF};

type
  { ein Knopf in der Leiste: Panel mit Symbol und Name, ganz anklickbar }
  TAddOnTile = class(TPanel)
  private
    FImage: TImage;
    FLabel: TLabel;
    FHover: Boolean;
    FName, FHintText: string;
    procedure ChildClick(Sender: TObject);
    procedure ChildEnter(Sender: TObject);
    procedure ChildLeave(Sender: TObject);
    procedure SetHover(AValue: Boolean);
  protected
    procedure Paint; override;
    procedure SetEnabled(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TAddOnBar = class(TPanel)
  private
    FTitle: TLabel;
    FTiles: TList;
    FArranging: Boolean;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Höhe (Bildschirm-Pixel), in der alle Knöpfe in voller Grösse passen }
    function FullHeight: Integer;
    { Knöpfe passend zur Höhe anordnen (läuft bei jeder Grössenänderung) }
    procedure ArrangeTiles;
    { Knopf für AddOns\<ExeFile> anlegen; nil, wenn die Exe fehlt }
    function AddTile(const ExeFile, ACaption, AHint: string;
      AOnClick: TNotifyEvent): TAddOnTile;
  end;

implementation

const
  TILE_W   = 80;
  ICON_PX  = 40;

type
  { Stufen, von gross nach klein; alle Masse in 96-dpi-Pixeln }
  TTileStufe = record
    Oben, Hoehe, Abstand, Symbol: Integer;
    MitTitel, MitName, ZweiSpalten: Boolean;
  end;

const
  STUFEN: array[0..3] of TTileStufe = (
    (Oben: 30; Hoehe: 74; Abstand: 6; Symbol: 40; MitTitel: True;  MitName: True;  ZweiSpalten: False),
    (Oben: 6;  Hoehe: 50; Abstand: 4; Symbol: 40; MitTitel: False; MitName: False; ZweiSpalten: False),
    (Oben: 4;  Hoehe: 34; Abstand: 2; Symbol: 26; MitTitel: False; MitName: False; ZweiSpalten: False),
    (Oben: 4;  Hoehe: 34; Abstand: 2; Symbol: 26; MitTitel: False; MitName: False; ZweiSpalten: True));

{ Pixel bei 96 dpi -> Pixel bei der aktuellen Bildschirm-Skalierung }
function S(X: Integer): Integer;
begin
  Result := MulDiv(X, Screen.PixelsPerInch, 96);
end;

{$IFDEF WINDOWS}
{ liefert ein Symbol in passender Grösse aus einer Exe (Windows ab Vista) }
function PrivateExtractIconsW(lpszFile: PWideChar; nIconIndex, cxIcon, cyIcon: Integer;
  phicon: Pointer; piconid: PUINT; nIcons, flags: UINT): UINT; stdcall;
  external 'user32.dll' name 'PrivateExtractIconsW';
{$ENDIF}

{ Symbol der Exe in Img laden; False = keins gefunden }
function LoadExeIcon(Img: TImage; const ExeFile: string; Size: Integer): Boolean;
{$IFDEF WINDOWS}
var
  H: HICON;
  Id: UINT;
  W: WideString;
begin
  Result := False;
  W := UTF8Decode(ExeFile);
  H := 0;
  if (PrivateExtractIconsW(PWideChar(W), 0, Size, Size, @H, @Id, 1, 0) = 1) and (H <> 0) then
  begin
    Img.Picture.Icon.Handle := H;   // TIcon übernimmt das Handle und gibt es frei
    Result := True;
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

{ TAddOnTile }

constructor TAddOnTile.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentColor := True;
  ShowHint := True;
  Cursor := crHandPoint;
  OnMouseEnter := @ChildEnter;
  OnMouseLeave := @ChildLeave;
  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Center := True;
  FImage.Stretch := True;          // kleinere Stufen: Symbol verkleinern
  FImage.Proportional := True;
  FImage.Cursor := crHandPoint;
  FImage.OnClick := @ChildClick;
  FImage.OnMouseEnter := @ChildEnter;
  FImage.OnMouseLeave := @ChildLeave;
  FLabel := TLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.Alignment := taCenter;
  FLabel.AutoSize := False;
  FLabel.Cursor := crHandPoint;
  FLabel.OnClick := @ChildClick;
  FLabel.OnMouseEnter := @ChildEnter;
  FLabel.OnMouseLeave := @ChildLeave;
end;

procedure TAddOnTile.ChildClick(Sender: TObject);
begin
  if Enabled then Click;
end;

procedure TAddOnTile.ChildEnter(Sender: TObject);
begin
  SetHover(True);
end;

{ Maus verlässt Symbol oder Text: nur aufhören, wenn sie auch nicht mehr
  über dem Knopf selbst ist (beim Wechsel Symbol -> Text kommt sonst ein
  kurzes Flackern) }
procedure TAddOnTile.ChildLeave(Sender: TObject);
begin
  SetHover(PtInRect(ClientRect, ScreenToClient(Mouse.CursorPos)));
end;

procedure TAddOnTile.SetHover(AValue: Boolean);
begin
  if FHover = AValue then Exit;
  FHover := AValue;
  Invalidate;
end;

procedure TAddOnTile.Paint;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  { Rahmen in der Markierfarbe, solange die Maus darüber ist }
  if FHover and Enabled then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := clHighlight;
    Canvas.Pen.Width := S(2);
    Canvas.RoundRect(S(1), S(1), Width - S(1), Height - S(1), S(10), S(10));
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TAddOnTile.SetEnabled(Value: Boolean);
begin
  inherited SetEnabled(Value);
  FLabel.Enabled := Value;
  FImage.Enabled := Value;
  Invalidate;
end;

{ TAddOnBar }

constructor TAddOnBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FTiles := TList.Create;
  { Breite in der dpi, die das Fenster JETZT hat (die Leiste entsteht in
    FormCreate, die LCL rechnet das Fenster danach evtl. noch um; sonst
    doppelt skaliert). Die Knöpfe ordnet ArrangeTiles bei jeder
    Grössenänderung mit Scale96ToForm neu an. }
  if AOwner is TCustomForm then
    Width := TCustomForm(AOwner).Scale96ToForm(TILE_W + 12)
  else
    Width := TILE_W + 12;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Self;
  FTitle.AutoSize := False;
  FTitle.Alignment := taCenter;
  FTitle.Caption := 'AddOns';
  FTitle.Font.Color := clGrayText;
end;

destructor TAddOnBar.Destroy;
begin
  FTiles.Free;
  inherited Destroy;
end;

function TAddOnBar.FullHeight: Integer;
begin
  Result := Scale96ToForm(STUFEN[0].Oben +
    FTiles.Count * (STUFEN[0].Hoehe + STUFEN[0].Abstand));
end;

procedure TAddOnBar.Resize;
begin
  inherited Resize;
  ArrangeTiles;
end;

{ grösste Stufe wählen, in der alle Knöpfe in die Höhe der Leiste passen }
procedure TAddOnBar.ArrangeTiles;
var
  St: Integer;
  Z: TTileStufe;
  I, N, Zeilen, W, Px, X, Y: Integer;
  T: TAddOnTile;
begin
  { Scale96ToForm braucht das Fenster (im Konstruktor noch ohne Parent) }
  if FArranging or (FTiles = nil) or (GetParentForm(Self) = nil) then Exit;
  N := FTiles.Count;
  St := High(STUFEN);
  for I := Low(STUFEN) to High(STUFEN) do
  begin
    Z := STUFEN[I];
    if Z.ZweiSpalten then Zeilen := (N + 1) div 2 else Zeilen := N;
    if Scale96ToForm(Z.Oben + Zeilen * (Z.Hoehe + Z.Abstand)) <= ClientHeight then
    begin
      St := I;
      Break;
    end;
  end;
  Z := STUFEN[St];
  FArranging := True;
  DisableAlign;
  try
    FTitle.Visible := Z.MitTitel;
    FTitle.SetBounds(0, Scale96ToForm(8), ClientWidth, Scale96ToForm(18));
    if Z.ZweiSpalten then W := Scale96ToForm(TILE_W div 2) else W := Scale96ToForm(TILE_W);
    Px := Scale96ToForm(Z.Symbol);
    for I := 0 to N - 1 do
    begin
      T := TAddOnTile(FTiles[I]);
      if Z.ZweiSpalten then
      begin
        X := Scale96ToForm(6) + (I mod 2) * W;
        Y := Scale96ToForm(Z.Oben + (I div 2) * (Z.Hoehe + Z.Abstand));
      end
      else
      begin
        X := Scale96ToForm(6);
        Y := Scale96ToForm(Z.Oben + I * (Z.Hoehe + Z.Abstand));
      end;
      T.SetBounds(X, Y, W, Scale96ToForm(Z.Hoehe));
      if Z.MitName then
        Y := Scale96ToForm(6)
      else
        Y := (Scale96ToForm(Z.Hoehe) - Px) div 2;
      T.FImage.SetBounds((W - Px) div 2, Y, Px, Px);
      T.FLabel.Visible := Z.MitName;
      if Z.MitName then
      begin
        T.FLabel.SetBounds(0, Scale96ToForm(6 + ICON_PX + 4), W, Scale96ToForm(18));
        T.Hint := T.FHintText;
      end
      else
        T.Hint := T.FName + ': ' + T.FHintText;   // Name fehlt -> im Tooltip
      T.FImage.Hint := T.Hint;
      T.FLabel.Hint := T.Hint;
    end;
  finally
    EnableAlign;
    FArranging := False;
  end;
end;

function TAddOnBar.AddTile(const ExeFile, ACaption, AHint: string;
  AOnClick: TNotifyEvent): TAddOnTile;
begin
  Result := nil;
  if not FileExists(ExeFile) then Exit;
  Result := TAddOnTile.Create(Self);
  Result.Parent := Self;
  { das Symbol in der grössten Endgrösse holen, kleinere Stufen verkleinern es }
  if not LoadExeIcon(Result.FImage, ExeFile, S(ICON_PX)) then
    Result.FImage.Visible := False;
  Result.FName := ACaption;
  Result.FHintText := AHint;
  Result.FLabel.Caption := ACaption;
  Result.FImage.ShowHint := True;
  Result.FLabel.ShowHint := True;
  Result.OnClick := AOnClick;
  FTiles.Add(Result);
  ArrangeTiles;
end;

end.
