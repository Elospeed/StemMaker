unit uSkalierung;

{ Windows-Skalierung (DPI): kein Fenster grösser als der freie Bildschirm.

  Lazarus rechnet jedes Fenster nach dem Erzeugen von 96 dpi auf die
  Bildschirm-DPI um (auch Fenster aus CreateNew). Bei 150 % wird ein
  Fenster mit 724 Pixeln Höhe so 1086 Pixel hoch und passt auf einem
  1920x1080-Bildschirm nicht mehr, bei 200 % auch die Mindestgrösse nicht.

  Diese Unit muss nur in der .lpr unter "uses" stehen: sie meldet sich bei
  Screen an und begrenzt jedes Fenster, sobald es sichtbar wird, auf den
  freien Bildschirm (ohne Taskleiste). Die Mindestgrösse bleibt dabei
  immer kleiner als die Startgrösse.

  Regel für eigenen Code: feste Pixel nur im Aufbau des Fensters (der wird
  danach umgerechnet). Alles, was später gesetzt oder gezeichnet wird, mit
  Scale96ToForm umrechnen; nie Screen.PixelsPerInch im Konstruktor. }

{$mode objfpc}{$H+}

interface

uses
  Classes, Types, Forms, Controls, Graphics, LCLType, Math;

{ Für Fenster, deren Konstruktor durchgehend Scale96ToForm benutzt:
  direkt nach "inherited CreateNew" aufrufen. Danach rechnet
  Scale96ToForm wirklich auf die Bildschirm-DPI um (vorher stand das
  Fenster bis zum Ende des Konstruktors auf 96 dpi, Werte in eigenen
  Variablen wie Spaltenbreiten oder Bildlisten blieben dann bei 100 %). }
procedure StelleAufBildschirmDPI(F: TCustomForm);

{ Für Fenster, die nach "F := TForm.CreateNew(nil)" AUSSERHALB eines
  Konstruktors mit 96-dpi-Pixeln aufgebaut werden: Lazarus hat das leere
  Fenster schon beim Erzeugen umgerechnet, alles danach Gesetzte bliebe
  bei 100 %. Einmal nach dem Aufbau und vor ShowModal aufrufen. Rechnet
  Grösse, Mindestgrösse, alle Elemente und feste Schriftgrössen um. }
procedure SkaliereDialog(F: TCustomForm);

{ Fenster auf den freien Bildschirm begrenzen. Läuft automatisch beim
  Sichtbarwerden; von Hand nur nötig, wenn ein sichtbares Fenster im
  Code grösser gemacht wird (z. B. beim Wechsel der Ansicht). }
procedure BegrenzeAufBildschirm(F: TCustomForm);

implementation

type
  { Zugriff auf Font/ParentFont (in TControl geschützt) }
  TControlZugriff = class(TControl);

  TSkalierungWaechter = class
    procedure FormSichtbar(Sender: TObject; Form: TCustomForm);
  end;

var
  Waechter: TSkalierungWaechter = nil;

function FreierBereich(F: TCustomForm): TRect;
var
  M: TMonitor;
begin
  M := nil;
  if F.HandleAllocated then
    M := Screen.MonitorFromRect(F.BoundsRect, mdNearest)
  else if (Application.MainForm <> nil) and Application.MainForm.HandleAllocated then
    M := Application.MainForm.Monitor;
  if M = nil then
    M := Screen.PrimaryMonitor;
  if M <> nil then
    Result := M.WorkareaRect
  else
    Result := Screen.WorkAreaRect;
end;

procedure BegrenzeAufBildschirm(F: TCustomForm);
var
  R: TRect;
  MaxB, MaxH: Integer;
begin
  if (F = nil) or (F.Parent <> nil) or (F.WindowState <> wsNormal) then Exit;
  R := FreierBereich(F);
  { Platz für Rahmen und Titelleiste lassen: Width/Height sind bei der
    LCL ohne Titelleiste gerechnet }
  MaxB := R.Right - R.Left - F.Scale96ToForm(16);
  MaxH := R.Bottom - R.Top - F.Scale96ToForm(48);
  if (MaxB < 200) or (MaxH < 150) then Exit;

  if F.Constraints.MinWidth > MaxB then
    F.Constraints.MinWidth := MaxB;
  if F.Constraints.MinHeight > MaxH then
    F.Constraints.MinHeight := MaxH;

  if F.Width > MaxB then
    F.Width := MaxB;
  if F.Height > MaxH then
    F.Height := MaxH;

  { Mindestgrösse kleiner als die Startgrösse, sonst lässt sich ein
    verkleinertes Fenster nicht mehr kleiner ziehen }
  if (F.BorderStyle in [bsSizeable, bsSizeToolWin]) then
  begin
    if F.Constraints.MinWidth >= F.Width then
      F.Constraints.MinWidth := Max(0, F.Width - F.Scale96ToForm(40));
    if F.Constraints.MinHeight >= F.Height then
      F.Constraints.MinHeight := Max(0, F.Height - F.Scale96ToForm(40));
  end;

  { ein Fenster, das unten oder rechts über den Rand ragt, zurückschieben }
  if F.Left + F.Width > R.Right then F.Left := Max(R.Left, R.Right - F.Width);
  if F.Top + F.Height + F.Scale96ToForm(32) > R.Bottom then
    F.Top := Max(R.Top, R.Bottom - F.Height - F.Scale96ToForm(32));
  if F.Left < R.Left then F.Left := R.Left;
  if F.Top < R.Top then F.Top := R.Top;
end;

procedure StelleAufBildschirmDPI(F: TCustomForm);
begin
  if F.PixelsPerInch <> Screen.PixelsPerInch then
    F.AutoAdjustLayout(lapAutoAdjustForDPI, F.PixelsPerInch, Screen.PixelsPerInch, 0, 0);
end;

procedure SkaliereSchriften(C: TControl; PPI: Integer);
var
  I: Integer;
begin
  { feste Schriftgrössen (Font.Height := -17) sind 96-dpi-Pixel }
  with TControlZugriff(C) do
    if not ParentFont and (Font.Height <> 0) then
      Font.Height := MulDiv(Font.Height, PPI, 96);
  if C is TWinControl then
    for I := 0 to TWinControl(C).ControlCount - 1 do
      SkaliereSchriften(TWinControl(C).Controls[I], PPI);
end;

procedure SkaliereDialog(F: TCustomForm);
var
  PPI, I: Integer;
begin
  PPI := F.PixelsPerInch;
  if PPI = 96 then Exit;
  F.DisableAutoSizing;
  try
    for I := 0 to F.ControlCount - 1 do
      SkaliereSchriften(F.Controls[I], PPI);
    for I := 0 to F.ControlCount - 1 do
      F.Controls[I].AutoAdjustLayout(lapAutoAdjustForDPI, 96, PPI, 0, 0);
    F.Constraints.AutoAdjustLayout(PPI / 96, PPI / 96);
    F.SetBounds(F.Left, F.Top, MulDiv(F.Width, PPI, 96), MulDiv(F.Height, PPI, 96));
  finally
    F.EnableAutoSizing;
  end;
end;

procedure TSkalierungWaechter.FormSichtbar(Sender: TObject; Form: TCustomForm);
begin
  if (Form <> nil) and Form.Visible then
    BegrenzeAufBildschirm(Form);
end;

initialization
  Waechter := TSkalierungWaechter.Create;
  Screen.AddHandlerFormVisibleChanged(@Waechter.FormSichtbar);

finalization
  if Screen <> nil then
    Screen.RemoveHandlerFormVisibleChanged(@Waechter.FormSichtbar);
  Waechter.Free;

end.
