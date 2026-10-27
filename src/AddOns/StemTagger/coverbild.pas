{ ============================================================================
  coverbild.pas  -  Cover-Bilder für den StemTagger vorbereiten

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Ein MP4-Cover muss JPEG oder PNG sein. Diese Unit
    - übernimmt JPEG/PNG unverändert (keine Qualitätsverluste),
    - wandelt BMP und GIF in JPEG um,
    - verkleinert auf Wunsch sehr grosse Bilder (z.B. 3000 x 3000 Pixel)
      auf eine vernünftige Grösse. Traktor zeigt das Cover ohnehin klein,
      ein 5-MB-Bild würde nur jede Datei unnötig aufblähen.
  Benutzt nur fcl-image aus Free Pascal (keine Fremdbibliothek).

  Versionen:
    1.0  (27.10.2026)  Erste Version
  ============================================================================ }
unit coverbild;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FPImage, FPImgCanv, FPCanvas, FPReadJPEG, FPWriteJPEG,
  FPReadPNG, FPReadBMP, FPReadGif;

const
  COVER_MAX_SIDE = 1000;   // so gross wird verkleinert (längere Seite)
  COVER_JPEG_QUALITY = 90;

{ Bilddaten (beliebiges unterstütztes Format) als Cover vorbereiten.
  MaxSide = 0: nie verkleinern. Info: kurzer Text für das Log
  (z.B. '3000x3000 -> 1000x1000'). False = kein lesbares Bild. }
function PrepareCover(const Data: TBytes; MaxSide: Integer; out Res: TBytes;
  out Info: string): Boolean;

{ Ein bereits geladenes Bild (z.B. aus der Zwischenablage) als JPEG-Cover }
function CoverFromImage(Img: TFPCustomImage; MaxSide: Integer): TBytes;

{ Dateiendung passend zum Cover: '.jpg' oder '.png' }
function CoverExt(const Data: TBytes): string;

{ Grösse eines Bildes lesen (für die Anzeige), False = nicht lesbar }
function CoverSize(const Data: TBytes; out W, H: Integer): Boolean;

implementation

type
  TImgKind = (ikNone, ikJpeg, ikPng, ikBmp, ikGif);

{ Bildformat an den ersten Bytes erkennen }
function DetectKind(const Data: TBytes): TImgKind;
begin
  Result := ikNone;
  if Length(Data) < 8 then Exit;
  if (Data[0] = $FF) and (Data[1] = $D8) then Result := ikJpeg
  else if (Data[0] = $89) and (Data[1] = $50) and (Data[2] = $4E) and (Data[3] = $47) then Result := ikPng
  else if (Data[0] = Ord('B')) and (Data[1] = Ord('M')) then Result := ikBmp
  else if (Data[0] = Ord('G')) and (Data[1] = Ord('I')) and (Data[2] = Ord('F')) then Result := ikGif;
end;

function MakeReader(K: TImgKind): TFPCustomImageReader;
begin
  case K of
    ikJpeg: Result := TFPReaderJPEG.Create;
    ikPng : Result := TFPReaderPNG.Create;
    ikBmp : Result := TFPReaderBMP.Create;
    ikGif : Result := TFPReaderGif.Create;
  else
    Result := nil;
  end;
end;

{ Bild laden, nil = nicht lesbar. Aufrufer gibt das Bild frei. }
function LoadImage(const Data: TBytes): TFPMemoryImage;
var
  R: TFPCustomImageReader;
  S: TMemoryStream;
begin
  Result := nil;
  R := MakeReader(DetectKind(Data));
  if R = nil then Exit;
  S := TMemoryStream.Create;
  try
    S.WriteBuffer(Data[0], Length(Data));
    S.Position := 0;
    Result := TFPMemoryImage.Create(0, 0);
    try
      Result.LoadFromStream(S, R);
    except
      FreeAndNil(Result);
    end;
  finally
    S.Free;
    R.Free;
  end;
end;

{ Als JPEG speichern, dabei auf MaxSide verkleinern (weiche Interpolation) }
function EncodeJpeg(Img: TFPCustomImage; MaxSide: Integer): TBytes;
var
  W, H: Integer;
  Dst: TFPMemoryImage;
  Cnv: TFPImageCanvas;
  Wr: TFPWriterJPEG;
  S: TMemoryStream;
  Src: TFPCustomImage;
begin
  Result := nil;
  W := Img.Width;
  H := Img.Height;
  if (MaxSide > 0) and ((W > MaxSide) or (H > MaxSide)) then
  begin
    if W >= H then
    begin
      H := Round(H * MaxSide / W);
      W := MaxSide;
    end
    else
    begin
      W := Round(W * MaxSide / H);
      H := MaxSide;
    end;
    if W < 1 then W := 1;
    if H < 1 then H := 1;
  end;
  Dst := nil;
  Src := Img;
  if (W <> Img.Width) or (H <> Img.Height) then
  begin
    Dst := TFPMemoryImage.Create(W, H);
    Cnv := TFPImageCanvas.Create(Dst);
    try
      Cnv.Interpolation := TMitchelInterpolation.Create;
      try
        Cnv.StretchDraw(0, 0, W, H, Img);
      finally
        Cnv.Interpolation.Free;
        Cnv.Interpolation := nil;
      end;
    finally
      Cnv.Free;
    end;
    Src := Dst;
  end;
  S := TMemoryStream.Create;
  Wr := TFPWriterJPEG.Create;
  try
    Wr.CompressionQuality := COVER_JPEG_QUALITY;
    Src.SaveToStream(S, Wr);
    SetLength(Result, S.Size);
    if S.Size > 0 then
      Move(S.Memory^, Result[0], S.Size);
  finally
    Wr.Free;
    S.Free;
    Dst.Free;
  end;
end;

function PrepareCover(const Data: TBytes; MaxSide: Integer; out Res: TBytes;
  out Info: string): Boolean;
var
  K: TImgKind;
  Img: TFPMemoryImage;
begin
  Result := False;
  Res := nil;
  Info := '';
  K := DetectKind(Data);
  if K = ikNone then Exit;
  Img := LoadImage(Data);
  if Img = nil then Exit;
  try
    Info := Format('%dx%d', [Img.Width, Img.Height]);
    if (K in [ikJpeg, ikPng]) and
       ((MaxSide = 0) or ((Img.Width <= MaxSide) and (Img.Height <= MaxSide))) then
      Res := Copy(Data)                       // unverändert übernehmen
    else
    begin
      Res := EncodeJpeg(Img, MaxSide);
      Info := Info + ' -> JPEG';
      if (MaxSide > 0) and ((Img.Width > MaxSide) or (Img.Height > MaxSide)) then
        Info := Info + Format(' %d px', [MaxSide]);
    end;
    Result := Length(Res) > 0;
  finally
    Img.Free;
  end;
end;

function CoverFromImage(Img: TFPCustomImage; MaxSide: Integer): TBytes;
begin
  Result := EncodeJpeg(Img, MaxSide);
end;

function CoverExt(const Data: TBytes): string;
begin
  if DetectKind(Data) = ikPng then
    Result := '.png'
  else
    Result := '.jpg';
end;

function CoverSize(const Data: TBytes; out W, H: Integer): Boolean;
var
  Img: TFPMemoryImage;
begin
  W := 0;
  H := 0;
  Img := LoadImage(Data);
  Result := Img <> nil;
  if Result then
  begin
    W := Img.Width;
    H := Img.Height;
    Img.Free;
  end;
end;

end.
