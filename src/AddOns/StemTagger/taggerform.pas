{ ============================================================================
  taggerform.pas  -  Hauptfenster des Elospeed StemTagger

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Der StemTagger setzt Titel, Interpret, Cover und weitere Tags in
  Traktor-Stem-Dateien (.stem.mp4). Normale Tag-Editoren schreiben die
  Datei dabei manchmal so um, dass Traktor sie nicht mehr als Stem
  erkennt. Hier werden nur die Tags in moov/udta/meta/ilst geändert,
  alles andere (5 Spuren, 'stem'-Box, Audiodaten) bleibt Byte für Byte
  gleich - das erledigt uStemMP4.WriteMp4Tags, inklusive Prüfung der
  neuen Datei, bevor das Original ersetzt wird.

  Bedienung:
    - Dateien oder Ordner hineinziehen (oder über die Knöpfe oben)
    - eine oder mehrere Zeilen markieren, Felder unten ändern
      (bei mehreren Dateien gilt eine Änderung für alle markierten)
    - Cover: Bild hineinziehen, laden, aus der Zwischenablage einfügen
    - Speichern (Strg+S) schreibt alle geänderten Dateien

  Sprache: wie der StemPlayer übernimmt der StemTagger die Sprache aus
  StemMaker.ini (gemeinsame Sprachdateien lang\*.po, siehe src\ulang.pas).

  Versionen:
    0.1  (27.10.2026)  Erste Version (nur Stem-Dateien, MP3 folgt)
  ============================================================================ }
unit taggerform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, LCLType, LCLIntf, Clipbrd, FileUtil, LazFileUtils, LazUTF8,
  IniFiles, IntfGraphics, Contnrs, uLang, uStemMP4, coverbild;

const
  APP_TITLE = 'Elospeed StemTagger';
  APP_VER   = '0.1';

type
  { Eine Datei in der Liste }
  TTagEntry = class
    FileName: string;
    Orig    : TMp4Tags;        // so steht es in der Datei
    Cur     : TMp4Tags;        // so soll es werden
    Dirty   : TMp4TagFields;   // geänderte Felder (noch nicht gespeichert)
    IsStem  : Boolean;         // nur Stem-Dateien dürfen bearbeitet werden
    Tracks  : Integer;
    Status  : string;          // letzte Meldung (gespeichert, Fehler ...)
  end;

  TMainForm = class(TForm)
  private
    FEntries   : TFPObjectList;   // gehört der Liste, gibt Einträge frei
    FList      : TListView;
    FEdits     : array[TMp4TagField] of TEdit;   // tfCover = nil
    FMixed     : array[TMp4TagField] of Boolean; // Feld zeigt "verschieden"
    FCoverImg  : TImage;
    FCoverInfo : TLabel;
    FCoverMixed: Boolean;
    FBtnAdd, FBtnFolder, FBtnRemove, FBtnClear: TButton;
    FBtnCoverLoad, FBtnCoverPaste, FBtnCoverDel, FBtnCoverSave: TButton;
    FBtnFromName, FBtnSave, FBtnRevert: TButton;
    FChkBackup, FChkShrink: TCheckBox;
    FStatus    : TStatusBar;
    FLoading   : Boolean;          // Felder werden gerade befüllt -> OnChange ignorieren
    FSelPending: Boolean;          // Anzeige der Auswahl ist schon bestellt
    FLastDir   : string;

    procedure LoadLanguage;
    procedure BuildUI;
    function  MakeButton(AParent: TWinControl; const ACaption: string;
                         ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
    function  FieldCaption(F: TMp4TagField): string;
    function  IniFileName: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure Log(const S: string);

    { Liste }
    procedure AddPath(const Path: string);
    procedure AddFile(const FileName: string);
    procedure RefreshRow(Item: TListItem);
    procedure UpdateStatusBar;
    function  SelectedEntries: TFPList;
    function  DirtyCount: Integer;
    procedure ShowSelection;
    procedure ShowSelectionAsync(Data: PtrInt);
    procedure ShowCover(const Data: TBytes);
    procedure ApplyCover(const Data: TBytes);
    procedure LoadCoverFile(const FileName: string);
    function  SaveAll: Boolean;

    { Ereignisse }
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FieldChange(Sender: TObject);
    procedure BtnAddClick(Sender: TObject);
    procedure BtnFolderClick(Sender: TObject);
    procedure BtnRemoveClick(Sender: TObject);
    procedure BtnClearClick(Sender: TObject);
    procedure BtnCoverLoadClick(Sender: TObject);
    procedure BtnCoverPasteClick(Sender: TObject);
    procedure BtnCoverDelClick(Sender: TObject);
    procedure BtnCoverSaveClick(Sender: TObject);
    procedure BtnFromNameClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnRevertClick(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

{ "Interpret - Titel" aus einem Dateinamen holen (öffentlich für Tests).
  False = kein Trenner gefunden, dann steht der ganze Name in Title. }
function SplitFileName(const FileName: string; out Artist, Title: string): Boolean;

implementation

const
  { Bildendungen, die als Cover gelten (beim Hineinziehen) }
  IMAGE_EXTS: array[0..5] of string = ('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.jfif');

function IsImageFile(const FileName: string): Boolean;
var
  E: string;
  I: Integer;
begin
  E := LowerCase(ExtractFileExt(FileName));
  for I := Low(IMAGE_EXTS) to High(IMAGE_EXTS) do
    if E = IMAGE_EXTS[I] then
      Exit(True);
  Result := False;
end;

{ Datei, die der StemTagger öffnen kann (MP4-Container) }
function IsTagFile(const FileName: string): Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  Result := (E = '.mp4') or (E = '.m4a');
end;

{ Name ohne .stem.mp4 / .mp4 / .m4a }
function BareName(const FileName: string): string;
var
  L: string;
begin
  Result := ExtractFileName(FileName);
  L := LowerCase(Result);
  if (Pos('.stem.mp4', L) > 0) and (Pos('.stem.mp4', L) = Length(L) - 8) then
    SetLength(Result, Length(Result) - 9)
  else if (Pos('.stem.m4a', L) > 0) and (Pos('.stem.m4a', L) = Length(L) - 8) then
    SetLength(Result, Length(Result) - 9)
  else
    Result := ChangeFileExt(Result, '');
end;

function SplitFileName(const FileName: string; out Artist, Title: string): Boolean;
var
  N: string;
  I, P, SepLen: Integer;
begin
  Artist := '';
  N := Trim(BareName(FileName));
  { Unterstriche statt Leerzeichen (Artist_-_Title) }
  if (Pos(' ', N) = 0) and (Pos('_', N) > 0) then
    N := StringReplace(N, '_', ' ', [rfReplaceAll]);
  { führende Tracknummer weg: "01. ", "01) ", "01 - Interpret - Titel".
    "50 Cent - Titel" bleibt, weil danach kein zweiter Trenner kommt. }
  I := 1;
  while (I <= Length(N)) and (I <= 3) and (N[I] in ['0'..'9']) do Inc(I);
  if (I > 1) and (I <= Length(N)) then
  begin
    if N[I] in ['.', ')'] then
      N := Trim(Copy(N, I + 1, MaxInt))
    else if (Copy(N, I, 3) = ' - ') and (Pos(' - ', Copy(N, I + 3, MaxInt)) > 0) then
      N := Trim(Copy(N, I + 3, MaxInt));
  end;
  { Trenner " - " oder mit Gedankenstrich " – " (UTF-8) }
  SepLen := 3;
  P := Pos(' - ', N);
  if P = 0 then
  begin
    P := Pos(' '#$E2#$80#$93' ', N);
    SepLen := 5;
  end;
  Result := P > 0;
  if Result then
  begin
    Artist := Trim(Copy(N, 1, P - 1));
    Title := Trim(Copy(N, P + SepLen, MaxInt));
    if (Artist = '') or (Title = '') then
    begin
      Result := False;
      Artist := '';
      Title := N;
    end;
  end
  else
    Title := N;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
            ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FileBytes(const FileName: string): TBytes;
var
  S: TFileStream;
begin
  Result := nil;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[0], S.Size);
  finally
    S.Free;
  end;
end;

{ ============================================================================
  Aufbau
  ============================================================================ }

constructor TMainForm.Create(TheOwner: TComponent);
var
  I: Integer;
begin
  inherited CreateNew(TheOwner);
  FEntries := TFPObjectList.Create(True);
  LoadLanguage;
  BuildUI;
  LoadSettings;
  { Dateien/Ordner von der Befehlszeile (z.B. Explorer "Öffnen mit") }
  for I := 1 to ParamCount do
    AddPath(ParamStr(I));
  UpdateStatusBar;
  ShowSelection;
end;

destructor TMainForm.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

{ Sprache wie StemMaker: zuerst StemMaker.ini im Programmordner, dann die
  in %APPDATA%, sonst die Sprache von Windows (gleich wie im StemPlayer) }
procedure TMainForm.LoadLanguage;
var
  Ini: TIniFile;
  Code, IniName: string;
  i: Integer;
begin
  Code := '';
  for i := 1 to 2 do
  begin
    if i = 1 then
      IniName := AppBaseDir + 'StemMaker.ini'
    else
      IniName := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
        'StemMaker' + PathDelim + 'StemMaker.ini';
    if not FileExists(IniName) then Continue;
    try
      Ini := TIniFile.Create(IniName);
      try
        Code := Trim(Ini.ReadString('Main', 'Language', ''));
      finally
        Ini.Free;
      end;
    except
      Code := '';
    end;
    if Code <> '' then Break;
  end;
  if Code = '' then
    Code := LangSystemDefault;
  LangLoad(Code);
end;

function TMainForm.FieldCaption(F: TMp4TagField): string;
begin
  case F of
    tfTitle      : Result := _('Titel');
    tfArtist     : Result := _('Interpret');
    tfAlbum      : Result := _('Album');
    tfAlbumArtist: Result := _('Album-Interpret');
    tfGenre      : Result := _('Genre');
    tfYear       : Result := _('Jahr');
    tfTrack      : Result := _('Track-Nr.');
    tfBpm        : Result := _('BPM');
    tfKey        : Result := _('Tonart');
    tfLabel      : Result := _('Label');
    tfComment    : Result := _('Kommentar');
  else
    Result := _('Cover');
  end;
end;

function TMainForm.MakeButton(AParent: TWinControl; const ACaption: string;
  ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(Scale96ToForm(ALeft), Scale96ToForm(ATop),
    Scale96ToForm(AWidth), Scale96ToForm(28));
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TMainForm.BuildUI;
const
  { linke und rechte Spalte der Felder }
  Col1: array[0..5] of TMp4TagField =
    (tfTitle, tfArtist, tfAlbum, tfAlbumArtist, tfGenre, tfYear);
  Col2: array[0..4] of TMp4TagField =
    (tfTrack, tfBpm, tfKey, tfLabel, tfComment);
  ROW_H = 32;
var
  PnlTop, PnlEdit, Fields, CoverPanel, Frame, Btns: TPanel;
  Col: TListColumn;
  Lbl: TLabel;
  F: TMp4TagField;
  I: Integer;

  procedure AddField(AField: TMp4TagField; X, Y: Integer);
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := Fields;
    Lbl.SetBounds(Scale96ToForm(X), Scale96ToForm(Y + 5), Scale96ToForm(110), Scale96ToForm(20));
    Lbl.Caption := FieldCaption(AField);
    FEdits[AField] := TEdit.Create(Self);
    FEdits[AField].Parent := Fields;
    FEdits[AField].SetBounds(Scale96ToForm(X + 115), Scale96ToForm(Y),
      Scale96ToForm(235), Scale96ToForm(26));
    FEdits[AField].Tag := Ord(AField);
    FEdits[AField].OnChange := @FieldChange;
    Lbl.FocusControl := FEdits[AField];
  end;

begin
  Caption := APP_TITLE + ' ' + APP_VER;
  Position := poScreenCenter;
  Width := Scale96ToForm(1000);
  Height := Scale96ToForm(700);
  Constraints.MinWidth := Scale96ToForm(880);
  Constraints.MinHeight := Scale96ToForm(560);
  KeyPreview := True;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  OnKeyDown := @FormKeyDown;
  OnCloseQuery := @FormCloseQuery;

  { --- oben: Dateien ------------------------------------------------------ }
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := Scale96ToForm(44);
  PnlTop.BevelOuter := bvNone;
  FBtnAdd    := MakeButton(PnlTop, _('Dateien...'), 8, 8, 120, @BtnAddClick);
  FBtnFolder := MakeButton(PnlTop, _('Ordner...'), 134, 8, 120, @BtnFolderClick);
  FBtnRemove := MakeButton(PnlTop, _('Entfernen'), 260, 8, 120, @BtnRemoveClick);
  FBtnClear  := MakeButton(PnlTop, _('Liste leeren'), 386, 8, 120, @BtnClearClick);
  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlTop;
  Lbl.SetBounds(Scale96ToForm(520), Scale96ToForm(14), Scale96ToForm(460), Scale96ToForm(20));
  Lbl.Caption := _('Stem-Dateien oder Ordner hierher ziehen');
  Lbl.Font.Color := clGrayText;

  { --- Statuszeile und Knöpfe unten -------------------------------------- }
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  Btns := TPanel.Create(Self);
  Btns.Parent := Self;
  Btns.Align := alBottom;
  Btns.Height := Scale96ToForm(44);
  Btns.BevelOuter := bvNone;
  FBtnSave   := MakeButton(Btns, _('Speichern'), 8, 8, 150, @BtnSaveClick);
  FBtnSave.Font.Style := [fsBold];
  FBtnRevert := MakeButton(Btns, _('Änderungen verwerfen'), 164, 8, 180, @BtnRevertClick);
  FChkBackup := TCheckBox.Create(Self);
  FChkBackup.Parent := Btns;
  FChkBackup.SetBounds(Scale96ToForm(364), Scale96ToForm(12), Scale96ToForm(250), Scale96ToForm(22));
  FChkBackup.Caption := _('Sicherungskopie anlegen (.bak)');
  FChkShrink := TCheckBox.Create(Self);
  FChkShrink.Parent := Btns;
  FChkShrink.SetBounds(Scale96ToForm(620), Scale96ToForm(12), Scale96ToForm(360), Scale96ToForm(22));
  FChkShrink.Caption := Format(_('Grosse Cover auf %d px verkleinern'), [COVER_MAX_SIDE]);
  FChkShrink.Checked := True;

  { --- Bearbeiten-Bereich ------------------------------------------------- }
  PnlEdit := TPanel.Create(Self);
  PnlEdit.Parent := Self;
  PnlEdit.Align := alBottom;
  PnlEdit.Height := Scale96ToForm(270);
  PnlEdit.BevelOuter := bvNone;

  CoverPanel := TPanel.Create(Self);
  CoverPanel.Parent := PnlEdit;
  CoverPanel.Align := alLeft;
  CoverPanel.Width := Scale96ToForm(230);
  CoverPanel.BevelOuter := bvNone;

  Frame := TPanel.Create(Self);
  Frame.Parent := CoverPanel;
  Frame.SetBounds(Scale96ToForm(8), Scale96ToForm(8), Scale96ToForm(176), Scale96ToForm(176));
  Frame.BevelOuter := bvLowered;
  Frame.Color := clBtnFace;
  FCoverImg := TImage.Create(Self);
  FCoverImg.Parent := Frame;
  FCoverImg.Align := alClient;
  FCoverImg.Stretch := True;
  FCoverImg.Proportional := True;
  FCoverImg.Center := True;

  FCoverInfo := TLabel.Create(Self);
  FCoverInfo.Parent := CoverPanel;
  FCoverInfo.SetBounds(Scale96ToForm(8), Scale96ToForm(188), Scale96ToForm(215), Scale96ToForm(18));
  FCoverInfo.Font.Color := clGrayText;

  FBtnCoverLoad  := MakeButton(CoverPanel, _('Bild...'), 8, 208, 106, @BtnCoverLoadClick);
  FBtnCoverPaste := MakeButton(CoverPanel, _('Einfügen'), 118, 208, 106, @BtnCoverPasteClick);
  FBtnCoverDel   := MakeButton(CoverPanel, _('Entfernen'), 8, 238, 106, @BtnCoverDelClick);
  FBtnCoverSave  := MakeButton(CoverPanel, _('Speichern...'), 118, 238, 106, @BtnCoverSaveClick);
  FBtnCoverPaste.Hint := _('Bild aus der Zwischenablage einfügen (Strg+V)');
  FBtnCoverPaste.ShowHint := True;

  Fields := TPanel.Create(Self);
  Fields.Parent := PnlEdit;
  Fields.Align := alClient;
  Fields.BevelOuter := bvNone;
  for F := Low(TMp4TagField) to High(TMp4TagField) do
    FEdits[F] := nil;
  for I := Low(Col1) to High(Col1) do
    AddField(Col1[I], 8, 8 + I * ROW_H);
  for I := Low(Col2) to High(Col2) do
    AddField(Col2[I], 375, 8 + I * ROW_H);
  FEdits[tfBpm].Hint := _('Ganze Zahl, z.B. 128 (Kommazahlen werden gerundet)');
  FEdits[tfBpm].ShowHint := True;
  FEdits[tfTrack].Hint := _('z.B. 3 oder 3/12');
  FEdits[tfTrack].ShowHint := True;
  FEdits[tfKey].Hint := _('z.B. Am, 8A oder 5m');
  FEdits[tfKey].ShowHint := True;
  FBtnFromName := MakeButton(Fields, _('Interpret/Titel aus Dateiname'),
    490, 8 + 5 * ROW_H, 235, @BtnFromNameClick);
  FBtnFromName.Hint := _('"Interpret - Titel.stem.mp4" füllt Interpret und Titel');
  FBtnFromName.ShowHint := True;

  { Reihenfolge unten festlegen (bei gleicher Ausrichtung entscheidet Top):
    Bearbeiten-Bereich, darunter Knöpfe, ganz unten die Statuszeile }
  PnlEdit.Top := 0;
  Btns.Top := PnlEdit.Top + PnlEdit.Height;
  FStatus.Top := Btns.Top + Btns.Height;

  { --- Liste (füllt den Rest) --------------------------------------------- }
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.MultiSelect := True;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.OnSelectItem := @ListSelectItem;
  FList.OnKeyDown := @ListKeyDown;
  Col := FList.Columns.Add; Col.Caption := _('Datei');     Col.Width := Scale96ToForm(240);
  Col := FList.Columns.Add; Col.Caption := _('Titel');     Col.Width := Scale96ToForm(170);
  Col := FList.Columns.Add; Col.Caption := _('Interpret'); Col.Width := Scale96ToForm(150);
  Col := FList.Columns.Add; Col.Caption := _('Album');     Col.Width := Scale96ToForm(110);
  Col := FList.Columns.Add; Col.Caption := _('BPM');       Col.Width := Scale96ToForm(45);
  Col := FList.Columns.Add; Col.Caption := _('Tonart');    Col.Width := Scale96ToForm(70);
  Col := FList.Columns.Add; Col.Caption := _('Cover');     Col.Width := Scale96ToForm(65);
  Col := FList.Columns.Add; Col.Caption := _('Status');    Col.Width := Scale96ToForm(140);
end;

{ ============================================================================
  Einstellungen und Log
  ============================================================================ }

{ StemTagger.ini neben der exe, bei schreibgeschütztem Ordner (Setup unter
  C:\Programme) in %APPDATA%\StemMaker\ - wie StemPlayer.ini }
function TMainForm.IniFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
  if not DirectoryIsWritable(ExtractFilePath(Result)) then
  begin
    Result := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
      'StemMaker' + PathDelim;
    ForceDirectories(Result);
    Result := Result + ExtractFileName(ChangeFileExt(Application.ExeName, '.ini'));
  end;
end;

procedure TMainForm.LoadSettings;
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      FChkBackup.Checked := Ini.ReadBool('Optionen', 'Sicherung', False);
      FChkShrink.Checked := Ini.ReadBool('Optionen', 'CoverVerkleinern', True);
      FLastDir := Ini.ReadString('Optionen', 'LetzterOrdner', '');
    finally
      Ini.Free;
    end;
  except
    { INI nicht lesbar -> Standardwerte }
  end;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Ini.WriteBool('Optionen', 'Sicherung', FChkBackup.Checked);
      Ini.WriteBool('Optionen', 'CoverVerkleinern', FChkShrink.Checked);
      Ini.WriteString('Optionen', 'LetzterOrdner', FLastDir);
    finally
      Ini.Free;
    end;
  except
    { nicht schlimm }
  end;
end;

{ Eine Zeile in logs\StemTagger.log (neben der exe, sonst %APPDATA%) }
procedure TMainForm.Log(const S: string);
var
  Dir, Fn: string;
  T: TextFile;
begin
  try
    Dir := ExtractFilePath(Application.ExeName) + 'logs';
    if not (ForceDirectories(Dir) and DirectoryIsWritable(Dir)) then
    begin
      Dir := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
        'StemMaker' + PathDelim + 'logs';
      ForceDirectories(Dir);
    end;
    Fn := IncludeTrailingPathDelimiter(Dir) + 'StemTagger.log';
    AssignFile(T, Fn);
    if FileExists(Fn) then Append(T) else Rewrite(T);
    try
      WriteLn(T, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + S);
    finally
      CloseFile(T);
    end;
  except
    { Log ist nur eine Hilfe - Fehler hier nie anzeigen }
  end;
end;

{ ============================================================================
  Liste
  ============================================================================ }

procedure TMainForm.AddPath(const Path: string);
var
  Files: TStringList;
  I: Integer;
begin
  if DirectoryExists(Path) then
  begin
    Files := FindAllFiles(Path, '*.stem.mp4;*.stem.m4a', True);
    try
      Files.Sort;
      FList.Items.BeginUpdate;
      try
        for I := 0 to Files.Count - 1 do
          AddFile(Files[I]);
      finally
        FList.Items.EndUpdate;
      end;
    finally
      Files.Free;
    end;
    FLastDir := Path;
  end
  else if FileExists(Path) and IsTagFile(Path) then
  begin
    AddFile(Path);
    FLastDir := ExtractFileDir(Path);
  end;
  UpdateStatusBar;
end;

procedure TMainForm.AddFile(const FileName: string);
var
  E: TTagEntry;
  I: Integer;
  Err: string;
  Item: TListItem;
begin
  { doppelte Dateien nicht nochmal aufnehmen }
  for I := 0 to FEntries.Count - 1 do
    if CompareFilenames(TTagEntry(FEntries[I]).FileName, FileName) = 0 then
      Exit;
  E := TTagEntry.Create;
  E.FileName := FileName;
  try
    E.Tracks := CountTracks(FileName);
    E.IsStem := (E.Tracks >= 5) and (ReadStemJSON(FileName) <> '');
    if not ReadMp4Tags(FileName, E.Orig, Err) then
    begin
      E.IsStem := False;
      E.Status := _('Nicht lesbar');
      Log('Nicht lesbar: ' + FileName + ' (' + Err + ')');
    end
    else if not E.IsStem then
      E.Status := _('Keine Stem-Datei');
  except
    on Ex: Exception do
    begin
      E.IsStem := False;
      E.Status := _('Nicht lesbar');
      Log('Nicht lesbar: ' + FileName + ' (' + Ex.Message + ')');
    end;
  end;
  E.Cur := E.Orig;
  E.Cur.Cover := Copy(E.Orig.Cover);
  FEntries.Add(E);
  Item := FList.Items.Add;
  Item.Data := E;
  RefreshRow(Item);
end;

procedure TMainForm.RefreshRow(Item: TListItem);
var
  E: TTagEntry;
  St: string;
begin
  E := TTagEntry(Item.Data);
  Item.Caption := ExtractFileName(E.FileName);
  Item.SubItems.Clear;
  Item.SubItems.Add(E.Cur.Text[tfTitle]);
  Item.SubItems.Add(E.Cur.Text[tfArtist]);
  Item.SubItems.Add(E.Cur.Text[tfAlbum]);
  Item.SubItems.Add(E.Cur.Text[tfBpm]);
  Item.SubItems.Add(E.Cur.Text[tfKey]);
  if Length(E.Cur.Cover) > 0 then
    Item.SubItems.Add(_('ja'))
  else
    Item.SubItems.Add('-');
  if E.Dirty <> [] then
    St := '* ' + _('geändert')
  else if E.Status <> '' then
    St := E.Status
  else
    St := Format(_('Stem OK (%d Spuren)'), [E.Tracks]);
  Item.SubItems.Add(St);
end;

function TMainForm.DirtyCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FEntries.Count - 1 do
    if TTagEntry(FEntries[I]).Dirty <> [] then
      Inc(Result);
end;

procedure TMainForm.UpdateStatusBar;
var
  N: Integer;
begin
  N := DirtyCount;
  FStatus.SimpleText := Format(_('%d Dateien, %d geändert'), [FEntries.Count, N]);
  FBtnSave.Enabled := N > 0;
  FBtnRevert.Enabled := N > 0;
end;

{ Liste der markierten Einträge (Aufrufer gibt die Liste frei) }
function TMainForm.SelectedEntries: TFPList;
var
  I: Integer;
begin
  Result := TFPList.Create;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
      Result.Add(FList.Items[I].Data);
end;

{ Felder mit den Werten der markierten Dateien füllen. Unterscheiden sich
  die Werte, bleibt das Feld leer und zeigt grau "<verschieden>". }
procedure TMainForm.ShowSelection;
var
  Sel: TFPList;
  F: TMp4TagField;
  I: Integer;
  V: string;
  CanEdit: Boolean;
  Cov: TBytes;
begin
  FSelPending := False;
  Sel := SelectedEntries;
  FLoading := True;
  try
    CanEdit := Sel.Count > 0;
    for I := 0 to Sel.Count - 1 do
      if not TTagEntry(Sel[I]).IsStem then
        CanEdit := False;
    for F := Low(TMp4TagField) to High(TMp4TagField) do
    begin
      if FEdits[F] = nil then Continue;
      FMixed[F] := False;
      V := '';
      if Sel.Count > 0 then
      begin
        V := TTagEntry(Sel[0]).Cur.Text[F];
        for I := 1 to Sel.Count - 1 do
          if TTagEntry(Sel[I]).Cur.Text[F] <> V then
          begin
            FMixed[F] := True;
            V := '';
            Break;
          end;
      end;
      FEdits[F].Text := V;
      if FMixed[F] then
        FEdits[F].TextHint := _('<verschieden>')
      else
        FEdits[F].TextHint := '';
      FEdits[F].Enabled := CanEdit;
    end;
    { Cover }
    Cov := nil;
    FCoverMixed := False;
    if Sel.Count > 0 then
    begin
      Cov := TTagEntry(Sel[0]).Cur.Cover;
      for I := 1 to Sel.Count - 1 do
        if not SameBytes(TTagEntry(Sel[I]).Cur.Cover, Cov) then
        begin
          FCoverMixed := True;
          Cov := nil;
          Break;
        end;
    end;
    ShowCover(Cov);
    if FCoverMixed then
      FCoverInfo.Caption := _('<verschieden>')
    else if Sel.Count = 0 then
      FCoverInfo.Caption := '';
    FBtnCoverLoad.Enabled := CanEdit;
    FBtnCoverPaste.Enabled := CanEdit;
    FBtnCoverDel.Enabled := CanEdit and (FCoverMixed or (Length(Cov) > 0));
    FBtnCoverSave.Enabled := Length(Cov) > 0;
    FBtnFromName.Enabled := CanEdit;
    FBtnRemove.Enabled := Sel.Count > 0;
  finally
    FLoading := False;
    Sel.Free;
  end;
end;

procedure TMainForm.ShowSelectionAsync(Data: PtrInt);
begin
  if FSelPending then
    ShowSelection;
end;

procedure TMainForm.ShowCover(const Data: TBytes);
var
  S: TMemoryStream;
  W, H: Integer;
begin
  FCoverImg.Picture.Clear;
  FCoverInfo.Caption := _('kein Cover');
  if Length(Data) = 0 then Exit;
  S := TMemoryStream.Create;
  try
    S.WriteBuffer(Data[0], Length(Data));
    S.Position := 0;
    try
      FCoverImg.Picture.LoadFromStream(S);
    except
      FCoverImg.Picture.Clear;
    end;
  finally
    S.Free;
  end;
  if CoverSize(Data, W, H) then
    FCoverInfo.Caption := Format('%d x %d, %d KB, %s',
      [W, H, (Length(Data) + 1023) div 1024, UpperCase(Copy(CoverExt(Data), 2, 3))])
  else
    FCoverInfo.Caption := Format('%d KB', [(Length(Data) + 1023) div 1024]);
end;

{ Neues Cover (oder leer = entfernen) für alle markierten Dateien }
procedure TMainForm.ApplyCover(const Data: TBytes);
var
  Sel: TFPList;
  I: Integer;
  E: TTagEntry;
begin
  Sel := SelectedEntries;
  try
    for I := 0 to Sel.Count - 1 do
    begin
      E := TTagEntry(Sel[I]);
      if not E.IsStem then Continue;
      E.Cur.Cover := Copy(Data);
      if SameBytes(E.Cur.Cover, E.Orig.Cover) then
        Exclude(E.Dirty, tfCover)
      else
        Include(E.Dirty, tfCover);
    end;
  finally
    Sel.Free;
  end;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
      RefreshRow(FList.Items[I]);
  ShowSelection;
  UpdateStatusBar;
end;

procedure TMainForm.LoadCoverFile(const FileName: string);
var
  Data, Res: TBytes;
  Info: string;
  Max: Integer;
begin
  try
    Data := FileBytes(FileName);
  except
    on E: Exception do
    begin
      MessageDlg(Format(_('Bild kann nicht gelesen werden:%s%s'), [LineEnding, FileName]),
        mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if FChkShrink.Checked then Max := COVER_MAX_SIDE else Max := 0;
  if not PrepareCover(Data, Max, Res, Info) then
  begin
    MessageDlg(_('Dieses Bildformat wird nicht unterstützt. Bitte JPEG, PNG, BMP oder GIF verwenden.'),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  Log('Cover geladen: ' + FileName + ' (' + Info + ')');
  ApplyCover(Res);
end;

{ ============================================================================
  Speichern
  ============================================================================ }

function TMainForm.SaveAll: Boolean;
var
  I, Ok, Bad: Integer;
  E: TTagEntry;
  Err, Bak: string;
  Fresh: TMp4Tags;
begin
  Ok := 0;
  Bad := 0;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to FList.Items.Count - 1 do
    begin
      E := TTagEntry(FList.Items[I].Data);
      if (E.Dirty = []) or not E.IsStem then Continue;
      FStatus.SimpleText := Format(_('Speichere %s ...'), [ExtractFileName(E.FileName)]);
      Application.ProcessMessages;
      { Sicherungskopie nur einmal anlegen - so bleibt das echte Original }
      if FChkBackup.Checked then
      begin
        Bak := E.FileName + '.bak';
        if not FileExists(Bak) and not CopyFile(E.FileName, Bak) then
        begin
          E.Status := _('Fehler: Sicherungskopie nicht möglich');
          Log('Sicherungskopie fehlgeschlagen: ' + Bak);
          Inc(Bad);
          RefreshRow(FList.Items[I]);
          Continue;
        end;
      end;
      if WriteMp4Tags(E.FileName, E.Cur, E.Dirty, Err) then
      begin
        Log('Gespeichert: ' + E.FileName);
        if ReadMp4Tags(E.FileName, Fresh, Err) then
          E.Orig := Fresh
        else
          E.Orig := E.Cur;
        E.Cur := E.Orig;
        E.Cur.Cover := Copy(E.Orig.Cover);
        E.Dirty := [];
        E.Status := _('Gespeichert');
        Inc(Ok);
      end
      else
      begin
        E.Status := _('Fehler: ') + Err;
        Log('Fehler beim Speichern: ' + E.FileName + ' (' + Err + ')');
        Inc(Bad);
      end;
      RefreshRow(FList.Items[I]);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  UpdateStatusBar;
  ShowSelection;
  if Bad > 0 then
    MessageDlg(Format(_('%d Dateien gespeichert, %d mit Fehler. Die Dateien mit Fehler sind unverändert, Details in der Spalte Status.'),
      [Ok, Bad]), mtWarning, [mbOK], 0)
  else if Ok > 0 then
    FStatus.SimpleText := Format(_('%d Dateien gespeichert'), [Ok]);
  Result := Bad = 0;
end;

{ ============================================================================
  Ereignisse
  ============================================================================ }

procedure TMainForm.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  { Bei "alle markieren" kommt das Ereignis für jede Zeile - die Anzeige
    nur einmal danach aktualisieren }
  if not FSelPending then
  begin
    FSelPending := True;
    Application.QueueAsyncCall(@ShowSelectionAsync, 0);
  end;
end;

procedure TMainForm.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  I: Integer;
begin
  if Key = VK_DELETE then
  begin
    BtnRemoveClick(nil);
    Key := 0;
  end
  else if (Key = VK_A) and (ssCtrl in Shift) then
  begin
    FList.Items.BeginUpdate;
    try
      for I := 0 to FList.Items.Count - 1 do
        FList.Items[I].Selected := True;
    finally
      FList.Items.EndUpdate;
    end;
    Key := 0;
  end;
end;

{ Ein Feld wurde geändert -> für alle markierten Dateien übernehmen }
procedure TMainForm.FieldChange(Sender: TObject);
var
  F: TMp4TagField;
  Sel: TFPList;
  I: Integer;
  E: TTagEntry;
  V: string;
begin
  if FLoading then Exit;
  F := TMp4TagField(TEdit(Sender).Tag);
  V := TEdit(Sender).Text;
  Sel := SelectedEntries;
  try
    for I := 0 to Sel.Count - 1 do
    begin
      E := TTagEntry(Sel[I]);
      if not E.IsStem then Continue;
      { Feld war "verschieden" und ist wieder leer: nichts ändern, jede
        Datei behält ihren eigenen Wert }
      if FMixed[F] and (V = '') then
        E.Cur.Text[F] := E.Orig.Text[F]
      else
        E.Cur.Text[F] := V;
      if E.Cur.Text[F] = E.Orig.Text[F] then
        Exclude(E.Dirty, F)
      else
        Include(E.Dirty, F);
    end;
  finally
    Sel.Free;
  end;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
      RefreshRow(FList.Items[I]);
  UpdateStatusBar;
end;

procedure TMainForm.BtnAddClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  I: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := _('Stem-Dateien öffnen');
    Dlg.Filter := _('Stem-Dateien') + ' (*.stem.mp4;*.stem.m4a)|*.stem.mp4;*.stem.m4a|' +
                  _('MP4-Dateien') + ' (*.mp4;*.m4a)|*.mp4;*.m4a';
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    Dlg.InitialDir := FLastDir;
    if Dlg.Execute then
    begin
      FList.Items.BeginUpdate;
      try
        for I := 0 to Dlg.Files.Count - 1 do
          AddPath(Dlg.Files[I]);
      finally
        FList.Items.EndUpdate;
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.BtnFolderClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := _('Ordner mit Stem-Dateien wählen (mit Unterordnern)');
    Dlg.InitialDir := FLastDir;
    if Dlg.Execute then
    begin
      Screen.Cursor := crHourGlass;
      try
        AddPath(Dlg.FileName);
      finally
        Screen.Cursor := crDefault;
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.BtnRemoveClick(Sender: TObject);
var
  I, Dirty: Integer;
begin
  Dirty := 0;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected and (TTagEntry(FList.Items[I].Data).Dirty <> []) then
      Inc(Dirty);
  if (Dirty > 0) and (MessageDlg(Format(_('%d markierte Dateien haben ungespeicherte Änderungen. Trotzdem aus der Liste nehmen?'),
      [Dirty]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  FList.Items.BeginUpdate;
  try
    for I := FList.Items.Count - 1 downto 0 do
      if FList.Items[I].Selected then
      begin
        FEntries.Remove(TTagEntry(FList.Items[I].Data));   // gibt den Eintrag frei
        FList.Items.Delete(I);
      end;
  finally
    FList.Items.EndUpdate;
  end;
  UpdateStatusBar;
  ShowSelection;
end;

procedure TMainForm.BtnClearClick(Sender: TObject);
begin
  if (DirtyCount > 0) and (MessageDlg(_('Es gibt ungespeicherte Änderungen. Liste trotzdem leeren?'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  FList.Items.Clear;
  FEntries.Clear;
  UpdateStatusBar;
  ShowSelection;
end;

procedure TMainForm.BtnCoverLoadClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := _('Cover-Bild wählen');
    Dlg.Filter := _('Bilder') + ' (*.jpg;*.jpeg;*.png;*.bmp;*.gif)|*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.gif';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then
      LoadCoverFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

{ Bild als Datei-Bytes aus der Zwischenablage holen, wenn ein Programm es
  als PNG oder JPEG hineingelegt hat (Browser, Bildbearbeitung). So bleibt
  das Original erhalten, ohne Umweg über ein Bitmap. }
function ClipboardImageBytes(out Data: TBytes): Boolean;
const
  Names: array[0..3] of string = ('PNG', 'image/png', 'JFIF', 'image/jpeg');
var
  I: Integer;
  Fmt: TClipboardFormat;
  S: TMemoryStream;
begin
  Result := False;
  Data := nil;
  for I := Low(Names) to High(Names) do
  begin
    Fmt := ClipboardRegisterFormat(Names[I]);
    if (Fmt = 0) or not Clipboard.HasFormat(Fmt) then Continue;
    S := TMemoryStream.Create;
    try
      if Clipboard.GetFormat(Fmt, S) and (S.Size > 8) then
      begin
        SetLength(Data, S.Size);
        Move(S.Memory^, Data[0], S.Size);
        Exit(True);
      end;
    finally
      S.Free;
    end;
  end;
end;

procedure TMainForm.BtnCoverPasteClick(Sender: TObject);
var
  Pic: TPicture;
  Img: TLazIntfImage;
  Max: Integer;
  Raw, Res: TBytes;
  Info: string;
begin
  if FChkShrink.Checked then Max := COVER_MAX_SIDE else Max := 0;
  { 1. Versuch: PNG/JPEG direkt }
  try
    if ClipboardImageBytes(Raw) and PrepareCover(Raw, Max, Res, Info) then
    begin
      Log('Cover aus Zwischenablage (' + Info + ')');
      ApplyCover(Res);
      Exit;
    end;
  except
    { weiter mit dem Bitmap-Weg }
  end;
  { 2. Versuch: normales Windows-Bitmap }
  if not Clipboard.HasPictureFormat then
  begin
    MessageDlg(_('In der Zwischenablage ist kein Bild.'), mtInformation, [mbOK], 0);
    Exit;
  end;
  Pic := TPicture.Create;
  try
    try
      Pic.Assign(Clipboard);
      Img := Pic.Bitmap.CreateIntfImage;
      try
        Log(Format('Cover aus Zwischenablage (%dx%d)', [Img.Width, Img.Height]));
        ApplyCover(CoverFromImage(Img, Max));
      finally
        Img.Free;
      end;
    except
      on E: Exception do
        MessageDlg(_('Das Bild aus der Zwischenablage kann nicht gelesen werden.'),
          mtWarning, [mbOK], 0);
    end;
  finally
    Pic.Free;
  end;
end;

procedure TMainForm.BtnCoverDelClick(Sender: TObject);
begin
  ApplyCover(nil);
end;

procedure TMainForm.BtnCoverSaveClick(Sender: TObject);
var
  Sel: TFPList;
  Data: TBytes;
  Dlg: TSaveDialog;
  S: TFileStream;
begin
  Sel := SelectedEntries;
  try
    if Sel.Count = 0 then Exit;
    Data := TTagEntry(Sel[0]).Cur.Cover;
    if Length(Data) = 0 then Exit;
    Dlg := TSaveDialog.Create(Self);
    try
      Dlg.Title := _('Cover speichern');
      Dlg.FileName := BareName(TTagEntry(Sel[0]).FileName) + CoverExt(Data);
      Dlg.InitialDir := ExtractFileDir(TTagEntry(Sel[0]).FileName);
      Dlg.Options := Dlg.Options + [ofOverwritePrompt];
      if Dlg.Execute then
      begin
        S := TFileStream.Create(Dlg.FileName, fmCreate);
        try
          S.WriteBuffer(Data[0], Length(Data));
        finally
          S.Free;
        end;
      end;
    finally
      Dlg.Free;
    end;
  finally
    Sel.Free;
  end;
end;

procedure TMainForm.BtnFromNameClick(Sender: TObject);
var
  I, N: Integer;
  E: TTagEntry;
  Artist, Title: string;
begin
  N := 0;
  for I := 0 to FList.Items.Count - 1 do
  begin
    if not FList.Items[I].Selected then Continue;
    E := TTagEntry(FList.Items[I].Data);
    if not E.IsStem then Continue;
    if SplitFileName(E.FileName, Artist, Title) then
    begin
      E.Cur.Text[tfArtist] := Artist;
      if Artist <> E.Orig.Text[tfArtist] then Include(E.Dirty, tfArtist)
      else Exclude(E.Dirty, tfArtist);
    end;
    E.Cur.Text[tfTitle] := Title;
    if Title <> E.Orig.Text[tfTitle] then Include(E.Dirty, tfTitle)
    else Exclude(E.Dirty, tfTitle);
    RefreshRow(FList.Items[I]);
    Inc(N);
  end;
  ShowSelection;
  UpdateStatusBar;
  if N > 0 then
    FStatus.SimpleText := Format(_('%d Dateien aus dem Dateinamen übernommen - noch nicht gespeichert'), [N]);
end;

procedure TMainForm.BtnSaveClick(Sender: TObject);
begin
  SaveAll;
end;

procedure TMainForm.BtnRevertClick(Sender: TObject);
var
  I: Integer;
  E: TTagEntry;
begin
  for I := 0 to FList.Items.Count - 1 do
  begin
    E := TTagEntry(FList.Items[I].Data);
    if E.Dirty = [] then Continue;
    E.Cur := E.Orig;
    E.Cur.Cover := Copy(E.Orig.Cover);
    E.Dirty := [];
    RefreshRow(FList.Items[I]);
  end;
  UpdateStatusBar;
  ShowSelection;
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  I: Integer;
  AllImages: Boolean;
  Sel: TFPList;
  HasSel: Boolean;
begin
  if Length(FileNames) = 0 then Exit;
  AllImages := True;
  for I := Low(FileNames) to High(FileNames) do
    if not IsImageFile(FileNames[I]) then
      AllImages := False;
  if AllImages then
  begin
    { ein Bild auf das Fenster gezogen = Cover der markierten Dateien }
    Sel := SelectedEntries;
    HasSel := Sel.Count > 0;
    Sel.Free;
    if HasSel and FBtnCoverLoad.Enabled then
      LoadCoverFile(FileNames[0])
    else
      MessageDlg(_('Zuerst die Stem-Dateien markieren, die dieses Cover bekommen sollen.'),
        mtInformation, [mbOK], 0);
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  FList.Items.BeginUpdate;
  try
    for I := Low(FileNames) to High(FileNames) do
      AddPath(FileNames[I]);
  finally
    FList.Items.EndUpdate;
    Screen.Cursor := crDefault;
  end;
  { ist noch nichts markiert, gleich die erste Datei markieren }
  if (FList.Selected = nil) and (FList.Items.Count > 0) then
    FList.Items[0].Selected := True;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and (Key = VK_S) then
  begin
    if FBtnSave.Enabled then SaveAll;
    Key := 0;
  end
  else if (ssCtrl in Shift) and (Key = VK_V) and not (ActiveControl is TCustomEdit) then
  begin
    { Strg+V ausserhalb eines Textfelds = Cover einfügen }
    if FBtnCoverPaste.Enabled then BtnCoverPasteClick(nil);
    Key := 0;
  end;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if DirtyCount > 0 then
    case MessageDlg(_('Es gibt ungespeicherte Änderungen. Jetzt speichern?'),
                    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes: CanClose := SaveAll;
      mrNo : CanClose := True;
    else
      CanClose := False;
    end;
  if CanClose then
    SaveSettings;
end;

end.
