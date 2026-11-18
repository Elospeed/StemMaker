{ ============================================================================
  zeittext.pas  -  Zeitbeschriftung für die Zoom-Wellenform (StemPlayer)

  Autor   : Elospeed

  Eigene Unit ohne LCL, damit der Konsolentest tests/zeittext_test sie
  ohne Oberfläche prüfen kann.
  ============================================================================ }
unit zeittext;

{$mode objfpc}{$H+}

interface

{ Zeit für die Rasterbeschriftung, z.B. 1:30.5, 1:30.25 oder 1:30.125.
  Digits = Nachkommastellen (0 bis 3). Erst wird auf die gezeigten Stellen
  gerundet, dann in Minuten und Sekunden zerlegt: so wird 59,999 s mit zwei
  Stellen zu 1:00.00 und nicht zu 0:60.00 (1.8.7). }
function ZoomTimeText(Sec: Double; Digits: Integer): string;

implementation

uses
  SysUtils;

function ZoomTimeText(Sec: Double; Digits: Integer): string;
var
  Teiler, Ganz, M, S, Rest: Int64;
  i: Integer;
begin
  if Digits < 0 then Digits := 0;
  if Digits > 3 then Digits := 3;
  if Sec < 0 then Sec := 0;
  Teiler := 1;
  for i := 1 to Digits do Teiler := Teiler * 10;
  Ganz := Round(Sec * Teiler);              // Zeit in 1/Teiler Sekunden
  M := Ganz div (60 * Teiler);
  Rest := Ganz mod (60 * Teiler);
  S := Rest div Teiler;
  Result := IntToStr(M) + ':' + Format('%.2d', [S]);
  if Digits > 0 then
    Result := Result + '.' + Format('%.*d', [Digits, Rest mod Teiler]);
end;

end.
