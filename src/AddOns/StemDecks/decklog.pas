{ ============================================================================
  decklog.pas  -  Sprache (DE/EN) und Protokoll für Elospeed StemDecks

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Sprache:
    T('Deutsch', 'English') liefert den Text in der eingestellten Sprache.
    Standard: Deutsch, wenn Windows auf Deutsch läuft, sonst Englisch.
    Umschalten über StemDecks.ini  [Allgemein] Sprache=de|en
    (im Fenster "EINSTELLUNGEN", gilt nach einem Neustart).

  Protokoll (Echtzeit-Log):
    Jede Zeile geht sofort
      - in die Datei  logs\StemDecks.log  neben der exe
        (ist der Ordner schreibgeschützt: %APPDATA%\ElospeedStemDecks\logs\)
      - und in das Log-Fenster (Knopf LOG), falls es offen ist.
    Wird die Datei grösser als 2 MB, wird sie beim Start zu
    StemDecks.old.log umbenannt. Bei Problemen schickt der Nutzer einfach
    diese Datei.

  Versionen:
    0.2  (10.10.2026)  Erste Version
  ============================================================================ }
unit decklog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLIntf;

var
  LangEN: Boolean = False;   // True = englische Oberfläche

{ Text in der eingestellten Sprache }
function T(const DE, EN: string): string;

{ Sprache aus der ini bzw. von Windows bestimmen (einmal beim Start) }
procedure InitLanguage(const IniLang: string);

{ Protokoll starten (Dateiname festlegen, Kopfzeilen schreiben) }
procedure LogInit(const AppTitle, AppVer: string);
{ Eine Zeile protokollieren (mit Uhrzeit) }
procedure Log(const Msg: string);
{ Mehrzeiligen Text protokollieren (z.B. Ausgabe von ffmpeg), eingerückt }
procedure LogBlock(const Text: string);
{ Pfad der Logdatei }
function LogFileName: string;
{ Log-Fenster zeigen (wird beim ersten Aufruf erzeugt) }
procedure ShowLogWindow;

implementation

uses
  Windows, LazFileUtils;

{ Fehlt in der Windows-Unit von Free Pascal: Sprache der Windows-Oberfläche }
function GetUserDefaultUILanguage: Word; stdcall; external 'kernel32.dll';

var
  FLogFile: string = '';
  FLogForm: TForm = nil;
  FLogMemo: TMemo = nil;

function T(const DE, EN: string): string;
begin
  if LangEN then Result := EN else Result := DE;
end;

procedure InitLanguage(const IniLang: string);
begin
  if SameText(IniLang, 'en') then LangEN := True
  else if SameText(IniLang, 'de') then LangEN := False
  else
    { Hauptsprache von Windows: $07 = Deutsch }
    LangEN := (GetUserDefaultUILanguage and $3FF) <> $07;
end;

function LogFileName: string;
begin
  Result := FLogFile;
end;

{ Prüft, ob in einen Ordner geschrieben werden kann }
function DirWritable(const Dir: string): Boolean;
var
  F: TFileStream;
  Probe: string;
begin
  Result := False;
  try
    ForceDirectories(Dir);
    Probe := IncludeTrailingPathDelimiter(Dir) + 'schreibtest.tmp';
    F := TFileStream.Create(Probe, fmCreate);
    F.Free;
    SysUtils.DeleteFile(Probe);
    Result := True;
  except
    Result := False;
  end;
end;

procedure AppendLine(const S: string);
var
  F: TFileStream;
  Line: string;
begin
  if FLogFile <> '' then
  try
    if FileExists(FLogFile) then
      F := TFileStream.Create(FLogFile, fmOpenWrite or fmShareDenyNone)
    else
      F := TFileStream.Create(FLogFile, fmCreate);
    try
      F.Seek(0, soEnd);
      Line := S + LineEnding;
      F.WriteBuffer(Line[1], Length(Line));
    finally
      F.Free;
    end;
  except
    { Log darf das Programm nie stören }
  end;
  if FLogMemo <> nil then
    FLogMemo.Lines.Add(S);
end;

procedure LogInit(const AppTitle, AppVer: string);
var
  Dir: string;
begin
  Dir := ExtractFilePath(Application.ExeName) + 'logs';
  if not DirWritable(Dir) then
    Dir := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
           'ElospeedStemDecks' + PathDelim + 'logs';
  ForceDirectories(Dir);
  FLogFile := IncludeTrailingPathDelimiter(Dir) + 'StemDecks.log';
  { Zu gross geworden? Alte Datei beiseite legen }
  try
    if FileExists(FLogFile) and (FileSizeUtf8(FLogFile) > 2 * 1024 * 1024) then
    begin
      SysUtils.DeleteFile(ChangeFileExt(FLogFile, '.old.log'));
      RenameFile(FLogFile, ChangeFileExt(FLogFile, '.old.log'));
    end;
  except
  end;
  AppendLine('');
  AppendLine('==================================================================');
  Log(Format('%s %s gestartet / started', [AppTitle, AppVer]));
  Log('exe : ' + Application.ExeName);
  Log(Format('Windows %d.%d (Build %d)', [Win32MajorVersion, Win32MinorVersion, Win32BuildNumber]));
  if LangEN then Log('Sprache / language: en') else Log('Sprache / language: de');
end;

procedure Log(const Msg: string);
begin
  AppendLine(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + Msg);
end;

procedure LogBlock(const Text: string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    L.Text := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
    for i := 0 to L.Count - 1 do
      if Trim(L[i]) <> '' then AppendLine('      | ' + L[i]);
  finally
    L.Free;
  end;
end;

{ --- Log-Fenster -------------------------------------------------------- }

type
  TLogButtons = class
    procedure OpenFolder(Sender: TObject);
    procedure Copy(Sender: TObject);
  end;

var
  FButtons: TLogButtons = nil;

procedure TLogButtons.OpenFolder(Sender: TObject);
begin
  OpenDocument(ExtractFilePath(FLogFile));
end;

procedure TLogButtons.Copy(Sender: TObject);
begin
  FLogMemo.SelectAll;
  FLogMemo.CopyToClipboard;
  FLogMemo.SelLength := 0;
end;

procedure ShowLogWindow;
var
  Pnl: TPanel;
  B: TButton;
begin
  if FLogForm = nil then
  begin
    FButtons := TLogButtons.Create;
    FLogForm := TForm.CreateNew(Application);
    FLogForm.Caption := 'StemDecks - Log';
    FLogForm.Width := 820;
    FLogForm.Height := 480;
    FLogForm.Position := poScreenCenter;

    Pnl := TPanel.Create(FLogForm);
    Pnl.Parent := FLogForm;
    Pnl.Align := alBottom;
    Pnl.Height := 40;
    Pnl.BevelOuter := bvNone;

    B := TButton.Create(FLogForm);
    B.Parent := Pnl;
    B.SetBounds(8, 6, 180, 28);
    B.Caption := T('Log-Ordner öffnen', 'Open log folder');
    B.OnClick := @FButtons.OpenFolder;

    B := TButton.Create(FLogForm);
    B.Parent := Pnl;
    B.SetBounds(196, 6, 180, 28);
    B.Caption := T('Alles kopieren', 'Copy all');
    B.OnClick := @FButtons.Copy;

    FLogMemo := TMemo.Create(FLogForm);
    FLogMemo.Parent := FLogForm;
    FLogMemo.Align := alClient;
    FLogMemo.ReadOnly := True;
    FLogMemo.ScrollBars := ssBoth;
    FLogMemo.WordWrap := False;
    FLogMemo.Font.Name := 'Consolas';
    { bisherigen Inhalt der Datei anzeigen }
    try
      if FileExists(FLogFile) then FLogMemo.Lines.LoadFromFile(FLogFile);
    except
    end;
  end;
  FLogForm.Show;
  FLogForm.BringToFront;
  FLogMemo.SelStart := Length(FLogMemo.Text);
end;

finalization
  FButtons.Free;
end.
