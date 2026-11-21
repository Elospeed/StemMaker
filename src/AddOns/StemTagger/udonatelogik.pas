{ ============================================================================
  StemTagger  -  Tags in Stem-Dateien bearbeiten
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udonatelogik.pas  (Unit uDonateLogik)
  Kopie aus StemMaker (src/udonatelogik.pas), nur VERSION_VOR_HINWEIS angepasst
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Die Entscheidung, ob nach dem Speichern das Dankfenster kommt (Fenster
  in uDankFenster). Ohne Fenster und ohne INI, damit sie sich automatisch
  testen lässt. Der StemTagger nutzt nur den Fall "neue Haupt- oder
  Unterversion" (z. B. 1.3, nicht 1.3.1): einmal nach dem ersten
  erfolgreichen Speichern in dieser Version, höchstens einmal pro Sitzung.
  Die Marken (MilestoneFor) braucht er nicht, die Funktion bleibt nur,
  damit die Unit gleich wie in StemMaker ist.

  Werte in StemTagger.ini, Abschnitt [Main]:
    HideDonate          "Nicht mehr fragen" (bis zur nächsten neuen Version)
    DonateHintShownFor  Version (z. B. 1.3), für die das Fenster schon kam
  ============================================================================ }
unit uDonateLogik;

{$mode objfpc}{$H+}

interface

type
  TDonateArt = (daKeiner, daMarke, daUpdate);

{ Haupt- und Unterversion: '2.5.1' -> '2.5', '2.5' -> '2.5' }
function HauptVersion(const V: string): string;

{ True, wenn Version A neuer ist als B (nur Haupt- und Unterversion).
  B = '' (noch nie gespeichert) gilt als älter als jede Version. }
function VersionNeuer(const A, B: string): Boolean;

{ Gespeicherte Version [Main] DonateHintShownFor, wie sie gilt.
  Leer heisst: gespeichert von einer Version vor diesem Hinweis (bis 1.2)
  oder neue Installation. Neue Installation (Vorher = 0): diese Version
  gilt als schon begrüsst, kein "Danke fürs Update". Sonst gilt 1.2,
  damit der erste Hinweis zum Update mit 1.3 kommt (nicht mit 1.2.x). }
function ShownForWirksam(Vorher: Integer; const ShownFor, AppVersion: string): string;

{ Marke für Stems Tracks: 10, 50, 100, 250, 500, 1000, 2000, 3000 ...
  (0 = noch keine) }
function MilestoneFor(Stems: Integer): Integer;

{ Welcher Hinweis ist jetzt fällig?
  AppVersion    APP_VERSION dieses Programms
  ShownFor      [Main] DonateHintShownFor
  Hide          [Main] HideDonate
  Stems         StemsTotal inklusive dieses Durchlaufs
  LastMilestone [Main] DonateMilestone
  HappyRun      guter Durchlauf (kein Abbruch, höchstens 10 % Fehler)
  SchonGezeigt  in dieser Sitzung kam schon ein Hinweis }
function DonateFaellig(const AppVersion, ShownFor: string; Hide: Boolean;
  Stems, LastMilestone: Integer; HappyRun, SchonGezeigt: Boolean): TDonateArt;

implementation

uses
  SysUtils;

function HauptVersion(const V: string): string;
var
  I, Punkte: Integer;
begin
  Result := Trim(V);
  Punkte := 0;
  for I := 1 to Length(Result) do
    if Result[I] = '.' then
    begin
      Inc(Punkte);
      if Punkte = 2 then
      begin
        SetLength(Result, I - 1);
        Exit;
      end;
    end;
end;

const
  { letzte Version ohne Hinweis zum Update }
  VERSION_VOR_HINWEIS = '1.2';

function ShownForWirksam(Vorher: Integer; const ShownFor, AppVersion: string): string;
begin
  Result := Trim(ShownFor);
  if Result <> '' then Exit;
  if Vorher <= 0 then
    Result := HauptVersion(AppVersion)
  else
    Result := VERSION_VOR_HINWEIS;
end;

{ Führende Ziffern als Zahl: '5' -> 5, '5-beta' -> 5, '' -> 0 }
function Zahl(const S: string): Integer;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do Inc(I);
  Result := StrToIntDef(Copy(S, 1, I - 1), 0);
end;

{ '2.5' -> Haupt 2, Unter 5. Fehlt etwas oder ist es keine Zahl, gilt 0. }
procedure Zerlege(const V: string; out Haupt, Unter: Integer);
var
  S: string;
  P: Integer;
begin
  S := HauptVersion(V);
  P := Pos('.', S);
  if P = 0 then
  begin
    Haupt := Zahl(S);
    Unter := 0;
  end
  else
  begin
    Haupt := Zahl(Copy(S, 1, P - 1));
    Unter := Zahl(Copy(S, P + 1, MaxInt));
  end;
end;

function VersionNeuer(const A, B: string): Boolean;
var
  HA, UA, HB, UB: Integer;
begin
  if Trim(B) = '' then Exit(Trim(A) <> '');
  Zerlege(A, HA, UA);
  Zerlege(B, HB, UB);
  Result := (HA > HB) or ((HA = HB) and (UA > UB));
end;

function MilestoneFor(Stems: Integer): Integer;
const
  MARKS: array[0..5] of Integer = (10, 50, 100, 250, 500, 1000);
var
  I: Integer;
begin
  Result := 0;
  for I := Low(MARKS) to High(MARKS) do
    if Stems >= MARKS[I] then
      Result := MARKS[I];
  if Stems >= 2000 then
    Result := (Stems div 1000) * 1000;     // ab 2000: alle 1000 Tracks
end;

function DonateFaellig(const AppVersion, ShownFor: string; Hide: Boolean;
  Stems, LastMilestone: Integer; HappyRun, SchonGezeigt: Boolean): TDonateArt;
var
  Mark: Integer;
begin
  Result := daKeiner;
  if (not HappyRun) or SchonGezeigt or (Stems <= 0) then Exit;
  if VersionNeuer(HauptVersion(AppVersion), ShownFor) then
    Exit(daUpdate);
  if Hide then Exit;
  Mark := MilestoneFor(Stems);
  if (Mark > 0) and (Mark > LastMilestone) then
    Result := daMarke;
end;

end.
