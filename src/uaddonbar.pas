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

  Versionen:
    1.0  (27.10.2026)  Erste Version (Wunsch Speedy: Leiste statt "Anhören")
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
    FNextTop: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    { Knopf für AddOns\<ExeFile> anlegen; nil, wenn die Exe fehlt }
    function AddTile(const ExeFile, ACaption, AHint: string;
      AOnClick: TNotifyEvent): TAddOnTile;
  end;

implementation

const
  TILE_W   = 80;
  TILE_H   = 74;
  ICON_PX  = 40;

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
  Width := S(TILE_W + 12);
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Self;
  FTitle.AutoSize := False;
  FTitle.Alignment := taCenter;
  FTitle.Caption := 'AddOns';
  FTitle.Font.Color := clGrayText;
  FTitle.SetBounds(0, S(8), Width, S(18));
  FNextTop := 30;
end;

function TAddOnBar.AddTile(const ExeFile, ACaption, AHint: string;
  AOnClick: TNotifyEvent): TAddOnTile;
var
  Px: Integer;
begin
  Result := nil;
  if not FileExists(ExeFile) then Exit;
  Result := TAddOnTile.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(S(6), S(FNextTop),
    S(TILE_W), S(TILE_H));
  Px := S(ICON_PX);
  Result.FImage.SetBounds((Result.Width - Px) div 2, S(6), Px, Px);
  if not LoadExeIcon(Result.FImage, ExeFile, Px) then
    Result.FImage.Visible := False;
  Result.FLabel.SetBounds(0, S(6 + ICON_PX + 4), Result.Width, S(18));
  Result.FLabel.Caption := ACaption;
  Result.Hint := AHint;
  Result.FImage.Hint := AHint;
  Result.FLabel.Hint := AHint;
  Result.FImage.ShowHint := True;
  Result.FLabel.ShowHint := True;
  Result.OnClick := AOnClick;
  Inc(FNextTop, TILE_H + 6);
end;

end.
