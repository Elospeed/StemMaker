{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uinfo.pas  (Unit uInfo)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Info-Fenster (Button "Info" oben links im Hauptfenster):
    - oben: Programmname, Version, Autor, Build-Datum, aktuelle Log-Datei
    - Mitte: der Inhalt von LIESMICH.md bzw. README.md (Anleitung)
    - unten: "Logs-Ordner öffnen", "Jetzt spenden", Sprachauswahl,
      "Schließen"

  Die Anleitung wird aus dem Programmordner gelesen:
    Sprache Deutsch ('de')  -> LIESMICH.md
    jede andere Sprache     -> README.md (fehlt sie: LIESMICH.md)
  Fehlt die Datei ganz, wird ein kurzer Ersatztext angezeigt.

  Sprachauswahl: Die gewählte Sprache wird sofort in StemMaker.ini
  gespeichert, wirkt aber erst beim nächsten Programmstart (die Texte
  der schon offenen Fenster werden nicht umgebaut).
  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uInfo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  LCLIntf, uDonate, uLog;

{ Info-Fenster anzeigen. Version/Autor kommen vom Hauptfenster. }
procedure ShowInfoDialog(const Version, Author: string);

implementation

uses
  Dialogs, uStemJob, uLang, uLangUI;

type
  TfrmInfo = class(TForm)
  private
    FLangCodes: TStringList;      // Sprach-Codes ('de', 'en', ...) in der
                                  // gleichen Reihenfolge wie in cbLang
    cbLang: TComboBox;            // Sprachauswahl unten im Fenster
    procedure btnDonateClick(Sender: TObject);
    procedure btnLogsClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure cbLangChange(Sender: TObject);
  public
    constructor CreateInfo(const Version, Author: string);
    destructor Destroy; override;
  end;

{ Markdown-Link "[Text](https://...)" -> "Text (https://...)"
  und "<https://...>" -> "https://..." }
function CleanLinks(const S: string): string;
var
  P, Q, R: Integer;
begin
  Result := S;
  repeat
    P := Pos('](', Result);
    if P = 0 then Break;
    Q := P;                                   // '[' davor suchen
    while (Q > 0) and (Result[Q] <> '[') do Dec(Q);
    R := PosEx(')', Result, P + 2);           // ')' danach suchen
    if (Q = 0) or (R = 0) then Break;
    Result := Copy(Result, 1, Q - 1) + Copy(Result, Q + 1, P - Q - 1) + ' (' +
      Copy(Result, P + 2, R - P - 2) + ')' + Copy(Result, R + 1, MaxInt);
  until False;
  Result := StringReplace(Result, '<http', 'http', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '', [rfReplaceAll]);
end;

{ Anleitung laden (deutsch: LIESMICH.md, sonst README.md) und für die
  Anzeige etwas vereinfachen:
  Markdown-Zeichen wie **fett** oder `Code` sehen im normalen Textfeld
  störend aus und werden entfernt. Überschriften (# ...) bekommen eine
  Linie darunter, damit man sie erkennt. }
function LoadReadme: string;
var
  L: TStringList;
  I: Integer;
  S, Title: string;
  Res: TStringList;
  FileName: string;     // welche Anleitung gelesen wird (ohne Pfad)
begin
  Result := '';
  { Dateiname je nach Sprache wählen: Deutsch -> LIESMICH.md,
    alle anderen -> README.md. Gibt es keine README.md, wird die
    deutsche Anleitung als Rückfall genommen (besser als gar nichts). }
  if LangCode = 'de' then
    FileName := 'LIESMICH.md'
  else
  begin
    FileName := 'README.md';
    if not FileExists(ExtractFilePath(ParamStr(0)) + FileName) then
      FileName := 'LIESMICH.md';
  end;
  if not FileExists(ExtractFilePath(ParamStr(0)) + FileName) then
  begin
    Result := Format(_('%s wurde nicht gefunden.'), [FileName]) +
      LineEnding + LineEnding +
      _('Die Anleitung liegt normalerweise im StemMaker-Ordner neben ' +
      'StemMaker.exe. Bitte das ZIP komplett entpacken.');
    Exit;
  end;
  L := TStringList.Create;
  Res := TStringList.Create;
  try
    L.LoadFromFile(ExtractFilePath(ParamStr(0)) + FileName);
    for I := 0 to L.Count - 1 do
    begin
      S := L[I];
      S := StringReplace(S, '**', '', [rfReplaceAll]);
      S := StringReplace(S, '`', '', [rfReplaceAll]);
      if Pos('|---', S) = 1 then Continue;    // Tabellen-Trennzeile weglassen
      S := CleanLinks(S);
      if (S = '```') or (Copy(S, 1, 3) = '```') then
        Continue;                          // Code-Block-Markierungen weglassen
      if Copy(S, 1, 1) = '#' then
      begin
        { "## Titel" -> "Titel" + Linie }
        Title := Trim(StringReplace(S, '#', '', [rfReplaceAll]));
        Res.Add('');
        Res.Add(Title);
        Res.Add(StringOfChar('-', Length(Title) + 4));
      end
      else
        Res.Add(S);
    end;
    Result := Res.Text;
  finally
    Res.Free;
    L.Free;
  end;
end;

constructor TfrmInfo.CreateInfo(const Version, Author: string);
var
  lblTitle, lblSub: TLabel;
  memText: TMemo;
  pnlBottom: TPanel;
  btnDonate, btnLogs, btnClose: TButton;
  lblLang: TLabel;
  I: Integer;
begin
  inherited CreateNew(nil);
  Caption := _('Info') + ' - ' + APP_NAME + ' ' + Version;
  Position := poMainFormCenter;
  Width := 720;
  Height := 560;
  { Mindestbreite so gewählt, dass die Button-Leiste unten (zwei Buttons
    links, Sprachauswahl, Schließen rechts) nie übereinander rutscht }
  Constraints.MinWidth := 700;
  Constraints.MinHeight := 360;

  { --- Kopf --- }
  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := Self;
  lblTitle.Align := alTop;
  lblTitle.BorderSpacing.Around := 10;
  lblTitle.Caption := APP_NAME + ' ' + Version;
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Height := -17;

  lblSub := TLabel.Create(Self);
  lblSub.Parent := Self;
  lblSub.Align := alTop;
  lblSub.Top := 100;                               // unter lblTitle
  lblSub.BorderSpacing.Left := 10;
  lblSub.BorderSpacing.Bottom := 8;
  lblSub.Caption :=
    Format(_('von %s  ·  Traktor-Stem-Dateien aus MP3  ·  kostenlos && quelloffen  ·  ' +
    'Build: %s'), [Author, {$I %DATE%}]) + LineEnding +
    Format(_('Aktuelles Log: %s'), [ExtractFileName(LogFileName)]);
  lblSub.Font.Color := clGrayText;

  { --- Buttons unten --- }
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 48;
  pnlBottom.BevelOuter := bvNone;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlBottom;
  btnClose.SetBounds(0, 8, 100, 32);
  btnClose.Anchors := [akTop, akRight];
  btnClose.Left := pnlBottom.ClientWidth - 110;
  btnClose.Caption := _('Schließen');
  btnClose.OnClick := @btnCloseClick;
  btnClose.Cancel := True;                         // Esc = schließen

  btnLogs := TButton.Create(Self);
  btnLogs.Parent := pnlBottom;
  btnLogs.SetBounds(10, 8, 150, 32);
  btnLogs.Caption := _('Logs-Ordner öffnen');
  btnLogs.OnClick := @btnLogsClick;

  btnDonate := TButton.Create(Self);
  btnDonate.Parent := pnlBottom;
  btnDonate.SetBounds(170, 8, 150, 32);
  btnDonate.Caption := _('Jetzt spenden');
  btnDonate.Font.Style := [fsBold];
  btnDonate.OnClick := @btnDonateClick;
  btnDonate.Hint := DONATE_URL;
  btnDonate.ShowHint := True;

  { --- Sprachauswahl (zwischen "Jetzt spenden" und "Schließen") ---
    Platzaufteilung der Leiste bei Fensterbreite 720 (Innenbreite ca. 704):
      10..160   Logs-Ordner öffnen
      170..320  Jetzt spenden
      334..     Label "Sprache:" (Breite je nach Sprache, ca. 50-70)
      danach    ComboBox, 6 Pixel rechts vom Label, 150 breit
                -> endet spätestens bei ca. 560
      ab ~594   Schließen (rechts verankert)
    Die ComboBox hängt per Anker am rechten Rand des Labels, damit ein
    längeres Wort (andere Sprache) sie automatisch weiterschiebt. }
  lblLang := TLabel.Create(Self);
  lblLang.Parent := pnlBottom;
  lblLang.Left := 334;
  lblLang.Top := 16;                               // mittig zu den Buttons
  lblLang.Caption := _('Sprache:');

  cbLang := TComboBox.Create(Self);
  cbLang.Parent := pnlBottom;
  cbLang.Style := csDropDownList;                  // nur auswählen, nicht tippen
  cbLang.Top := 12;
  cbLang.Width := 150;
  cbLang.AnchorSideLeft.Control := lblLang;
  cbLang.AnchorSideLeft.Side := asrRight;
  cbLang.BorderSpacing.Left := 6;
  cbLang.Anchors := [akTop, akLeft];

  { alle vorhandenen Sprachen eintragen, die aktuelle vorauswählen.
    Die Codes merken wir uns in FLangCodes (gleiche Reihenfolge). }
  FLangCodes := LangAvailable;
  for I := 0 to FLangCodes.Count - 1 do
    cbLang.Items.Add(LangDisplayName(FLangCodes[I]));
  cbLang.ItemIndex := FLangCodes.IndexOf(LangCode);
  { OnChange erst NACH der Vorauswahl setzen, sonst käme die Meldung
    schon beim Öffnen des Fensters }
  cbLang.OnChange := @cbLangChange;

  { --- Anleitung --- }
  memText := TMemo.Create(Self);
  memText.Parent := Self;
  memText.Align := alClient;
  memText.BorderSpacing.Left := 10;
  memText.BorderSpacing.Right := 10;
  memText.ReadOnly := True;
  memText.ScrollBars := ssAutoVertical;
  memText.WordWrap := True;
  memText.Text := LoadReadme;
end;

destructor TfrmInfo.Destroy;
begin
  FLangCodes.Free;
  inherited Destroy;
end;

{ Andere Sprache gewählt: in StemMaker.ini speichern und Hinweis zeigen.
  Umgeschaltet wird erst beim nächsten Programmstart. }
procedure TfrmInfo.cbLangChange(Sender: TObject);
begin
  if (cbLang.ItemIndex < 0) or (cbLang.ItemIndex >= FLangCodes.Count) then
    Exit;
  LangSaveChoice(StemIniFileName, FLangCodes[cbLang.ItemIndex]);
  MessageDlg(_('Die Sprache wird beim nächsten Start übernommen.'),
    mtInformation, [mbOK], 0);
end;

procedure TfrmInfo.btnDonateClick(Sender: TObject);
begin
  OpenDonatePage;
end;

procedure TfrmInfo.btnLogsClick(Sender: TObject);
begin
  OpenDocument(LogDir);
end;

procedure TfrmInfo.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure ShowInfoDialog(const Version, Author: string);
var
  F: TfrmInfo;
begin
  F := TfrmInfo.CreateInfo(Version, Author);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
