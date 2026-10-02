{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udonate.pas  (Unit uDonate)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das kleine Spendenfenster, das vor dem Programmstart erscheint.
  StemMaker ist kostenlos und quelloffen - hier wird freundlich auf eine
  freiwillige Spende über Ko-fi hingewiesen.

    [ Jetzt spenden ]  -> öffnet ko-fi.com/elospeed im Browser
                          und startet danach trotzdem das Tool
    [ Tool starten  ]  -> einfach weiter
    [x] Beim Start nicht mehr anzeigen
        -> wird in StemMaker.ini gespeichert ([Main] HideDonate=1)

  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uDonate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLIntf,
  IniFiles, uStemJob, uLog, uLang;

const
  DONATE_URL = 'https://ko-fi.com/elospeed';

{ Zeigt das Spendenfenster - aber nur, wenn der Benutzer es nicht per
  Häkchen abgeschaltet hat. Gibt False zurück, wenn das Fenster mit dem
  X geschlossen wurde (dann startet das Tool trotzdem - wir wollen
  niemanden aussperren, darum wird das Ergebnis nicht ausgewertet). }
procedure ShowDonateDialogIfWanted;

{ Ko-fi-Seite im Standard-Browser öffnen }
procedure OpenDonatePage;

implementation

type
  TfrmDonate = class(TForm)
  private
    chkHide: TCheckBox;
    procedure btnDonateClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
  public
    constructor CreateDonate;
  end;

procedure OpenDonatePage;
begin
  OpenURL(DONATE_URL);
end;

{ ---------------------------------------------------------------------------
  Fenster aufbauen
  --------------------------------------------------------------------------- }
constructor TfrmDonate.CreateDonate;
var
  lblTitle, lblText, lblLink: TLabel;
  btnDonate, btnStart: TButton;
  pnlHeart: TShape;
begin
  inherited CreateNew(nil);
  Caption := APP_NAME + _(' - kostenlos & quelloffen');
  BorderStyle := bsDialog;
  Icon.Assign(Application.Icon);   // Programmsymbol auch in diesem Fenster
  Position := poScreenCenter;
  ClientWidth := 480;
  ClientHeight := 272;

  { kleines farbiges Element links als Blickfang (Ko-fi-Rot) }
  pnlHeart := TShape.Create(Self);
  pnlHeart.Parent := Self;
  pnlHeart.Shape := stRoundRect;
  pnlHeart.Brush.Color := $005E5AFF;     // TColor = $BBGGRR -> #FF5A5E
  pnlHeart.Pen.Style := psClear;
  pnlHeart.SetBounds(20, 22, 8, 150);

  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := Self;
  lblTitle.SetBounds(42, 18, 420, 24);
  lblTitle.Caption := _('StemMaker ist kostenlos');
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Height := -17;

  { der eigentliche Text - kurz, ehrlich, ohne Druck }
  lblText := TLabel.Create(Self);
  lblText.Parent := Self;
  lblText.AutoSize := False;
  lblText.WordWrap := True;
  lblText.SetBounds(42, 50, 420, 100);
  lblText.Caption :=
    _('StemMaker und sein Quellcode sind frei für alle. Ich entwickle das ' +
    'Tool in meiner Freizeit.') + LineEnding + LineEnding +
    _('Wenn es dir Zeit spart oder einfach Spass macht, freue ich mich über ' +
    'einen kleinen, freiwilligen Beitrag - er hilft, StemMaker weiter zu ' +
    'pflegen und zu verbessern. Danke!');

  lblLink := TLabel.Create(Self);
  lblLink.Parent := Self;
  lblLink.SetBounds(42, 152, 420, 18);
  lblLink.Caption := '- Elospeed   ·   ko-fi.com/elospeed';
  lblLink.Font.Color := clGrayText;

  chkHide := TCheckBox.Create(Self);
  chkHide.Parent := Self;
  chkHide.SetBounds(20, 238, 260, 22);
  chkHide.Caption := _('Beim Start nicht mehr anzeigen');

  { Buttons rechts, darunter das Häkchen }
  btnStart := TButton.Create(Self);
  btnStart.Parent := Self;
  btnStart.SetBounds(ClientWidth - 20 - 120, 186, 120, 32);
  btnStart.Caption := _('Tool starten');
  btnStart.OnClick := @btnStartClick;
  btnStart.Default := True;      // Enter = Tool starten

  btnDonate := TButton.Create(Self);
  btnDonate.Parent := Self;
  btnDonate.SetBounds(ClientWidth - 20 - 120 - 10 - 140, 186, 140, 32);
  btnDonate.Caption := _('Jetzt spenden');
  btnDonate.Font.Style := [fsBold];
  btnDonate.OnClick := @btnDonateClick;
  ActiveControl := btnStart;     // Fokus auf "Tool starten"
end;

procedure TfrmDonate.btnDonateClick(Sender: TObject);
begin
  OpenDonatePage;          // Browser öffnen ...
  ModalResult := mrOK;     // ... und das Tool trotzdem starten
end;

procedure TfrmDonate.btnStartClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

{ ---------------------------------------------------------------------------
  Aufruf von außen
  --------------------------------------------------------------------------- }
procedure ShowDonateDialogIfWanted;
var
  Ini: TIniFile;
  F: TfrmDonate;
begin
  { abgeschaltet? -> gar nicht erst anzeigen }
  Ini := TIniFile.Create(StemIniFileName);
  try
    if Ini.ReadBool('Main', 'HideDonate', False) then
      Exit;
  finally
    Ini.Free;
  end;

  F := TfrmDonate.CreateDonate;
  try
    F.ShowModal;
    { Häkchen merken (egal ob gespendet, gestartet oder X) }
    if F.chkHide.Checked then
    try
      Ini := TIniFile.Create(StemIniFileName);
      try
        Ini.WriteBool('Main', 'HideDonate', True);
      finally
        Ini.Free;
      end;
    except
      { INI nicht schreibbar - dann kommt das Fenster eben wieder }
    end;
  finally
    F.Free;
  end;
end;

end.
