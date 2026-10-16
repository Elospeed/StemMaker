program spendentest;
{ Vorübergehender Test (wird wieder entfernt): Spenden-Hinweis zeigen,
  Bildschirmfoto des Fensters speichern, Zähl-Logik prüfen. }
{$mode objfpc}{$H+}
uses
  Interfaces, Classes, SysUtils, Forms, Graphics, ExtCtrls, Controls, IniFiles,
  uLang, uStemJob, uDonate;

type
  TShot = class
    T: TTimer;
    procedure Tick(Sender: TObject);
  end;

var
  ShotName: string;

procedure TShot.Tick(Sender: TObject);
var
  B: TBitmap;
  P: TPortableNetworkGraphic;
  F: TCustomForm;
begin
  T.Enabled := False;
  F := Screen.ActiveCustomForm;
  if F = nil then begin WriteLn('KEIN FENSTER'); Exit; end;
  B := F.GetFormImage;
  P := TPortableNetworkGraphic.Create;
  try
    P.Assign(B);
    P.SaveToFile(ShotName);
    WriteLn('Foto: ', ShotName, '  ', F.Caption);
  finally
    P.Free; B.Free;
  end;
  F.ModalResult := mrOK;
end;

procedure SetIni(Total, Mark: Integer);
var Ini: TIniFile;
begin
  Ini := TIniFile.Create(StemIniFileName);
  Ini.WriteInteger('Main', 'StemsTotal', Total);
  Ini.WriteInteger('Main', 'DonateMilestone', Mark);
  Ini.WriteInt64('Main', 'StemsAudioSec', 10500);
  Ini.WriteBool('Main', 'HideDonate', False);
  Ini.Free;
end;

procedure Check(const What: string; Got, Want: Boolean);
begin
  if Got = Want then WriteLn('OK    ', What) else WriteLn('FALSCH ', What);
end;

var
  S: TShot;
begin
  Application.Initialize;
  LangLoad(ParamStr(1));
  ShotName := 'spenden-' + ParamStr(1) + '.png';

  { Logik }
  SetIni(5, 0);
  Check('5+3=8 Tracks: kein Hinweis', CountStemsForDonate(3, 60000, True), False);
  Check('8+2=10 Tracks: Hinweis', CountStemsForDonate(2, 60000, True), True);
  SetIni(49, 10);
  Check('Durchlauf mit Fehler bei 50: kein Hinweis', CountStemsForDonate(1, 0, False), False);
  Check('naechster guter Durchlauf: Hinweis nachgeholt', CountStemsForDonate(1, 0, True), True);
  SetIni(2999, 1000);
  Check('3000 Tracks: Hinweis', CountStemsForDonate(1, 0, True), True);

  { Fenster mit 50 Tracks, knapp 3 Stunden }
  SetIni(50, 10);
  S := TShot.Create;
  S.T := TTimer.Create(nil);
  S.T.Interval := 1500;
  S.T.OnTimer := @S.Tick;
  S.T.Enabled := True;
  ShowDonateThanks;
  with TIniFile.Create(StemIniFileName) do
  begin
    Check('Marke 50 gemerkt', ReadInteger('Main', 'DonateMilestone', 0) = 50, True);
    Free;
  end;
  Check('gleich danach 51 Tracks: kein Hinweis', CountStemsForDonate(1, 0, True), False);
  WriteLn('FERTIG');
end.
