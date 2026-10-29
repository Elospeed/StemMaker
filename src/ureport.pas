{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ureport.pas  (Unit uReport)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Fenster "Fehlerbericht senden". Es erscheint nur, wenn der Nutzer es
  will: nach einem Absturz (Frage beim nächsten Start), im Fenster
  "Unerwarteter Fehler" oder über Info -> "Fehlerbericht senden...".

  NICHTS WIRD AUTOMATISCH GESENDET
  StemMaker hat keinen eigenen Server. Das Fenster zeigt den Bericht
  (= Log-Datei) vollständig an, bevor er den PC verlässt. Der Nutzer
  schickt ihn dann selbst:
    - "Per E-Mail senden": Bericht als Datei speichern, im Explorer
      markieren und eine fertige Mail an elospeed.dev@gmail.com öffnen.
      Einen Anhang kann ein mailto-Link nicht mitgeben - die Datei zieht
      der Nutzer selbst in die Mail.
    - "Als GitHub-Issue": vorausgefülltes Issue im Browser (braucht ein
      GitHub-Konto, Issues sind ÖFFENTLICH). Das ganze Log passt nicht in
      die Adresse, darum steht dort nur eine Kurzfassung; die Datei wird
      ins Issue gezogen.
  Zusätzlich liegt der ganze Bericht in der Zwischenablage (Strg+V).

  DATENSCHUTZ
  Logs enthalten volle Pfade, z.B. C:\Users\Max\Music\Song.mp3. Der
  Benutzerordner wird deshalb durch %USERPROFILE% ersetzt und ein
  Ordner mit dem Windows-Benutzernamen durch <Benutzer>. Songnamen bleiben
  drin (Fehler hängen oft an Sonderzeichen) - der Nutzer sieht sie ja.
  ============================================================================ }
unit uReport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  Clipbrd, LCLIntf, LazUTF8, LazFileUtils, FileUtil
  {$IFDEF WINDOWS}, Windows{$ENDIF};

const
  REPORT_MAIL  = 'elospeed.dev@gmail.com';
  REPORT_ISSUE = 'https://github.com/Elospeed/StemMaker/issues/new';

var
  { Programmversion für den Kopf des Berichts (setzt das Hauptfenster) }
  ReportAppVersion: string = '';

{ Fenster "Fehlerbericht senden" zeigen.
  LogPath = vorausgewähltes Log ('' = aktuelles Log),
  Reason  = kurzer Anlass, z.B. die Fehlermeldung ('' = keiner) }
procedure ShowErrorReport(const LogPath, Reason: string);

{ Pfade mit Benutzernamen unkenntlich machen (auch für Tests nutzbar) }
function AnonymizeReport(const S, UserProfile, UserName: string): string;

implementation

uses
  uLog, uLang;

const
  MAX_LOG_BYTES = 1024 * 1024;   // größere Logs: Anfang + Ende
  HEAD_BYTES    = 32 * 1024;     // Anfang (Rechner-Infos, Einstellungen)
  MAIL_URL_MAX  = 1800;          // manche Mailprogramme schneiden längere Links ab
  ISSUE_URL_MAX = 6000;          // GitHub nimmt ca. 8000 Zeichen

type
  TfrmReport = class(TForm)
  private
    cbLog: TComboBox;            // welches Log
    memReport: TMemo;            // der Bericht, genau so wie er gesendet wird
    FLogs: TStringList;          // volle Pfade zu cbLog
    FReason: string;
    FSavedFile: string;          // zuletzt gespeicherter Bericht
    procedure cbLogChange(Sender: TObject);
    procedure btnMailClick(Sender: TObject);
    procedure btnIssueClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure LoadLog;
    function SaveReport: Boolean;
    function Summary: string;
  public
    constructor CreateReport(const LogPath, Reason: string);
    destructor Destroy; override;
  end;

{ ---------------------------------------------------------------------------
  Hilfsfunktionen
  --------------------------------------------------------------------------- }

{ Text für eine Web-Adresse kodieren (UTF-8, Leerzeichen als %20 -
  "+" verstehen Mailprogramme im mailto-Link nicht als Leerzeichen) }
function UrlEncode(const S: string): string;
const
  SAFE = ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'];
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in SAFE then
      Result := Result + S[I]
    else
      Result := Result + '%' + IntToHex(Ord(S[I]), 2);
end;

function AnonymizeReport(const S, UserProfile, UserName: string): string;
var
  P: string;
begin
  Result := S;
  P := ExcludeTrailingPathDelimiter(UserProfile);
  { 1. ganzer Benutzerordner, mit \ und mit / geschrieben }
  if Length(P) > 3 then
  begin
    Result := StringReplace(Result, P, '%USERPROFILE%', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, StringReplace(P, '\', '/', [rfReplaceAll]),
      '%USERPROFILE%', [rfReplaceAll, rfIgnoreCase]);
  end;
  { 2. Ordner mit dem Benutzernamen an anderer Stelle (z.B. D:\Max\Musik).
    Nur als ganzer Ordnername, damit Songtitel nicht verändert werden. }
  if Length(UserName) >= 2 then
  begin
    Result := StringReplace(Result, '\' + UserName + '\', '\<Benutzer>\',
      [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '/' + UserName + '/', '/<Benutzer>/',
      [rfReplaceAll, rfIgnoreCase]);
  end;
end;

{ Log lesen, auch das gerade laufende (es ist zum Mitlesen geöffnet) }
function ReadLogText(const FileName: string): string;
var
  FS: TFileStream;
  Size: Int64;
  Head, Tail: string;
begin
  Result := '';
  if not FileExists(FileName) then Exit;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Size := FS.Size;
      if Size <= MAX_LOG_BYTES then
      begin
        SetLength(Result, Size);
        if Size > 0 then FS.ReadBuffer(Result[1], Size);
      end
      else
      begin
        { sehr langes Log (z.B. großer Stapel): Anfang + Ende reichen }
        SetLength(Head, HEAD_BYTES);
        FS.ReadBuffer(Head[1], HEAD_BYTES);
        SetLength(Tail, MAX_LOG_BYTES - HEAD_BYTES);
        FS.Seek(Size - Length(Tail), soBeginning);
        FS.ReadBuffer(Tail[1], Length(Tail));
        Result := Head + LineEnding + LineEnding +
          Format('[... %d KB in der Mitte ausgelassen ...]',
          [(Size - MAX_LOG_BYTES) div 1024]) + LineEnding + LineEnding + Tail;
      end;
    finally
      FS.Free;
    end;
  except
    on E: Exception do
      Result := Format(_('Log konnte nicht gelesen werden: %s'), [E.Message]);
  end;
end;

{ ---------------------------------------------------------------------------
  Fenster
  --------------------------------------------------------------------------- }
constructor TfrmReport.CreateReport(const LogPath, Reason: string);
var
  lblInfo, lblLog: TLabel;
  pnlTop, pnlBottom: TPanel;
  btnMail, btnIssue, btnClose: TButton;
  L: TStringList;
  I, Sel: Integer;
  Want: string;
begin
  inherited CreateNew(nil);
  { auch der Anlass (Fehlermeldung) kann Pfade enthalten }
  FReason := AnonymizeReport(Reason, GetEnvironmentVariableUTF8('USERPROFILE'),
    GetEnvironmentVariableUTF8('USERNAME'));
  Caption := _('Fehlerbericht senden');
  Position := poMainFormCenter;
  Width := 760;
  Height := 560;
  Constraints.MinWidth := 640;
  Constraints.MinHeight := 380;

  { --- oben: Erklärung + Auswahl des Logs --- }
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.BevelOuter := bvNone;
  pnlTop.AutoSize := True;

  lblInfo := TLabel.Create(Self);
  lblInfo.Parent := pnlTop;
  lblInfo.Align := alTop;
  lblInfo.BorderSpacing.Around := 10;
  lblInfo.WordWrap := True;
  lblInfo.Caption :=
    _('Mit diesem Bericht kann Elospeed den Fehler finden. Es wird NICHTS ' +
    'automatisch gesendet: Unten steht genau der Text, der den PC verlässt. ' +
    'Dein Benutzername ist bereits entfernt, Dateinamen deiner Songs bleiben drin.') +
    LineEnding + LineEnding +
    Format(_('"Per E-Mail senden" speichert den Bericht als Datei, zeigt sie im ' +
    'Explorer und öffnet eine fertige Mail. Bitte die markierte Datei in die Mail ' +
    'ziehen. Öffnet sich keine Mail (z. B. bei Webmail), schick die Datei einfach ' +
    'an %s. Der ganze Bericht liegt zusätzlich in der Zwischenablage (Strg+V).'),
    [REPORT_MAIL]);

  lblLog := TLabel.Create(Self);
  lblLog.Parent := pnlTop;
  lblLog.Align := alTop;
  lblLog.Top := 200;                               // unter lblInfo
  lblLog.BorderSpacing.Left := 10;
  lblLog.Caption := _('Log:');

  cbLog := TComboBox.Create(Self);
  cbLog.Parent := pnlTop;
  cbLog.Align := alTop;
  cbLog.Top := 300;                                // unter lblLog
  cbLog.BorderSpacing.Left := 10;
  cbLog.BorderSpacing.Right := 10;
  cbLog.BorderSpacing.Bottom := 8;
  cbLog.Style := csDropDownList;
  cbLog.OnChange := @cbLogChange;

  { --- unten: Knöpfe --- }
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 48;
  pnlBottom.BevelOuter := bvNone;

  btnMail := TButton.Create(Self);
  btnMail.Parent := pnlBottom;
  btnMail.SetBounds(10, 8, 190, 32);
  btnMail.Caption := _('Per E-Mail senden');
  btnMail.Font.Style := [fsBold];
  btnMail.OnClick := @btnMailClick;

  btnIssue := TButton.Create(Self);
  btnIssue.Parent := pnlBottom;
  btnIssue.SetBounds(210, 8, 260, 32);
  btnIssue.Caption := _('Als GitHub-Issue (öffentlich)');
  btnIssue.Hint := _('Braucht ein GitHub-Konto. Issues kann jeder lesen.');
  btnIssue.ShowHint := True;
  btnIssue.OnClick := @btnIssueClick;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlBottom;
  btnClose.SetBounds(0, 8, 120, 32);
  btnClose.Anchors := [akTop, akRight];
  btnClose.Left := pnlBottom.ClientWidth - 130;
  btnClose.Caption := _('Nicht senden');
  btnClose.Cancel := True;                         // Esc = schließen
  btnClose.OnClick := @btnCloseClick;

  { --- Mitte: der Bericht --- }
  memReport := TMemo.Create(Self);
  memReport.Parent := Self;
  memReport.Align := alClient;
  memReport.BorderSpacing.Left := 10;
  memReport.BorderSpacing.Right := 10;
  memReport.ReadOnly := True;
  memReport.ScrollBars := ssBoth;
  memReport.WordWrap := False;
  memReport.Font.Name := MonoFontName;   // Japanisch: MS Gothic (uLang)

  { --- Logs auflisten, neuestes zuerst --- }
  FLogs := TStringList.Create;
  L := FindAllFiles(LogDir, 'StemMaker_*.log', False);
  try
    L.Sort;                                        // Name = Datum -> zeitlich
    for I := L.Count - 1 downto 0 do
      FLogs.Add(L[I]);
  finally
    L.Free;
  end;
  Want := LogPath;
  if Want = '' then Want := LogFileName;
  Sel := 0;
  for I := 0 to FLogs.Count - 1 do
  begin
    if SameFileName(FLogs[I], Want) then Sel := I;
    if SameFileName(FLogs[I], LogFileName) then
      cbLog.Items.Add(ExtractFileName(FLogs[I]) + '  ' + _('(aktueller Lauf)'))
    else
      cbLog.Items.Add(ExtractFileName(FLogs[I]));
  end;
  if cbLog.Items.Count > 0 then
    cbLog.ItemIndex := Sel;
  LoadLog;
end;

destructor TfrmReport.Destroy;
begin
  FLogs.Free;
  inherited Destroy;
end;

procedure TfrmReport.cbLogChange(Sender: TObject);
begin
  FSavedFile := '';
  LoadLog;
end;

{ Bericht = kurzer Kopf + Log, Benutzername entfernt }
procedure TfrmReport.LoadLog;
var
  S, LogName: string;
begin
  LogName := '';
  if cbLog.ItemIndex >= 0 then
    LogName := FLogs[cbLog.ItemIndex];
  S := '=== Fehlerbericht ' + APP_NAME + ' ' + ReportAppVersion + ' ===' + LineEnding +
    'Erstellt: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + LineEnding +
    'Windows : ' + SysWindowsVersion + LineEnding;
  if FReason <> '' then
    S := S + 'Anlass  : ' + FReason + LineEnding;
  if LogName <> '' then
    S := S + 'Log     : ' + ExtractFileName(LogName) + LineEnding + LineEnding +
      ReadLogText(LogName)
  else
    S := S + LineEnding + _('(kein Log gefunden)');
  memReport.Text := AnonymizeReport(S, GetEnvironmentVariableUTF8('USERPROFILE'),
    GetEnvironmentVariableUTF8('USERNAME'));
end;

{ Bericht als Datei in den Logs-Ordner schreiben und in die Zwischenablage }
function TfrmReport.SaveReport: Boolean;
var
  FS: TFileStream;
  S: string;
begin
  Result := False;
  S := memReport.Text;
  Clipboard.AsText := S;
  if FSavedFile = '' then
    FSavedFile := LogDir + 'Fehlerbericht_' +
      FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now) + '.txt';
  try
    FS := TFileStream.Create(FSavedFile, fmCreate);
    try
      if S <> '' then FS.WriteBuffer(S[1], Length(S));
    finally
      FS.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      MessageDlg(_('Fehlerbericht'), Format(_('Der Bericht konnte nicht gespeichert ' +
        'werden: %s') + LineEnding + LineEnding + _('Er liegt aber in der ' +
        'Zwischenablage (Strg+V).'), [E.Message]), mtWarning, [mbOK], 0);
      FSavedFile := '';
    end;
  end;
  { Datei im Explorer markieren -> direkt in Mail/Browser ziehen }
  if Result then
  begin
    {$IFDEF WINDOWS}
    ShellExecuteW(0, 'open', 'explorer.exe',
      PWideChar(UTF8Decode('/select,"' + FSavedFile + '"')), nil, SW_SHOWNORMAL);
    {$ELSE}
    OpenDocument(LogDir);
    {$ENDIF}
  end;
end;

{ Kurzfassung für Mail/Issue: Anlass, Fehlerzeilen ("!!!") und die letzten
  Zeilen des Logs, höchstens MaxLen Zeichen }
function TfrmReport.Summary: string;
var
  L, Err: TStringList;
  I, First: Integer;
begin
  L := TStringList.Create;
  Err := TStringList.Create;
  try
    L.Text := memReport.Text;
    for I := 0 to L.Count - 1 do
      if (Pos('!!!', L[I]) > 0) and (Err.Count < 15) then
        Err.Add(Trim(L[I]));
    Result := '';
    if Err.Count > 0 then
      Result := 'Fehlerzeilen:' + LineEnding + Err.Text + LineEnding;
    First := L.Count - 15;
    if First < 0 then First := 0;
    Result := Result + 'Letzte Zeilen:' + LineEnding;
    for I := First to L.Count - 1 do
      Result := Result + L[I] + LineEnding;
  finally
    Err.Free;
    L.Free;
  end;
end;

{ Text kürzen, bis die kodierte Adresse unter Max Zeichen bleibt }
function FitUrl(const Prefix, Body: string; Max: Integer): string;
var
  B: string;
begin
  B := Body;
  Result := Prefix + UrlEncode(B);
  while (Length(Result) > Max) and (Length(B) > 0) do
  begin
    B := UTF8Copy(B, 1, UTF8Length(B) * 4 div 5) + LineEnding + '[...]';
    if Length(B) < 20 then B := '';
    Result := Prefix + UrlEncode(B);
  end;
end;

procedure TfrmReport.btnMailClick(Sender: TObject);
var
  Body: string;
begin
  if not SaveReport then Exit;
  Body := _('Hallo Elospeed,') + LineEnding + LineEnding +
    _('in StemMaker ist ein Fehler aufgetreten. Der Bericht ist angehängt ' +
    '(Datei aus dem Explorer-Fenster in diese Mail ziehen):') + LineEnding +
    ExtractFileName(FSavedFile) + LineEnding + LineEnding +
    _('Was habe ich gerade gemacht?') + LineEnding + LineEnding + LineEnding +
    '----' + LineEnding + Summary;
  OpenURL(FitUrl('mailto:' + REPORT_MAIL + '?subject=' +
    UrlEncode('StemMaker ' + ReportAppVersion + ' Fehlerbericht') + '&body=',
    Body, MAIL_URL_MAX));
end;

procedure TfrmReport.btnIssueClick(Sender: TObject);
var
  Title, Body: string;
begin
  if MessageDlg(_('Als GitHub-Issue'),
    _('GitHub-Issues sind öffentlich, jeder kann sie lesen. Prüfe den Bericht ' +
    'vorher auf Dinge, die du nicht zeigen möchtest (z. B. Songnamen). ' +
    'Du brauchst ein GitHub-Konto.') + LineEnding + LineEnding +
    _('Weiter zu GitHub?'), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not SaveReport then Exit;
  Title := 'StemMaker ' + ReportAppVersion + ': ';
  if FReason <> '' then
    Title := Title + UTF8Copy(FReason, 1, 80)
  else
    Title := Title + 'Fehlerbericht';
  Body := '**Was habe ich gerade gemacht?**' + LineEnding + LineEnding + LineEnding +
    '**Bericht:** ' + _('Bitte die Datei aus dem Explorer-Fenster hier hineinziehen:') +
    ' `' + ExtractFileName(FSavedFile) + '`' + LineEnding + LineEnding +
    '```' + LineEnding + Summary + '```' + LineEnding;
  OpenURL(FitUrl(REPORT_ISSUE + '?title=' + UrlEncode(Title) + '&body=', Body,
    ISSUE_URL_MAX));
end;

procedure TfrmReport.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure ShowErrorReport(const LogPath, Reason: string);
var
  F: TfrmReport;
begin
  F := TfrmReport.CreateReport(LogPath, Reason);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
