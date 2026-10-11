{ ============================================================================
  stem51form.pas  -  Fenster von "Elospeed 5.1 -> Stem" (Stem51.exe)

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Die schlanke Variante von StemDecks, nur für einen Zweck:
    5.1-Datei (VOB, MKV, MP4, DTS, AC3 ...) aufs Fenster ziehen
    -> daneben entsteht <Name>.stem.mp4 für Traktor, OHNE KI:
         Stem 1..4 = die vier 5.1-Teile gemäss Zuordnung
         (Standard: Front L/R, LFE, Center, Surround L/R)
         Master    = gleich wie Stem 1 oder still
  Hat die Quelle mehrere 5.1-Tonspuren (DVD: AC3 und DTS), wird gefragt,
  welche. Es wird immer die ganze Datei umgewandelt.

  Mitbenutzt aus StemDecks: surround51.pas (ffmpeg-Parameter),
  decklog.pas (Sprache DE/EN, Protokoll logs\Stem51.log mit Log-Fenster),
  ..\..\ustemmp4.pas (Stem-Block wie in StemMaker).

  Einstellungen in Stem51.ini neben der exe (gleicher Aufbau wie
  StemDecks.ini): [Zuordnung] DeckA..DeckD, LfeAuf0dB, MasterStill,
  [Allgemein] Sprache, [Pfade] ffmpeg.

  Versionen:
    0.1  (10.10.2026)  Erste Version (Test für einen Nutzer auf r/Traktor)
  ============================================================================ }
unit stem51form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, LCLType, LCLIntf, Process, FileUtil, LazFileUtils, IniFiles,
  uStemMP4, surround51, decklog;

const
  APP_TITLE = 'Elospeed 5.1 -> Stem';
  APP_VER   = '0.1';

type
  { TPackForm }

  TPackForm = class(TForm)
  private
    PnlDrop    : TPanel;
    LblDrop    : TLabel;
    LblMap     : TLabel;
    BtnOpen    : TButton;
    BtnSettings: TButton;
    BtnLog     : TButton;
    LblStatus  : TLabel;
    SrcDlg     : TOpenDialog;

    FFFmpeg     : string;
    FBusy       : Boolean;
    FCancel     : Boolean;
    FCloseAfter : Boolean;
    FParts      : TDeckParts;
    FLfeNorm    : Boolean;
    FMasterSilent: Boolean;
    FIniLang    : string;
    { Bedienelemente im Fenster Einstellungen (nur solange es offen ist) }
    FSetCb      : array[0..3] of TComboBox;
    FSetLfe     : TCheckBox;
    FSetMaster  : TComboBox;

    procedure BuildUI;
    procedure UpdateMapText;
    function  PartsText: string;
    function  IniFileName: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ShowSettings;
    procedure SettingsDefaultClick(Sender: TObject);
    procedure SettingsCloseQuery(Sender: TObject; var CanClose: Boolean);
    function  FindFFmpeg: string;
    function  EnsureFFmpeg: Boolean;
    function  RunTool(const Exe: string; Args: TStrings; const What: string;
                      out OutText: string): Integer;
    procedure SetBusy(B: Boolean);
    function  ChooseTrack(const Tracks: TAudioTracks; out Idx: Integer): Boolean;
    function  ProbeSource(const FileName: string; out Track: Integer;
                          out Layout, AudioLine: string): Boolean;
    function  MeasureLfeGain(const FileName, Layout: string; Track: Integer): Double;
    procedure Pack51(const FileName: string);
    procedure DeferredClose(Data: PtrInt);

    procedure BtnOpenClick(Sender: TObject);
    procedure BtnSettingsClick(Sender: TObject);
    procedure BtnLogClick(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure OpenParamLater(Data: PtrInt);
  public
    constructor Create(TheOwner: TComponent); override;
  end;

var
  PackForm: TPackForm;

implementation

const
  { Stem-Farben je 5.1-Teil (Front, Center, LFE, Surround) wie in StemDecks }
  PART_COLORS: array[0..3] of string = ('#56B4E9', '#CC79A7', '#D55E00', '#009E73');
  SRC_FILTER_EXT =
    '*.vob;*.mkv;*.mka;*.mp4;*.m4v;*.m4a;*.mov;*.ac3;*.eac3;*.dts;*.thd;*.wav;*.flac;' +
    '*.ts;*.m2ts;*.mts;*.avi;*.webm;*.ogg;*.opus';

{ ============================================================================
  Aufbau
  ============================================================================ }

constructor TPackForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);    // keine .lfm-Datei
  LoadSettings;
  InitLanguage(FIniLang);
  LogInit(APP_TITLE, APP_VER);
  Log('Zuordnung / mapping: ' + PartsText);

  Caption := APP_TITLE + ' ' + APP_VER + T('  -  von Elospeed', '  -  by Elospeed');
  ClientWidth := 600;
  ClientHeight := 380;
  Position := poScreenCenter;
  BorderIcons := [biSystemMenu, biMinimize];
  BorderStyle := bsSingle;
  Font.Name := 'Segoe UI';
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  OnCloseQuery := @FormCloseQuery;
  OnClose := @FormClose;
  OnShow := @FormShow;

  BuildUI;
  UpdateMapText;

  SrcDlg := TOpenDialog.Create(Self);
  SrcDlg.Title := T('5.1-Datei wählen', 'Choose a 5.1 file');
  SrcDlg.Filter := T('5.1-Ton (Video/Audio)', '5.1 audio (video/audio)') + '|' +
    SRC_FILTER_EXT + '|' + T('Alle Dateien', 'All files') + ' (*.*)|*.*';

  FFFmpeg := FindFFmpeg;
  Log('ffmpeg : ' + FFFmpeg);
  if FFFmpeg = '' then
    LblStatus.Caption := T('ffmpeg.exe nicht gefunden - wird beim ersten Gebrauch abgefragt.',
                           'ffmpeg.exe not found - you will be asked for it on first use.')
  else
    LblStatus.Caption := T('Bereit.', 'Ready.') + '   Log: ' + LogFileName;
end;

procedure TPackForm.BuildUI;
begin
  PnlDrop := TPanel.Create(Self);
  PnlDrop.Parent := Self;
  PnlDrop.SetBounds(16, 16, ClientWidth - 32, 200);
  PnlDrop.BevelOuter := bvLowered;
  PnlDrop.Color := $00F4EEE8;

  LblDrop := TLabel.Create(Self);
  LblDrop.Parent := PnlDrop;
  LblDrop.Align := alClient;
  LblDrop.Alignment := taCenter;
  LblDrop.Layout := tlCenter;
  LblDrop.WordWrap := True;
  LblDrop.Font.Size := 13;
  LblDrop.Caption :=
    T('5.1-Datei hier hineinziehen', 'Drop your 5.1 file here') + LineEnding +
    '(VOB, MKV, MP4, DTS, AC3 ...)' + LineEnding + LineEnding +
    T('Daneben entsteht  <Name>.stem.mp4  für Traktor', 'This creates  <name>.stem.mp4  for Traktor') +
    LineEnding + T('(ohne KI, die 5.1-Kanäle werden direkt zu Stems)',
                   '(no AI, the 5.1 channels become the stems directly)');

  LblMap := TLabel.Create(Self);
  LblMap.Parent := Self;
  LblMap.SetBounds(16, 226, ClientWidth - 32, 20);
  LblMap.AutoSize := False;
  LblMap.Font.Color := clGrayText;

  BtnOpen := TButton.Create(Self);
  BtnOpen.Parent := Self;
  BtnOpen.SetBounds(16, 258, 180, 34);
  BtnOpen.Caption := T('Datei öffnen ...', 'Open file ...');
  BtnOpen.OnClick := @BtnOpenClick;

  BtnSettings := TButton.Create(Self);
  BtnSettings.Parent := Self;
  BtnSettings.SetBounds(206, 258, 180, 34);
  BtnSettings.Caption := T('Einstellungen ...', 'Settings ...');
  BtnSettings.OnClick := @BtnSettingsClick;

  BtnLog := TButton.Create(Self);
  BtnLog.Parent := Self;
  BtnLog.SetBounds(396, 258, 188, 34);
  BtnLog.Caption := T('Log anzeigen', 'Show log');
  BtnLog.OnClick := @BtnLogClick;

  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := Self;
  LblStatus.SetBounds(16, 306, ClientWidth - 32, 60);
  LblStatus.AutoSize := False;
  LblStatus.WordWrap := True;
end;

function TPackForm.PartsText: string;
var s: Integer;
begin
  Result := '';
  for s := 0 to 3 do
  begin
    if s > 0 then Result := Result + '  ·  ';
    Result := Result + Format('%d = %s', [s + 1, PART_NAMES[FParts[s]]]);
  end;
end;

procedure TPackForm.UpdateMapText;
begin
  LblMap.Caption := 'Stems:  ' + PartsText;
end;

{ ============================================================================
  Einstellungen (wie in StemDecks)
  ============================================================================ }

function TPackForm.IniFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TPackForm.LoadSettings;
var
  Ini: TIniFile;
  d: Integer;
begin
  FParts := DEFAULT_PARTS;
  FLfeNorm := True;
  FMasterSilent := False;
  FIniLang := '';
  try
    Ini := TIniFile.Create(IniFileName);
    try
      for d := 0 to 3 do
        FParts[d] := Ini.ReadInteger('Zuordnung', 'Deck' + DECK_LETTERS[d], DEFAULT_PARTS[d]);
      FLfeNorm := Ini.ReadBool('Zuordnung', 'LfeAuf0dB', True);
      FMasterSilent := Ini.ReadBool('Zuordnung', 'MasterStill', False);
      FIniLang := Trim(Ini.ReadString('Allgemein', 'Sprache', ''));
    finally
      Ini.Free;
    end;
  except
  end;
  if not PartsValid(FParts) then FParts := DEFAULT_PARTS;
end;

procedure TPackForm.SaveSettings;
var
  Ini: TIniFile;
  d: Integer;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      for d := 0 to 3 do
        Ini.WriteInteger('Zuordnung', 'Deck' + DECK_LETTERS[d], FParts[d]);
      Ini.WriteBool('Zuordnung', 'LfeAuf0dB', FLfeNorm);
      Ini.WriteBool('Zuordnung', 'MasterStill', FMasterSilent);
      Ini.WriteString('Allgemein', 'Sprache', FIniLang);
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      Log('Einstellungen nicht gespeichert / settings not saved: ' + E.Message);
  end;
end;

procedure TPackForm.ShowSettings;
var
  F: TForm;
  Cb: array[0..3] of TComboBox;
  CbMaster, CbLang: TComboBox;
  ChkLfe: TCheckBox;
  L: TLabel;
  B: TButton;
  d, k, Y: Integer;
  OldLang: string;

  function AddLabel(const S: string; X, AY: Integer): TLabel;
  begin
    Result := TLabel.Create(F);
    Result.Parent := F;
    Result.Left := X;
    Result.Top := AY;
    Result.Caption := S;
  end;

  function AddCombo(X, AY, AW: Integer): TComboBox;
  begin
    Result := TComboBox.Create(F);
    Result.Parent := F;
    Result.Style := csDropDownList;
    Result.SetBounds(X, AY, AW, 26);
  end;

  function AddButton(const S: string; X: Integer; MR: TModalResult): TButton;
  begin
    Result := TButton.Create(F);
    Result.Parent := F;
    Result.SetBounds(X, F.ClientHeight - 44, 130, 30);
    Result.Caption := S;
    Result.ModalResult := MR;
  end;

begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := APP_TITLE + ' - ' + T('Einstellungen', 'Settings');
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.ClientWidth := 580;
    F.ClientHeight := 400;

    L := AddLabel(T('Welcher 5.1-Teil kommt in welchen Stem?',
                    'Which 5.1 part goes into which stem?'), 16, 16);
    L.Font.Style := [fsBold];

    for d := 0 to 3 do
    begin
      Y := 60 + d * 34;
      AddLabel(Format('Stem %d', [d + 1]), 16, Y + 4);
      Cb[d] := AddCombo(190, Y, 220);
      for k := 0 to 3 do Cb[d].Items.Add(PART_NAMES[k]);
      Cb[d].ItemIndex := FParts[d];
    end;

    ChkLfe := TCheckBox.Create(F);
    ChkLfe.Parent := F;
    ChkLfe.SetBounds(16, 206, 550, 24);
    ChkLfe.Caption := T('LFE (Sub) auf 0 dB Spitzenpegel anheben (ist auf DVDs meist sehr leise)',
                        'Raise LFE (sub) to 0 dB peak (usually very quiet on DVDs)');
    ChkLfe.Checked := FLfeNorm;

    AddLabel(T('Master-Spur der Stem-Datei:', 'Master track of the stem file:'), 16, 248);
    CbMaster := AddCombo(250, 244, 220);
    CbMaster.Items.Add(T('gleich wie Stem 1', 'same as stem 1'));
    CbMaster.Items.Add(T('still (leer)', 'silent (empty)'));
    if FMasterSilent then CbMaster.ItemIndex := 1 else CbMaster.ItemIndex := 0;

    AddLabel('Sprache / Language:', 16, 290);
    CbLang := AddCombo(250, 286, 220);
    CbLang.Items.Add('Automatisch / Automatic');
    CbLang.Items.Add('Deutsch');
    CbLang.Items.Add('English');
    if SameText(FIniLang, 'de') then CbLang.ItemIndex := 1
    else if SameText(FIniLang, 'en') then CbLang.ItemIndex := 2
    else CbLang.ItemIndex := 0;
    L := AddLabel(T('(gilt nach einem Neustart)', '(takes effect after a restart)'), 250, 316);
    L.Font.Color := clGrayText;

    B := AddButton(T('Standard', 'Default'), 16, mrNone);
    B.OnClick := @SettingsDefaultClick;
    B := AddButton('OK', F.ClientWidth - 2 * 138, mrOK);
    B.Default := True;
    B := AddButton(T('Abbrechen', 'Cancel'), F.ClientWidth - 138, mrCancel);
    B.Cancel := True;

    for d := 0 to 3 do FSetCb[d] := Cb[d];
    FSetLfe := ChkLfe;
    FSetMaster := CbMaster;
    F.OnCloseQuery := @SettingsCloseQuery;
    if F.ShowModal <> mrOK then Exit;

    for d := 0 to 3 do FParts[d] := Cb[d].ItemIndex;
    FLfeNorm := ChkLfe.Checked;
    FMasterSilent := CbMaster.ItemIndex = 1;
    OldLang := FIniLang;
    case CbLang.ItemIndex of
      1: FIniLang := 'de';
      2: FIniLang := 'en';
    else
      FIniLang := '';
    end;
    SaveSettings;
    UpdateMapText;
    Log(Format('Einstellungen / settings: %s  ·  LFE 0 dB=%s  ·  master silent=%s  ·  lang=%s',
      [PartsText, BoolToStr(FLfeNorm, True), BoolToStr(FMasterSilent, True), FIniLang]));
    if not SameText(OldLang, FIniLang) then
      MessageDlg(APP_TITLE, T('Die Sprache wird beim nächsten Start umgestellt.',
                              'The language changes at the next start.'), mtInformation, [mbOK], 0);
  finally
    FSetLfe := nil;
    FSetMaster := nil;
    F.Free;
  end;
end;

procedure TPackForm.SettingsDefaultClick(Sender: TObject);
var d: Integer;
begin
  for d := 0 to 3 do FSetCb[d].ItemIndex := DEFAULT_PARTS[d];
  FSetLfe.Checked := True;
  FSetMaster.ItemIndex := 0;
end;

{ Bei OK prüfen, ob jeder Teil genau einmal vorkommt }
procedure TPackForm.SettingsCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  P: TDeckParts;
  d: Integer;
begin
  if TForm(Sender).ModalResult <> mrOK then Exit;
  for d := 0 to 3 do P[d] := FSetCb[d].ItemIndex;
  CanClose := PartsValid(P);
  if not CanClose then
    MessageDlg(APP_TITLE, T('Jeder 5.1-Teil darf nur einmal vorkommen.',
                            'Each 5.1 part may be used only once.'), mtWarning, [mbOK], 0);
end;

{ ============================================================================
  ffmpeg
  ============================================================================ }

function TPackForm.FindFFmpeg: string;
const
  Candidates: array[0..9] of string = (
    'ffmpeg.exe', 'tools\ffmpeg.exe', 'bin\ffmpeg.exe', 'ffmpeg\bin\ffmpeg.exe',
    '..\ffmpeg.exe', '..\tools\ffmpeg.exe', '..\bin\ffmpeg.exe',
    '..\ffmpeg\bin\ffmpeg.exe', '..\..\tools\ffmpeg.exe', '..\..\ffmpeg.exe');
var
  Ini: TIniFile;
  Base, S: string;
  i: Integer;
begin
  S := '';
  try
    Ini := TIniFile.Create(IniFileName);
    try
      S := Ini.ReadString('Pfade', 'ffmpeg', '');
    finally
      Ini.Free;
    end;
  except
  end;
  if (S <> '') and FileExists(S) then Exit(S);
  Base := ExtractFilePath(Application.ExeName);
  for i := Low(Candidates) to High(Candidates) do
  begin
    S := ExpandFileName(Base + Candidates[i]);
    if FileExists(S) then Exit(S);
  end;
  Result := FindDefaultExecutablePath('ffmpeg.exe');
end;

{ Fragt einmalig nach ffmpeg.exe und merkt sich den Pfad in der .ini }
function TPackForm.EnsureFFmpeg: Boolean;
var
  Dlg: TOpenDialog;
  Ini: TIniFile;
begin
  if (FFFmpeg <> '') and FileExists(FFFmpeg) then Exit(True);
  Log('ffmpeg.exe nicht gefunden / not found - frage Nutzer / asking user');
  MessageDlg(APP_TITLE, T('ffmpeg.exe wurde nicht gefunden.' + LineEnding +
    'Bitte im nächsten Dialog die ffmpeg.exe auswählen' + LineEnding +
    '(z.B. aus StemMaker\tools\ oder von ffmpeg.org).',
    'ffmpeg.exe was not found.' + LineEnding +
    'Please select ffmpeg.exe in the next dialog' + LineEnding +
    '(e.g. from StemMaker\tools\ or from ffmpeg.org).'), mtInformation, [mbOK], 0);
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'ffmpeg.exe';
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|' + T('Programme', 'Programs') + ' (*.exe)|*.exe';
    if Dlg.Execute then FFFmpeg := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  Log('ffmpeg = ' + FFFmpeg);
  if FFFmpeg <> '' then
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Ini.WriteString('Pfade', 'ffmpeg', FFFmpeg);
    finally
      Ini.Free;
    end;
  except
  end;
  Result := FFFmpeg <> '';
end;

{ Startet ffmpeg ohne Konsolenfenster, liest die Ausgabe laufend mit und
  hält das Fenster bedienbar. Aufruf, Exit-Code, Dauer und Ausgabe kommen
  ins Protokoll. Rückgabe: Exit-Code, -1 bei Abbruch oder Startfehler. }
function TPackForm.RunTool(const Exe: string; Args: TStrings; const What: string;
  out OutText: string): Integer;
var
  P: TProcess;
  Buf: array[0..4095] of Char;
  Chunk, Cmd: string;
  n: LongInt;
  i: Integer;
  T0: QWord;

  procedure Drain;
  begin
    while P.Output.NumBytesAvailable > 0 do
    begin
      n := P.Output.Read(Buf, SizeOf(Buf));
      if n <= 0 then Break;
      SetString(Chunk, PChar(@Buf[0]), n);
      OutText := OutText + Chunk;
      if Length(OutText) > 60000 then
        OutText := Copy(OutText, Length(OutText) - 30000, MaxInt);
    end;
  end;

begin
  Result := -1;
  OutText := '';
  Cmd := '"' + Exe + '"';
  for i := 0 to Args.Count - 1 do
    if Pos(' ', Args[i]) > 0 then Cmd := Cmd + ' "' + Args[i] + '"'
    else Cmd := Cmd + ' ' + Args[i];
  Log(What);
  Log('  > ' + Cmd);
  T0 := GetTickCount64;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Parameters.Assign(Args);
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHIDE;
    try
      P.Execute;
    except
      on E: Exception do
      begin
        Log('  ! Start fehlgeschlagen / failed to start: ' + E.Message);
        OutText := E.Message;
        Exit(-1);
      end;
    end;
    while P.Running do
    begin
      Drain;
      if FCancel then
      begin
        P.Terminate(1);
        P.WaitOnExit;
        Log('  ! abgebrochen / cancelled');
        Exit(-1);
      end;
      LblStatus.Caption := Format('%s ... %d s', [What, (GetTickCount64 - T0) div 1000]);
      Application.ProcessMessages;
      Sleep(40);
    end;
    Drain;
    Result := P.ExitStatus;
  finally
    P.Free;
  end;
  Log(Format('  < Exit-Code %d nach / after %.1f s', [Result, (GetTickCount64 - T0) / 1000]));
  if Length(OutText) > 12000 then
    LogBlock('[...]' + LineEnding + Copy(OutText, Length(OutText) - 12000, MaxInt))
  else
    LogBlock(OutText);
end;

procedure TPackForm.SetBusy(B: Boolean);
begin
  FBusy := B;
  if B then Screen.Cursor := crHourGlass else Screen.Cursor := crDefault;
  BtnOpen.Enabled := not B;
  BtnSettings.Enabled := not B;
end;

procedure TPackForm.DeferredClose(Data: PtrInt);
begin
  Close;
end;

{ ============================================================================
  5.1 -> Stem-Datei
  ============================================================================ }

function TPackForm.ChooseTrack(const Tracks: TAudioTracks; out Idx: Integer): Boolean;
var
  F: TForm;
  LB: TListBox;
  L: TLabel;
  B: TButton;
  i: Integer;
begin
  Result := False;
  Idx := 0;
  F := TForm.CreateNew(nil);
  try
    F.Caption := APP_TITLE + ' - ' + T('Tonspur wählen', 'Choose audio track');
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.ClientWidth := 760;
    F.ClientHeight := 260;

    L := TLabel.Create(F);
    L.Parent := F;
    L.SetBounds(12, 12, 730, 20);
    L.Caption := T('Diese Datei hat mehrere 5.1-Tonspuren. Welche soll verwendet werden?',
                   'This file has several 5.1 audio tracks. Which one should be used?');

    LB := TListBox.Create(F);
    LB.Parent := F;
    LB.SetBounds(12, 40, 736, 160);
    for i := 0 to High(Tracks) do
      LB.Items.Add(Format(T('Tonspur %d:  %s', 'Audio track %d:  %s'),
        [Tracks[i].Index + 1, Tracks[i].Line]));
    LB.ItemIndex := 0;

    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(F.ClientWidth - 2 * 128, 214, 116, 30);
    B.Caption := 'OK';
    B.ModalResult := mrOK;
    B.Default := True;

    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(F.ClientWidth - 128, 214, 116, 30);
    B.Caption := T('Abbrechen', 'Cancel');
    B.ModalResult := mrCancel;
    B.Cancel := True;

    if (F.ShowModal = mrOK) and (LB.ItemIndex >= 0) then
    begin
      Idx := LB.ItemIndex;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

function TPackForm.ProbeSource(const FileName: string; out Track: Integer;
  out Layout, AudioLine: string): Boolean;
var
  Args: TStringList;
  OutText, AllLines: string;
  Tracks, Usable: TAudioTracks;
  i, n, Idx, Code: Integer;
begin
  Result := False;
  Track := -1;
  Layout := '';
  AudioLine := '';
  Log('Quelle / source: ' + FileName);
  Args := TStringList.Create;
  try
    Args.Add('-hide_banner');
    Args.Add('-nostdin');
    Args.Add('-probesize'); Args.Add('100M');
    Args.Add('-analyzeduration'); Args.Add('100M');
    Args.Add('-i'); Args.Add(FileName);
    Code := RunTool(FFFmpeg, Args, T('Prüfe Tonspuren', 'Checking audio tracks'), OutText);
  finally
    Args.Free;
  end;
  if Code < 0 then Exit;

  Tracks := ParseAudioTracks(OutText);
  Usable := nil;
  n := 0;
  AllLines := '';
  for i := 0 to High(Tracks) do
  begin
    AllLines := AllLines + '  ' + Tracks[i].Line + LineEnding;
    if IsSupported51(Tracks[i].Layout) then
    begin
      SetLength(Usable, n + 1);
      Usable[n] := Tracks[i];
      Inc(n);
    end;
  end;
  Log(Format('%d Tonspur(en) / audio track(s), davon 5.1 / of which 5.1: %d', [Length(Tracks), n]));

  if Length(Tracks) = 0 then
  begin
    MessageDlg(APP_TITLE, T('In dieser Datei wurde keine Tonspur gefunden:',
      'No audio track was found in this file:') + LineEnding + FileName + LineEnding + LineEnding +
      T('Bei DVDs: die grossen VOB-Dateien des Films nehmen (z.B. VTS_01_1.VOB),' + LineEnding +
        'nicht VIDEO_TS.VOB. Kopiergeschützte DVDs kann ffmpeg nicht lesen.',
        'For DVDs: use the big VOB files of the movie (e.g. VTS_01_1.VOB),' + LineEnding +
        'not VIDEO_TS.VOB. ffmpeg cannot read copy-protected DVDs.'),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  if n = 0 then
  begin
    MessageDlg(APP_TITLE, T('Keine 5.1-Tonspur gefunden. Vorhandene Tonspuren:',
      'No 5.1 audio track found. Audio tracks in this file:') + LineEnding + LineEnding +
      AllLines + LineEnding +
      T('Unterstützt wird 5.1 (6 Kanäle).', 'Supported: 5.1 (6 channels).'), mtWarning, [mbOK], 0);
    Exit;
  end;

  Idx := 0;
  if n > 1 then
    if not ChooseTrack(Usable, Idx) then Exit;
  Track := Usable[Idx].Index;
  Layout := Usable[Idx].Layout;
  AudioLine := Usable[Idx].Line;
  Log(Format('Gewählt / selected: Tonspur / audio track %d (%s)  %s', [Track + 1, Layout, AudioLine]));
  Result := True;
end;

function TPackForm.MeasureLfeGain(const FileName, Layout: string; Track: Integer): Double;
var
  Args: TStringList;
  OutText: string;
  Peak: Double;
  Code: Integer;
begin
  Result := 0;
  if not FLfeNorm then Exit;
  Args := TStringList.Create;
  try
    BuildLfePeakArgs(FileName, Layout, Track, 0, Args);
    Code := RunTool(FFFmpeg, Args, T('Messe LFE-Pegel', 'Measuring LFE level'), OutText);
  finally
    Args.Free;
  end;
  if Code <> 0 then Exit;
  if not ParseMaxVolume(OutText, Peak) then
  begin
    Log('LFE: kein max_volume gefunden / not found');
    Exit;
  end;
  if Peak < -80 then
  begin
    Log(Format('LFE ist praktisch stumm / practically silent (%.1f dB) - keine Anhebung / no gain', [Peak]));
    Exit;
  end;
  Result := EnsureRange(-Peak, 0, 40);
  Log(Format('LFE Spitze / peak %.1f dB -> Anhebung / gain +%.1f dB', [Peak, Result]));
end;

procedure TPackForm.Pack51(const FileName: string);
var
  Args: TStringList;
  OutText, AudioLine, Layout, OutFile, TmpFile, Err: string;
  Track, Code, s: Integer;
  Gain: Double;
  Stems: TStemInfoArray;
begin
  if FBusy or not FileExists(FileName) or not EnsureFFmpeg then Exit;
  OutFile := '';
  SetBusy(True);
  Args := TStringList.Create;
  try
    Log('--- 5.1 -> STEM ---');
    if not ProbeSource(FileName, Track, Layout, AudioLine) then Exit;

    OutFile := ExtractFilePath(FileName) + ExtractFileNameOnly(FileName) + '.stem.mp4';
    TmpFile := ExtractFilePath(FileName) + ExtractFileNameOnly(FileName) + '.stem51.tmp.mp4';
    if FileExists(OutFile) then
      if MessageDlg(APP_TITLE, ExtractFileName(OutFile) +
           T(' gibt es schon. Überschreiben?', ' already exists. Overwrite?'),
           mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      begin
        OutFile := '';
        Exit;
      end;

    Gain := MeasureLfeGain(FileName, Layout, Track);
    if FCancel then begin OutFile := ''; Exit; end;

    BuildPackArgs(FileName, TmpFile, Layout, Track, 0, FParts, Gain, FMasterSilent, Args);
    Code := RunTool(FFFmpeg, Args, T('Erstelle Stem-Datei', 'Creating stem file'), OutText);
    if (Code <> 0) or not FileExists(TmpFile) then
    begin
      DeleteFile(TmpFile);
      if Code >= 0 then
        MessageDlg(APP_TITLE, T('ffmpeg konnte die Stem-Datei nicht erstellen:',
          'ffmpeg could not create the stem file:') + LineEnding + LineEnding +
          Copy(Trim(OutText), 1, 1500) + LineEnding + LineEnding +
          T('Bitte das Log schicken (Knopf "Log anzeigen" -> "Log-Ordner öffnen").',
            'Please send us the log ("Show log" button -> "Open log folder").'), mtError, [mbOK], 0);
      OutFile := '';
      Exit;
    end;

    { Stem-Block (Namen + Farben für Traktor) wie in StemMaker }
    for s := 0 to 3 do
    begin
      Stems[s].Name := PART_STEM_NAMES[FParts[s]];
      Stems[s].Color := PART_COLORS[FParts[s]];
    end;
    if not InjectStemMetadata(TmpFile, BuildStemJSON(Stems), nil, Err) then
    begin
      Log('Stem-Block fehlgeschlagen / stem block failed: ' + Err);
      DeleteFile(TmpFile);
      MessageDlg(APP_TITLE, T('Stem-Block konnte nicht geschrieben werden:',
        'Could not write the stem block:') + LineEnding + Err, mtError, [mbOK], 0);
      OutFile := '';
      Exit;
    end;
    if FileExists(OutFile) then DeleteFile(OutFile);
    if not RenameFile(TmpFile, OutFile) then
    begin
      Log('Umbenennen fehlgeschlagen / rename failed: ' + TmpFile + ' -> ' + OutFile);
      MessageDlg(APP_TITLE, T('Konnte die Datei nicht umbenennen:', 'Could not rename the file:') +
        LineEnding + TmpFile, mtError, [mbOK], 0);
      OutFile := '';
      Exit;
    end;
    Log('Fertig / done: ' + OutFile);
    LblStatus.Caption := T('Fertig: ', 'Done: ') + OutFile;
    MessageDlg(APP_TITLE, T('Fertig:', 'Done:') + LineEnding + OutFile + LineEnding + LineEnding +
      'Stems:  ' + PartsText + LineEnding + LineEnding +
      T('Die Datei kann direkt in Traktor geladen werden. Der Ordner wird jetzt geöffnet.',
        'You can load the file straight into Traktor. The folder opens now.'),
      mtInformation, [mbOK], 0);
  finally
    Args.Free;
    SetBusy(False);
    if FCloseAfter then Application.QueueAsyncCall(@DeferredClose, 0);
  end;
  if (OutFile <> '') and not FCancel then
    OpenDocument(ExtractFilePath(OutFile));
end;

{ ============================================================================
  Ereignisse
  ============================================================================ }

procedure TPackForm.BtnOpenClick(Sender: TObject);
begin
  if FBusy then Exit;
  if SrcDlg.Execute then Pack51(SrcDlg.FileName);
end;

procedure TPackForm.BtnSettingsClick(Sender: TObject);
begin
  if FBusy then Exit;
  ShowSettings;
end;

procedure TPackForm.BtnLogClick(Sender: TObject);
begin
  ShowLogWindow;
end;

procedure TPackForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if (Length(FileNames) > 0) and not FBusy then Pack51(FileNames[0]);
end;

procedure TPackForm.FormShow(Sender: TObject);
begin
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then
    Application.QueueAsyncCall(@OpenParamLater, 0);
end;

procedure TPackForm.OpenParamLater(Data: PtrInt);
begin
  Pack51(ParamStr(1));
end;

{ Läuft ffmpeg noch, erst abbrechen und danach schliessen }
procedure TPackForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FBusy then
  begin
    FCancel := True;
    FCloseAfter := True;
    LblStatus.Caption := T('Breche ab ...', 'Cancelling ...');
    CanClose := False;
  end
  else
    CanClose := True;
end;

procedure TPackForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  Log('Beendet / closed');
end;

end.
