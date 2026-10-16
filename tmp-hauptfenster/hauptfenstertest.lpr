program hauptfenstertest;
{ Vorübergehender Test (wird vor dem Mergen wieder entfernt):
  Liste und Farbstreifen wie im Hauptfenster mit uStatusDraw zeichnen,
  Bildschirmfotos speichern. }
{$mode objfpc}{$H+}
uses
  Interfaces, Windows, Classes, SysUtils, Forms, Graphics, ExtCtrls, Controls,
  ComCtrls, StdCtrls, uStatusDraw;

type
  TTest = class
    F: TForm;
    Strip: TPaintBox;
    LV: TListView;
    Lbl: TButton;
    T: TTimer;
    Step: Integer;
    procedure StripPaint(Sender: TObject);
    procedure Draw(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure Tick(Sender: TObject);
  end;

const
  COLS: TStemColorArray = (TColor($003A6AFF), TColor($00F03CD2), TColor($00A4E822), TColor($00FFD04A));
  // Zustand im Data-Feld: 0 wartet, 1 OK, 3 Fehler, 5 läuft, 2 übersprungen
  NAMES: array[0..5] of string = ('Kungs - Clap Your Hands.mp3', 'The Hardline.mp3',
    'Daft Punk - One More Time.mp3', 'Fisher - Losing It.mp3', 'Bicep - Glue.mp3', 'Track 06.mp3');
  STATES: array[0..5] of Integer = (1, 1, 5, 0, 3, 2);
  TEXTS: array[0..5] of string = ('OK (2:41)', 'OK (1:58)', 'läuft... 62 %', 'wartet', 'Fehler', 'existiert schon');

procedure TTest.StripPaint(Sender: TObject);
begin
  DrawAccentStrip(Strip.Canvas, Strip.ClientRect, COLS);
end;

procedure TTest.Draw(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  R: TRect; Look: TStatusLook;
begin
  if SubItem <> 1 then Exit;
  R := Item.DisplayRectSubItem(1, drBounds);
  case PtrInt(Item.Data) of
    0: Look := slWait; 1: Look := slOK; 3: Look := slFail; 5: Look := slRun;
  else Look := slOther; end;
  if Item.Selected and (LV.Focused or not LV.HideSelection) then Exit;
  Sender.Canvas.Font.Assign(LV.Font);
  DrawStatusCell(Sender.Canvas, R, Look, 62, Item.SubItems[0], COLS, clWindow, clWindowText,
    False, Screen.PixelsPerInch);
  DefaultDraw := False;
end;

procedure SaveScreen(Fm: TForm; const Name: string);
var
  B: TBitmap; P: TPortableNetworkGraphic;
begin
  { Bildschirm direkt abgreifen geht auf dem GitHub-Rechner nicht (schwarz),
    darum das Fenster sich selbst zeichnen lassen }
  WriteLn('--- Foto Anfang');
  B := Fm.GetFormImage;
  WriteLn('--- Foto Ende');
  P := TPortableNetworkGraphic.Create;
  try
    P.Assign(B);
    P.SaveToFile(Name);
    WriteLn('Foto: ', Name);
  finally
    P.Free; B.Free;
  end;
end;

procedure TTest.Tick(Sender: TObject);
begin
  Inc(Step);
  case Step of
    1: begin
         F.BringToFront; LV.SetFocus;
         LV.Items[2].Selected := True; LV.Items[2].Focused := True;
       end;
    2: SaveScreen(F, 'a-laeuft.png');
    3: begin LV.Items[2].Selected := False; LV.Items[0].Selected := True; LV.Items[0].Focused := True; end;
    4: SaveScreen(F, 'b-ok-markiert.png');
    5: begin Lbl.Caption := 'ohne Fokus'; Lbl.SetFocus; end;
    6: SaveScreen(F, 'c-ohne-fokus.png');
  else
    T.Enabled := False;
    F.Close;
  end;
end;

var
  X: TTest;
  I: Integer;
  It: TListItem;
  C: TListColumn;
begin
  Application.Initialize;
  X := TTest.Create;
  Application.CreateForm(TForm, X.F);
  X.F.Caption := 'Test';
  X.F.SetBounds(20, 20, 700, 230);
  X.Lbl := TButton.Create(X.F); X.Lbl.Parent := X.F; X.Lbl.Align := alTop; X.Lbl.Caption := ' Knopfleiste';
  X.Lbl.Height := 30;
  X.Strip := TPaintBox.Create(X.F); X.Strip.Parent := X.F; X.Strip.Align := alTop; X.Strip.Height := 3;
  X.Strip.Top := 40;
  X.Strip.OnPaint := @X.StripPaint;
  X.LV := TListView.Create(X.F); X.LV.Parent := X.F; X.LV.Align := alClient;
  X.LV.ViewStyle := vsReport; X.LV.RowSelect := True; X.LV.ReadOnly := True;
  C := X.LV.Columns.Add; C.Caption := 'Datei'; C.Width := 240;
  C := X.LV.Columns.Add; C.Caption := 'Status'; C.Width := 220;
  C := X.LV.Columns.Add; C.Caption := 'Pfad'; C.Width := 200;
  for I := 0 to 5 do
  begin
    It := X.LV.Items.Add; It.Caption := NAMES[I];
    It.SubItems.Add(TEXTS[I]); It.SubItems.Add('D:\Musik\House');
    It.Data := Pointer(PtrInt(STATES[I]));
  end;
  X.LV.OnCustomDrawSubItem := @X.Draw;
  X.T := TTimer.Create(nil); X.T.Interval := 1000; X.T.OnTimer := @X.Tick; X.T.Enabled := True;
  Application.Run;
  WriteLn('FERTIG');
end.
