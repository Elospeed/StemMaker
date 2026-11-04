{ ============================================================================
  taggerform.pas  -  Hauptfenster des Elospeed StemTagger

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Der StemTagger setzt Titel, Interpret, Cover und weitere Tags in
  Traktor-Stem-Dateien (.stem.mp4) und MP3-Dateien. Normale Tag-Editoren schreiben die
  Datei dabei manchmal so um, dass Traktor sie nicht mehr als Stem
  erkennt. Hier werden nur die Tags in moov/udta/meta/ilst geändert,
  alles andere (5 Spuren, 'stem'-Box, Audiodaten) bleibt Byte für Byte
  gleich - das erledigt uMp4Tags.WriteMp4Tags, inklusive Prüfung der
  neuen Datei, bevor das Original ersetzt wird. Bei MP3 macht dasselbe
  uId3Tags.WriteMp3Tags: nur die geänderten ID3v2-Frames werden ersetzt,
  Audiodaten und Traktors eigene Frames bleiben Byte für Byte gleich.

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
         (27.10.2026)  Wünsche Speedy: Genre und Tonart mit Auswahlliste,
                       Tooltip an jedem Feld, BPM nur 20-300, Sicherungs-
                       kopie standardmässig an, Hinweis nach dem Laden eines
                       Ordners, Rückfrage vor dem Speichern mehrerer Dateien,
                       Status "Ohne Tags"/"Ohne Cover", Sortieren per Klick
                       auf die Spaltenüberschrift
         (28.10.2026)  Sicherungskopie standardmässig wieder aus (das
                       Speichern geht über eine geprüfte Zwischendatei),
                       Ko-fi-Knopf unten rechts wie in StemMaker
    1.0.1 (30.10.2026)  eigenes Repository Elospeed/StemTagger
    1.1.0 (30.10.2026)  MP3-Dateien (ID3v2, eigener Code in uid3tags.pas);
                       Traktors Daten in der MP3 (PRIV/GEOB "TRAKTOR4") und
                       alle unbekannten Frames bleiben erhalten;
                       Spalte "Traktor" zeigt, welche MP3s Traktor-Daten haben;
                       Eingabefelder wachsen mit dem Fenster (Skalierungstest)
    1.2.0 (30.10.2026)  Französisch, Portugiesisch (BR), Italienisch, Japanisch,
                       Niederländisch, Polnisch (wie StemMaker 2.2); Windows-
                       Sprache wird genommen, wenn es eine .po dazu gibt
  ============================================================================ }
unit taggerform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, LCLType, LCLIntf, Clipbrd, FileUtil, LazFileUtils, LazUTF8,
  IniFiles, IntfGraphics, Contnrs, ImgList, Math, uLang, uMp4Tags, uId3Tags, uStatusDraw, djcontrols, djextra, coverbild,
  uSkalierung;

const
  APP_TITLE = 'Elospeed StemTagger';
  APP_VER   = '1.2.0';
  KOFI_URL  = 'https://ko-fi.com/elospeed';

type
  { Eine Datei in der Liste }
  TTagEntry = class
    FileName: string;
    Orig    : TMp4Tags;        // so steht es in der Datei
    Cur     : TMp4Tags;        // so soll es werden
    Dirty   : TMp4TagFields;   // geänderte Felder (noch nicht gespeichert)
    IsStem  : Boolean;         // gültige Stem-Datei (5 Spuren + 'stem'-Box)
    IsMp3   : Boolean;         // MP3-Datei (Tags im ID3v2-Block)
    Mp3     : TMp3Info;        // ID3-Version, Traktor-Daten (nur bei MP3)
    CanEdit : Boolean;         // darf bearbeitet werden: Stem-Datei oder schreibbare MP3
    Tracks  : Integer;
    Status  : string;          // letzte Meldung (gespeichert, Fehler ...)
  end;

  TMainForm = class(TForm)
  private
    FEntries   : TFPObjectList;   // gehört der Liste, gibt Einträge frei
    FList      : TListView;
    FEdits     : array[TMp4TagField] of TWinControl; // TEdit oder TDJCombo, tfCover = nil
    FMixed     : array[TMp4TagField] of Boolean; // Feld zeigt "verschieden"
    FCoverImg  : TImage;
    FCoverInfo : TLabel;
    FCoverMixed: Boolean;
    { Knöpfe und Schalter im dunklen Stil des StemPlayers (djcontrols.pas) }
    FBtnAdd, FBtnFolder, FBtnRemove, FBtnClear: TDJButton;
    FBtnCoverLoad, FBtnCoverPaste, FBtnCoverDel, FBtnCoverSave: TDJButton;
    FBtnFromName, FBtnSave, FBtnRevert: TDJButton;
    FChkBackup, FChkShrink: TDJLedSwitch; // Schalter mit LED: Down = eingeschaltet
    { eigene Kopfzeile der Liste (die Windows-Kopfzeile wäre hell) }
    FHead      : TPaintBox;
    FColW      : array[0..7] of Integer;  // Spaltenbreiten in Pixeln, die letzte füllt den Rest
    FDragCol   : Integer;          // Spalte, deren rechter Rand gerade gezogen wird, -1 = keine
    FDragX0, FDragW0: Integer;     // Maus und Breite beim Beginn des Ziehens
    FDragged   : Boolean;          // wirklich gezogen (dann kein Sortieren)
    FLastAvail : Integer;          // Breite der Liste beim letzten Anpassen, 0 = noch nie
    FStatus    : TLabel;            // Statuszeile unten links
    FKofi      : TPaintBox;       // Ko-fi-Knopf unten rechts (wie in StemMaker)
    FKofiHover : Boolean;
    FLoading   : Boolean;          // Felder werden gerade befüllt -> OnChange ignorieren
    FFields    : TDJPanel;         // Bereich mit den Eingabefeldern (wächst mit dem Fenster)
    FLabels    : array[TMp4TagField] of TLabel;   // Beschriftung je Feld, nil = nicht angezeigt
    FFieldCol  : array[TMp4TagField] of Integer;  // Feld steht in Spalte 0 (links) oder 1 (rechts)
    FSelPending: Boolean;          // Anzeige der Auswahl ist schon bestellt
    FLastDir   : string;
    FFolderHint: Boolean;          // Hinweis nach dem Laden eines Ordners zeigen
    FFolderHintPending: Boolean;
    FSortCol   : Integer;          // zuletzt sortierte Spalte, -1 = keine
    FSortDesc  : Boolean;
    procedure ListColumnClick(Sender: TObject; Column: TListColumn);
    function  FieldText(F: TMp4TagField): string;
    procedure SetFieldText(F: TMp4TagField; const V: string; Mixed: Boolean);
    procedure CheckBpmField;
    procedure SetFieldHint(F: TMp4TagField; const H: string);
    procedure ComboSelect(Sender: TObject);
    procedure ComboSelectAsync(Data: PtrInt);
    procedure ShowFolderHint(Data: PtrInt);
    procedure KofiPaint(Sender: TObject);
    procedure KofiClick(Sender: TObject);
    procedure KofiEnter(Sender: TObject);
    procedure KofiLeave(Sender: TObject);

    procedure LoadLanguage;
    procedure BuildUI;
    function  MakeButton(AParent: TWinControl; const ACaption: string;
                         ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TDJButton;
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
    function  SaveAll(Ask: Boolean): Boolean;

    { Ereignisse }
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure HeadPaint(Sender: TObject);
    procedure HeadMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HeadMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure HeadMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function  HeadDivider(X: Integer): Integer;
    procedure FitColumns;
    function  HeadTextWidth(Col: Integer): Integer;
    procedure FieldsResize(Sender: TObject);
    procedure AutoFitColumn(Col: Integer);
    procedure ListResize(Sender: TObject);
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

{ Datei, die der StemTagger öffnen kann (MP4-Container oder MP3) }
function IsTagFile(const FileName: string): Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  Result := (E = '.mp4') or (E = '.m4a') or (E = '.mp3');
end;

{ Name ohne .stem.mp4 / .mp4 / .m4a / .mp3 }
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

const
  { Auswahl im Feld Genre - man kann auch selbst etwas eintippen.
    Genre-Namen sind international, deshalb nicht übersetzt. }
  GENRES: array[0..47] of string = (
    'Acid House', 'Afro House', 'Afrobeats', 'Amapiano', 'Ambient',
    'Bass House', 'Big Room', 'Breakbeat', 'Chillout', 'Dance', 'Deep House',
    'Disco', 'Downtempo', 'Drum & Bass', 'Dubstep', 'EDM', 'Electro',
    'Electro House', 'Electronica', 'Funk', 'Funky House', 'Hard Techno',
    'Hardcore', 'Hardstyle', 'Hip-Hop', 'House', 'Indie Dance', 'Jazz',
    'Latin', 'Melodic House & Techno', 'Minimal', 'Nu Disco',
    'Organic House', 'Pop', 'Progressive House', 'Psytrance', 'R&B',
    'Reggae', 'Reggaeton', 'Rock', 'Schlager', 'Soul', 'Tech House',
    'Techno', 'Trance', 'Trap', 'UK Garage', 'Urban');

  { Tonarten in der Reihenfolge des Camelot-Rads (1A, 1B, 2A ...).
    Gespeichert wird nur der erste Teil (z.B. "Am"), die Klammer zeigt
    dieselbe Tonart in Camelot- und Open-Key-Schreibweise. }
  KEYS: array[0..23] of string = (
    'G#m   (1A / 6m)',  'B     (1B / 6d)',
    'Ebm   (2A / 7m)',  'F#    (2B / 7d)',
    'Bbm   (3A / 8m)',  'Db    (3B / 8d)',
    'Fm    (4A / 9m)',  'Ab    (4B / 9d)',
    'Cm    (5A / 10m)', 'Eb    (5B / 10d)',
    'Gm    (6A / 11m)', 'Bb    (6B / 11d)',
    'Dm    (7A / 12m)', 'F     (7B / 12d)',
    'Am    (8A / 1m)',  'C     (8B / 1d)',
    'Em    (9A / 2m)',  'G     (9B / 2d)',
    'Bm    (10A / 3m)', 'D     (10B / 3d)',
    'F#m   (11A / 4m)', 'A     (11B / 4d)',
    'C#m   (12A / 5m)', 'E     (12B / 5d)');

  { Felder im Fenster: was Traktor und Mixxx anzeigen und durchsuchen
    (Speedy, 27.10.2026). Album-Interpret, Track-Nr., BPM und Tonart
    bleiben in der Datei unangetastet, werden aber nicht mehr gezeigt -
    BPM und Tonart rechnen Traktor und Mixxx beim Analysieren selbst aus. }
  SHOWN_FIELDS: TMp4TagFields =
    [tfTitle, tfArtist, tfAlbum, tfGenre, tfYear, tfLabel, tfComment];

  BPM_MIN = 20;
  BPM_MAX = 300;

{ Auswahl aus der Tonart-Liste: nur den Teil vor der Klammer übernehmen }
function CleanKey(const V: string): string;
var
  P: Integer;
begin
  Result := V;
  P := Pos('(', Result);
  if P > 0 then
    Result := Trim(Copy(Result, 1, P - 1));
end;

{ leer oder ganze Zahl von BPM_MIN bis BPM_MAX }
function BpmValid(const V: string): Boolean;
var
  N: Integer;
begin
  if V = '' then Exit(True);
  Result := TryStrToInt(V, N) and (N >= BPM_MIN) and (N <= BPM_MAX)
    and (Pos('-', V) = 0) and (Pos('+', V) = 0);
end;

constructor TMainForm.Create(TheOwner: TComponent);
var
  I: Integer;
begin
  inherited CreateNew(TheOwner);
  { gleich auf die Bildschirm-DPI: BuildUI rechnet alles mit Scale96ToForm }
  StelleAufBildschirmDPI(Self);
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
  ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TDJButton;
begin
  Result := TDJButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(Scale96ToForm(ALeft), Scale96ToForm(ATop),
    Scale96ToForm(AWidth), Scale96ToForm(26));
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

{ Fenster im dunklen Stil des StemPlayers (Farben und Knöpfe aus djcontrols.pas),
  damit alle AddOns zusammenpassen. Die Listen-Überschrift ist selbst gebaut,
  weil Windows die echte Kopfzeile immer hell zeichnet. }
procedure TMainForm.BuildUI;
const
  { Reihenfolge der Felder: erste Hälfte links, Rest rechts.
    Angezeigt werden nur die Felder in SHOWN_FIELDS. }
  FIELD_ORDER: array[0..10] of TMp4TagField =
    (tfTitle, tfArtist, tfAlbum, tfGenre, tfYear, tfLabel, tfComment,
     tfAlbumArtist, tfTrack, tfBpm, tfKey);
  ROW_H = 28;
  { Spalten der Liste: Überschrift und Breite (96 dpi) }
  COL_W: array[0..7] of Integer = (190, 130, 115, 95, 85, 50, 60, 140);
var
  Shown: array of TMp4TagField;
  Half: Integer;
  Cb: TDJCombo;
  Box: TDJPanel;
  RowImg: TImageList;   // leere Bildliste, nur für die Zeilenhöhe   // dunkler Rahmen um ein Eingabefeld
  PnlTop, Foot, SaveBox: TPanel;
  PnlEdit, Fields, CoverPanel, Frame, PnlHead, PnlList: TDJPanel;
  Col: TListColumn;
  Lbl: TLabel;
  F: TMp4TagField;
  I, X: Integer;
  ColCaps: array[0..7] of string;

  procedure AddField(AField: TMp4TagField; AX, AY: Integer);
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := Fields;
    Lbl.SetBounds(Scale96ToForm(AX), Scale96ToForm(AY + 5), Scale96ToForm(80), Scale96ToForm(20));
    Lbl.Caption := FieldCaption(AField);
    Lbl.Font.Color := DJ_DIM;
    FLabels[AField] := Lbl;
    if AX > 4 then FFieldCol[AField] := 1 else FFieldCol[AField] := 0;
    if AField in [tfGenre, tfKey] then
    begin
      { Auswahlliste, aber auch freie Eingabe }
      Cb := TDJCombo.Create(Self);
      Cb.OnSelect := @ComboSelect;
      FEdits[AField] := Cb;
    end
    else
    begin
      { Eingabefeld ohne eigenen Rahmen in einem dunklen Rahmen: der
        Windows-Rahmen wäre auf dunklem Grund hell und grell }
      Box := TDJPanel.Create(Self);
      Box.Parent := Fields;
      Box.SetBounds(Scale96ToForm(AX + 82), Scale96ToForm(AY),
        Scale96ToForm(196), Scale96ToForm(24));
      Box.Color := DJ_BG;
      Box.BorderColor := DJ_BORDER;
      FEdits[AField] := TEdit.Create(Self);
      TEdit(FEdits[AField]).BorderStyle := bsNone;
    end;
    if FEdits[AField] is TDJCombo then
    begin
      FEdits[AField].Parent := Fields;
      FEdits[AField].SetBounds(Scale96ToForm(AX + 82), Scale96ToForm(AY),
        Scale96ToForm(196), Scale96ToForm(24));
    end
    else
    begin
      FEdits[AField].Parent := Box;
      FEdits[AField].SetBounds(Scale96ToForm(6), Scale96ToForm(4),
        Box.Width - Scale96ToForm(12), Box.Height - Scale96ToForm(8));
    end;
    FEdits[AField].Tag := Ord(AField);
    FEdits[AField].Color := DJ_BG;
    FEdits[AField].Font.Color := DJ_TEXT;
    if FEdits[AField] is TDJCombo then
      TDJCombo(FEdits[AField]).OnChange := @FieldChange
    else
      TEdit(FEdits[AField]).OnChange := @FieldChange;
    FEdits[AField].ShowHint := True;
    Lbl.ShowHint := True;
    if FEdits[AField] is TDJCombo then
      Lbl.FocusControl := TDJCombo(FEdits[AField]).Edit
    else
      Lbl.FocusControl := FEdits[AField];
  end;

  { Schalter in der Fusszeile: Breite passend zum (übersetzten) Text, rechts angedockt }
  procedure FitToggle(B: TDJLedSwitch);
  begin
    B.Width := B.NeededWidth;
    B.Align := alRight;
    B.BorderSpacing.Right := Scale96ToForm(14);
    B.BorderSpacing.Top := Scale96ToForm(5);
    B.BorderSpacing.Bottom := Scale96ToForm(5);
  end;

  function MakeArea(AParent: TWinControl): TDJPanel;
  begin
    Result := TDJPanel.Create(Self);
    Result.Parent := AParent;
    Result.BorderColor := clNone;
  end;

begin
  Caption := APP_TITLE + ' ' + APP_VER;
  Position := poScreenCenter;
  Width := Scale96ToForm(920);         // bei 150 % passt die Fusszeile sonst knapp nicht
  Height := Scale96ToForm(540);
  Constraints.MinWidth := Scale96ToForm(880);  // schmaler ragen Jahr/Label/Kommentar und der Namens-Knopf rechts hinaus (Live-Test 30.10.)
  Constraints.MinHeight := Scale96ToForm(420);
  Color := DJ_BG;
  Font.Color := DJ_TEXT;
  KeyPreview := True;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  OnKeyDown := @FormKeyDown;
  OnCloseQuery := @FormCloseQuery;

  { --- oben: Dateien links, Speichern rechts ------------------------------ }
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := Scale96ToForm(40);
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := DJ_BG;
  PnlTop.ParentBackground := False;
  FBtnAdd    := MakeButton(PnlTop, _('Dateien...'), 8, 7, 100, @BtnAddClick);
  FBtnFolder := MakeButton(PnlTop, _('Ordner...'), 112, 7, 100, @BtnFolderClick);
  FBtnRemove := MakeButton(PnlTop, _('Entfernen'), 216, 7, 100, @BtnRemoveClick);
  FBtnClear  := MakeButton(PnlTop, _('Liste leeren'), 320, 7, 100, @BtnClearClick);
  SaveBox := TPanel.Create(Self);
  SaveBox.Parent := PnlTop;
  SaveBox.Align := alRight;
  SaveBox.Width := Scale96ToForm(300);
  SaveBox.BevelOuter := bvNone;
  SaveBox.Color := DJ_BG;
  SaveBox.ParentBackground := False;
  FBtnRevert := MakeButton(SaveBox, _('Änderungen verwerfen'), 0, 7, 170, @BtnRevertClick);
  FBtnSave   := MakeButton(SaveBox, _('Speichern'), 174, 7, 118, @BtnSaveClick);
  { leuchtet grün, sobald es etwas zu speichern gibt (siehe UpdateStatusBar) }
  FBtnSave.LitColor := DJ_GREEN;

  { --- Fusszeile: Statuszeile, die zwei Schalter, rechts der Ko-fi-Knopf --- }
  Foot := TPanel.Create(Self);
  Foot.Parent := Self;
  Foot.Align := alBottom;
  Foot.Height := Scale96ToForm(32);
  Foot.BevelOuter := bvNone;
  Foot.Color := DJ_FOOTER;
  Foot.ParentBackground := False;
  FKofi := TPaintBox.Create(Self);
  FKofi.Parent := Foot;
  FKofi.Align := alRight;
  FKofi.BorderSpacing.Right := Scale96ToForm(8);
  FKofi.Canvas.Font.Style := [fsBold];
  FKofi.Width := KofiButtonWidth(FKofi.Canvas, _('Kaffee spendieren'), Screen.PixelsPerInch);
  FKofi.Cursor := crHandPoint;
  FKofi.Hint := 'ko-fi.com/elospeed';
  FKofi.ShowHint := True;
  FKofi.OnPaint := @KofiPaint;
  FKofi.OnClick := @KofiClick;
  FKofi.OnMouseEnter := @KofiEnter;
  FKofi.OnMouseLeave := @KofiLeave;

  { zwei Schalter mit LED davor: rot = aus, grün = an }
  FChkBackup := TDJLedSwitch.Create(Self);
  FChkBackup.Parent := Foot;
  FChkBackup.Caption := _('Sicherungskopie anlegen (.bak)');
  FChkBackup.Hint := _('Legt vor dem ersten Speichern eine Kopie der Originaldatei an (Name.stem.mp4.bak).') +
    LineEnding + _('Die Kopie wird nie überschrieben, sie bleibt also das echte Original.');
  FChkBackup.ShowHint := True;
  FChkShrink := TDJLedSwitch.Create(Self);
  FChkShrink.Parent := Foot;
  FChkShrink.Caption := Format(_('Grosse Cover auf %d px verkleinern'), [COVER_MAX_SIDE]);
  FChkShrink.Down := True;
  FitToggle(FChkBackup);
  FitToggle(FChkShrink);
  { Reihenfolge bei alRight: wer weiter links stehen soll, bekommt das kleinere
    Left (Ko-fi ganz rechts, davor die Schalter) }
  FChkBackup.Left := 1000;
  FChkShrink.Left := 2000;
  FKofi.Left := 3000;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Foot;
  FStatus.Align := alClient;
  FStatus.Layout := tlCenter;
  FStatus.BorderSpacing.Left := Scale96ToForm(10);
  FStatus.Font.Color := DJ_DIM;

  { --- Bearbeiten-Bereich ------------------------------------------------- }
  PnlEdit := MakeArea(Self);
  PnlEdit.Align := alBottom;
  PnlEdit.Height := Scale96ToForm(140);
  PnlEdit.BorderColor := DJ_BORDER;

  CoverPanel := MakeArea(PnlEdit);
  CoverPanel.Align := alLeft;
  CoverPanel.Width := Scale96ToForm(236);
  CoverPanel.BorderSpacing.Around := 1;

  Frame := MakeArea(CoverPanel);
  Frame.SetBounds(Scale96ToForm(8), Scale96ToForm(7), Scale96ToForm(108), Scale96ToForm(108));
  Frame.Color := DJ_BG;
  Frame.BorderColor := DJ_BORDER;
  FCoverImg := TImage.Create(Self);
  FCoverImg.Parent := Frame;
  FCoverImg.Align := alClient;
  FCoverImg.BorderSpacing.Around := 1;
  FCoverImg.Stretch := True;
  FCoverImg.Proportional := True;
  FCoverImg.Center := True;

  FCoverInfo := TLabel.Create(Self);
  FCoverInfo.Parent := CoverPanel;
  FCoverInfo.SetBounds(Scale96ToForm(8), Scale96ToForm(118), Scale96ToForm(224), Scale96ToForm(18));
  FCoverInfo.Font.Color := DJ_DIM;

  { die vier Cover-Knöpfe senkrecht neben dem Bild }
  FBtnCoverLoad  := MakeButton(CoverPanel, _('Bild...'), 122, 7, 106, @BtnCoverLoadClick);
  FBtnCoverPaste := MakeButton(CoverPanel, _('Einfügen'), 122, 34, 106, @BtnCoverPasteClick);
  FBtnCoverDel   := MakeButton(CoverPanel, _('Entfernen'), 122, 61, 106, @BtnCoverDelClick);
  FBtnCoverSave  := MakeButton(CoverPanel, _('Speichern...'), 122, 88, 106, @BtnCoverSaveClick);
  FBtnCoverPaste.Hint := _('Bild aus der Zwischenablage einfügen (Strg+V)');
  FBtnCoverPaste.ShowHint := True;

  Fields := MakeArea(PnlEdit);
  Fields.Align := alClient;
  Fields.BorderSpacing.Around := 1;
  for F := Low(TMp4TagField) to High(TMp4TagField) do
  begin
    FEdits[F] := nil;
    FLabels[F] := nil;
  end;
  Shown := nil;
  for I := Low(FIELD_ORDER) to High(FIELD_ORDER) do
    if FIELD_ORDER[I] in SHOWN_FIELDS then
    begin
      SetLength(Shown, Length(Shown) + 1);
      Shown[High(Shown)] := FIELD_ORDER[I];
    end;
  Half := (Length(Shown) + 1) div 2;
  for I := 0 to High(Shown) do
    if I < Half then
      AddField(Shown[I], 4, 7 + I * ROW_H)
    else
      AddField(Shown[I], 296, 7 + (I - Half) * ROW_H);
  if FEdits[tfGenre] <> nil then
  begin
    TDJCombo(FEdits[tfGenre]).AutoComplete := True;   // "Tech H" ergänzt zu "Tech House"
    for I := Low(GENRES) to High(GENRES) do
      TDJCombo(FEdits[tfGenre]).Items.Add(GENRES[I]);
  end;
  if FEdits[tfKey] <> nil then
    for I := Low(KEYS) to High(KEYS) do
      TDJCombo(FEdits[tfKey]).Items.Add(KEYS[I]);
  if FEdits[tfBpm] <> nil then
  begin
    TEdit(FEdits[tfBpm]).NumbersOnly := True;
    TEdit(FEdits[tfBpm]).MaxLength := 3;
  end;
  if FEdits[tfYear] <> nil then
    TEdit(FEdits[tfYear]).MaxLength := 10;

  { Tooltips: was gehört in welches Feld }
  SetFieldHint(tfTitle, _('Name des Tracks, z.B. „Clap Your Hands“'));
  SetFieldHint(tfArtist, _('Künstler oder Band, z.B. „Kungs“'));
  SetFieldHint(tfAlbum, _('Album, EP oder Single, auf der der Track erschienen ist'));
  SetFieldHint(tfAlbumArtist, _('Interpret des ganzen Albums, z.B. „Various Artists“ bei Compilations.') +
    LineEnding + _('Leer lassen, wenn er gleich ist wie der Interpret.'));
  SetFieldHint(tfGenre, _('Musikstil: aus der Liste wählen oder selbst eintippen'));
  SetFieldHint(tfYear, _('Erscheinungsjahr, z.B. 2016'));
  SetFieldHint(tfTrack, _('Nummer auf dem Album, z.B. 3 oder 3/12 (Track 3 von 12)'));
  SetFieldHint(tfBpm, Format(_('Tempo in Schlägen pro Minute, nur ganze Zahlen von %d bis %d, z.B. 128.'),
    [BPM_MIN, BPM_MAX]) + LineEnding +
    _('Traktor misst das Tempo beim Analysieren ohnehin selbst.'));
  SetFieldHint(tfKey, _('Tonart des Tracks: aus der Liste wählen oder selbst eintippen.') + LineEnding +
    LineEnding +
    _('Es gibt drei übliche Schreibweisen für dieselbe Tonart:') + LineEnding +
    _('  Klassisch:  Am = a-Moll, C = C-Dur (m = Moll, ohne m = Dur)') + LineEnding +
    _('  Camelot (Mixed In Key):  8A = a-Moll, 8B = C-Dur (A = Moll, B = Dur)') + LineEnding +
    _('  Open Key (Traktor):  1m = a-Moll, 1d = C-Dur (m = Moll, d = Dur)') + LineEnding +
    LineEnding +
    _('Die Liste zeigt alle drei, gespeichert wird die klassische (z.B. Am).') + LineEnding +
    _('Benachbarte Zahlen passen beim Mixen gut zusammen (z.B. 8A zu 7A, 9A und 8B).'));
  SetFieldHint(tfLabel, _('Plattenfirma, die den Track veröffentlicht hat'));
  SetFieldHint(tfComment, _('Freier Text, z.B. Notizen fürs Auflegen'));
  FBtnFromName := MakeButton(Fields, _('Interpret/Titel aus Dateiname'),
    378, 7 + (Length(Shown) - Half) * ROW_H, 196, @BtnFromNameClick);
  FBtnFromName.Height := Scale96ToForm(24);
  FBtnFromName.Hint := _('"Interpret - Titel.stem.mp4" füllt Interpret und Titel');
  FBtnFromName.ShowHint := True;
  { Felder beim Vergrössern des Fensters mitziehen (siehe FieldsResize) }
  FFields := Fields;
  Fields.OnResize := @FieldsResize;

  { Reihenfolge unten festlegen (bei gleicher Ausrichtung entscheidet Top):
    Bearbeiten-Bereich, ganz unten die Fusszeile }
  PnlEdit.Top := 0;
  Foot.Top := PnlEdit.Top + PnlEdit.Height;

  { --- Liste mit eigener Kopfzeile (füllt den Rest) ----------------------- }
  PnlList := MakeArea(Self);
  PnlList.Align := alClient;
  PnlList.BorderColor := DJ_BORDER;
  PnlList.BorderSpacing.Bottom := Scale96ToForm(6);

  ColCaps[0] := _('Datei');  ColCaps[1] := _('Titel'); ColCaps[2] := _('Interpret');
  ColCaps[3] := _('Album');  ColCaps[4] := _('Genre'); ColCaps[5] := _('Cover');
  ColCaps[6] := _('Traktor');  ColCaps[7] := _('Status');
  PnlHead := MakeArea(PnlList);
  PnlHead.Align := alTop;
  PnlHead.Height := Scale96ToForm(24);
  PnlHead.BorderSpacing.Around := 1;
  PnlHead.Color := DJ_BTN;
  for I := 0 to High(COL_W) do
    FColW[I] := Scale96ToForm(COL_W[I]);
  FDragCol := -1;
  FHead := TPaintBox.Create(Self);
  FHead.Parent := PnlHead;
  FHead.Align := alClient;
  FHead.Font.Style := [fsBold];
  FHead.Font.Size := 8;
  FHead.Hint := _('Klick sortiert, nochmal klicken sortiert umgekehrt') + LineEnding +
    _('Rand zwischen zwei Spalten ziehen ändert die Breite') + LineEnding +
    _('Doppelklick auf den Rand passt die Spalte an den Text an');
  FHead.ShowHint := True;
  FHead.OnPaint := @HeadPaint;
  FHead.OnMouseDown := @HeadMouseDown;
  FHead.OnMouseMove := @HeadMouseMove;
  FHead.OnMouseUp := @HeadMouseUp;
  FList := TListView.Create(Self);
  FList.Parent := PnlList;
  FList.Align := alClient;
  FList.BorderSpacing.Around := 1;
  FList.BorderStyle := bsNone;
  FList.ViewStyle := vsReport;
  FList.ShowColumnHeaders := False;
  FList.Color := DJ_PANEL;
  FList.Font.Color := DJ_TEXT;
  FList.MultiSelect := True;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.OnSelectItem := @ListSelectItem;
  FList.OnKeyDown := @ListKeyDown;
  FList.OnColumnClick := @ListColumnClick;
  FList.OnCustomDrawItem := @ListDrawItem;
  { höhere Zeilen: Windows richtet die Zeilenhöhe nach der Bildliste }
  RowImg := TImageList.Create(Self);
  RowImg.Width := 1;
  RowImg.Height := Scale96ToForm(22);
  FList.SmallImages := RowImg;
  FList.OnResize := @ListResize;
  FSortCol := -1;
  for I := 0 to High(COL_W) do
  begin
    Col := FList.Columns.Add;
    Col.Caption := ColCaps[I];
    Col.Width := Scale96ToForm(COL_W[I]);
  end;
end;

{ ---------- eigene Kopfzeile der Liste ----------------------------------- }

{ Spaltenbreiten an die Liste anpassen: die letzte Spalte (Status) füllt
  den Rest, so gibt es nie einen waagrechten Rollbalken und die Kopfzeile
  passt immer genau über die Spalten }
procedure TMainForm.FitColumns;
var
  I, Sum, Avail: Integer;
begin
  if (FList = nil) or (FList.Columns.Count <= High(FColW)) then Exit;
  Avail := FList.ClientWidth - 2;
  { Liste breiter oder schmaler geworden: alle Spalten anteilig mitziehen }
  { (erst wenn das Fenster sichtbar ist: beim Aufbau ist die Liste kurz winzig) }
  if not Showing then
    FLastAvail := 0
  else
  begin
    { erstes Mal sichtbar: bisherige Gesamtbreite der Spalten als Bezug }
    if FLastAvail = 0 then
      for I := 0 to High(FColW) do
        Inc(FLastAvail, FColW[I]);
    if (FLastAvail > 0) and (Avail <> FLastAvail) and (FDragCol < 0) then
      for I := 0 to High(FColW) - 1 do
      begin
        FColW[I] := MulDiv(FColW[I], Avail, FLastAvail);
        if FColW[I] < Scale96ToForm(40) then FColW[I] := Scale96ToForm(40);
      end;
    FLastAvail := Avail;
  end;
  Sum := 0;
  for I := 0 to High(FColW) - 1 do
    Inc(Sum, FColW[I]);
  { passt nicht (sehr schmales Fenster): alle Spalten verkleinern, damit
    Status sichtbar bleibt und kein waagrechter Rollbalken entsteht }
  if (Sum > Avail - Scale96ToForm(60)) and (Sum > 0) and (Avail > Scale96ToForm(300)) then
  begin
    for I := 0 to High(FColW) - 1 do
      FColW[I] := Max(Scale96ToForm(30), MulDiv(FColW[I], Avail - Scale96ToForm(60), Sum));
    Sum := 0;
    for I := 0 to High(FColW) - 1 do
      Inc(Sum, FColW[I]);
  end;
  { die schmalen Spalten Cover und Traktor nie schmaler als ihre Überschrift
    (bei 150 % und 200 % war "TRAKTOR" sonst abgeschnitten, Test 30.10.) }
  for I := 5 to 6 do
    if FColW[I] < HeadTextWidth(I) then
    begin
      Inc(Sum, HeadTextWidth(I) - FColW[I]);
      FColW[I] := HeadTextWidth(I);
    end;
  FColW[High(FColW)] := Avail - Sum;
  if FColW[High(FColW)] < Scale96ToForm(60) then
    FColW[High(FColW)] := Scale96ToForm(60);
  FList.BeginUpdate;
  try
    for I := 0 to High(FColW) do
      if FList.Columns[I].Width <> FColW[I] then
        FList.Columns[I].Width := FColW[I];
  finally
    FList.EndUpdate;
  end;
  if FHead <> nil then FHead.Invalidate;
end;

{ Platz, den die Überschrift einer Spalte braucht (Text in Grossbuchstaben,
  fett, dazu Abstand und Platz für den Sortierpfeil, wie in HeadPaint) }
function TMainForm.HeadTextWidth(Col: Integer): Integer;
begin
  Result := 0;
  if (FHead = nil) or (FList = nil) or (Col >= FList.Columns.Count) then Exit;
  FHead.Canvas.Font := FHead.Font;
  Result := FHead.Canvas.TextWidth(UTF8UpperCase(FList.Columns[Col].Caption)) + Scale96ToForm(22);
end;

{ Eingabefelder auf die Breite des Bereichs verteilen: zwei gleich breite
  Spalten (Beschriftung + Feld), die Felder wachsen mit dem Fenster }
procedure TMainForm.FieldsResize(Sender: TObject);
var
  F: TMp4TagField;
  ColW, EdW, X: Integer;   // Breite einer Spalte, Breite eines Felds, linker Rand
  C: TControl;             // Feld (Auswahlliste) bzw. dunkler Rahmen um das Eingabefeld
begin
  if FFields = nil then Exit;
  ColW := Max(Scale96ToForm(292), (FFields.ClientWidth - Scale96ToForm(8)) div 2);
  EdW := ColW - Scale96ToForm(96);
  for F := Low(TMp4TagField) to High(TMp4TagField) do
  begin
    if (FLabels[F] = nil) or (FEdits[F] = nil) then Continue;
    X := Scale96ToForm(4) + FFieldCol[F] * ColW;
    FLabels[F].Left := X;
    if FEdits[F] is TDJCombo then
      C := FEdits[F]
    else
      C := FEdits[F].Parent;
    C.SetBounds(X + Scale96ToForm(82), C.Top, EdW, C.Height);
    if C <> FEdits[F] then
      FEdits[F].Width := C.Width - Scale96ToForm(12);
  end;
  if FBtnFromName <> nil then
    FBtnFromName.SetBounds(Scale96ToForm(4) + ColW + Scale96ToForm(82), FBtnFromName.Top,
      EdW, FBtnFromName.Height);
end;

procedure TMainForm.ListResize(Sender: TObject);
begin
  FitColumns;
end;

{ Spalte so breit machen, dass der längste Text ganz sichtbar ist
  (Doppelklick auf den Trennstrich, wie im Windows-Explorer) }
procedure TMainForm.AutoFitColumn(Col: Integer);
var
  I, W, Others, MaxW: Integer;
  S: string;
begin
  FHead.Canvas.Font := FHead.Font;
  W := FHead.Canvas.TextWidth(UTF8UpperCase(FList.Columns[Col].Caption)) + Scale96ToForm(20);
  FList.Canvas.Font := FList.Font;
  for I := 0 to FList.Items.Count - 1 do
  begin
    if Col = 0 then S := FList.Items[I].Caption
    else if Col - 1 < FList.Items[I].SubItems.Count then S := FList.Items[I].SubItems[Col - 1]
    else S := '';
    if FList.Canvas.TextWidth(S) + Scale96ToForm(14) > W then
      W := FList.Canvas.TextWidth(S) + Scale96ToForm(14);
  end;
  { die letzte Spalte (Status) behält mindestens 60 px }
  Others := 0;
  for I := 0 to High(FColW) - 1 do
    if I <> Col then Inc(Others, FColW[I]);
  MaxW := FList.ClientWidth - 2 - Others - Scale96ToForm(60);
  if W > MaxW then W := MaxW;
  if W < Scale96ToForm(40) then W := Scale96ToForm(40);
  FColW[Col] := W;
  FitColumns;
end;

{ Index der Spalte, deren rechter Rand bei X liegt (±4 px), sonst -1.
  Der Rand der letzten Spalte lässt sich nicht ziehen (sie füllt den Rest). }
function TMainForm.HeadDivider(X: Integer): Integer;
var
  I, Edge: Integer;
begin
  Result := -1;
  Edge := 0;
  for I := 0 to High(FColW) - 1 do
  begin
    Inc(Edge, FColW[I]);
    if Abs(X - Edge) <= Scale96ToForm(4) then Exit(I);
  end;
end;

procedure TMainForm.HeadPaint(Sender: TObject);
var
  I, X, TH, TX, CX, CY, D: Integer;
  S: string;
begin
  with FHead.Canvas do
  begin
    Brush.Color := DJ_BTN;
    FillRect(FHead.ClientRect);
    Font := FHead.Font;
    TH := TextHeight('Ag');
    X := 0;
    for I := 0 to High(FColW) do
    begin
      S := UTF8UpperCase(FList.Columns[I].Caption);
      if I = FSortCol then Font.Color := DJ_TEXT else Font.Color := DJ_DIM;
      TX := X + Scale96ToForm(6);
      { Text abschneiden, damit er nicht in die nächste Spalte ragt }
      if I = FSortCol then
        ClipRect := Rect(X, 0, X + FColW[I] - Scale96ToForm(14), FHead.Height)
      else
        ClipRect := Rect(X, 0, X + FColW[I] - Scale96ToForm(3), FHead.Height);
      Clipping := True;
      Brush.Style := bsClear;
      TextOut(TX, (FHead.Height - TH) div 2, S);
      Brush.Style := bsSolid;
      Clipping := False;
      { kleiner Pfeil für die Sortierrichtung }
      if I = FSortCol then
      begin
        CX := TX + TextWidth(S) + Scale96ToForm(8);
        if CX > X + FColW[I] - Scale96ToForm(8) then
          CX := X + FColW[I] - Scale96ToForm(8);
        CY := FHead.Height div 2;
        D := Scale96ToForm(3);
        Brush.Color := DJ_GREEN;
        Pen.Color := DJ_GREEN;
        if FSortDesc then
          Polygon([Point(CX - D, CY - D div 2), Point(CX + D, CY - D div 2), Point(CX, CY + D)])
        else
          Polygon([Point(CX - D, CY + D div 2), Point(CX + D, CY + D div 2), Point(CX, CY - D)]);
        Brush.Color := DJ_BTN;
      end;
      Inc(X, FColW[I]);
      { Trennstrich zwischen den Spalten (dort kann man ziehen) }
      if I < High(FColW) then
      begin
        if I = FDragCol then Pen.Color := DJ_GREEN else Pen.Color := DJ_BTNBORDER;
        MoveTo(X - 1, Scale96ToForm(4));
        LineTo(X - 1, FHead.Height - Scale96ToForm(4));
      end;
    end;
  end;
end;

procedure TMainForm.HeadMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  FDragged := False;
  FDragCol := HeadDivider(X);
  { Doppelklick auf den Trennstrich: Spalte an den Text anpassen }
  if (ssDouble in Shift) and (FDragCol >= 0) then
  begin
    AutoFitColumn(FDragCol);
    FDragged := True;   // beim Loslassen nicht sortieren
    Exit;
  end;
  if FDragCol >= 0 then
  begin
    FDragX0 := X;
    FDragW0 := FColW[FDragCol];
    FHead.Invalidate;
  end;
end;

procedure TMainForm.HeadMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  I, W, Others, MaxW: Integer;
begin
  if FDragCol < 0 then
  begin
    { Mauszeiger zeigt, wo man ziehen kann }
    if HeadDivider(X) >= 0 then FHead.Cursor := crHSplit
    else FHead.Cursor := crHandPoint;
    Exit;
  end;
  { Breite ändern: mindestens 40 px, und die letzte Spalte behält 60 px }
  Others := 0;
  for I := 0 to High(FColW) - 1 do
    if I <> FDragCol then Inc(Others, FColW[I]);
  MaxW := FList.ClientWidth - 2 - Others - Scale96ToForm(60);
  W := FDragW0 + X - FDragX0;
  if W > MaxW then W := MaxW;
  if W < Scale96ToForm(40) then W := Scale96ToForm(40);
  if W <> FColW[FDragCol] then
  begin
    FColW[FDragCol] := W;
    FDragged := True;
    FitColumns;
  end;
end;

procedure TMainForm.HeadMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I, Edge: Integer;
begin
  if Button <> mbLeft then Exit;
  if FDragCol >= 0 then
  begin
    { Klick auf einen Trennstrich sortiert nie (er gehört zum Ziehen) }
    FDragCol := -1;
    FHead.Invalidate;
    Exit;
  end;
  { einfacher Klick: nach dieser Spalte sortieren }
  Edge := 0;
  for I := 0 to High(FColW) do
  begin
    Inc(Edge, FColW[I]);
    if (X < Edge) or (I = High(FColW)) then
    begin
      ListColumnClick(FList, FList.Columns[I]);
      FHead.Invalidate;
      Exit;
    end;
  end;
end;

{ Zeilen ganz selbst zeichnen: Windows würde markierte Zeilen hell bzw.
  blau hinterlegen, das passt nicht zum dunklen Fenster.
  Markiert = etwas hellere Fläche mit grünem Streifen links (wie die Genre-
  Liste). Status farbig: grün = fertig, gelb = geändert, orange = es fehlt etwas. }
procedure TMainForm.ListDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  E: TTagEntry;
  R, CR: TRect;
  I, X: Integer;
  S: string;
  TS: TTextStyle;
  StatusCol: TColor;
begin
  DefaultDraw := False;
  R := Item.DisplayRect(drBounds);
  R.Left := 0;
  R.Right := Sender.ClientWidth;
  with Sender.Canvas do
  begin
    if Item.Selected then Brush.Color := DJ_BTNBORDER else Brush.Color := DJ_PANEL;
    FillRect(R);
    if Item.Selected then
    begin
      Brush.Color := DJ_GREEN;
      FillRect(Rect(R.Left, R.Top, R.Left + Scale96ToForm(3), R.Bottom));
    end;

    { Farbe der Spalte Status }
    StatusCol := DJ_TEXT;
    E := TTagEntry(Item.Data);
    if E <> nil then
    begin
      if E.Dirty <> [] then
        StatusCol := DJ_YELLOW
      else if E.Status <> '' then
        StatusCol := DJ_TEXT
      else if (Length(E.Cur.Cover) = 0) or
              ((E.Cur.Text[tfTitle] = '') and (E.Cur.Text[tfArtist] = '')) then
        StatusCol := DJ_KOFI   // orange
      else
        StatusCol := DJ_GREEN;
    end;

    TS := TextStyle;
    TS.SingleLine := True;
    TS.Layout := tlCenter;
    TS.Opaque := False;
    TS.Clipping := True;
    Brush.Style := bsClear;
    X := 0;
    for I := 0 to FList.Columns.Count - 1 do
    begin
      if I = 0 then S := Item.Caption
      else if I - 1 < Item.SubItems.Count then S := Item.SubItems[I - 1]
      else S := '';
      if I = FList.Columns.Count - 1 then Font.Color := StatusCol
      else if Item.Selected then Font.Color := clWhite
      else Font.Color := DJ_TEXT;
      CR := Rect(X + Scale96ToForm(6), R.Top, X + FList.Columns[I].Width - Scale96ToForm(4), R.Bottom);
      { zu langen Text kürzen und mit "…" enden lassen }
      if TextWidth(S) > CR.Right - CR.Left then
      begin
        while (S <> '') and (TextWidth(S + '…') > CR.Right - CR.Left) do
          UTF8Delete(S, UTF8Length(S), 1);
        S := S + '…';
      end;
      TextRect(CR, CR.Left, CR.Top, S, TS);
      Inc(X, FList.Columns[I].Width);
    end;
    Brush.Style := bsSolid;
  end;
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
  Parts: TStringList;   // Spaltenbreiten aus der INI
  I, W: Integer;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      FChkBackup.Down := Ini.ReadBool('Optionen', 'SicherungAnlegen', False);
      FFolderHint := Ini.ReadBool('Optionen', 'OrdnerHinweis', True);
      FChkShrink.Down := Ini.ReadBool('Optionen', 'CoverVerkleinern', True);
      FLastDir := Ini.ReadString('Optionen', 'LetzterOrdner', '');
      { Spaltenbreiten (bei 96 dpi), z.B. "190,130,115,95,85,50,60";
        bis 1.0.1 waren es 6 Werte (ohne Spalte Traktor), die gelten weiter }
      Parts := TStringList.Create;
      try
        Parts.CommaText := Ini.ReadString('Ansicht', 'Spalten', '');
        if (Parts.Count = High(FColW)) or (Parts.Count = High(FColW) - 1) then
          for I := 0 to Parts.Count - 1 do
          begin
            W := StrToIntDef(Parts[I], 0);
            if (W >= 40) and (W <= 1000) then
              FColW[I] := Scale96ToForm(W);
          end;
      finally
        Parts.Free;
      end;
    finally
      Ini.Free;
    end;
  except
    { INI nicht lesbar -> Standardwerte }
  end;
  FitColumns;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
  S: string;     // Spaltenbreiten bei 96 dpi, mit Komma getrennt
  I: Integer;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Ini.WriteBool('Optionen', 'SicherungAnlegen', FChkBackup.Down);
      Ini.WriteBool('Optionen', 'OrdnerHinweis', FFolderHint);
      Ini.WriteBool('Optionen', 'CoverVerkleinern', FChkShrink.Down);
      Ini.WriteString('Optionen', 'LetzterOrdner', FLastDir);
      S := '';
      for I := 0 to High(FColW) - 1 do
      begin
        if S <> '' then S := S + ',';
        S := S + IntToStr(MulDiv(FColW[I], 96, PixelsPerInch));
      end;
      Ini.WriteString('Ansicht', 'Spalten', S);
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
    Files := FindAllFiles(Path, '*.stem.mp4;*.stem.m4a;*.mp3', True);
    try
      Files.Sort;
      FList.Items.BeginUpdate;
      try
        for I := 0 to Files.Count - 1 do
          AddFile(Files[I]);
      finally
        FList.Items.EndUpdate;
      end;
      { Hinweis erst zeigen, wenn alles geladen ist (auch bei mehreren Ordnern nur einmal) }
      if FFolderHint and (Files.Count > 0) and not FFolderHintPending then
      begin
        FFolderHintPending := True;
        Application.QueueAsyncCall(@ShowFolderHint, 0);
      end
      else if Files.Count = 0 then
        MessageDlg(Format(_('Im Ordner wurden keine Stem- oder MP3-Dateien gefunden:%s%s'), [LineEnding, Path]),
          mtInformation, [mbOK], 0);
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
  E.IsMp3 := IsMp3File(FileName);
  try
    if E.IsMp3 then
    begin
      if not ReadMp3Tags(FileName, E.Orig, E.Mp3, Err) then
      begin
        E.Status := _('Nicht lesbar');
        Log('Nicht lesbar: ' + FileName + ' (' + Err + ')');
      end
      else if not E.Mp3.CanWrite then
      begin
        { ID3v2.2 oder beschädigter Block: nur anzeigen, nie schreiben }
        E.Status := _('Nur lesen (alter oder beschädigter ID3-Tag)');
        Log('Nur lesen: ' + FileName + ' (' + E.Mp3.Problem + ')');
      end
      else
        E.CanEdit := True;
    end
    else
    begin
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
      E.CanEdit := E.IsStem;
    end;
  except
    on Ex: Exception do
    begin
      E.IsStem := False;
      E.CanEdit := False;
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
  Item.SubItems.Add(E.Cur.Text[tfGenre]);
  if Length(E.Cur.Cover) > 0 then
    Item.SubItems.Add(_('ja'))
  else
    Item.SubItems.Add('-');
  { Spalte Traktor: hat Traktor schon Cue-Punkte, Beatgrid usw. in die MP3
    geschrieben? Bei Stem-Dateien bleibt sie leer (dort nicht geprüft). }
  if E.IsMp3 and E.Mp3.HasTraktor then
    Item.SubItems.Add(_('ja'))
  else if E.IsMp3 then
    Item.SubItems.Add('-')
  else
    Item.SubItems.Add('');
  if E.Dirty <> [] then
    St := '* ' + _('geändert')
  else if E.Status <> '' then
    St := E.Status
  else if (E.Cur.Text[tfTitle] = '') and (E.Cur.Text[tfArtist] = '') then
  begin
    { auf einen Blick sehen, wo noch etwas fehlt }
    if Length(E.Cur.Cover) = 0 then
      St := _('Ohne Tags und Cover')
    else
      St := _('Ohne Tags');
  end
  else if Length(E.Cur.Cover) = 0 then
    St := _('Ohne Cover')
  else if E.IsMp3 and E.Mp3.HasTraktor then
    St := _('MP3 OK, mit Traktor-Daten')
  else if E.IsMp3 then
    St := _('MP3 OK')
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
  if FEntries.Count = 0 then
    FStatus.Caption := _('Stem-Dateien, MP3s oder Ordner hierher ziehen')
  else
    FStatus.Caption := Format(_('%d Dateien, %d geändert'), [FEntries.Count, N]);
  FBtnSave.Enabled := N > 0;
  FBtnSave.Down := N > 0;   // leuchtet grün, solange etwas zu speichern ist
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
      if not TTagEntry(Sel[I]).CanEdit then
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
      SetFieldText(F, V, FMixed[F]);
      FEdits[F].Enabled := CanEdit;
    end;
    CheckBpmField;
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

{ Text eines Felds (TEdit oder TDJCombo) }
function TMainForm.FieldText(F: TMp4TagField): string;
begin
  if FEdits[F] is TDJCombo then
    Result := TDJCombo(FEdits[F]).Text
  else
    Result := TEdit(FEdits[F]).Text;
end;

{ Feld befüllen; Mixed = Werte der markierten Dateien sind verschieden }
procedure TMainForm.SetFieldText(F: TMp4TagField; const V: string; Mixed: Boolean);
var
  H: string;
begin
  if Mixed then H := _('<verschieden>') else H := '';
  if FEdits[F] is TDJCombo then
  begin
    TDJCombo(FEdits[F]).Text := V;
    TDJCombo(FEdits[F]).TextHint := H;
  end
  else
  begin
    TEdit(FEdits[F]).Text := V;
    TEdit(FEdits[F]).TextHint := H;
  end;
end;

{ Tooltip für ein Feld (ausgeblendete Felder haben kein Steuerelement) }
procedure TMainForm.SetFieldHint(F: TMp4TagField; const H: string);
begin
  if FEdits[F] <> nil then
    FEdits[F].Hint := H;
  if FEdits[F] is TDJCombo then
    TDJCombo(FEdits[F]).Edit.Hint := H;
end;

{ BPM-Feld rot färben, solange die Eingabe ungültig ist }
procedure TMainForm.CheckBpmField;
begin
  if FEdits[tfBpm] = nil then Exit;
  if BpmValid(Trim(FieldText(tfBpm))) then
    FEdits[tfBpm].Color := DJ_BG
  else
    FEdits[tfBpm].Color := $00303078;   // dunkles Rot: Wert wird nicht gespeichert
  { den dunklen Rahmen um das Feld gleich mitfärben }
  if FEdits[tfBpm].Parent is TDJPanel then
  begin
    FEdits[tfBpm].Parent.Color := FEdits[tfBpm].Color;
    FEdits[tfBpm].Parent.Invalidate;
  end;
end;

{ Eintrag aus der Liste gewählt: Der Text steht erst nach dem Ereignis
  sicher im Feld, deshalb kurz danach übernehmen }
procedure TMainForm.ComboSelect(Sender: TObject);
begin
  Application.QueueAsyncCall(@ComboSelectAsync, PtrInt(Sender));
end;

procedure TMainForm.ComboSelectAsync(Data: PtrInt);
var
  Cb: TDJCombo;
  V: string;
begin
  Cb := TDJCombo(Data);
  if Cb = FEdits[tfKey] then
  begin
    { "Am   (8A / 1m)" -> "Am" }
    V := CleanKey(Cb.Text);
    if V <> Cb.Text then
    begin
      Cb.Text := V;      // löst FieldChange aus
    end;
  end;
  FieldChange(Cb);
end;

{ Nach dem Laden eines Ordners einmal erklären, was passiert und was nicht }
{ Ko-fi-Knopf unten rechts: dunkle Pille mit dem StemTagger-Symbol (uStatusDraw, gleich wie in StemMaker) }
procedure TMainForm.KofiPaint(Sender: TObject);
begin
  FKofi.Canvas.Font.Style := [fsBold];
  DrawKofiButton(FKofi.Canvas, FKofi.ClientRect, _('Kaffee spendieren'),
    FKofiHover, TPanel(FKofi.Parent).Color, Screen.PixelsPerInch, Application.Icon);
end;

procedure TMainForm.KofiClick(Sender: TObject);
begin
  OpenURL(KOFI_URL);
end;

procedure TMainForm.KofiEnter(Sender: TObject);
begin
  FKofiHover := True;
  FKofi.Invalidate;
end;

procedure TMainForm.KofiLeave(Sender: TObject);
begin
  FKofiHover := False;
  FKofi.Invalidate;
end;

procedure TMainForm.ShowFolderHint(Data: PtrInt);
begin
  FFolderHintPending := False;
  if QuestionDlg(_('Ordner geladen'),
       Format(_('%d Dateien in der Liste.'), [FList.Items.Count]) + LineEnding + LineEnding +
       _('Beim Laden wird nichts verändert. In die Dateien geschrieben wird erst mit „Speichern“, und nur bei Dateien mit Änderungen.') +
       LineEnding + LineEnding +
       _('Achtung bei Mehrfachauswahl: Sind mehrere Zeilen markiert, bekommen alle markierten Dateien den neuen Wert (z.B. alle dasselbe Album oder Cover). Felder mit „<verschieden>“ bleiben pro Datei erhalten, solange du sie nicht änderst.') +
       LineEnding + LineEnding +
       _('Audio, Stems und Traktors eigene Daten (auch in MP3s) bleiben immer unverändert, neu geschrieben werden nur die Tags.'),
       mtInformation, [mrOk, 'OK', mrNo, _('Nicht mehr anzeigen')], 0) = mrNo then
  begin
    FFolderHint := False;
    SaveSettings;
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
      if not E.CanEdit then Continue;
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
  if FChkShrink.Down then Max := COVER_MAX_SIDE else Max := 0;
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

function TMainForm.SaveAll(Ask: Boolean): Boolean;
var
  I, Ok, Bad, N: Integer;
  E: TTagEntry;
  Err, Bak: string;
  Fresh: TMp4Tags;
  Written, ReadOk: Boolean;   // Schreiben bzw. Nachlesen hat geklappt
begin
  Result := False;
  Ok := 0;
  Bad := 0;
  { ungültige BPM nicht speichern }
  N := 0;
  for I := 0 to FEntries.Count - 1 do
  begin
    E := TTagEntry(FEntries[I]);
    if (tfBpm in E.Dirty) and not BpmValid(E.Cur.Text[tfBpm]) then
    begin
      MessageDlg(Format(_('BPM „%s“ bei %s ist ungültig. Bitte eine ganze Zahl von %d bis %d eingeben oder das Feld leeren.'),
        [E.Cur.Text[tfBpm], ExtractFileName(E.FileName), BPM_MIN, BPM_MAX]), mtWarning, [mbOK], 0);
      Exit;
    end;
    if E.CanEdit and (E.Dirty <> []) then
      Inc(N);
  end;
  if N = 0 then Exit(True);
  { bei mehreren Dateien lieber nachfragen - eine Änderung bei markierten
    Zeilen gilt für alle markierten }
  if Ask and (N > 1) and (MessageDlg(Format(_('%d Dateien werden geändert.'), [N]) + LineEnding + LineEnding +
      _('Neu geschrieben werden nur die geänderten Tags, Audio, Stems und Traktor-Daten bleiben unverändert.') +
      LineEnding + _('Jetzt speichern?'), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to FList.Items.Count - 1 do
    begin
      E := TTagEntry(FList.Items[I].Data);
      if (E.Dirty = []) or not E.CanEdit then Continue;
      FStatus.Caption := Format(_('Speichere %s ...'), [ExtractFileName(E.FileName)]);
      Application.ProcessMessages;
      { Sicherungskopie nur einmal anlegen - so bleibt das echte Original }
      if FChkBackup.Down then
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
      if E.IsMp3 then
        Written := WriteMp3Tags(E.FileName, E.Cur, E.Dirty, Err)
      else
        Written := WriteMp4Tags(E.FileName, E.Cur, E.Dirty, Err);
      if Written then
      begin
        Log('Gespeichert: ' + E.FileName);
        if E.IsMp3 then
          ReadOk := ReadMp3Tags(E.FileName, Fresh, E.Mp3, Err)
        else
          ReadOk := ReadMp4Tags(E.FileName, Fresh, Err);
        if ReadOk then
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
    FStatus.Caption := Format(_('%d Dateien gespeichert'), [Ok]);
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

{ Vergleich für das Sortieren: Param = Spalte + 1, negativ = absteigend }
function CompareRows(Item1, Item2: TListItem; AOptionalParam: PtrInt): Integer; stdcall;
var
  Col: Integer;

  function CellText(It: TListItem): string;
  begin
    if Col = 0 then
      Result := It.Caption
    else if Col - 1 < It.SubItems.Count then
      Result := It.SubItems[Col - 1]
    else
      Result := '';
  end;

begin
  Col := Abs(AOptionalParam) - 1;
  Result := UTF8CompareText(CellText(Item1), CellText(Item2));
  if Result = 0 then
    Result := UTF8CompareText(Item1.Caption, Item2.Caption);
  if AOptionalParam < 0 then
    Result := -Result;
end;

{ Klick auf eine Spaltenüberschrift sortiert, zweiter Klick umgekehrt.
  Leere Zellen kommen zuerst - so stehen z.B. alle Tracks ohne Cover
  zusammen. Beim Bearbeiten wird nicht neu sortiert (Zeilen springen nicht). }
procedure TMainForm.ListColumnClick(Sender: TObject; Column: TListColumn);
begin
  if Column.Index = FSortCol then
    FSortDesc := not FSortDesc
  else
  begin
    FSortCol := Column.Index;
    FSortDesc := False;
  end;
  if FSortDesc then
    FList.CustomSort(@CompareRows, -(FSortCol + 1))
  else
    FList.CustomSort(@CompareRows, FSortCol + 1);
  if FList.Selected <> nil then
    FList.Selected.MakeVisible(False);
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
  F := TMp4TagField(TControl(Sender).Tag);
  V := Trim(FieldText(F));
  if F = tfKey then
    V := CleanKey(V);
  if F = tfBpm then
    CheckBpmField;
  Sel := SelectedEntries;
  try
    for I := 0 to Sel.Count - 1 do
    begin
      E := TTagEntry(Sel[I]);
      if not E.CanEdit then Continue;
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
    Dlg.Title := _('Dateien öffnen');
    Dlg.Filter := _('Stem- und MP3-Dateien') + ' (*.stem.mp4;*.stem.m4a;*.mp3)|*.stem.mp4;*.stem.m4a;*.mp3|' +
                  _('Stem-Dateien') + ' (*.stem.mp4;*.stem.m4a)|*.stem.mp4;*.stem.m4a|' +
                  _('MP3-Dateien') + ' (*.mp3)|*.mp3|' +
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
    Dlg.Title := _('Ordner mit Stem- oder MP3-Dateien wählen (mit Unterordnern)');
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
  if FChkShrink.Down then Max := COVER_MAX_SIDE else Max := 0;
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
    if not E.CanEdit then Continue;
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
    FStatus.Caption := Format(_('%d Dateien aus dem Dateinamen übernommen - noch nicht gespeichert'), [N]);
end;

procedure TMainForm.BtnSaveClick(Sender: TObject);
begin
  SaveAll(True);
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
      MessageDlg(_('Zuerst die Dateien markieren, die dieses Cover bekommen sollen.'),
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
    if FBtnSave.Enabled then SaveAll(True);
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
      mrYes: CanClose := SaveAll(False);
      mrNo : CanClose := True;
    else
      CanClose := False;
    end;
  if CanClose then
    SaveSettings;
end;

end.
