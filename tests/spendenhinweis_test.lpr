{ ============================================================================
  spendenhinweis_test.lpr  -  Automatischer Test: wann kommt der Spenden-Hinweis?

  Autor   : Elospeed

  Prüft uDonateLogik: Marken, einmal pro neuer Haupt-/Unterversion (nicht
  bei 2.5.1), "Nicht mehr fragen" bis zur nächsten Version, höchstens ein
  Hinweis pro Sitzung, nie nach einem schlechten Durchlauf.
  Ende mit Code 0 = alles gut, 1 = mindestens ein Fehler.
  ============================================================================ }
program spendenhinweis_test;

{$mode objfpc}{$H+}

uses
  SysUtils, uDonateLogik;

var
  Fehler: Integer = 0;

procedure Soll(Ok: Boolean; const Was: string);
begin
  if Ok then
    WriteLn('ok      ', Was)
  else
  begin
    WriteLn('FEHLER  ', Was);
    Inc(Fehler);
  end;
end;

function F(const AppV, ShownFor: string; Hide: Boolean; Stems, Last: Integer;
  Happy, Schon: Boolean): TDonateArt;
begin
  Result := DonateFaellig(AppV, ShownFor, Hide, Stems, Last, Happy, Schon);
end;

begin
  Soll(HauptVersion('2.5.1') = '2.5', 'HauptVersion 2.5.1 -> 2.5');
  Soll(HauptVersion('2.5') = '2.5', 'HauptVersion 2.5 -> 2.5');
  Soll(HauptVersion('3') = '3', 'HauptVersion 3 -> 3');
  Soll(VersionNeuer('2.5', '2.4'), '2.5 neuer als 2.4');
  Soll(VersionNeuer('2.10', '2.9'), '2.10 neuer als 2.9 (Zahlen, nicht Text)');
  Soll(VersionNeuer('3.0', '2.9'), '3.0 neuer als 2.9');
  Soll(not VersionNeuer('2.5', '2.5'), '2.5 nicht neuer als 2.5');
  Soll(not VersionNeuer('2.5.1', '2.5'), '2.5.1 nicht neuer als 2.5 (Fehlerbehebung)');
  Soll(not VersionNeuer('2.4', '2.5'), '2.4 nicht neuer als 2.5 (ältere Version)');
  Soll(VersionNeuer('2.5', ''), 'leer gilt als älter');

  Soll(MilestoneFor(9) = 0, 'Marke 9 -> 0');
  Soll(MilestoneFor(10) = 10, 'Marke 10');
  Soll(MilestoneFor(1999) = 1000, 'Marke 1999 -> 1000');
  Soll(MilestoneFor(3500) = 3000, 'Marke 3500 -> 3000');

  { Update von 2.4 auf 2.5: erster guter Durchlauf -> Hinweis zum Update }
  Soll(F('2.5', '2.4', False, 30, 10, True, False) = daUpdate, 'Update 2.4 -> 2.5');
  Soll(F('2.5', '', False, 30, 10, True, False) = daUpdate, 'Update von alter Version ohne Eintrag');
  { "Nicht mehr fragen" aus der alten Version gilt nach dem Update nicht }
  Soll(F('2.5', '2.4', True, 30, 10, True, False) = daUpdate, 'Update trotz HideDonate der alten Version');
  { Patch-Version: kein neuer Hinweis }
  Soll(F('2.5.1', '2.5', False, 30, 10, True, False) = daKeiner, '2.5.1 nach 2.5: kein Hinweis');
  { schlechter Durchlauf oder schon gezeigt: nichts }
  Soll(F('2.5', '2.4', False, 30, 10, False, False) = daKeiner, 'schlechter Durchlauf: kein Hinweis');
  Soll(F('2.5', '2.4', False, 50, 10, True, True) = daKeiner, 'schon einer in dieser Sitzung: kein zweiter');
  { Marke und Update zugleich: nur einer (der zum Update) }
  Soll(F('2.5', '2.4', False, 50, 10, True, False) = daUpdate, 'Marke + Update -> nur Update');
  { gleiche Version: Marken wie bisher }
  Soll(F('2.5', '2.5', False, 50, 10, True, False) = daMarke, 'Marke 50 fällig');
  Soll(F('2.5', '2.5', False, 49, 10, True, False) = daKeiner, 'keine neue Marke');
  Soll(F('2.5', '2.5', True, 50, 10, True, False) = daKeiner, 'Nicht mehr fragen gilt in derselben Version');
  Soll(F('2.5.1', '2.5', True, 50, 10, True, False) = daKeiner, 'Nicht mehr fragen gilt auch in 2.5.1');
  Soll(F('2.6', '2.5', True, 50, 50, True, False) = daUpdate, 'Nicht mehr fragen endet mit 2.6');

  { neue Installation: Version gilt als begrüsst, kein Hinweis zum Update }
  Soll(ShownForWirksam(0, '', '2.5') = '2.5', 'neue Installation: 2.5 gilt als begrüsst');
  Soll(F('2.5', ShownForWirksam(0, '', '2.5'), False, 1, 0, True, False) = daKeiner,
    'neue Installation: kein Danke fürs Update');
  { Update von bis 2.4 (kein Eintrag): erst ab 2.5, nicht mit 2.4.x }
  Soll(F('2.4.1', ShownForWirksam(30, '', '2.4.1'), False, 30, 10, True, False) = daKeiner,
    '2.4.1 ohne Eintrag: kein Hinweis zum Update');
  Soll(F('2.5', ShownForWirksam(30, '', '2.5'), False, 30, 10, True, False) = daUpdate,
    '2.5 nach 2.4 ohne Eintrag: Hinweis zum Update');
  Soll(ShownForWirksam(30, '2.5', '2.6') = '2.5', 'gespeicherter Wert bleibt');
  { ältere Version nach neuerer: Marken wie bisher }
  Soll(F('2.5', '2.6', False, 50, 10, True, False) = daMarke, 'Downgrade: Marke wie bisher');
  Soll(F('2.5', '2.6', True, 50, 10, True, False) = daKeiner, 'Downgrade: Nicht mehr fragen gilt');
  Soll(F('2.5', '2.5', False, 0, 0, True, False) = daKeiner, 'keine Tracks: nichts');
  Soll(VersionNeuer('2.5.1', '2.4'), '2.5.1 neuer als 2.4');
  Soll(VersionNeuer('2.6-beta', '2.5'), '2.6-beta neuer als 2.5');
  Soll(F('2.5', '2.5', False, 2000, 1000, True, False) = daMarke, 'Marke 2000 fällig');
  Soll(F('2.5', '2.5', False, 1999, 1000, True, False) = daKeiner, '1999: keine neue Marke');

  if Fehler = 0 then
    WriteLn('Alle Prüfungen bestanden.')
  else
    WriteLn(Fehler, ' Fehler.');
  Halt(Ord(Fehler > 0));
end.
