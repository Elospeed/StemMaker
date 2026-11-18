{ ============================================================================
  zeittext_test.lpr  -  Automatischer Test der Zeitbeschriftung (StemPlayer)

  Autor   : Elospeed

  Prüft ZoomTimeText, besonders die Minutenwechsel (Fehler bis 1.8.6:
  "0:60.00" statt "1:00.00" und falsche Sekunden bei 1:10).
  Ende mit Code 0 = alles gut, 1 = mindestens ein Fehler.
  ============================================================================ }
program zeittext_test;

{$mode objfpc}{$H+}

uses
  SysUtils, zeittext;

var
  Fehler: Integer = 0;

procedure Pruefe(Sec: Double; Digits: Integer; const Soll: string);
var
  Ist: string;
begin
  Ist := ZoomTimeText(Sec, Digits);
  if Ist = Soll then
    WriteLn('ok      ', Sec:0:4, ' s, ', Digits, ' Stellen -> ', Ist)
  else
  begin
    WriteLn('FEHLER  ', Sec:0:4, ' s, ', Digits, ' Stellen -> ', Ist, ' (soll ', Soll, ')');
    Inc(Fehler);
  end;
end;

var
  i, d: Integer;
  T: Double;
  Txt: string;
begin
  Pruefe(0, 1, '0:00.0');
  Pruefe(57, 2, '0:57.00');
  Pruefe(60, 2, '1:00.00');
  Pruefe(59.9999, 2, '1:00.00');
  Pruefe(59.996, 2, '1:00.00');
  Pruefe(59.994, 2, '0:59.99');
  Pruefe(69.5, 2, '1:09.50');
  Pruefe(70, 2, '1:10.00');
  Pruefe(69.99999, 2, '1:10.00');
  Pruefe(70.5, 2, '1:10.50');
  Pruefe(90.5, 1, '1:30.5');
  Pruefe(90.25, 2, '1:30.25');
  Pruefe(90.125, 3, '1:30.125');
  Pruefe(65.3, 1, '1:05.3');
  Pruefe(599.96, 1, '10:00.0');
  Pruefe(3600, 1, '60:00.0');
  Pruefe(-1, 1, '0:00.0');
  Pruefe(61, 0, '1:01');
  { Rastermarken wie in der Wellenform (Vielfache eines Schritts, mit
    Rundungsfehlern): Sekunden nie 60 oder mehr, immer zweistellig }
  for d := 1 to 3 do
    for i := 0 to 20000 do
    begin
      T := i * 0.01 * 0.7 + i * 0.003;
      Txt := ZoomTimeText(T, d);
      if (Pos(':', Txt) = 0) or (Length(Copy(Txt, Pos(':', Txt) + 1, 2)) <> 2) or
         (StrToInt(Copy(Txt, Pos(':', Txt) + 1, 2)) >= 60) then
      begin
        WriteLn('FEHLER  ', T:0:6, ' s -> ', Txt);
        Inc(Fehler);
        Break;
      end;
    end;
  if Fehler = 0 then
    WriteLn('Alle Tests bestanden.')
  else
    WriteLn(Fehler, ' Test(s) fehlgeschlagen.');
  ExitCode := Ord(Fehler > 0);
end.
