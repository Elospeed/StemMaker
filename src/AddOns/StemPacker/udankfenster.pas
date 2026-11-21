{ ============================================================================
  StemPacker  -  fertige Spuren zu Stem-Dateien packen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udankfenster.pas  (Unit uDankFenster)
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Dankfenster mit Link zu ko-fi.com/elospeed. Es kommt einmal pro
  neuer Haupt- oder Unterversion (0.4, 0.5, nicht 0.4.1), nach dem ersten
  erfolgreichen Packen in dieser Version. Nie beim Start, höchstens
  einmal pro Sitzung. Bei einer neuen Installation kommt es nicht.
  Die Entscheidung steht in uDonateLogik (gleiche Unit wie in StemMaker).

    [ Kaffee spendieren ]  -> öffnet ko-fi.com/elospeed im Browser
    [ Weiter            ]  -> schliesst das Fenster (Enter, Esc)
    [x] Nicht mehr fragen   -> [Main] HideDonate=1, gilt bis zur nächsten
                               neuen Version

  Werte in StemPacker.ini, Abschnitt [Main]: DonateHintShownFor, HideDonate.

  Das Fenster wird im Code aufgebaut: StelleAufBildschirmDPI gleich nach
  CreateNew, danach alle Masse mit Scale96ToForm (wie das Hauptfenster).
  Normale Knöpfe; hell oder dunkel kommt wie im Hauptfenster aus uPackDesign.
  ============================================================================ }
unit uDankFenster;

{$mode objfpc}{$H+}

interface

{ Nach einem erfolgreichen Packen aufrufen.
  IniName      StemPacker.ini
  AppName      'StemPacker'
  AppVer       APP_VER, z. B. '0.4'
  WarSchonDa   die INI gab es schon beim Programmstart (also keine neue
               Installation)
  KofiUrl      Ziel des Knopfs "Kaffee spendieren" }
procedure DankNachPacken(const IniName, AppName, AppVer: string;
  WarSchonDa: Boolean; const KofiUrl: string);

implementation

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLIntf,
  LCLType, IniFiles, uLang, uDonateLogik, uSkalierung;

type
  TDankForm = class(TForm)
  private
    FHide: TCheckBox;
    FUrl: string;
    procedure KofiClick(Sender: TObject);
    procedure WeiterClick(Sender: TObject);
    procedure TasteGedrueckt(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateDank(const AppName, AppVer, KofiUrl: string);
  end;

var
  SchonGezeigt: Boolean = False;     // höchstens ein Fenster pro Sitzung

constructor TDankForm.CreateDank(const AppName, AppVer, KofiUrl: string);
const
  B = 480;                           // Breite (96 dpi)
var
  Streifen: TShape;
  Titel, Txt, Link: TLabel;
  Kofi, Weiter: TButton;
begin
  inherited CreateNew(nil);
  StelleAufBildschirmDPI(Self);      // danach rechnet Scale96ToForm wirklich um
  FUrl := KofiUrl;
  Caption := AppName;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  Icon.Assign(Application.Icon);
  ClientWidth := Scale96ToForm(B);
  ClientHeight := Scale96ToForm(300);
  KeyPreview := True;
  OnKeyDown := @TasteGedrueckt;

  { farbiger Streifen links (#FF5A5E) }
  Streifen := TShape.Create(Self);
  Streifen.Parent := Self;
  Streifen.Shape := stRoundRect;
  Streifen.Brush.Color := $005E5AFF;
  Streifen.Pen.Style := psClear;
  Streifen.SetBounds(Scale96ToForm(20), Scale96ToForm(22), Scale96ToForm(8), Scale96ToForm(190));

  Titel := TLabel.Create(Self);
  Titel.Parent := Self;
  Titel.SetBounds(Scale96ToForm(42), Scale96ToForm(18), Scale96ToForm(B - 62), Scale96ToForm(24));
  Titel.Caption := Format(_('Danke fürs Update auf StemPacker %s!'),
    [HauptVersion(AppVer)]);
  Titel.Font.Style := [fsBold];
  Titel.Font.Height := Scale96ToForm(-17);

  Txt := TLabel.Create(Self);
  Txt.Parent := Self;
  Txt.AutoSize := False;
  Txt.WordWrap := True;
  Txt.SetBounds(Scale96ToForm(42), Scale96ToForm(50), Scale96ToForm(B - 62), Scale96ToForm(140));
  Txt.Caption :=
    _('StemPacker bleibt gratis, ohne Abo und ohne Werbung. Ich entwickle ' +
      'es in meiner Freizeit, mit viel Zeit und Herzblut.') +
    LineEnding + LineEnding +
    _('Wenn StemPacker dir Zeit spart, hilft ein Kaffee, dass es weitergeht.') +
    ' ☕' + LineEnding + LineEnding +
    _('Und wenn nicht, ist das völlig in Ordnung. Viel Spass beim Auflegen!');

  Link := TLabel.Create(Self);
  Link.Parent := Self;
  Link.SetBounds(Scale96ToForm(42), Scale96ToForm(194), Scale96ToForm(B - 62), Scale96ToForm(18));
  Link.Caption := '- Elospeed   ·   ko-fi.com/elospeed';
  Link.Font.Color := clGrayText;

  Weiter := TButton.Create(Self);
  Weiter.Parent := Self;
  Weiter.SetBounds(Scale96ToForm(B - 20 - 120), Scale96ToForm(226), Scale96ToForm(120), Scale96ToForm(30));
  Weiter.Caption := _('Weiter');
  Weiter.OnClick := @WeiterClick;
  Weiter.Default := True;
  Weiter.Cancel := True;

  Kofi := TButton.Create(Self);
  Kofi.Parent := Self;
  Kofi.SetBounds(Scale96ToForm(B - 20 - 120 - 10 - 170), Scale96ToForm(226), Scale96ToForm(170), Scale96ToForm(30));
  Kofi.Caption := _('Kaffee spendieren');
  Kofi.Font.Style := [fsBold];
  Kofi.OnClick := @KofiClick;

  FHide := TCheckBox.Create(Self);
  FHide.Parent := Self;
  FHide.SetBounds(Scale96ToForm(20), Scale96ToForm(268), Scale96ToForm(260), Scale96ToForm(22));
  FHide.Caption := _('Nicht mehr fragen');
end;

procedure TDankForm.KofiClick(Sender: TObject);
begin
  OpenURL(FUrl);
  ModalResult := mrOK;
end;

procedure TDankForm.WeiterClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TDankForm.TasteGedrueckt(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key in [VK_RETURN, VK_ESCAPE] then
  begin
    Key := 0;
    ModalResult := mrOK;
  end;
end;

procedure DankNachPacken(const IniName, AppName, AppVer: string;
  WarSchonDa: Boolean; const KofiUrl: string);
var
  Ini: TIniFile;
  ShownFor: string;
  Vorher: Integer;
  F: TDankForm;
begin
  if SchonGezeigt then Exit;
  try
    Ini := TIniFile.Create(IniName);
    try
      ShownFor := Ini.ReadString('Main', 'DonateHintShownFor', '');
      if WarSchonDa then Vorher := 1 else Vorher := 0;
      { neue Installation: diese Version gilt als schon begrüsst }
      if (Vorher = 0) and (Trim(ShownFor) = '') then
        Ini.WriteString('Main', 'DonateHintShownFor', HauptVersion(AppVer));
      if DonateFaellig(AppVer, ShownForWirksam(Vorher, ShownFor, AppVer),
        Ini.ReadBool('Main', 'HideDonate', False), 1, MaxInt, True,
        SchonGezeigt) <> daUpdate then Exit;
      { gleich merken, damit es nie zweimal kommt (auch beim Schliessen mit X);
        "Nicht mehr fragen" der alten Version gilt nicht mehr }
      Ini.WriteString('Main', 'DonateHintShownFor', HauptVersion(AppVer));
      Ini.WriteBool('Main', 'HideDonate', False);
    finally
      Ini.Free;
    end;
  except
    Exit;                            // INI nicht schreibbar: kein Fenster
  end;
  SchonGezeigt := True;

  F := TDankForm.CreateDank(AppName, AppVer, KofiUrl);
  try
    F.ShowModal;
    if F.FHide.Checked then
    try
      Ini := TIniFile.Create(IniName);
      try
        Ini.WriteBool('Main', 'HideDonate', True);
      finally
        Ini.Free;
      end;
    except
    end;
  finally
    F.Free;
  end;
end;

end.
