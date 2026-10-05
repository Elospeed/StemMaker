{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uupdateui.pas  (Unit uUpdateUI)
  Version : 1.7
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Update-Prüfung beim Start und das Fenster dazu.

  ABLAUF
    1. Das Hauptfenster startet StartUpdateCheck. Ein Hintergrund-Thread
       holt update.json (max. 5 s, siehe uUpdate). Das Fenster ist dabei
       sofort bedienbar - niemand wartet auf die Prüfung.
    2. Gibt es eine neuere Version (und wurde sie nicht übersprungen),
       meldet der Thread das dem Hauptfenster (OnUpdateFound). Läuft gerade
       eine Umwandlung, wartet das Hauptfenster damit bis zum Ende -
       ein Update wird NIE während einer Konvertierung angeboten.
    3. ShowUpdateDialog: "Jetzt aktualisieren / Später / Version überspringen"
       und das Häkchen "Beim Start nach Updates suchen".
    4. "Jetzt": Release-ZIP laden (Fortschrittsfenster), SHA-256 prüfen,
       InstallUpdate (uUpdate), StemMaker mit --nach-update neu starten.
       Ohne Prüfsumme in update.json wird NICHT automatisch installiert,
       sondern nur die Release-Seite im Browser geöffnet.

  Die Fenster werden im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uUpdateUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, LCLIntf, UTF8Process, Process, uUpdate, uDownload, uLang, uLog,
  uStemJob;

type
  { wird im Hauptthread aufgerufen, wenn eine neuere Version da ist }
  TUpdateFoundEvent = procedure(const Info: TUpdateInfo) of object;

{ Prüfung im Hintergrund starten (nur wenn in der INI nicht abgeschaltet).
  OnFound wird nur bei einer neueren, nicht übersprungenen Version gerufen. }
procedure StartUpdateCheck(const CurrentVersion: string; OnFound: TUpdateFoundEvent);

{ Hauptfenster wird geschlossen: späte Ergebnisse nicht mehr melden }
procedure CancelUpdateCheck;

{ Update-Fenster. True = Update installiert, StemMaker soll sich beenden
  (der Neustart ist dann schon angestossen). }
function ShowUpdateDialog(const Info: TUpdateInfo; const CurrentVersion: string): Boolean;

implementation

type
  TUpdateCheckThread = class(TThread)
  private
    FOK: Boolean;
    FInfo: TUpdateInfo;
    FErr: string;
    procedure Done(Sender: TObject);
  protected
    procedure Execute; override;
  end;

var
  GOnFound: TUpdateFoundEvent = nil;
  GCurrent: string = '';

procedure TUpdateCheckThread.Execute;
begin
  FOK := FetchUpdateInfo(UPDATE_TIMEOUT_MS, FInfo, FErr);
end;

{ läuft im Hauptthread (OnTerminate) }
procedure TUpdateCheckThread.Done(Sender: TObject);
var
  Skip: string;
begin
  try
    if not FOK then
    begin
      LogLine('Update-Prüfung: update.json nicht erreichbar (' + FErr + ')');
      Exit;
    end;
    LogLine(Format('Update-Prüfung: neueste Version %s, installiert %s',
      [FInfo.Version, GCurrent]));
    if not IsNewerVersion(FInfo.Version, GCurrent) then Exit;
    Skip := UpdateSkipVersion(StemIniFileName);
    if (Skip <> '') and (Skip = FInfo.Version) then
    begin
      LogLine('Update-Prüfung: Version ' + Skip + ' wird übersprungen (INI)');
      Exit;
    end;
    if Assigned(GOnFound) then
      GOnFound(FInfo);
  finally
    FreeUpdateInfo(FInfo);
  end;
end;

procedure StartUpdateCheck(const CurrentVersion: string; OnFound: TUpdateFoundEvent);
var
  T: TUpdateCheckThread;
begin
  if not UpdateAutoCheck(StemIniFileName) then
  begin
    LogLine('Update-Prüfung beim Start ist abgeschaltet ([Update] AutoCheck=0)');
    Exit;
  end;
  GOnFound := OnFound;
  GCurrent := CurrentVersion;
  T := TUpdateCheckThread.Create(True);
  T.FreeOnTerminate := True;
  T.OnTerminate := @T.Done;
  T.Start;
end;

procedure CancelUpdateCheck;
begin
  GOnFound := nil;
end;

{ ---------------------------------------------------------------------------
  Download-Fenster: Balken + Abbrechen, Download im Thread
  --------------------------------------------------------------------------- }
type
  TfrmUpdateDl = class;

  TUpdateDlThread = class(TThread)
  private
    FForm: TfrmUpdateDl;
    FURL, FDest: string;
    FDone, FTotal: Int64;
    procedure Progress(Done, Total: Int64);
    function IsCancelled: Boolean;
    procedure SyncProgress;
  protected
    procedure Execute; override;
  public
    OK: Boolean;
    ErrMsg: string;
  end;

  TfrmUpdateDl = class(TForm)
  private
    pb: TProgressBar;
    lbl: TLabel;
    FThread: TUpdateDlThread;       // läuft gerade (nil = fertig)
    FFinished: TUpdateDlThread;     // fertiger Thread, wird nach dem Fenster freigegeben
    procedure btnCancelClick(Sender: TObject);
    procedure ThreadDone(Sender: TObject);
    procedure FormCloseQueryDl(Sender: TObject; var CanClose: Boolean);
  public
    OK: Boolean;
    ErrMsg: string;
    constructor CreateDl(const URL, Dest, Version: string);
    procedure ShowProgress(Done, Total: Int64);
  end;

procedure TUpdateDlThread.Progress(Done, Total: Int64);
begin
  FDone := Done;
  FTotal := Total;
  Synchronize(@SyncProgress);
end;

function TUpdateDlThread.IsCancelled: Boolean;
begin
  Result := Terminated;
end;

procedure TUpdateDlThread.SyncProgress;
begin
  FForm.ShowProgress(FDone, FTotal);
end;

procedure TUpdateDlThread.Execute;
begin
  OK := HttpDownload(FURL, FDest, @Progress, @IsCancelled, ErrMsg);
end;

constructor TfrmUpdateDl.CreateDl(const URL, Dest, Version: string);
var
  btnCancel: TButton;
begin
  inherited CreateNew(nil);
  Caption := APP_NAME + ' - ' + Format(_('Update auf %s'), [Version]);
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 460;
  ClientHeight := 120;
  OnCloseQuery := @FormCloseQueryDl;

  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.SetBounds(16, 14, 428, 18);
  lbl.Caption := Format(_('Lade StemMaker %s ...'), [Version]);

  pb := TProgressBar.Create(Self);
  pb.Parent := Self;
  pb.SetBounds(16, 40, 428, 20);
  pb.Smooth := True;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := Self;
  btnCancel.SetBounds(ClientWidth - 16 - 110, 76, 110, 30);
  btnCancel.Caption := _('Abbrechen');
  btnCancel.OnClick := @btnCancelClick;

  FThread := TUpdateDlThread.Create(True);
  FThread.FForm := Self;
  FThread.FURL := URL;
  FThread.FDest := Dest;
  FThread.FreeOnTerminate := False;
  FThread.OnTerminate := @ThreadDone;
  FThread.Start;
end;

procedure TfrmUpdateDl.ShowProgress(Done, Total: Int64);
begin
  if Total > 0 then
  begin
    pb.Style := pbstNormal;
    pb.Position := Round(Done * 100 / Total);
    lbl.Caption := Format(_('%.1f von %.1f MB'), [Done / 1048576, Total / 1048576]);
  end
  else
  begin
    pb.Style := pbstMarquee;
    lbl.Caption := Format(_('%.1f MB'), [Done / 1048576]);
  end;
end;

procedure TfrmUpdateDl.btnCancelClick(Sender: TObject);
begin
  if FThread <> nil then
    FThread.Terminate;            // Download bricht ab, ThreadDone schliesst
end;

procedure TfrmUpdateDl.FormCloseQueryDl(Sender: TObject; var CanClose: Boolean);
begin
  { mit dem X: wie Abbrechen - zu geht das Fenster erst, wenn der Thread fertig ist }
  CanClose := FThread = nil;
  if not CanClose then
    FThread.Terminate;
end;

procedure TfrmUpdateDl.ThreadDone(Sender: TObject);
begin
  OK := FThread.OK;
  ErrMsg := FThread.ErrMsg;
  { Thread nicht hier im eigenen OnTerminate freigeben (siehe Entwicklungslog),
    sondern erst, wenn das Fenster zu ist (ShowUpdateDialog) }
  FFinished := FThread;
  FThread := nil;
  if OK then ModalResult := mrOK else ModalResult := mrCancel;
end;

{ ---------------------------------------------------------------------------
  Update-Fenster
  --------------------------------------------------------------------------- }
const
  MR_NOW  = mrYes;
  MR_SKIP = mrIgnore;

function AskUpdate(const Info: TUpdateInfo; const CurrentVersion: string;
  out AutoCheck: Boolean): TModalResult;
var
  F: TForm;
  lblTitle, lblSub: TLabel;
  mem: TMemo;
  chk: TCheckBox;
  pnl: TPanel;
  bNow, bLater, bSkip: TButton;
begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := APP_NAME + ' - ' + _('Update');
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 560;
    F.ClientHeight := 360;

    lblTitle := TLabel.Create(F);
    lblTitle.Parent := F;
    lblTitle.SetBounds(16, 12, 528, 24);
    lblTitle.Caption := Format(_('StemMaker %s ist da'), [Info.Version]);
    lblTitle.Font.Style := [fsBold];
    lblTitle.Font.Height := -17;

    lblSub := TLabel.Create(F);
    lblSub.Parent := F;
    lblSub.SetBounds(16, 42, 528, 18);
    lblSub.Caption := Format(_('Installiert ist %s. Einstellungen, Liste, Logs, ' +
      'Modelle und ffmpeg bleiben erhalten.'), [CurrentVersion]);

    mem := TMemo.Create(F);
    mem.Parent := F;
    mem.SetBounds(16, 68, 528, 192);
    mem.ReadOnly := True;
    mem.WordWrap := True;
    mem.ScrollBars := ssAutoVertical;
    mem.Text := AdjustLineBreaks(StringReplace(Info.Notes, '\n', LineEnding, [rfReplaceAll]));
    if Info.PageURL <> '' then
      mem.Lines.Add(LineEnding + Info.PageURL);

    chk := TCheckBox.Create(F);
    chk.Parent := F;
    chk.SetBounds(16, 268, 528, 22);
    chk.Caption := _('Beim Start nach Updates suchen');
    chk.Checked := True;

    pnl := TPanel.Create(F);
    pnl.Parent := F;
    pnl.SetBounds(0, 300, 560, 60);
    pnl.BevelOuter := bvNone;

    bNow := TButton.Create(F);
    bNow.Parent := pnl;
    bNow.SetBounds(16, 12, 190, 32);
    bNow.Caption := _('Jetzt aktualisieren');
    bNow.Font.Style := [fsBold];
    bNow.ModalResult := MR_NOW;
    bNow.Default := True;

    bLater := TButton.Create(F);
    bLater.Parent := pnl;
    bLater.SetBounds(214, 12, 110, 32);
    bLater.Caption := _('Später');
    bLater.ModalResult := mrCancel;
    bLater.Cancel := True;

    bSkip := TButton.Create(F);
    bSkip.Parent := pnl;
    bSkip.SetBounds(332, 12, 212, 32);
    bSkip.Caption := _('Diese Version überspringen');
    bSkip.ModalResult := MR_SKIP;

    Result := F.ShowModal;
    AutoCheck := chk.Checked;
  finally
    F.Free;
  end;
end;

{ neuen StemMaker starten (wartet selbst, bis dieser hier zu ist) }
procedure RestartStemMaker;
var
  P: TProcessUTF8;
begin
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := ParamStr(0);
    P.CurrentDirectory := ExtractFilePath(ParamStr(0));
    P.Parameters.Add('--nach-update');
    P.Options := [];
    P.Execute;
  finally
    P.Free;
  end;
end;

function ShowUpdateDialog(const Info: TUpdateInfo; const CurrentVersion: string): Boolean;
var
  R: TModalResult;
  AutoCheck: Boolean;
  Zip, Got, Err: string;
  Dl: TfrmUpdateDl;
  Th: TThread;
begin
  Result := False;
  R := AskUpdate(Info, CurrentVersion, AutoCheck);
  UpdateSetAutoCheck(StemIniFileName, AutoCheck);
  if R = MR_SKIP then
  begin
    UpdateSetSkipVersion(StemIniFileName, Info.Version);
    LogLine('Update ' + Info.Version + ': übersprungen');
    Exit;
  end;
  if R <> MR_NOW then
  begin
    LogLine('Update ' + Info.Version + ': später');
    Exit;
  end;

  { ohne ZIP-Adresse oder Prüfsumme nicht automatisch installieren }
  if (Info.ZipURL = '') or (Info.ZipSHA256 = '') then
  begin
    LogLine('Update ' + Info.Version + ': keine Prüfsumme in update.json -> Release-Seite');
    MessageDlg(_('Dieses Update kann nicht automatisch installiert werden. ' +
      'Die Download-Seite wird im Browser geöffnet.'), mtInformation, [mbOK], 0);
    if Info.PageURL <> '' then OpenURL(Info.PageURL);
    Exit;
  end;

  Zip := GetTempDir(False) + 'StemMaker-update.zip';
  LogLine('Update ' + Info.Version + ': lade ' + Info.ZipURL);
  Dl := TfrmUpdateDl.CreateDl(Info.ZipURL, Zip, Info.Version);
  try
    Dl.ShowModal;
    Th := Dl.FFinished;
    if Th <> nil then
    begin
      Th.WaitFor;
      Th.Free;
    end;
    if not Dl.OK then
    begin
      LogLine('Update-Download fehlgeschlagen: ' + Dl.ErrMsg);
      MessageDlg(Format(_('Update konnte nicht geladen werden: %s'), [Dl.ErrMsg]),
        mtError, [mbOK], 0);
      Exit;
    end;
  finally
    Dl.Free;
  end;

  Got := FileSHA256(Zip);
  if not SameText(Got, Info.ZipSHA256) then
  begin
    LogLine(Format('Update: Prüfsumme falsch, erwartet %s, erhalten %s', [Info.ZipSHA256, Got]));
    SysUtils.DeleteFile(Zip);
    MessageDlg(_('Die Prüfsumme (SHA-256) des Updates stimmt nicht. Die Datei ' +
      'wurde verworfen, an StemMaker wurde nichts geändert.'), mtError, [mbOK], 0);
    Exit;
  end;
  LogLine('Update: Prüfsumme OK, installiere ...');

  if not InstallUpdate(Zip, ExtractFilePath(ParamStr(0)), Err) then
  begin
    SysUtils.DeleteFile(Zip);
    LogLine('Update-Installation fehlgeschlagen: ' + Err);
    MessageDlg(Format(_('Update konnte nicht installiert werden: %s'), [Err]) +
      LineEnding + LineEnding + _('Im Zweifel das ZIP von der Release-Seite ' +
      'von Hand entpacken.'), mtError, [mbOK], 0);
    Exit;
  end;
  SysUtils.DeleteFile(Zip);
  LogLine('Update auf ' + Info.Version + ' installiert - Neustart');
  MessageDlg(Format(_('StemMaker %s ist installiert. StemMaker startet jetzt neu.'),
    [Info.Version]), mtInformation, [mbOK], 0);
  RestartStemMaker;
  Result := True;
end;

end.
