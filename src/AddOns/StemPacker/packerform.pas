{ ============================================================================
  packerform.pas  -  Hauptfenster des Elospeed StemPacker

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Der StemPacker macht aus fertigen Einzelspuren Traktor-Stem-Dateien,
  OHNE KI-Trennung und im Stapel: pro Song Master + Stem 1..4 (z. B. aus
  der DAW, aus 5.1-DVDs oder aus einem anderen Trennprogramm) ergeben
  eine <Song>.stem.mp4.

  Bedienung (Einfach-Modus, Standard):
    Ordner hineinziehen oder „Ordner wählen …“. Die Benennung der Dateien
    wird erkannt, die Songs erscheinen in der Liste, dann „Alle packen“.

  Bedienung mit „Ordner und Muster selbst einstellen“:
    1. Vorlage wählen (oder eigene Muster eintragen) und die Ordner der
       Spuren angeben. Stern * im Muster = Songname.
    2. "Songs suchen" zeigt jeden Song mit den gefundenen Dateien.
    3. "Alle packen" baut die Stem-Dateien. Tags und Cover kommen von der
       Master-Datei, Stem-Namen und -Farben aus den Einstellungen.

  Die Logik steckt in packmatch.pas (Songs finden) und packjob.pas
  (ffmpeg-Aufruf). Den Stem-Block schreibt ..\..\ustemmp4.pas wie in
  StemMaker. Sprache wie die anderen AddOns: StemMaker.ini, sonst die
  Sprache von Windows (lang\*.po, siehe ..\..\ulang.pas).

  Einstellungen in StemPacker.ini neben der exe (schreibgeschützter
  Ordner: %APPDATA%\StemMaker\). Fenstergrösse in 96-dpi-Einheiten.

  Versionen:
    0.1  (01.11.2026)  Erste Testversion
    0.2  (04.11.2026)  Fehlt ein Stem: gesuchter Dateiname und ähnliche Datei
                       in der Liste; Längenprüfung (Spur kürzer/länger als
                       der Master); Info-Knopf mit Dank an Cuiusquemodi;
                       gewählte Zeile zeigt den ganzen Status unten
    0.3  (07.11.2026)  Einfach-Modus: Ordner hineinziehen oder wählen, die
                       Benennung wird erkannt (packdetect.pas); Ordner und
                       Muster selbst einstellen bleibt als Häkchen; neun
                       Sprachen wie StemMaker
  ============================================================================ }
unit packerform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, LCLType, LCLIntf, FileUtil, LazFileUtils, LazUTF8,
  IniFiles, UTF8Process, Process,
  uLang, uStemMP4, uStatusDraw, uSkalierung, packmatch, packjob, packdetect;

const
  APP_TITLE = 'Elospeed StemPacker';
  APP_VER   = '0.3';
  KOFI_URL  = 'https://ko-fi.com/elospeed';
  PAGE_URL  = 'https://elospeed.github.io/StemPacker/';

type
  { Eine Zeile pro Spur: Name, Ordner, Muster, Stem-Name, Farbe }
  TRoleRow = record
    Panel   : TPanel;
    Caption : TLabel;
    Folder  : TEdit;
    Browse  : TButton;
    Pattern : TEdit;
    StemName: TEdit;
    ColorBox: TPanel;
  end;

  { TPackerForm }

  TPackerForm = class(TForm)
  private
    FRows      : array[0..ROLE_COUNT - 1] of TRoleRow;
    FSimple    : TPanel;     // Einfach-Modus: Ordner ziehen oder wählen
    FBtnPick   : TButton;    // „Ordner wählen …“
    FDetect    : TLabel;     // was erkannt wurde
    FChkExpert : TCheckBox;  // Ordner und Muster selbst einstellen
    FPTop      : TPanel;     // Vorlage + Schalter (nur im erweiterten Modus)
    FHead      : TPanel;     // Spaltenüberschriften der fünf Zeilen
    FOptPanels : array[0..2] of TPanel;  // Ziel, Format, Extras (für die Reihenfolge)
    FCbPreset  : TComboBox;
    FChkMix    : TCheckBox;
    FChkSub    : TCheckBox;
    FRbNext    : TRadioButton;
    FRbFolder  : TRadioButton;
    FEdOut     : TEdit;
    FBtnOut    : TButton;
    FCbFormat  : TComboBox;
    FChkFill   : TCheckBox;
    FChkCover  : TCheckBox;
    FChkOver   : TCheckBox;
    FList      : TListView;
    FBtnScan   : TButton;
    FBtnStart  : TButton;
    FBtnCancel : TButton;
    FBtnLog    : TButton;
    FBtnInfo   : TButton;
    FStatus    : TLabel;
    FKofi      : TPaintBox;
    FKofiHover : Boolean;

    FSongs     : TList;      // TPackSong
    FFFmpeg    : string;
    FBusy      : Boolean;
    FCancel    : Boolean;
    FCloseAfter: Boolean;
    FWarned    : Integer;    // Songs mit Längen-Warnung beim letzten Packen
    FLoading   : Boolean;
    FLogFile   : string;

    procedure LoadLanguage;
    procedure BuildUI;
    function  MakeRow(AParent: TWinControl; Role: Integer): TRoleRow;
    function  RoleCaption(Role: Integer): string;
    procedure ApplyPreset(Idx: Integer);
    procedure UpdateEnabled;
    procedure ShowExpert;
    procedure RunDetect(const Folder: string);
    function  IniFileName: string;
    procedure LoadSettings;
    procedure SaveSettings;
    function  GetRules: TPackRules;
    function  GetOptions: TPackOptions;
    function  StemInfos: TStemInfoArray;
    function  OutFileFor(Song: TPackSong): string;
    function  CheckInput(Quiet: Boolean): Boolean;
    procedure ScanSongs;
    procedure ShowSongs;
    function  CheckLengths(Song: TPackSong): string;
    procedure SetRowStatus(i: Integer; const S: string);
    function  PackSong(Song: TPackSong; Row: Integer): Boolean;
    procedure PackAll;
    procedure SetBusy(B: Boolean);

    procedure Log(const S: string);
    function  FindFFmpeg: string;
    function  EnsureFFmpeg: Boolean;
    function  RunTool(Args: TStrings; const What: string; out OutText: string): Integer;

    procedure PresetChange(Sender: TObject);
    procedure PatternChange(Sender: TObject);
    procedure MixClick(Sender: TObject);
    procedure ExpertClick(Sender: TObject);
    procedure BtnPickClick(Sender: TObject);
    procedure OutModeClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure BtnOutClick(Sender: TObject);
    procedure ColorClick(Sender: TObject);
    procedure BtnScanClick(Sender: TObject);
    procedure BtnStartClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure BtnLogClick(Sender: TObject);
    procedure BtnInfoClick(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure KofiPaint(Sender: TObject);
    procedure KofiClick(Sender: TObject);
    procedure KofiEnter(Sender: TObject);
    procedure KofiLeave(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure DeferredClose(Data: PtrInt);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainPacker: TPackerForm;

implementation

type
  TPreset = record
    Patterns: TRoleFiles;
    Names   : array[1..4] of string;
    Colors  : array[1..4] of string;
  end;

const
  PRESET_CUSTOM = 3;
  PRESETS: array[0..2] of TPreset = (
    { 5.1-DVD wie bei Cuiusquemodi: Downmix + A..D in eigenem Ordner.
      Farben wie Stem51 (Front, LFE, Center, Rear) }
    (Patterns: ('* (DOWNMIX #1)', '* (A)', '* (B)', '* (C)', '* (D)');
     Names: ('Front', 'LFE', 'Center', 'Rear');
     Colors: ('#56B4E9', '#D55E00', '#CC79A7', '#009E73')),
    { DAW-Export: Song.wav + Song_drums.wav ... (Farben wie StemMaker) }
    (Patterns: ('*', '*_drums', '*_bass', '*_other', '*_vocals');
     Names: ('Drums', 'Bass', 'Other', 'Vox');
     Colors: ('#009E73', '#D55E00', '#CC79A7', '#56B4E9')),
    { Nummern _0 bis _4 }
    (Patterns: ('*_0', '*_1', '*_2', '*_3', '*_4');
     Names: ('Drums', 'Bass', 'Other', 'Vox');
     Colors: ('#009E73', '#D55E00', '#CC79A7', '#56B4E9'))
  );

  COL_SONG = 0; COL_FILES = 1; COL_STATUS = 2; COL_TARGET = 3;

function HexToColor(const S: string): TColor;
var V: LongInt;
begin
  if (Length(S) = 7) and (S[1] = '#') and TryStrToInt('$' + Copy(S, 2, 6), V) then
    Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF)
  else
    Result := clGray;
end;

function ColorToHex(C: TColor): string;
var V: LongInt;
begin
  V := ColorToRGB(C);
  Result := Format('#%.2X%.2X%.2X', [Red(V), Green(V), Blue(V)]);
end;

{ ============================================================================
  Aufbau
  ============================================================================ }

constructor TPackerForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);   // keine .lfm-Datei
  { gleich auf die Bildschirm-DPI: BuildUI rechnet alles mit Scale96ToForm }
  StelleAufBildschirmDPI(Self);
  FSongs := TList.Create;
  LoadLanguage;

  Caption := APP_TITLE + ' ' + APP_VER + '  -  ' + _('fertige Spuren zu Stem-Dateien packen');
  Position := poScreenCenter;
  Font.Name := 'Segoe UI';
  ClientWidth := Scale96ToForm(900);
  ClientHeight := Scale96ToForm(640);
  Constraints.MinWidth := Scale96ToForm(720);
  Constraints.MinHeight := Scale96ToForm(470);
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  OnCloseQuery := @FormCloseQuery;

  BuildUI;
  LoadSettings;
  UpdateEnabled;

  FFFmpeg := FindFFmpeg;
  Log(Format('=== %s %s ===  ffmpeg: %s', [APP_TITLE, APP_VER, FFFmpeg]));
  if FFFmpeg = '' then
    FStatus.Caption := _('ffmpeg.exe nicht gefunden - wird beim ersten Gebrauch abgefragt.')
  else if FChkExpert.Checked then
    FStatus.Caption := _('Ordner und Muster einstellen, dann „Songs suchen“.')
  else
    FStatus.Caption := _('Ordner mit den Spuren hineinziehen oder „Ordner wählen …“ klicken.');

  { Ordner von der Befehlszeile (z. B. aus StemMaker) = Master-Ordner }
  if (ParamCount >= 1) and DirectoryExistsUTF8(ParamStr(1)) then
  begin
    if FChkExpert.Checked then
      FRows[0].Folder.Text := ExcludeTrailingPathDelimiter(ParamStr(1))
    else
      RunDetect(ExcludeTrailingPathDelimiter(ParamStr(1)));
  end;
end;

destructor TPackerForm.Destroy;
begin
  if Assigned(FSongs) then FreeSongs(FSongs);
  FSongs.Free;
  inherited Destroy;
end;

{ Sprache wie StemMaker: zuerst StemMaker.ini im Programmordner, dann die
  in %APPDATA%, sonst die Sprache von Windows (gleich wie StemTagger) }
procedure TPackerForm.LoadLanguage;
var
  Ini: TIniFile;
  Code, IniName: string;
  i: Integer;
begin
  Code := '';
  for i := 1 to 3 do
  begin
    case i of
      1: IniName := IniFileName;                       // eigene Wahl (Standalone)
      2: IniName := AppBaseDir + 'StemMaker.ini';
    else
      IniName := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
        'StemMaker' + PathDelim + 'StemMaker.ini';
    end;
    if not FileExists(IniName) then Continue;
    try
      Ini := TIniFile.Create(IniName);
      try
        if i = 1 then
          Code := Trim(Ini.ReadString('Allgemein', 'Sprache', ''))
        else
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

function TPackerForm.RoleCaption(Role: Integer): string;
begin
  if Role = 0 then Result := _('Master')
  else Result := Format(_('Stem %d'), [Role]);
end;

{ Eine Zeile: [Name] [Ordner .........] [...] [Muster] [Stem-Name] [Farbe]
  Alles über Align, so wächst der Ordner mit dem Fenster. }
function TPackerForm.MakeRow(AParent: TWinControl; Role: Integer): TRoleRow;
begin
  Result.Panel := TPanel.Create(Self);
  Result.Panel.Parent := AParent;
  Result.Panel.Align := alTop;
  Result.Panel.Top := 1000 + Role;          // Reihenfolge von oben nach unten
  Result.Panel.Height := Scale96ToForm(30);
  Result.Panel.BevelOuter := bvNone;

  Result.Caption := TLabel.Create(Self);
  Result.Caption.Parent := Result.Panel;
  Result.Caption.Align := alLeft;
  Result.Caption.AutoSize := False;
  Result.Caption.Width := Scale96ToForm(70);
  Result.Caption.Layout := tlCenter;
  Result.Caption.Caption := RoleCaption(Role);
  if Role = 0 then Result.Caption.Font.Style := [fsBold];

  { rechts: Farbe, Stem-Name, Muster, Knopf (kleineres Left = weiter links) }
  Result.ColorBox := TPanel.Create(Self);
  Result.ColorBox.Parent := Result.Panel;
  Result.ColorBox.Align := alRight;
  Result.ColorBox.Left := 4000;
  Result.ColorBox.Width := Scale96ToForm(44);
  Result.ColorBox.BorderSpacing.Around := Scale96ToForm(3);
  Result.ColorBox.BevelOuter := bvLowered;
  Result.ColorBox.ParentBackground := False;
  Result.ColorBox.Cursor := crHandPoint;
  Result.ColorBox.Tag := Role;
  Result.ColorBox.OnClick := @ColorClick;
  Result.ColorBox.Hint := _('Farbe des Stems in Traktor (klicken zum Ändern)');
  Result.ColorBox.ShowHint := True;
  Result.ColorBox.Visible := Role > 0;

  Result.StemName := TEdit.Create(Self);
  Result.StemName.Parent := Result.Panel;
  Result.StemName.Align := alRight;
  Result.StemName.Left := 3000;
  Result.StemName.Width := Scale96ToForm(110);
  Result.StemName.BorderSpacing.Around := Scale96ToForm(3);
  Result.StemName.MaxLength := 32;
  Result.StemName.Hint := _('Name des Stems, so zeigt ihn Traktor an');
  Result.StemName.ShowHint := True;
  Result.StemName.Visible := Role > 0;
  if Role = 0 then
  begin
    { Platzhalter, damit die Muster-Spalte bündig bleibt }
    Result.StemName.Visible := True;
    Result.StemName.Enabled := False;
    Result.StemName.Width := Scale96ToForm(110 + 47);
    Result.StemName.Text := _('(Tags und Cover)');
  end;

  Result.Pattern := TEdit.Create(Self);
  Result.Pattern.Parent := Result.Panel;
  Result.Pattern.Align := alRight;
  Result.Pattern.Left := 2000;
  Result.Pattern.Width := Scale96ToForm(190);
  Result.Pattern.BorderSpacing.Around := Scale96ToForm(3);
  Result.Pattern.Tag := Role;
  Result.Pattern.OnChange := @PatternChange;
  Result.Pattern.Hint := _('Dateiname ohne Endung, * steht für den Songnamen.') + LineEnding +
    _('Beispiel: „* (A)“ findet „Hello (A).wav“, der Song heisst dann „Hello“.');
  Result.Pattern.ShowHint := True;

  Result.Browse := TButton.Create(Self);
  Result.Browse.Parent := Result.Panel;
  Result.Browse.Align := alRight;
  Result.Browse.Left := 1000;
  Result.Browse.Width := Scale96ToForm(32);
  Result.Browse.BorderSpacing.Around := Scale96ToForm(3);
  Result.Browse.Caption := '...';
  Result.Browse.Tag := Role;
  Result.Browse.OnClick := @BrowseClick;
  Result.Browse.Hint := _('Ordner wählen');
  Result.Browse.ShowHint := True;

  Result.Folder := TEdit.Create(Self);
  Result.Folder.Parent := Result.Panel;
  Result.Folder.Align := alClient;
  Result.Folder.BorderSpacing.Around := Scale96ToForm(3);
  if Role = 0 then
    Result.Folder.TextHint := _('Ordner mit den Master-Dateien')
  else if Role = 1 then
    Result.Folder.TextHint := _('leer = wie Master')
  else
    Result.Folder.TextHint := Format(_('leer = wie Stem %d'), [Role - 1]);
end;

procedure TPackerForm.BuildUI;
var
  PTop, Head, Opt, Opt2, Opt3, Bottom, Foot, SRow1, SRow2: TPanel;
  L: TLabel;
  r: Integer;

  function NewPanel(AParent: TWinControl; AAlign: TAlign; H, ATop: Integer): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := AParent;
    Result.Align := AAlign;
    Result.Top := ATop;
    Result.Height := Scale96ToForm(H);
    Result.BevelOuter := bvNone;
  end;

  function NewLabel(AParent: TWinControl; const S: string; AAlign: TAlign; W: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Align := AAlign;
    Result.AutoSize := False;
    Result.Width := Scale96ToForm(W);
    Result.Layout := tlCenter;
    Result.Caption := S;
    Result.BorderSpacing.Around := Scale96ToForm(3);
  end;

  function NewCheck(AParent: TWinControl; const S: string; ALeft: Integer;
    AAlign: TAlign = alLeft): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := AParent;
    Result.Align := AAlign;
    Result.Left := ALeft;
    Result.Caption := S;
    Result.AutoSize := True;
    Result.BorderSpacing.Left := Scale96ToForm(14);
    Result.BorderSpacing.Top := Scale96ToForm(5);
  end;

begin
  { --- Einfach-Modus: Ordner ziehen oder wählen ------------------------ }
  FSimple := NewPanel(Self, alTop, 64, 0);
  FSimple.BorderSpacing.Left := Scale96ToForm(10);
  FSimple.BorderSpacing.Right := Scale96ToForm(10);
  FSimple.BorderSpacing.Top := Scale96ToForm(8);
  FSimple.BevelOuter := bvLowered;
  SRow1 := NewPanel(FSimple, alTop, 32, 0);
  FBtnPick := TButton.Create(Self);
  FBtnPick.Parent := SRow1;
  FBtnPick.Align := alRight;
  FBtnPick.Width := Scale96ToForm(150);
  FBtnPick.BorderSpacing.Around := Scale96ToForm(3);
  FBtnPick.Caption := _('Ordner wählen …');
  FBtnPick.Font.Style := [fsBold];
  FBtnPick.OnClick := @BtnPickClick;
  L := NewLabel(SRow1, _('Ordner mit den Spuren hier hineinziehen'), alClient, 100);
  L.Font.Style := [fsBold];
  L.BorderSpacing.Left := Scale96ToForm(8);
  SRow2 := NewPanel(FSimple, alClient, 28, 100);
  FChkExpert := NewCheck(SRow2, _('Ordner und Muster selbst einstellen'), 4000, alRight);
  FChkExpert.BorderSpacing.Top := Scale96ToForm(3);
  FChkExpert.BorderSpacing.Right := Scale96ToForm(8);
  FChkExpert.Hint := _('Für Benennungen, die nicht erkannt werden: Ordner, Namensmuster, Stem-Namen und Farben je Spur selbst eintragen.');
  FChkExpert.ShowHint := True;
  FChkExpert.OnClick := @ExpertClick;
  FDetect := NewLabel(SRow2, _('Die Benennung wird erkannt, z. B. „Song_drums“, „Song (Vocals)“, „Song (A)“ oder „Song_1“.'), alClient, 100);
  FDetect.BorderSpacing.Left := Scale96ToForm(8);
  FDetect.Font.Color := clGrayText;
  FDetect.ShowHint := True;

  { --- oben: Vorlage + Schalter --------------------------------------- }
  PTop := NewPanel(Self, alTop, 34, 50);
  FPTop := PTop;
  PTop.BorderSpacing.Left := Scale96ToForm(10);
  PTop.BorderSpacing.Right := Scale96ToForm(10);
  PTop.BorderSpacing.Top := Scale96ToForm(6);
  NewLabel(PTop, _('Vorlage:'), alLeft, 66).Left := 0;
  FCbPreset := TComboBox.Create(Self);
  FCbPreset.Parent := PTop;
  FCbPreset.Align := alClient;      // wird schmaler, wenn das Fenster schmal ist
  FCbPreset.BorderSpacing.Around := Scale96ToForm(3);
  FCbPreset.Style := csDropDownList;
  FCbPreset.Items.Add(_('5.1-DVD: „Song (DOWNMIX #1)“ + „Song (A)“ … „(D)“'));
  FCbPreset.Items.Add(_('DAW-Export: „Song“ + „Song_drums“ … „_vocals“'));
  FCbPreset.Items.Add(_('Nummern: „Song_0“ (Master) bis „Song_4“'));
  FCbPreset.Items.Add(_('Eigene Muster'));
  FCbPreset.OnChange := @PresetChange;
  FChkMix := NewCheck(PTop, _('Master aus den Stems mischen'), 3000, alRight);
  FChkMix.Hint := _('Für Spuren ohne fertigen Master: die vier Stems werden ohne Pegeländerung zusammengemischt.');
  FChkMix.ShowHint := True;
  FChkMix.OnClick := @MixClick;
  FChkSub := NewCheck(PTop, _('Unterordner durchsuchen'), 4000, alRight);
  FChkSub.Hint := _('Auch in Unterordnern suchen. Die Unterordner müssen in allen Ordnern gleich heissen.');
  FChkSub.ShowHint := True;

  { --- Überschriften der Spalten -------------------------------------- }
  Head := NewPanel(Self, alTop, 22, 100);
  FHead := Head;
  Head.BorderSpacing.Left := Scale96ToForm(10);
  Head.BorderSpacing.Right := Scale96ToForm(10);
  Head.BorderSpacing.Top := Scale96ToForm(6);
  NewLabel(Head, _('Spur'), alLeft, 64).Font.Color := clGrayText;
  L := NewLabel(Head, _('Farbe'), alRight, 44);
  L.Left := 4000; L.Font.Color := clGrayText;
  L := NewLabel(Head, _('Stem-Name'), alRight, 110);
  L.Left := 3000; L.Font.Color := clGrayText;
  L := NewLabel(Head, _('Namensmuster (* = Songname)'), alRight, 190 + 38);
  L.Left := 2000; L.Font.Color := clGrayText;
  L := NewLabel(Head, _('Ordner'), alClient, 100);
  L.Font.Color := clGrayText;

  { --- die fünf Zeilen ------------------------------------------------ }
  for r := 0 to ROLE_COUNT - 1 do
  begin
    FRows[r] := MakeRow(Self, r);
    FRows[r].Panel.Top := 200 + r;
    FRows[r].Panel.BorderSpacing.Left := Scale96ToForm(10);
    FRows[r].Panel.BorderSpacing.Right := Scale96ToForm(10);
  end;

  { --- Ziel ----------------------------------------------------------- }
  Opt := NewPanel(Self, alTop, 32, 300);
  FOptPanels[0] := Opt;
  Opt.BorderSpacing.Left := Scale96ToForm(10);
  Opt.BorderSpacing.Right := Scale96ToForm(10);
  Opt.BorderSpacing.Top := Scale96ToForm(10);
  NewLabel(Opt, _('Ziel:'), alLeft, 64).Font.Style := [fsBold];
  FRbNext := TRadioButton.Create(Self);
  FRbNext.Parent := Opt;
  FRbNext.Align := alLeft;
  FRbNext.Left := 100;
  FRbNext.AutoSize := True;
  FRbNext.BorderSpacing.Top := Scale96ToForm(5);
  FRbNext.Caption := _('neben die Master-Datei');
  FRbNext.Checked := True;
  FRbNext.OnClick := @OutModeClick;
  FRbFolder := TRadioButton.Create(Self);
  FRbFolder.Parent := Opt;
  FRbFolder.Align := alLeft;
  FRbFolder.Left := 200;
  FRbFolder.AutoSize := True;
  FRbFolder.BorderSpacing.Left := Scale96ToForm(16);
  FRbFolder.BorderSpacing.Top := Scale96ToForm(5);
  FRbFolder.Caption := _('in diesen Ordner:');
  FRbFolder.OnClick := @OutModeClick;
  FBtnOut := TButton.Create(Self);
  FBtnOut.Parent := Opt;
  FBtnOut.Align := alRight;
  FBtnOut.Width := Scale96ToForm(32);
  FBtnOut.BorderSpacing.Around := Scale96ToForm(3);
  FBtnOut.Caption := '...';
  FBtnOut.OnClick := @BtnOutClick;
  FEdOut := TEdit.Create(Self);
  FEdOut.Parent := Opt;
  FEdOut.Align := alClient;
  FEdOut.BorderSpacing.Around := Scale96ToForm(3);
  FEdOut.TextHint := _('Ausgabeordner (Unterordner werden übernommen)');

  { --- Format und Schalter -------------------------------------------- }
  Opt2 := NewPanel(Self, alTop, 32, 400);
  FOptPanels[1] := Opt2;
  Opt2.BorderSpacing.Left := Scale96ToForm(10);
  Opt2.BorderSpacing.Right := Scale96ToForm(10);
  NewLabel(Opt2, _('Format:'), alLeft, 64).Font.Style := [fsBold];
  FCbFormat := TComboBox.Create(Self);
  FCbFormat.Parent := Opt2;
  FCbFormat.Align := alLeft;
  FCbFormat.Left := 100;
  FCbFormat.Width := Scale96ToForm(300);
  FCbFormat.BorderSpacing.Around := Scale96ToForm(3);
  FCbFormat.Style := csDropDownList;
  FCbFormat.Items.Add(_('AAC 320 kbit/s (wie Traktor-Stems)'));
  FCbFormat.Items.Add(_('ALAC verlustfrei, 16 Bit / 44,1 kHz'));
  FCbFormat.Items.Add(_('ALAC 24 Bit, Original-Abtastrate (Test)'));
  FCbFormat.Hint := _('24 Bit / 96 kHz ist noch nicht in Traktor geprüft. Bitte zuerst mit einem Song testen.');
  FCbFormat.ShowHint := True;
  FChkOver := NewCheck(Opt2, _('Vorhandene überschreiben'), 400);
  FChkOver.Hint := _('Sonst werden Songs übersprungen, deren Stem-Datei es schon gibt.');
  FChkOver.ShowHint := True;

  { --- Extras --------------------------------------------------------- }
  Opt3 := NewPanel(Self, alTop, 30, 500);
  FOptPanels[2] := Opt3;
  Opt3.BorderSpacing.Left := Scale96ToForm(10);
  Opt3.BorderSpacing.Right := Scale96ToForm(10);
  NewLabel(Opt3, _('Extras:'), alLeft, 64).Font.Style := [fsBold];
  FChkFill := NewCheck(Opt3, _('Fehlende Stems still füllen'), 200);
  FChkFill.Hint := _('Fehlt ein Stem, wird eine stille Spur eingesetzt, statt den Song zu überspringen.');
  FChkFill.ShowHint := True;
  FChkCover := NewCheck(Opt3, _('Cover aus dem Ordner, wenn die Datei keins hat'), 300);
  FChkCover.Hint := _('Hat die Master-Datei kein Cover, wird cover.jpg, folder.jpg, front.jpg oder <Song>.jpg aus ihrem Ordner genommen.');
  FChkCover.ShowHint := True;
  { --- Fusszeile: Status, rechts Ko-fi -------------------------------- }
  Foot := NewPanel(Self, alBottom, 30, 10000);
  FKofi := TPaintBox.Create(Self);
  FKofi.Parent := Foot;
  FKofi.Align := alRight;
  FKofi.BorderSpacing.Right := Scale96ToForm(8);
  FKofi.BorderSpacing.Top := Scale96ToForm(3);
  FKofi.BorderSpacing.Bottom := Scale96ToForm(3);
  FKofi.Canvas.Font.Style := [fsBold];
  FKofi.Width := KofiButtonWidth(FKofi.Canvas, _('Kaffee spendieren'), Screen.PixelsPerInch);
  FKofi.Cursor := crHandPoint;
  FKofi.Hint := 'ko-fi.com/elospeed';
  FKofi.ShowHint := True;
  FKofi.OnPaint := @KofiPaint;
  FKofi.OnClick := @KofiClick;
  FKofi.OnMouseEnter := @KofiEnter;
  FKofi.OnMouseLeave := @KofiLeave;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Foot;
  FStatus.Align := alClient;
  FStatus.Layout := tlCenter;
  FStatus.BorderSpacing.Left := Scale96ToForm(12);
  FStatus.Font.Color := clGrayText;

  { --- Knöpfe --------------------------------------------------------- }
  Bottom := NewPanel(Self, alBottom, 44, 9000);
  Bottom.BorderSpacing.Left := Scale96ToForm(7);
  Bottom.BorderSpacing.Right := Scale96ToForm(7);
  FBtnScan := TButton.Create(Self);
  FBtnScan.Parent := Bottom;
  FBtnScan.Align := alLeft;
  FBtnScan.Left := 0;
  FBtnScan.Width := Scale96ToForm(150);
  FBtnScan.BorderSpacing.Around := Scale96ToForm(4);
  FBtnScan.Caption := _('Songs suchen');
  FBtnScan.OnClick := @BtnScanClick;
  FBtnStart := TButton.Create(Self);
  FBtnStart.Parent := Bottom;
  FBtnStart.Align := alLeft;
  FBtnStart.Left := 200;
  FBtnStart.Width := Scale96ToForm(150);
  FBtnStart.BorderSpacing.Around := Scale96ToForm(4);
  FBtnStart.Caption := _('Alle packen');
  FBtnStart.Font.Style := [fsBold];
  FBtnStart.OnClick := @BtnStartClick;
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := Bottom;
  FBtnCancel.Align := alLeft;
  FBtnCancel.Left := 400;
  FBtnCancel.Width := Scale96ToForm(120);
  FBtnCancel.BorderSpacing.Around := Scale96ToForm(4);
  FBtnCancel.Caption := _('Abbrechen');
  FBtnCancel.Enabled := False;
  FBtnCancel.OnClick := @BtnCancelClick;
  FBtnLog := TButton.Create(Self);
  FBtnLog.Parent := Bottom;
  FBtnLog.Align := alRight;
  FBtnLog.Width := Scale96ToForm(120);
  FBtnLog.BorderSpacing.Around := Scale96ToForm(4);
  FBtnLog.Caption := _('Log anzeigen');
  FBtnLog.OnClick := @BtnLogClick;
  FBtnInfo := TButton.Create(Self);
  FBtnInfo.Parent := Bottom;
  FBtnInfo.Align := alRight;
  FBtnInfo.Width := Scale96ToForm(90);
  FBtnInfo.BorderSpacing.Around := Scale96ToForm(4);
  FBtnInfo.Caption := _('Info');
  FBtnInfo.OnClick := @BtnInfoClick;

  { --- Liste der Songs (wächst mit dem Fenster) ----------------------- }
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.BorderSpacing.Left := Scale96ToForm(10);
  FList.BorderSpacing.Right := Scale96ToForm(10);
  FList.BorderSpacing.Top := Scale96ToForm(8);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  with FList.Columns.Add do begin Caption := _('Song');    Width := Scale96ToForm(220); end;
  with FList.Columns.Add do begin Caption := _('Dateien'); Width := Scale96ToForm(60);  end;
  with FList.Columns.Add do begin Caption := _('Status');  Width := Scale96ToForm(360); end;
  with FList.Columns.Add do begin Caption := _('Ziel');    Width := Scale96ToForm(300); end;
  { gewählte Zeile: ganzer Status unten in der Fusszeile (die Spalte ist
    für lange Meldungen zu schmal) }
  FList.OnSelectItem := @ListSelectItem;
end;

{ ============================================================================
  Vorlagen und Einstellungen
  ============================================================================ }

procedure TPackerForm.ApplyPreset(Idx: Integer);
var r: Integer;
begin
  if (Idx < Low(PRESETS)) or (Idx > High(PRESETS)) then Exit;
  FLoading := True;
  try
    for r := 0 to ROLE_COUNT - 1 do
      FRows[r].Pattern.Text := PRESETS[Idx].Patterns[r];
    for r := 1 to ROLE_COUNT - 1 do
    begin
      FRows[r].StemName.Text := PRESETS[Idx].Names[r];
      FRows[r].ColorBox.Color := HexToColor(PRESETS[Idx].Colors[r]);
    end;
    FChkMix.Checked := False;
  finally
    FLoading := False;
  end;
  UpdateEnabled;
end;

procedure TPackerForm.UpdateEnabled;
var r: Integer;
begin
  FRows[0].Pattern.Enabled := not FChkMix.Checked and not FBusy;
  FRows[0].Folder.Enabled := not FChkMix.Checked and not FBusy;
  FRows[0].Browse.Enabled := not FChkMix.Checked and not FBusy;
  if FChkMix.Checked then
    FRows[1].Folder.TextHint := _('Ordner mit den Stems')
  else
    FRows[1].Folder.TextHint := _('leer = wie Master');
  FEdOut.Enabled := FRbFolder.Checked and not FBusy;
  FBtnOut.Enabled := FRbFolder.Checked and not FBusy;
  for r := 1 to ROLE_COUNT - 1 do
  begin
    FRows[r].Folder.Enabled := not FBusy;
    FRows[r].Browse.Enabled := not FBusy;
    FRows[r].Pattern.Enabled := not FBusy;
    FRows[r].StemName.Enabled := not FBusy;
    FRows[r].ColorBox.Enabled := not FBusy;
  end;
  FCbPreset.Enabled := not FBusy;
  FBtnPick.Enabled := not FBusy;
  FChkExpert.Enabled := not FBusy;
  FChkMix.Enabled := not FBusy;
  FChkSub.Enabled := not FBusy;
  FRbNext.Enabled := not FBusy;
  FRbFolder.Enabled := not FBusy;
  FCbFormat.Enabled := not FBusy;
  FChkFill.Enabled := not FBusy;
  FChkCover.Enabled := not FBusy;
  FChkOver.Enabled := not FBusy;
  FBtnScan.Enabled := not FBusy;
  FBtnStart.Enabled := not FBusy;
  FBtnCancel.Enabled := FBusy;
end;

{ Erweiterte Einstellungen (Vorlage, fünf Zeilen) zeigen oder verstecken.
  Danach bekommen alle alTop-Panels der Reihe nach aufsteigende Top-Werte,
  sonst landen die wieder sichtbaren Zeilen unter „Ziel“ und „Format“. }
procedure TPackerForm.ShowExpert;
var
  r: Integer;
  B: Boolean;
begin
  B := FChkExpert.Checked;
  DisableAlign;
  try
    FPTop.Visible := B;
    FHead.Visible := B;
    for r := 0 to ROLE_COUNT - 1 do
      FRows[r].Panel.Visible := B;
    { Reihenfolge von oben: Einfach, Vorlage, Überschriften, fünf Zeilen,
      Ziel, Format, Extras }
    FSimple.Top := 0;
    FPTop.Top := 1;
    FHead.Top := 2;
    for r := 0 to ROLE_COUNT - 1 do
      FRows[r].Panel.Top := 3 + r;
    for r := 0 to High(FOptPanels) do
      FOptPanels[r].Top := 3 + ROLE_COUNT + r;
  finally
    EnableAlign;
  end;
end;

{ Einfach-Modus: Benennung im Ordner erkennen, die Zeilen damit füllen
  und gleich die Songs suchen }
procedure TPackerForm.RunDetect(const Folder: string);
var
  Det: TDetectResult;
  i, r, P: Integer;
  Same: Boolean;
  MasterTxt: string;
begin
  Screen.Cursor := crHourGlass;
  try
    Det := DetectLayout(Folder);
  finally
    Screen.Cursor := crDefault;
  end;
  if Det.Kind = dkNone then
  begin
    Log('Erkennung: keine bekannte Benennung in ' + Folder);
    FreeSongs(FSongs);
    FList.Items.Clear;
    FDetect.Caption := _('Keine bekannte Benennung gefunden. Bitte Ordner und Muster selbst einstellen.');
    FDetect.Font.Color := clRed;
    FStatus.Caption := FDetect.Caption;
    { Zeilen zeigen, der Ordner steht schon beim Master }
    FLoading := True;
    try
      for r := 0 to ROLE_COUNT - 1 do FRows[r].Folder.Text := '';
      FRows[0].Folder.Text := Folder;
      FChkMix.Checked := False;
      FChkSub.Checked := False;
    finally
      FLoading := False;
    end;
    FChkExpert.Checked := True;
    ShowExpert;
    UpdateEnabled;
    Exit;
  end;

  { gleiche Muster wie eine Vorlage? Dann diese anzeigen, sonst „Eigene“ }
  P := PRESET_CUSTOM;
  for i := Low(PRESETS) to High(PRESETS) do
  begin
    Same := True;
    for r := 0 to ROLE_COUNT - 1 do
      if not ((r = 0) and Det.Rules.MixMaster) and
         (UTF8LowerCase(PRESETS[i].Patterns[r]) <> UTF8LowerCase(Det.Rules.Patterns[r])) then
        Same := False;
    if Same then begin P := i; Break; end;
  end;

  FLoading := True;
  try
    { Stem-Namen und Farben: 5.1-DVD wie die DVD-Vorlage, sonst wie StemMaker }
    if Det.Kind = dkDvd then i := 0 else i := 1;
    for r := 1 to ROLE_COUNT - 1 do
    begin
      FRows[r].StemName.Text := PRESETS[i].Names[r];
      FRows[r].ColorBox.Color := HexToColor(PRESETS[i].Colors[r]);
    end;
    for r := 0 to ROLE_COUNT - 1 do
    begin
      FRows[r].Folder.Text := Det.Rules.Folders[r];
      FRows[r].Pattern.Text := Det.Rules.Patterns[r];
    end;
    FChkMix.Checked := Det.Rules.MixMaster;
    FChkSub.Checked := Det.Rules.SubFolders;
    FCbPreset.ItemIndex := P;
  finally
    FLoading := False;
  end;
  UpdateEnabled;

  if Det.Rules.MixMaster then
    MasterTxt := _('Master aus den Stems gemischt')
  else
    MasterTxt := Format(_('Master „%s“'), [ExpectedName(Det.Rules.Patterns[0], 'Song')]);
  FDetect.Font.Color := clGrayText;
  FDetect.Caption := Format(_('Erkannt: „%s“ … „%s“, %s.'),
    [ExpectedName(Det.Rules.Patterns[1], 'Song'), ExpectedName(Det.Rules.Patterns[4], 'Song'), MasterTxt]);
  FDetect.Hint := Folder;
  Log(Format('Erkennung: %s -> %s | %s | %s | %s | %s (mischen %s, Unterordner %s)',
    [Folder, Det.Rules.Patterns[0], Det.Rules.Patterns[1], Det.Rules.Patterns[2],
     Det.Rules.Patterns[3], Det.Rules.Patterns[4],
     BoolToStr(Det.Rules.MixMaster, True), BoolToStr(Det.Rules.SubFolders, True)]));
  if CheckInput(True) then BtnScanClick(nil);
end;

{ StemPacker.ini neben der exe, bei schreibgeschütztem Ordner (Setup unter
  C:\Programme) in %APPDATA%\StemMaker\ - wie StemTagger.ini }
function TPackerForm.IniFileName: string;
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

procedure TPackerForm.LoadSettings;
var
  Ini: TIniFile;
  r, P, W, H: Integer;
begin
  FLoading := True;
  try
    Ini := TIniFile.Create(IniFileName);
    try
      P := Ini.ReadInteger('Muster', 'Vorlage', 0);
      if (P < 0) or (P > PRESET_CUSTOM) then P := 0;
      FCbPreset.ItemIndex := P;
      if P <= High(PRESETS) then ApplyPreset(P) else ApplyPreset(0);
      FLoading := True;
      for r := 0 to ROLE_COUNT - 1 do
      begin
        FRows[r].Folder.Text := Ini.ReadString('Ordner', 'Spur' + IntToStr(r), '');
        if P = PRESET_CUSTOM then
          FRows[r].Pattern.Text := Ini.ReadString('Muster', 'Spur' + IntToStr(r), FRows[r].Pattern.Text);
        if r > 0 then
        begin
          FRows[r].StemName.Text := Ini.ReadString('Stems', 'Name' + IntToStr(r), FRows[r].StemName.Text);
          FRows[r].ColorBox.Color := HexToColor(Ini.ReadString('Stems', 'Farbe' + IntToStr(r),
            ColorToHex(FRows[r].ColorBox.Color)));
        end;
      end;
      FChkMix.Checked := Ini.ReadBool('Muster', 'MasterMischen', False);
      FChkSub.Checked := Ini.ReadBool('Muster', 'Unterordner', False);
      FRbFolder.Checked := Ini.ReadBool('Ziel', 'EigenerOrdner', False);
      FRbNext.Checked := not FRbFolder.Checked;
      FEdOut.Text := Ini.ReadString('Ziel', 'Ordner', '');
      FCbFormat.ItemIndex := EnsureRange(Ini.ReadInteger('Ziel', 'Format', 0), 0, 2);
      FChkFill.Checked := Ini.ReadBool('Ziel', 'StilleFuellen', False);
      FChkCover.Checked := Ini.ReadBool('Ziel', 'CoverAusOrdner', True);
      FChkOver.Checked := Ini.ReadBool('Ziel', 'Ueberschreiben', False);
      FChkExpert.Checked := Ini.ReadBool('Ansicht', 'SelbstEinstellen', False);
      { Fenstergrösse in 96-dpi-Einheiten }
      W := Ini.ReadInteger('Fenster', 'Breite96', 0);
      H := Ini.ReadInteger('Fenster', 'Hoehe96', 0);
      if (W >= 720) and (H >= 470) then
      begin
        ClientWidth := Scale96ToForm(W);
        ClientHeight := Scale96ToForm(H);
      end;
    finally
      Ini.Free;
    end;
  except
    FCbPreset.ItemIndex := 0;
    FCbFormat.ItemIndex := 0;
  end;
  FLoading := False;
  ShowExpert;
end;

procedure TPackerForm.SaveSettings;
var
  Ini: TIniFile;
  r: Integer;
begin
  try
    Ini := TIniFile.Create(IniFileName);
    try
      Ini.WriteInteger('Muster', 'Vorlage', FCbPreset.ItemIndex);
      Ini.WriteBool('Muster', 'MasterMischen', FChkMix.Checked);
      Ini.WriteBool('Muster', 'Unterordner', FChkSub.Checked);
      for r := 0 to ROLE_COUNT - 1 do
      begin
        Ini.WriteString('Ordner', 'Spur' + IntToStr(r), Trim(FRows[r].Folder.Text));
        Ini.WriteString('Muster', 'Spur' + IntToStr(r), Trim(FRows[r].Pattern.Text));
        if r > 0 then
        begin
          Ini.WriteString('Stems', 'Name' + IntToStr(r), Trim(FRows[r].StemName.Text));
          Ini.WriteString('Stems', 'Farbe' + IntToStr(r), ColorToHex(FRows[r].ColorBox.Color));
        end;
      end;
      Ini.WriteBool('Ziel', 'EigenerOrdner', FRbFolder.Checked);
      Ini.WriteString('Ziel', 'Ordner', Trim(FEdOut.Text));
      Ini.WriteInteger('Ziel', 'Format', FCbFormat.ItemIndex);
      Ini.WriteBool('Ziel', 'StilleFuellen', FChkFill.Checked);
      Ini.WriteBool('Ziel', 'CoverAusOrdner', FChkCover.Checked);
      Ini.WriteBool('Ziel', 'Ueberschreiben', FChkOver.Checked);
      Ini.WriteBool('Ansicht', 'SelbstEinstellen', FChkExpert.Checked);
      if WindowState = wsNormal then
      begin
        Ini.WriteInteger('Fenster', 'Breite96', MulDiv(ClientWidth, 96, PixelsPerInch));
        Ini.WriteInteger('Fenster', 'Hoehe96', MulDiv(ClientHeight, 96, PixelsPerInch));
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do Log('Einstellungen nicht gespeichert: ' + E.Message);
  end;
end;

function TPackerForm.GetRules: TPackRules;
var r: Integer;
begin
  Result := Default(TPackRules);
  for r := 0 to ROLE_COUNT - 1 do
  begin
    Result.Folders[r] := Trim(FRows[r].Folder.Text);
    Result.Patterns[r] := Trim(FRows[r].Pattern.Text);
  end;
  Result.MixMaster := FChkMix.Checked;
  Result.SubFolders := FChkSub.Checked;
  if Result.MixMaster then Result.Folders[0] := '';
end;

function TPackerForm.GetOptions: TPackOptions;
begin
  Result := Default(TPackOptions);
  Result.Format := TPackFormat(EnsureRange(FCbFormat.ItemIndex, 0, 2));
  Result.AacKbps := 320;
  Result.FillSilence := FChkFill.Checked;
  Result.MixMaster := FChkMix.Checked;
end;

function TPackerForm.StemInfos: TStemInfoArray;
var r: Integer;
begin
  Result := DefaultStemInfo;
  for r := 1 to ROLE_COUNT - 1 do
  begin
    if Trim(FRows[r].StemName.Text) <> '' then
      Result[r - 1].Name := Trim(FRows[r].StemName.Text);
    Result[r - 1].Color := ColorToHex(FRows[r].ColorBox.Color);
  end;
end;

function TPackerForm.OutFileFor(Song: TPackSong): string;
var Dir: string;
begin
  if FRbFolder.Checked and (Trim(FEdOut.Text) <> '') then
    Dir := IncludeTrailingPathDelimiter(Trim(FEdOut.Text)) + Song.SubDir
  else
    Dir := ExtractFilePath(TagSourceFile(Song));
  Result := IncludeTrailingPathDelimiter(Dir) + Song.Name + '.stem.mp4';
end;

function TPackerForm.CheckInput(Quiet: Boolean): Boolean;
var
  Rules: TPackRules;
  r: Integer;
  Msg, Dir: string;
begin
  Rules := GetRules;
  Msg := '';
  for r := 0 to ROLE_COUNT - 1 do
  begin
    if (r = 0) and Rules.MixMaster then Continue;
    if not PatternValid(Rules.Patterns[r]) then
    begin
      Msg := Format(_('Im Muster von „%s“ fehlt der Stern * für den Songnamen.'), [RoleCaption(r)]);
      Break;
    end;
    Dir := RoleFolder(Rules, r);
    if (Dir = '') or not DirectoryExistsUTF8(Dir) then
    begin
      Msg := Format(_('Der Ordner von „%s“ fehlt oder existiert nicht.'), [RoleCaption(r)]);
      Break;
    end;
  end;
  if (Msg = '') and FRbFolder.Checked and (Trim(FEdOut.Text) = '') then
    Msg := _('Bitte einen Ausgabeordner angeben (oder „neben die Master-Datei“ wählen).');
  Result := Msg = '';
  if not Result and not Quiet then
    MessageDlg(APP_TITLE, Msg, mtWarning, [mbOK], 0);
end;

{ ============================================================================
  Songs suchen und anzeigen
  ============================================================================ }

procedure TPackerForm.ScanSongs;
begin
  FreeSongs(FSongs);
  FindSongs(GetRules, FSongs);
  Log(Format('Suche: %d Songs gefunden', [FSongs.Count]));
  ShowSongs;
end;

procedure TPackerForm.ShowSongs;
var
  i, r, Ready: Integer;
  S: TPackSong;
  It: TListItem;
  Why, Target: string;
  Opt: TPackOptions;
  Rules: TPackRules;
  Lists: array[0..ROLE_COUNT - 1] of TStringList;

  { Dateiliste der Rolle, erst bei Bedarf gelesen }
  function RoleList(Role: Integer): TStringList;
  var Paths: TStringList;
  begin
    if Lists[Role] = nil then
    begin
      Lists[Role] := TStringList.Create;
      Paths := TStringList.Create;
      try
        ListAudio(RoleFolder(Rules, Role), Rules.SubFolders, Lists[Role], Paths);
      finally
        Paths.Free;
      end;
    end;
    Result := Lists[Role];
  end;

  { fehlende Spuren mit gesuchtem Dateinamen und, wenn es eine gibt, einer
    ähnlich heissenden Datei. Details kommen ins Log. }
  function MissingText(Song: TPackSong): string;
  var
    q: Integer;
    Exp, Sim, Part: string;
  begin
    Result := '';
    for q := 0 to ROLE_COUNT - 1 do
      if (Song.Files[q] = '') and not ((q = 0) and Opt.MixMaster) then
      begin
        Exp := ExpectedName(Rules.Patterns[q], Song.Name);
        Sim := FindSimilar(RoleList(q), RoleFolder(Rules, q), Exp, Song);
        Part := Format(_('%s „%s“'), [RoleCaption(q), Exp]);
        if Sim <> '' then
          Part := Part + ' (' + Format(_('ähnlich: „%s“'), [ExtractFileName(Sim)]) + ')';
        if Result <> '' then Result := Result + ', ';
        Result := Result + Part;
        if Sim <> '' then
          Log(Format('  %s%s: %s fehlt, gesucht %s%s.*, ähnlich: %s',
            [Song.SubDir, Song.Name, RoleCaption(q), RoleFolder(Rules, q),
             Song.SubDir + Exp, RoleFolder(Rules, q) + Sim]))
        else
          Log(Format('  %s%s: %s fehlt, gesucht %s%s.*',
            [Song.SubDir, Song.Name, RoleCaption(q), RoleFolder(Rules, q),
             Song.SubDir + Exp]));
      end;
  end;

begin
  Opt := GetOptions;
  Rules := GetRules;
  for r := 0 to ROLE_COUNT - 1 do Lists[r] := nil;
  Ready := 0;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to FSongs.Count - 1 do
    begin
      S := TPackSong(FSongs[i]);
      It := FList.Items.Add;
      It.Caption := S.SubDir + S.Name;
      if Opt.MixMaster then
        It.SubItems.Add(Format('%d / 4', [S.StemCount]))
      else
        It.SubItems.Add(Format('%d / 5', [S.FoundCount]));
      Target := OutFileFor(S);
      if not SongReady(S, Opt, Why) then
        It.SubItems.Add(_('fehlt: ') + MissingText(S))
      else if FileExistsUTF8(Target) and not FChkOver.Checked then
        It.SubItems.Add(_('gibt es schon, wird übersprungen'))
      else
      begin
        if S.StemCount < 4 then
          It.SubItems.Add(_('bereit, still gefüllt: ') + MissingText(S))
        else
          It.SubItems.Add(_('bereit'));
        Inc(Ready);
      end;
      It.SubItems.Add(Target);
    end;
  finally
    FList.Items.EndUpdate;
    for r := 0 to ROLE_COUNT - 1 do Lists[r].Free;
  end;
  if FSongs.Count = 0 then
    FStatus.Caption := _('Keine Songs gefunden. Ordner und Muster prüfen (Stern * = Songname).')
  else
    FStatus.Caption := Format(_('%d Songs gefunden, %d bereit zum Packen.'), [FSongs.Count, Ready]);
end;

procedure TPackerForm.SetRowStatus(i: Integer; const S: string);
begin
  if (i >= 0) and (i < FList.Items.Count) then
  begin
    FList.Items[i].SubItems[COL_STATUS - 1] := S;
    FList.Items[i].MakeVisible(False);
  end;
end;

{ Längenprüfung: ffmpeg liest die Länge jeder Spur. Weicht eine Spur mehr
  als LENGTH_TOLERANCE vom Master ab (beim Mischen: von der längsten Spur),
  kommt ein Hinweis zurück, sonst ''. Gepackt wird trotzdem. }
function TPackerForm.CheckLengths(Song: TPackSong): string;
var
  Args: TStringList;
  Idx: array of Integer;
  D: TDurations;
  OutText, RefName, Part: string;
  r, k, Ref: Integer;
  RefLen, Diff: Double;
begin
  Result := '';
  Args := TStringList.Create;
  try
    Args.AddStrings(['-hide_banner', '-nostdin']);
    Idx := nil;
    for r := 0 to ROLE_COUNT - 1 do
      if Song.Files[r] <> '' then
      begin
        Args.AddStrings(['-i', Song.Files[r]]);
        SetLength(Idx, Length(Idx) + 1);
        Idx[High(Idx)] := r;
      end;
    if Length(Idx) < 2 then Exit;
    { nichts umwandeln (-t 0), nur die Längen aus der Ausgabe lesen }
    Args.AddStrings(['-t', '0', '-f', 'null', '-']);
    RunTool(Args, _('Längen prüfen'), OutText);
    if FCancel then Exit;
    D := ParseDurations(OutText, Length(Idx));
    { Bezug: der Master, sonst die längste Spur }
    Ref := -1;
    if Idx[0] = 0 then
      Ref := 0
    else
      for k := 0 to High(D) do
        if (D[k] >= 0) and ((Ref < 0) or (D[k] > D[Ref])) then Ref := k;
    if (Ref < 0) or (D[Ref] < 0) then Exit;
    RefLen := D[Ref];
    if Idx[0] = 0 then RefName := _('der Master') else RefName := _('die längste Spur');
    for k := 0 to High(D) do
    begin
      if (k = Ref) or (D[k] < 0) then Continue;
      Diff := D[k] - RefLen;
      if Abs(Diff) <= LENGTH_TOLERANCE then Continue;
      if Diff < 0 then
        Part := Format(_('%s ist %s s kürzer als %s'),
          [RoleCaption(Idx[k]), FormatFloat('0.0', -Diff), RefName])
      else
        Part := Format(_('%s ist %s s länger als %s'),
          [RoleCaption(Idx[k]), FormatFloat('0.0', Diff), RefName]);
      if Result <> '' then Result := Result + ', ';
      Result := Result + Part;
      Log(Format('Länge: %s %.2f s, Bezug %.2f s', [RoleCaption(Idx[k]), D[k], RefLen]));
    end;
  finally
    Args.Free;
  end;
end;

{ ============================================================================
  Packen
  ============================================================================ }

function TPackerForm.PackSong(Song: TPackSong; Row: Integer): Boolean;
var
  Args: TStringList;
  OutFile, TmpFile, MetaFile, OutText, Cover, Err, Src: string;
  Tags: TSrcTags;
  Meta: TStringList;
  Extra: TMp4TagArray;
  Code: Integer;
  Warn: string;

  procedure AddExtra(const AName, AValue: string; Free: Boolean);
  begin
    if AValue = '' then Exit;
    SetLength(Extra, Length(Extra) + 1);
    Extra[High(Extra)].Name := AName;
    Extra[High(Extra)].Value := AValue;
    Extra[High(Extra)].Freeform := Free;
  end;

begin
  Result := False;
  OutFile := OutFileFor(Song);
  Src := TagSourceFile(Song);
  ForceDirectories(ExtractFilePath(OutFile));
  TmpFile := ChangeFileExt(ChangeFileExt(OutFile, ''), '') + '.packer.tmp.mp4';
  MetaFile := IncludeTrailingPathDelimiter(GetTempDir) + 'stempacker-meta.txt';
  Log('--- ' + Song.SubDir + Song.Name + ' ---');
  Args := TStringList.Create;
  try
    { 1. Tags der Quelle lesen (BPM, Tonart, Label, ISRC, Titel) und
         schauen, ob sie ein Cover hat }
    DeleteFile(MetaFile);
    Args.AddStrings(['-hide_banner', '-nostdin', '-y', '-i', Src, '-f', 'ffmetadata', MetaFile]);
    Code := RunTool(Args, _('Tags lesen'), OutText);
    if FCancel then Exit;
    Tags := Default(TSrcTags);
    if (Code = 0) and FileExists(MetaFile) then
    begin
      Meta := TStringList.Create;
      try
        try
          Meta.LoadFromFile(MetaFile);
          Tags := ParseFFMetadata(Meta.Text);
        except
        end;
      finally
        Meta.Free;
      end;
      DeleteFile(MetaFile);
    end;
    Cover := '';
    if FChkCover.Checked and (Pos('(attached pic)', OutText) = 0) then
    begin
      Cover := FindFolderCover(ExtractFilePath(Src), Song.Name);
      if Cover <> '' then Log('Cover aus dem Ordner: ' + Cover);
    end;

    { 2. Längen vergleichen (nur Hinweis, gepackt wird trotzdem) }
    Warn := CheckLengths(Song);
    if FCancel then Exit;
    if Warn <> '' then Log('Achtung: ' + Warn);

    { 3. MP4 mit 5 Spuren }
    SetRowStatus(Row, _('wird gepackt ...'));
    BuildPackArgs(Song, GetOptions, Cover, TmpFile, Tags, Args);
    Code := RunTool(Args, Format(_('Packe %s'), [Song.Name]), OutText);
    if FCancel then
    begin
      DeleteFile(TmpFile);
      SetRowStatus(Row, _('abgebrochen'));
      Exit;
    end;
    if (Code <> 0) or not FileExists(TmpFile) then
    begin
      DeleteFile(TmpFile);
      SetRowStatus(Row, Format(_('Fehler: ffmpeg Code %d (siehe Log)'), [Code]));
      Exit;
    end;

    { 4. Stem-Block (Namen, Farben) und was ffmpeg nicht schreiben kann }
    Extra := nil;
    AddExtra('initialkey', Tags.Key, True);
    AddExtra(#$A9'pub', Tags.Publisher, False);
    AddExtra('ISRC', Tags.ISRC, True);
    if not InjectStemMetadata(TmpFile, BuildStemJSON(StemInfos), Extra, Err) then
    begin
      Log('Stem-Block fehlgeschlagen: ' + Err);
      DeleteFile(TmpFile);
      SetRowStatus(Row, _('Fehler: Stem-Block') + ' (' + Err + ')');
      Exit;
    end;
    if CountTracks(TmpFile) <> 5 then
    begin
      DeleteFile(TmpFile);
      SetRowStatus(Row, _('Fehler: Ergebnis hat nicht 5 Spuren'));
      Exit;
    end;
    if not ReplaceFileSafe(TmpFile, OutFile) then
    begin
      DeleteFile(TmpFile);
      SetRowStatus(Row, _('Fehler: Datei konnte nicht gespeichert werden'));
      Exit;
    end;
    Log('Fertig: ' + OutFile);
    if Warn <> '' then
    begin
      SetRowStatus(Row, _('fertig, Achtung: ') + Warn);
      Inc(FWarned);
    end
    else
      SetRowStatus(Row, _('fertig'));
    Result := True;
  finally
    Args.Free;
  end;
end;

procedure TPackerForm.PackAll;
var
  i, Done, Failed, Skipped: Integer;
  S: TPackSong;
  Why, LastOut: string;
  Opt: TPackOptions;
  T0: QWord;
begin
  if FBusy then Exit;
  if not CheckInput(False) then Exit;
  if not EnsureFFmpeg then Exit;
  SaveSettings;
  ScanSongs;
  if FSongs.Count = 0 then
  begin
    MessageDlg(APP_TITLE, FStatus.Caption, mtInformation, [mbOK], 0);
    Exit;
  end;
  Opt := GetOptions;
  Log(Format('Start: %d Songs, Format %d, Stems: %s', [FSongs.Count, Ord(Opt.Format),
    BuildStemJSON(StemInfos)]));
  Done := 0; Failed := 0; Skipped := 0;
  FWarned := 0;
  LastOut := '';
  FCancel := False;
  T0 := GetTickCount64;
  SetBusy(True);
  try
    for i := 0 to FSongs.Count - 1 do
    begin
      if FCancel then Break;
      S := TPackSong(FSongs[i]);
      if not SongReady(S, Opt, Why) or
         (FileExistsUTF8(OutFileFor(S)) and not FChkOver.Checked) then
      begin
        Inc(Skipped);
        Continue;
      end;
      FStatus.Caption := Format(_('Song %d von %d: %s'), [i + 1, FSongs.Count, S.Name]);
      if PackSong(S, i) then
      begin
        Inc(Done);
        LastOut := OutFileFor(S);
      end
      else if not FCancel then
        Inc(Failed);
    end;
  finally
    SetBusy(False);
  end;
  Log(Format('Ende: %d fertig (%d mit Längen-Warnung), %d Fehler, %d übersprungen, %.0f s',
    [Done, FWarned, Failed, Skipped, (GetTickCount64 - T0) / 1000]));
  FStatus.Caption := Format(_('%d fertig, %d Fehler, %d übersprungen.'), [Done, Failed, Skipped]);
  if FCloseAfter then
  begin
    Application.QueueAsyncCall(@DeferredClose, 0);
    Exit;
  end;
  if FCancel then Exit;
  Why := '';
  if FWarned > 0 then
    Why := LineEnding + LineEnding + Format(_('Längen-Warnung bei %d Song(s): eine Spur ist kürzer oder länger als der Rest (siehe Liste). Bitte in Traktor anhören, ob alles zusammenpasst.'), [FWarned]);
  if MessageDlg(APP_TITLE, Format(_('%d Stem-Dateien erstellt, %d Fehler, %d übersprungen.'),
       [Done, Failed, Skipped]) + Why + LineEnding + LineEnding +
       _('Die Dateien lassen sich direkt in Traktor laden. Ordner jetzt öffnen?'),
       mtInformation, [mbYes, mbNo], 0) = mrYes then
    if LastOut <> '' then OpenDocument(ExtractFilePath(LastOut));
end;

procedure TPackerForm.SetBusy(B: Boolean);
begin
  FBusy := B;
  if B then Screen.Cursor := crAppStart else Screen.Cursor := crDefault;
  UpdateEnabled;
end;

{ ============================================================================
  Log und ffmpeg
  ============================================================================ }

procedure TPackerForm.Log(const S: string);
var
  F: TextFile;
  Dir: string;
begin
  try
    if FLogFile = '' then
    begin
      Dir := ExtractFilePath(IniFileName) + 'logs' + PathDelim;
      ForceDirectories(Dir);
      FLogFile := Dir + 'StemPacker.log';
      { nicht endlos wachsen lassen }
      if FileExists(FLogFile) and (FileSize(FLogFile) > 2 * 1024 * 1024) then
        DeleteFile(FLogFile);
    end;
    AssignFile(F, FLogFile);
    if FileExists(FLogFile) then Append(F) else Rewrite(F);
    try
      WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + S);
    finally
      CloseFile(F);
    end;
  except
  end;
end;

function TPackerForm.FindFFmpeg: string;
const
  Candidates: array[0..6] of string = (
    'tools\ffmpeg.exe', 'ffmpeg.exe', '..\tools\ffmpeg.exe', 'bin\ffmpeg.exe',
    '..\ffmpeg.exe', '..\..\tools\ffmpeg.exe', 'ffmpeg\bin\ffmpeg.exe');
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
    S := ExpandFileName(Base + SetDirSeparators(Candidates[i]));
    if FileExists(S) then Exit(S);
  end;
  Result := FindDefaultExecutablePath({$IFDEF WINDOWS}'ffmpeg.exe'{$ELSE}'ffmpeg'{$ENDIF});
end;

function TPackerForm.EnsureFFmpeg: Boolean;
var
  Dlg: TOpenDialog;
  Ini: TIniFile;
begin
  if (FFFmpeg <> '') and FileExists(FFFmpeg) then Exit(True);
  MessageDlg(APP_TITLE, _('ffmpeg.exe wurde nicht gefunden.') + LineEnding +
    _('Bitte im nächsten Fenster die ffmpeg.exe auswählen (z. B. aus StemMaker\tools\).'),
    mtInformation, [mbOK], 0);
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'ffmpeg.exe';
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|*.exe|*.exe';
    if Dlg.Execute then FFFmpeg := Dlg.FileName;
  finally
    Dlg.Free;
  end;
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
  Log('ffmpeg = ' + FFFmpeg);
  Result := FFFmpeg <> '';
end;

{ Startet ffmpeg ohne Konsolenfenster, liest die Ausgabe laufend mit (nie
  poWaitOnExit zusammen mit Pipes) und hält das Fenster bedienbar. }
function TPackerForm.RunTool(Args: TStrings; const What: string; out OutText: string): Integer;
var
  P: TProcessUTF8;
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
  Cmd := '"' + FFFmpeg + '"';
  for i := 0 to Args.Count - 1 do
    if Pos(' ', Args[i]) > 0 then Cmd := Cmd + ' "' + Args[i] + '"'
    else Cmd := Cmd + ' ' + Args[i];
  Log('  > ' + Cmd);
  T0 := GetTickCount64;
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := FFFmpeg;
    P.Parameters.Assign(Args);
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    P.ShowWindow := swoHIDE;
    try
      P.Execute;
    except
      on E: Exception do
      begin
        Log('  ! Start fehlgeschlagen: ' + E.Message);
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
        Log('  ! abgebrochen');
        Exit(-1);
      end;
      Application.ProcessMessages;
      Sleep(30);
    end;
    Drain;
    Result := P.ExitStatus;
  finally
    P.Free;
  end;
  Log(Format('  < %s: Code %d nach %.1f s', [What, Result, (GetTickCount64 - T0) / 1000]));
  if Result <> 0 then
    Log(Copy(OutText, Max(1, Length(OutText) - 6000), MaxInt));
end;

{ ============================================================================
  Ereignisse
  ============================================================================ }

procedure TPackerForm.PresetChange(Sender: TObject);
begin
  if FCbPreset.ItemIndex <= High(PRESETS) then
    ApplyPreset(FCbPreset.ItemIndex);
end;

procedure TPackerForm.PatternChange(Sender: TObject);
begin
  if not FLoading then
    FCbPreset.ItemIndex := PRESET_CUSTOM;
end;

procedure TPackerForm.MixClick(Sender: TObject);
begin
  UpdateEnabled;
end;

procedure TPackerForm.ExpertClick(Sender: TObject);
begin
  if FLoading then Exit;
  ShowExpert;
end;

procedure TPackerForm.BtnPickClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  if FBusy then Exit;
  Dlg := TSelectDirectoryDialog.Create(nil);
  try
    Dlg.Title := _('Ordner mit den Spuren wählen');
    if DirectoryExistsUTF8(FDetect.Hint) then
      Dlg.InitialDir := FDetect.Hint
    else if DirectoryExistsUTF8(FRows[0].Folder.Text) then
      Dlg.InitialDir := FRows[0].Folder.Text;
    if Dlg.Execute then
      RunDetect(ExcludeTrailingPathDelimiter(Dlg.FileName));
  finally
    Dlg.Free;
  end;
end;

procedure TPackerForm.OutModeClick(Sender: TObject);
begin
  UpdateEnabled;
end;

procedure TPackerForm.BrowseClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
  Role: Integer;
begin
  Role := TComponent(Sender).Tag;
  Dlg := TSelectDirectoryDialog.Create(nil);
  try
    Dlg.Title := RoleCaption(Role) + ': ' + _('Ordner wählen');
    if DirectoryExistsUTF8(FRows[Role].Folder.Text) then
      Dlg.InitialDir := FRows[Role].Folder.Text
    else if DirectoryExistsUTF8(FRows[0].Folder.Text) then
      Dlg.InitialDir := FRows[0].Folder.Text;
    if Dlg.Execute then
      FRows[Role].Folder.Text := ExcludeTrailingPathDelimiter(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TPackerForm.BtnOutClick(Sender: TObject);
var Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(nil);
  try
    Dlg.Title := _('Ausgabeordner wählen');
    if DirectoryExistsUTF8(FEdOut.Text) then Dlg.InitialDir := FEdOut.Text;
    if Dlg.Execute then
    begin
      FEdOut.Text := ExcludeTrailingPathDelimiter(Dlg.FileName);
      FRbFolder.Checked := True;
      UpdateEnabled;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TPackerForm.ColorClick(Sender: TObject);
var
  Dlg: TColorDialog;
  Box: TPanel;
begin
  if FBusy then Exit;
  Box := TPanel(Sender);
  Dlg := TColorDialog.Create(nil);
  try
    Dlg.Color := Box.Color;
    if Dlg.Execute then Box.Color := Dlg.Color;
  finally
    Dlg.Free;
  end;
end;

procedure TPackerForm.BtnScanClick(Sender: TObject);
begin
  if FBusy then Exit;
  if not CheckInput(False) then Exit;
  SaveSettings;
  Screen.Cursor := crHourGlass;
  try
    ScanSongs;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TPackerForm.BtnStartClick(Sender: TObject);
begin
  PackAll;
end;

procedure TPackerForm.BtnCancelClick(Sender: TObject);
begin
  FCancel := True;
  FStatus.Caption := _('Breche ab ...');
end;

procedure TPackerForm.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and (Item <> nil) and (Item.SubItems.Count >= COL_STATUS) then
  begin
    FStatus.Caption := Item.Caption + ':  ' + Item.SubItems[COL_STATUS - 1];
    FStatus.Hint := FStatus.Caption;
    FStatus.ShowHint := True;
  end;
end;

{ Info mit Version, Projektseite und Dank }
procedure TPackerForm.BtnInfoClick(Sender: TObject);
begin
  MessageDlg(APP_TITLE,
    APP_TITLE + ' ' + APP_VER + LineEnding + LineEnding +
    _('Packt fertige Einzelspuren (Master und 4 Stems) ohne KI-Trennung zu Traktor-Stem-Dateien.') +
    LineEnding + LineEnding + PAGE_URL + LineEnding + LineEnding +
    _('Danke an Cuiusquemodi für die Idee, den Test mit 178 Songs und die vielen Rückmeldungen.') +
    LineEnding + LineEnding +
    _('Frei unter der MIT-Lizenz. Enthält ffmpeg (LGPL).'),
    mtInformation, [mbOK], 0);
end;

procedure TPackerForm.BtnLogClick(Sender: TObject);
begin
  Log('Log geöffnet');
  if FLogFile <> '' then OpenDocument(FLogFile);
end;

{ Ko-fi-Knopf unten rechts: dunkle Pille mit dem Programmsymbol (Stil E,
  uStatusDraw, gleich wie StemMaker und StemTagger) }
procedure TPackerForm.KofiPaint(Sender: TObject);
begin
  FKofi.Canvas.Font.Style := [fsBold];
  DrawKofiButton(FKofi.Canvas, FKofi.ClientRect, _('Kaffee spendieren'),
    FKofiHover, TPanel(FKofi.Parent).Color, Screen.PixelsPerInch, Application.Icon);
end;

procedure TPackerForm.KofiClick(Sender: TObject);
begin
  OpenURL(KOFI_URL);
end;

procedure TPackerForm.KofiEnter(Sender: TObject);
begin
  FKofiHover := True;
  FKofi.Invalidate;
end;

procedure TPackerForm.KofiLeave(Sender: TObject);
begin
  FKofiHover := False;
  FKofi.Invalidate;
end;

{ Ordner aufs Fenster ziehen = Master-Ordner (beim Mischen Stem-1-Ordner) }
procedure TPackerForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  P: string;
  Role: Integer;
begin
  if FBusy or (Length(FileNames) = 0) then Exit;
  P := FileNames[0];
  if not DirectoryExistsUTF8(P) then P := ExtractFileDir(P);
  P := ExcludeTrailingPathDelimiter(P);
  { Einfach-Modus: Benennung erkennen. Mit „selbst einstellen“ wie bisher:
    der Ordner kommt in die erste Zeile. }
  if not FChkExpert.Checked then
  begin
    RunDetect(P);
    Exit;
  end;
  if FChkMix.Checked then Role := 1 else Role := 0;
  FRows[Role].Folder.Text := ExcludeTrailingPathDelimiter(P);
  if CheckInput(True) then BtnScanClick(nil);
end;

procedure TPackerForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FBusy then
  begin
    FCancel := True;
    FCloseAfter := True;
    FStatus.Caption := _('Breche ab ...');
    CanClose := False;
    Exit;
  end;
  SaveSettings;
  Log('Beendet');
  CanClose := True;
end;

procedure TPackerForm.DeferredClose(Data: PtrInt);
begin
  Close;
end;

end.
