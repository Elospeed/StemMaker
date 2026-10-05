{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulicenseui.pas  (Unit uLicenseUI)
  Version : 1.7
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Fenster "Bitte vor der ersten Benutzung lesen" (Haftungsausschluss
  und Lizenzhinweise). Text, PC-Kennung und INI stehen in uLicense.

    [x] Ich habe den Text gelesen und bin einverstanden
    [ Einverstanden - StemMaker starten ]   (erst mit Häkchen aktiv)
    [ Beenden ]                             (oder X: StemMaker startet nicht)

  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uLicenseUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  uLicense, uLang, uLog;

{ Fragt nach, falls auf diesem PC noch nicht bestätigt wurde.
  True = bestätigt (jetzt oder früher), False = abgelehnt -> Programm beenden }
function EnsureTermsAccepted(const IniName: string): Boolean;

implementation

type
  TfrmTerms = class(TForm)
  private
    chkAccept: TCheckBox;
    btnAccept: TButton;
    procedure chkAcceptChange(Sender: TObject);
  public
    constructor CreateTerms;
  end;

constructor TfrmTerms.CreateTerms;
var
  lblTitle: TLabel;
  memText: TMemo;
  pnlBottom: TPanel;
  btnQuit: TButton;
begin
  inherited CreateNew(nil);
  Caption := APP_NAME + ' - ' + TermsTitle;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Icon.Assign(Application.Icon);
  Position := poScreenCenter;
  Width := 640;
  Height := 520;
  Constraints.MinWidth := 560;
  Constraints.MinHeight := 380;

  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := Self;
  lblTitle.Align := alTop;
  lblTitle.BorderSpacing.Around := 12;
  lblTitle.Caption := TermsTitle;
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Height := -17;

  { unten: Häkchen und die zwei Knöpfe }
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 84;
  pnlBottom.BevelOuter := bvNone;

  chkAccept := TCheckBox.Create(Self);
  chkAccept.Parent := pnlBottom;
  chkAccept.SetBounds(12, 8, 600, 22);
  chkAccept.Caption := _('Ich habe den Haftungsausschluss und die Lizenzhinweise ' +
    'gelesen und bin einverstanden.');
  chkAccept.OnChange := @chkAcceptChange;

  btnQuit := TButton.Create(Self);
  btnQuit.Parent := pnlBottom;
  btnQuit.SetBounds(pnlBottom.ClientWidth - 12 - 110, 40, 110, 32);
  btnQuit.Anchors := [akTop, akRight];
  btnQuit.Caption := _('Beenden');
  btnQuit.ModalResult := mrCancel;
  btnQuit.Cancel := True;                     // Esc = Beenden

  btnAccept := TButton.Create(Self);
  btnAccept.Parent := pnlBottom;
  btnAccept.SetBounds(btnQuit.Left - 10 - 260, 40, 260, 32);
  btnAccept.Anchors := [akTop, akRight];
  btnAccept.Caption := _('Einverstanden - StemMaker starten');
  btnAccept.Font.Style := [fsBold];
  btnAccept.ModalResult := mrOK;
  btnAccept.Enabled := False;                 // erst mit Häkchen

  { der Text in einem Textfeld mit Bildlaufleiste (passt so auch bei
    grosser Schrift oder Englisch) }
  memText := TMemo.Create(Self);
  memText.Parent := Self;
  memText.Align := alClient;
  memText.BorderSpacing.Left := 12;
  memText.BorderSpacing.Right := 12;
  memText.ReadOnly := True;
  memText.WordWrap := True;
  memText.ScrollBars := ssAutoVertical;
  memText.Text := TermsText;

  ActiveControl := chkAccept;
end;

procedure TfrmTerms.chkAcceptChange(Sender: TObject);
begin
  btnAccept.Enabled := chkAccept.Checked;
end;

function EnsureTermsAccepted(const IniName: string): Boolean;
var
  F: TfrmTerms;
begin
  Result := TermsAccepted(IniName);
  if Result then Exit;
  LogLine('Haftungsausschluss/Lizenz auf diesem PC noch nicht bestätigt - Fenster wird gezeigt');
  F := TfrmTerms.CreateTerms;
  try
    Result := F.ShowModal = mrOK;
  finally
    F.Free;
  end;
  if Result then
  begin
    TermsSaveAccepted(IniName);
    LogLine('Haftungsausschluss/Lizenz bestätigt (PC-Kennung ' + Copy(MachineIdHash, 1, 8) + '...)');
  end
  else
    LogLine('Haftungsausschluss/Lizenz nicht bestätigt - StemMaker wird beendet');
end;

end.
