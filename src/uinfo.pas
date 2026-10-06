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
    - Mitte, zwei Reiter:
        "Anleitung": der Inhalt von LIESMICH.md bzw. README.md
        "Lizenzen" : Haftungsausschluss (uLicense), LICENSE und
                     THIRD-PARTY-NOTICES.md (ab 1.7)
    - darüber: "Nach Updates suchen" und das Häkchen "Beim Start nach
      Updates suchen" (ab 1.7)
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
  ComCtrls, LCLIntf, uDonate, uLog, uUpdate, uUpdateUI;

{ Info-Fenster anzeigen. Version/Autor kommen vom Hauptfenster.
  Findet "Nach Updates suchen" eine neue Version, geht das Info-Fenster zu
  und OnUpdateFound wird gerufen (Hauptfenster bietet das Update an). }
procedure ShowInfoDialog(const Version, Author: string;
  OnUpdateFound: TUpdateFoundEvent);

implementation

uses
  Dialogs, uStemJob, uLang, uLangUI, uLicense;

type
  TfrmInfo = class(TForm)
  private
    FLangCodes: TStringList;      // Sprach-Codes ('de', 'en', ...) in der
                                  // gleichen Reihenfolge wie in cbLang
    cbLang: TComboBox;            // Sprachauswahl unten im Fenster
    btnUpdate: TButton;           // "Nach Updates suchen"
    chkAutoUpdate: TCheckBox;     // "Beim Start nach Updates suchen"
    FVersion: string;
    procedure btnUpdateClick(Sender: TObject);
    procedure chkAutoUpdateChange(Sender: TObject);
    procedure btnDonateClick(Sender: TObject);
    procedure btnLogsClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure cbLangChange(Sender: TObject);
  public
    FoundUpdate: Boolean;         // neue Version gefunden -> FoundInfo
    FoundInfo: TUpdateInfo;
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

{ Eine Markdown-Datei für die Anzeige etwas vereinfachen:
  Markdown-Zeichen wie **fett** oder `Code` sehen im normalen Textfeld
  störend aus und werden entfernt. Überschriften (# ...) bekommen eine
  Linie darunter, damit man sie erkennt. }
function MarkdownToText(const FullName: string): string;
var
  L: TStringList;
  I: Integer;
  S, Title: string;
  Res: TStringList;
begin
  L := TStringList.Create;
  Res := TStringList.Create;
  try
    L.LoadFromFile(FullName);
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

{ Anleitung laden (deutsch: LIESMICH.md, sonst README.md) }
function LoadReadme: string;
var
  FileName: string;     // welche Anleitung gelesen wird (ohne Pfad)
begin
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
  Result := MarkdownToText(ExtractFilePath(ParamStr(0)) + FileName);
end;

{ Reiter "Lizenzen": Haftungsausschluss (gleicher Text wie beim ersten
  Start), danach LICENSE und THIRD-PARTY-NOTICES.md aus dem Programmordner.
  Die zwei Dateien gibt es nur auf Englisch (rechtlich massgebend). }
function LoadLicenses: string;
var
  Dir: string;
  L: TStringList;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := TermsText + LineEnding + LineEnding;
  if FileExists(Dir + 'LICENSE') then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(Dir + 'LICENSE');
      Result := Result + 'LICENSE' + LineEnding + '-----------' + LineEnding +
        L.Text + LineEnding;
    finally
      L.Free;
    end;
  end;
  if FileExists(Dir + 'THIRD-PARTY-NOTICES.md') then
    Result := Result + MarkdownToText(Dir + 'THIRD-PARTY-NOTICES.md')
  else
    Result := Result + Format(_('%s wurde nicht gefunden.'), ['THIRD-PARTY-NOTICES.md']);
end;

constructor TfrmInfo.CreateInfo(const Version, Author: string);
var
  lblTitle, lblSub: TLabel;
  memText, memLic: TMemo;
  pcText: TPageControl;
  tsHelp, tsLic: TTabSheet;
  pnlBottom, pnlUpdate: TPanel;
  btnDonate, btnLogs, btnClose: TButton;
  lblLang: TLabel;
  I: Integer;
begin
  inherited CreateNew(nil);
  FVersion := Version;
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

  { --- Updates (Zeile über den Buttons) ---
    Wer im Update-Fenster "Beim Start nach Updates suchen" abgehakt oder
    eine Version übersprungen hat, kommt hier wieder dran. }
  pnlUpdate := TPanel.Create(Self);
  pnlUpdate.Parent := Self;
  pnlUpdate.Align := alBottom;
  pnlUpdate.Top := 0;                              // über pnlBottom
  pnlUpdate.Height := 44;
  pnlUpdate.BevelOuter := bvNone;

  btnUpdate := TButton.Create(Self);
  btnUpdate.Parent := pnlUpdate;
  btnUpdate.SetBounds(10, 8, 200, 32);
  btnUpdate.Caption := _('Nach Updates suchen');
  btnUpdate.OnClick := @btnUpdateClick;

  chkAutoUpdate := TCheckBox.Create(Self);
  chkAutoUpdate.Parent := pnlUpdate;
  chkAutoUpdate.Left := 224;
  chkAutoUpdate.Top := 14;
  chkAutoUpdate.Caption := _('Beim Start nach Updates suchen');
  chkAutoUpdate.Checked := UpdateAutoCheck(StemIniFileName);
  chkAutoUpdate.OnChange := @chkAutoUpdateChange;  // erst nach Checked setzen

  { --- Mitte: zwei Reiter (Anleitung, Lizenzen) --- }
  pcText := TPageControl.Create(Self);
  pcText.Parent := Self;
  pcText.Align := alClient;
  pcText.BorderSpacing.Left := 10;
  pcText.BorderSpacing.Right := 10;

  tsHelp := pcText.AddTabSheet;
  tsHelp.Caption := _('Anleitung');
  memText := TMemo.Create(Self);
  memText.Parent := tsHelp;
  memText.Align := alClient;
  memText.ReadOnly := True;
  memText.ScrollBars := ssAutoVertical;
  memText.WordWrap := True;
  memText.Text := LoadReadme;

  tsLic := pcText.AddTabSheet;
  tsLic.Caption := _('Lizenzen');
  memLic := TMemo.Create(Self);
  memLic.Parent := tsLic;
  memLic.Align := alClient;
  memLic.ReadOnly := True;
  memLic.ScrollBars := ssAutoVertical;
  memLic.WordWrap := True;
  memLic.Text := LoadLicenses;

  pcText.ActivePage := tsHelp;
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

procedure TfrmInfo.chkAutoUpdateChange(Sender: TObject);
begin
  UpdateSetAutoCheck(StemIniFileName, chkAutoUpdate.Checked);
end;

{ Von Hand suchen. Neue Version: Fenster zu, das Hauptfenster bietet sie
  an (ShowInfoDialog). Sonst kurze Meldung. }
procedure TfrmInfo.btnUpdateClick(Sender: TObject);
var
  Info: TUpdateInfo;
  Err: string;
  R: TManualCheckResult;
begin
  btnUpdate.Enabled := False;
  btnUpdate.Caption := _('Suche ...');
  Screen.Cursor := crHourGlass;
  try
    R := CheckUpdateNow(FVersion, Info, Err);
  finally
    Screen.Cursor := crDefault;
    btnUpdate.Caption := _('Nach Updates suchen');
    btnUpdate.Enabled := True;
  end;
  case R of
    mcNewer:
      begin
        FoundInfo := Info;
        FoundUpdate := True;
        ModalResult := mrOK;
      end;
    mcCurrent:
      MessageDlg(Format(_('Du hast die neueste Version (%s).'), [FVersion]),
        mtInformation, [mbOK], 0);
  else
    MessageDlg(Format(_('Die Suche nach Updates hat nicht geklappt: %s'), [Err]),
      mtWarning, [mbOK], 0);
  end;
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

procedure ShowInfoDialog(const Version, Author: string;
  OnUpdateFound: TUpdateFoundEvent);
var
  F: TfrmInfo;
  Info: TUpdateInfo;
  Found: Boolean;
begin
  F := TfrmInfo.CreateInfo(Version, Author);
  try
    F.ShowModal;
    Found := F.FoundUpdate;
    Info := F.FoundInfo;
  finally
    F.Free;
  end;
  { erst nach dem Schliessen anbieten, nicht als Fenster im Fenster }
  if Found and Assigned(OnUpdateFound) then
    OnUpdateFound(Info);
end;

end.
