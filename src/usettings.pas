{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : usettings.pas  (Unit uSettings)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Das Fenster "Einstellungen" (Zahnrad-Button im Hauptfenster).

  Im Hauptfenster bleibt nur, was man pro Umwandlung ändert
  (Ausgabeordner, Modell, Format, Club-Pegel, Bass-Fix, Herunterfahren).
  Alles, was man einmal einstellt und dann vergisst, steht hier:
    - Umwandlung: Teile (Kerne), Überschreiben, Unterordner nachbauen,
                  PC wach halten
    - Engine:     Turbo (StemOnnx) oder Klassisch (demucs.cpp), Gerät für
                  Turbo, Knopf "Vortest ..." (ab 2.0, siehe uTurboTest)
    - Stems:      Namen und Farben der 4 Stems (so zeigt Traktor sie an)
    - Programm:   Sprache, beim Start nach Updates suchen, Symbol im
                  Infobereich (neben der Uhr, siehe uMain)
    - Werkzeuge:  wo ffmpeg, demucs.cpp und die Modelle liegen (nur Anzeige,
                  ändern geht wie bisher in StemMaker.ini, Abschnitt [Tools])
  Unten: "Standard wiederherstellen", OK, Abbrechen.

  Die Werte kommen als TStemPrefs-Record vom Hauptfenster und gehen nur
  bei OK zurück. Gespeichert (StemMaker.ini) wird wie bisher vom
  Hauptfenster. Ausnahme: Sprache, Update-Prüfung und Engine schreibt
  dieses Fenster bei OK selbst (die haben eigene Funktionen in uLangUI,
  uUpdate und uStemJob.SaveTurboSettings).

  Das Fenster wird im Code aufgebaut (keine .lfm-Datei), wie das
  Info-Fenster.
  ============================================================================ }
unit uSettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Spin,
  Buttons, Dialogs, LCLIntf, uStemJob;

type
  { Die Einstellungen, die dieses Fenster bearbeitet }
  TStemPrefs = record
    Threads    : Integer;                 // Teile, die demucs gleichzeitig rechnet
    ThreadsAuto: Boolean;                 // Teile automatisch wählen
    Overwrite  : Boolean;                 // vorhandene .stem.mp4 überschreiben
    KeepTree   : Boolean;                 // Unterordner im Ausgabeordner nachbauen
    KeepAwake  : Boolean;                 // PC während der Arbeit wach halten
    TrayMinimize: Boolean;                // minimiert: nur noch Symbol neben der Uhr
    TrayNotify : Boolean;                 // Meldung neben der Uhr, wenn alles fertig ist
    Engine     : TStemEngine;             // Turbo oder Klassisch (ab 2.0)
    TurboDevice: TTurboDevice;            // Turbo: automatisch oder nur CPU
    StemNames  : array[0..3] of string;   // Drums, Bass, Other, Vox
    StemColors : array[0..3] of TColor;
  end;

{ Standardwerte (wie bei einer frischen Installation) }
function DefaultStemPrefs: TStemPrefs;

{ Fenster zeigen. True = OK gedrückt, P enthält dann die neuen Werte.
  BesideInput: im Hauptfenster ist "neben der Originaldatei speichern" an
  -> "Unterordner nachbauen" wird ausgegraut (geht nur mit Ausgabeordner).
  Die drei Pfade werden nur angezeigt. }
function ShowSettingsDialog(var P: TStemPrefs; BesideInput: Boolean;
  const FFmpegExe, DemucsDir, ModelsDir: string): Boolean;

{ Zahnrad-Symbol auf einen Button legen (für den Button im Hauptfenster) }
procedure LoadGearGlyph(Btn: TBitBtn);

implementation

uses
  uLang, uLangUI, uUpdate, uTurboTest;

{$I gearicon.inc}

type
  TfrmSettings = class(TForm)
  private
    FLangCodes: TStringList;      // Sprach-Codes in der Reihenfolge von cbLang
    FNextTop: Integer;            // Top für die nächste Gruppe (NewGroup)
    seThreads: TSpinEdit;
    chkAutoThreads: TCheckBox;
    lblCores: TLabel;
    chkOverwrite, chkKeepTree, chkKeepAwake: TCheckBox;
    edtStem: array[0..3] of TEdit;
    clrStem: array[0..3] of TColorButton;
    cbLang: TComboBox;
    chkAutoUpdate: TCheckBox;
    chkTrayMinimize, chkTrayNotify: TCheckBox;
    cbEngine, cbDevice: TComboBox;
    lblTurbo: TLabel;
    procedure chkAutoThreadsChange(Sender: TObject);
    procedure cbEngineChange(Sender: TObject);
    procedure btnVortestClick(Sender: TObject);
    procedure ShowTurboSummary;
    procedure seThreadsChange(Sender: TObject);
    procedure btnDefaultsClick(Sender: TObject);
    procedure btnTraktorColorsClick(Sender: TObject);
    procedure btnProgDirClick(Sender: TObject);
    function NewGroup(const ACaption: string; AHeight: Integer): TGroupBox;
    function NewCheck(AParent: TWinControl; X, Y: Integer;
      const ACaption, AHint: string): TCheckBox;
    function NewLabel(AParent: TWinControl; X, Y: Integer;
      const ACaption: string): TLabel;
    procedure ShowPrefs(const P: TStemPrefs);
  public
    constructor CreateSettings(BesideInput: Boolean;
      const FFmpegExe, DemucsDir, ModelsDir: string);
    destructor Destroy; override;
    procedure SetPrefs(const P: TStemPrefs);
    function GetPrefs: TStemPrefs;
    procedure SaveProgramPrefs;
  end;

{ '#RRGGBB' (wie Traktor) -> TColor ($00BBGGRR). Ungültig -> clBlack }
function HexToCol(const S: string): TColor;
var
  V: LongInt;
begin
  Result := clBlack;
  if (Length(S) = 7) and (S[1] = '#') and TryStrToInt('$' + Copy(S, 2, 6), V) then
    Result := TColor(((V shr 16) and $FF) or (V and $FF00) or ((V and $FF) shl 16));
end;

function DefaultStemPrefs: TStemPrefs;
var
  D: TStemSettings;
  I: Integer;
begin
  D := DefaultStemSettings;
  Result.Threads := AutoThreads;
  Result.ThreadsAuto := True;
  Result.Overwrite := False;
  Result.KeepTree := True;
  Result.KeepAwake := True;
  Result.TrayMinimize := False;    // aus: sonst sucht man das Fenster
  Result.TrayNotify := True;
  Result.Engine := D.Engine;
  Result.TurboDevice := D.TurboDevice;
  for I := 0 to 3 do
  begin
    Result.StemNames[I] := D.Stems[I].Name;
    Result.StemColors[I] := HexToCol(D.Stems[I].Color);
  end;
end;

procedure LoadGearGlyph(Btn: TBitBtn);
var
  MS: TMemoryStream;
  Png: TPortableNetworkGraphic;
begin
  MS := TMemoryStream.Create;
  Png := TPortableNetworkGraphic.Create;
  try
    MS.WriteBuffer(GEAR_PNG[0], Length(GEAR_PNG));
    MS.Position := 0;
    Png.LoadFromStream(MS);
    Btn.Glyph.Assign(Png);
  finally
    Png.Free;
    MS.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Hilfsfunktionen zum Aufbau
  --------------------------------------------------------------------------- }
function TfrmSettings.NewGroup(const ACaption: string; AHeight: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  { alTop ordnet nach Top: jede neue Gruppe kommt unter die bisherigen }
  Result.Top := FNextTop;
  Inc(FNextTop, AHeight + 10);
  Result.Height := AHeight;
  Result.BorderSpacing.Left := 10;
  Result.BorderSpacing.Right := 10;
  Result.BorderSpacing.Top := 6;
  Result.Caption := ACaption;
end;

function TfrmSettings.NewCheck(AParent: TWinControl; X, Y: Integer;
  const ACaption, AHint: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := AHint <> '';
end;

function TfrmSettings.NewLabel(AParent: TWinControl; X, Y: Integer;
  const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := ACaption;
end;

constructor TfrmSettings.CreateSettings(BesideInput: Boolean;
  const FFmpegExe, DemucsDir, ModelsDir: string);
const
  { Spalten für die 4 Stems: 2 x 2 }
  COL_X: array[0..3] of Integer = (12, 300, 12, 300);
  ROW_Y: array[0..3] of Integer = (6, 6, 40, 40);
var
  gb: TGroupBox;
  pnlBottom: TPanel;
  btnOK, btnCancel, btnDefaults, btnProgDir, btnTraktor, btnTest: TButton;
  lbl: TLabel;
  edt: TEdit;
  I: Integer;
  ThreadHint: string;

  procedure PathRow(Y: Integer; const ACaption, APath: string);
  begin
    NewLabel(gb, 12, Y + 4, ACaption);
    edt := TEdit.Create(Self);
    edt.Parent := gb;
    edt.SetBounds(110, Y, 460, 25);
    edt.ReadOnly := True;                  // nur Anzeige, markieren/kopieren geht
    edt.Color := clBtnFace;
    edt.Text := APath;
    edt.Hint := APath;
    edt.ShowHint := True;
  end;

begin
  inherited CreateNew(nil);
  Caption := _('Einstellungen');
  Position := poMainFormCenter;
  BorderStyle := bsDialog;
  Width := 600;
  Height := 716;
  ShowHint := True;

  { --- Umwandlung --- }
  gb := NewGroup(_('Umwandlung'), 132);
  ThreadHint := _('Wie viele Teile des Songs demucs gleichzeitig rechnet. ' +
    'Jeder Teil nutzt zusätzlich mehrere Kerne und braucht gut 2 GB RAM.');
  lbl := NewLabel(gb, 12, 10, _('Teile:'));
  lbl.Hint := ThreadHint;
  lbl.ShowHint := True;
  seThreads := TSpinEdit.Create(Self);
  seThreads.Parent := gb;
  seThreads.SetBounds(110, 6, 60, 25);
  seThreads.MinValue := 1;
  seThreads.MaxValue := TThread.ProcessorCount * 2;
  if seThreads.MaxValue < 1 then seThreads.MaxValue := 1;
  seThreads.Hint := ThreadHint;
  seThreads.ShowHint := True;
  chkAutoThreads := NewCheck(gb, 180, 8, _('Auto'),
    _('Auto: so viele Teile wie der Prozessor echte Kerne hat (höchstens 4) ' +
    'und der Arbeitsspeicher verkraftet'));
  lblCores := NewLabel(gb, 250, 10, '');
  chkOverwrite := NewCheck(gb, 12, 38,
    _('vorhandene Stem-Dateien überschreiben'), '');
  chkKeepTree := NewCheck(gb, 12, 62,
    _('Unterordner im Ausgabeordner nachbauen'),
    _('Bei ganzen Ordnern: Musik\House\2024\track.mp3 wird zu ' +
    '<Ausgabeordner>\House\2024\track.stem.mp4'));
  if BesideInput then
  begin
    { geht nur mit eigenem Ausgabeordner }
    chkKeepTree.Enabled := False;
    chkKeepTree.Hint := _('Nur mit eigenem Ausgabeordner (im Hauptfenster ' +
      '"neben der Originaldatei speichern" ist an).');
  end;
  chkKeepAwake := NewCheck(gb, 12, 86,
    _('PC während der Konvertierung wach halten (kein Standby)'),
    _('Verhindert den Ruhezustand und setzt den Energiesparmodus ' +
    'vorübergehend aus.') + LineEnding + _('Danach wird alles wieder so ' +
    'eingestellt wie vorher. Der Bildschirm darf ausgehen.'));

  { --- Engine (ab 2.0) --- }
  gb := NewGroup(_('Engine (trennt die Stems)'), 106);
  NewLabel(gb, 12, 10, _('Engine:'));
  cbEngine := TComboBox.Create(Self);
  cbEngine.Parent := gb;
  cbEngine.Style := csDropDownList;
  cbEngine.SetBounds(110, 6, 300, 25);
  cbEngine.Items.Add(_('Turbo (schnell, Standard)'));
  cbEngine.Items.Add(_('Klassisch (demucs.cpp, wie bis 1.9)'));
  cbEngine.Hint := _('Beide rechnen dasselbe Modell, die Stems sind gleich. ' +
    'Turbo ist auf der CPU etwa 5-8x schneller und kann die Grafikkarte nutzen.') +
    LineEnding + _('Klappt Turbo bei einer Datei nicht, nimmt StemMaker für ' +
    'diese Datei von selbst Klassisch. htdemucs v3 rechnet immer klassisch.');
  cbEngine.ShowHint := True;
  NewLabel(gb, 12, 40, _('Gerät:'));
  cbDevice := TComboBox.Create(Self);
  cbDevice.Parent := gb;
  cbDevice.Style := csDropDownList;
  cbDevice.SetBounds(110, 36, 300, 25);
  cbDevice.Items.Add(_('Automatisch (Grafikkarte, wenn sie mitmacht)'));
  cbDevice.Items.Add(_('Nur CPU'));
  cbDevice.Hint := _('Automatisch: Die Grafikkarte wird nur genommen, wenn sie ' +
    'im Test gleiche Stems liefert und schneller ist als die CPU (Beta).');
  cbDevice.ShowHint := True;
  btnTest := TButton.Create(Self);
  btnTest.Parent := gb;
  btnTest.SetBounds(420, 6, 150, 26);
  btnTest.Caption := _('Vortest ...');
  btnTest.Hint := _('Misst CPU und Grafikkarte und sagt, wie lange ein Track ' +
    'auf diesem PC etwa dauert');
  btnTest.ShowHint := True;
  btnTest.OnClick := @btnVortestClick;
  { Ergebnis des Vortests, bis zwei Zeilen (auf Windows war eine Zeile
    zu kurz und unten abgeschnitten) }
  lblTurbo := NewLabel(gb, 12, 64, '');
  lblTurbo.AutoSize := False;
  lblTurbo.WordWrap := True;
  lblTurbo.SetBounds(12, 64, 560, 30);
  lblTurbo.Font.Color := clGrayText;
  lblTurbo.ShowHint := True;

  { --- Stems --- }
  gb := NewGroup(_('Stems (Namen und Farben, so zeigt Traktor sie an)'), 118);
  for I := 0 to 3 do
  begin
    NewLabel(gb, COL_X[I], ROW_Y[I] + 4, IntToStr(I + 1) + ':');
    edtStem[I] := TEdit.Create(Self);
    edtStem[I].Parent := gb;
    edtStem[I].SetBounds(COL_X[I] + 22, ROW_Y[I], 180, 25);
    edtStem[I].MaxLength := 32;
    clrStem[I] := TColorButton.Create(Self);
    clrStem[I].Parent := gb;
    clrStem[I].SetBounds(COL_X[I] + 208, ROW_Y[I], 40, 25);
    clrStem[I].BorderWidth := 2;
    clrStem[I].ButtonColorSize := 16;
    clrStem[I].Hint := _('Farbe wählen');
    clrStem[I].ShowHint := True;
  end;
  { Knopf: Farben wie in Traktors eigenen Stem-Dateien. Die Symbole
    (Trommel, Lautsprecher, Welle, Mikrofon) zeigt Traktor fest nach
    Platz 1-4, das Stem-Format kennt nur Name und Farbe. }
  btnTraktor := TButton.Create(Self);
  btnTraktor.Parent := gb;
  btnTraktor.SetBounds(12, 72, 190, 26);
  btnTraktor.Caption := _('Traktor-Farben');
  btnTraktor.Hint := _('Setzt die 4 Farben auf die Werte aus Traktors ' +
    'eigenen Stem-Dateien (Orange, Lila, Grün, Hellblau). Die Namen ' +
    'bleiben.') + LineEnding + _('Die Symbole zeigt Traktor fest nach ' +
    'Platz 1-4, sie lassen sich nicht ändern.');
  btnTraktor.ShowHint := True;
  btnTraktor.OnClick := @btnTraktorColorsClick;

  { --- Programm --- }
  gb := NewGroup(_('Programm'), 140);
  lbl := NewLabel(gb, 12, 10, _('Sprache:'));
  cbLang := TComboBox.Create(Self);
  cbLang.Parent := gb;
  cbLang.Style := csDropDownList;
  cbLang.SetBounds(110, 6, 180, 25);
  FLangCodes := LangAvailable;
  for I := 0 to FLangCodes.Count - 1 do
    cbLang.Items.Add(LangDisplayName(FLangCodes[I]));
  cbLang.ItemIndex := FLangCodes.IndexOf(LangCode);
  lbl := NewLabel(gb, 300, 10, _('(gilt ab dem nächsten Start)'));
  lbl.Font.Color := clGrayText;
  chkAutoUpdate := NewCheck(gb, 12, 40, _('Beim Start nach Updates suchen'), '');
  chkAutoUpdate.Checked := UpdateAutoCheck(StemIniFileName);
  chkTrayMinimize := NewCheck(gb, 12, 64,
    _('Beim Minimieren nur das Symbol neben der Uhr zeigen'),
    _('Das Fenster verschwindet aus der Taskleiste. Klick auf das Symbol ' +
    'neben der Uhr holt es zurück.') + LineEnding + _('Fährt man mit der ' +
    'Maus über das Symbol, steht dort der Fortschritt.'));
  chkTrayNotify := NewCheck(gb, 12, 88,
    _('Meldung neben der Uhr, wenn die Umwandlung fertig ist'),
    _('Nur wenn StemMaker gerade nicht im Vordergrund ist.'));

  { --- Werkzeuge (nur Anzeige) --- }
  gb := NewGroup(_('Werkzeuge'), 116);
  PathRow(4, 'ffmpeg:', FFmpegExe);
  PathRow(31, 'demucs.cpp:', DemucsDir);
  PathRow(58, _('Modelle:'), ModelsDir);
  lbl := NewLabel(gb, 12, 86, _('Ändern nur bei Bedarf: StemMaker.ini, ' +
    'Abschnitt [Tools] (bei geschlossenem StemMaker).'));
  lbl.Font.Color := clGrayText;

  { --- Buttons unten --- }
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 48;
  pnlBottom.BevelOuter := bvNone;

  btnDefaults := TButton.Create(Self);
  btnDefaults.Parent := pnlBottom;
  btnDefaults.SetBounds(10, 8, 190, 32);
  btnDefaults.Caption := _('Standard wiederherstellen');
  btnDefaults.Hint := _('Setzt die Werte in diesem Fenster auf den ' +
    'Auslieferungszustand (Sprache bleibt).');
  btnDefaults.OnClick := @btnDefaultsClick;

  btnProgDir := TButton.Create(Self);
  btnProgDir.Parent := pnlBottom;
  btnProgDir.SetBounds(206, 8, 150, 32);
  btnProgDir.Caption := _('INI-Ordner öffnen');
  btnProgDir.Hint := _('Öffnet den Ordner, in dem StemMaker.ini liegt');
  btnProgDir.OnClick := @btnProgDirClick;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := pnlBottom;
  btnCancel.SetBounds(pnlBottom.ClientWidth - 110, 8, 100, 32);
  btnCancel.Anchors := [akTop, akRight];
  btnCancel.Caption := _('Abbrechen');
  btnCancel.ModalResult := mrCancel;
  btnCancel.Cancel := True;                // Esc = abbrechen

  btnOK := TButton.Create(Self);
  btnOK.Parent := pnlBottom;
  btnOK.SetBounds(pnlBottom.ClientWidth - 216, 8, 100, 32);
  btnOK.Anchors := [akTop, akRight];
  btnOK.Caption := _('OK');
  btnOK.ModalResult := mrOK;
  btnOK.Default := True;                   // Enter = OK

  { OnChange erst nach dem Aufbau setzen }
  chkAutoThreads.OnChange := @chkAutoThreadsChange;
  seThreads.OnChange := @seThreadsChange;
  cbEngine.OnChange := @cbEngineChange;
end;

destructor TfrmSettings.Destroy;
begin
  FLangCodes.Free;
  inherited Destroy;
end;

procedure TfrmSettings.ShowPrefs(const P: TStemPrefs);
var
  I: Integer;
begin
  seThreads.Value := P.Threads;
  chkAutoThreads.Checked := P.ThreadsAuto;
  chkOverwrite.Checked := P.Overwrite;
  chkKeepTree.Checked := P.KeepTree;
  chkKeepAwake.Checked := P.KeepAwake;
  chkTrayMinimize.Checked := P.TrayMinimize;
  chkTrayNotify.Checked := P.TrayNotify;
  for I := 0 to 3 do
  begin
    edtStem[I].Text := P.StemNames[I];
    clrStem[I].ButtonColor := P.StemColors[I];
  end;
  chkAutoThreadsChange(nil);
  cbEngine.ItemIndex := Ord(P.Engine);
  cbDevice.ItemIndex := Ord(P.TurboDevice);
  cbEngineChange(nil);
  ShowTurboSummary;
end;

procedure TfrmSettings.SetPrefs(const P: TStemPrefs);
begin
  ShowPrefs(P);
end;

function TfrmSettings.GetPrefs: TStemPrefs;
var
  I: Integer;
begin
  Result.Threads := seThreads.Value;
  Result.ThreadsAuto := chkAutoThreads.Checked;
  Result.Overwrite := chkOverwrite.Checked;
  Result.KeepTree := chkKeepTree.Checked;
  Result.KeepAwake := chkKeepAwake.Checked;
  Result.TrayMinimize := chkTrayMinimize.Checked;
  Result.TrayNotify := chkTrayNotify.Checked;
  for I := 0 to 3 do
  begin
    Result.StemNames[I] := Trim(edtStem[I].Text);
    if Result.StemNames[I] = '' then         // leer = Standardname behalten
      Result.StemNames[I] := DefaultStemSettings.Stems[I].Name;
    Result.StemColors[I] := clrStem[I].ButtonColor;
  end;
  Result.Engine := TStemEngine(cbEngine.ItemIndex);
  Result.TurboDevice := TTurboDevice(cbDevice.ItemIndex);
end;

{ Sprache und Update-Prüfung haben eigene Speicher-Funktionen }
procedure TfrmSettings.SaveProgramPrefs;
begin
  UpdateSetAutoCheck(StemIniFileName, chkAutoUpdate.Checked);
  SaveTurboSettings(TStemEngine(cbEngine.ItemIndex), TTurboDevice(cbDevice.ItemIndex));
  if (cbLang.ItemIndex >= 0) and (cbLang.ItemIndex < FLangCodes.Count) and
     (FLangCodes[cbLang.ItemIndex] <> LangCode) then
  begin
    LangSaveChoice(StemIniFileName, FLangCodes[cbLang.ItemIndex]);
    MessageDlg(_('Die Sprache wird beim nächsten Start übernommen.'),
      mtInformation, [mbOK], 0);
  end;
end;

{ "Auto" an: Wert ausrechnen und Eingabefeld sperren }
procedure TfrmSettings.chkAutoThreadsChange(Sender: TObject);
begin
  if chkAutoThreads.Checked then
    seThreads.Value := AutoThreads;
  seThreads.Enabled := not chkAutoThreads.Checked;
  seThreadsChange(nil);
end;

{ Neben "Teile" anzeigen, wie viele Kerne jeder Teil bekommt.
  Gleiche Rechnung wie in uStemJob (TStemJob.OmpThreads):
  echte Kerne geteilt durch Teile, mindestens 1.
  Beispiel i7-12700KF: 12 Kerne / 4 Teile -> "je 3 Kerne (12 von 12)" }
procedure TfrmSettings.seThreadsChange(Sender: TObject);
var
  Per, Used: Integer;
begin
  if seThreads.Value < 1 then Exit;
  Per := PhysicalCoreCount div seThreads.Value;
  if Per < 1 then Per := 1;
  Used := Per * seThreads.Value;
  if Per = 1 then
    lblCores.Caption := Format(_('je 1 Kern (%d von %d)'), [Used, PhysicalCoreCount])
  else
    lblCores.Caption := Format(_('je %d Kerne (%d von %d)'), [Per, Used, PhysicalCoreCount]);
  { mehr Teile als der RAM verkraftet? -> rot als Warnung }
  if seThreads.Value > AutoThreadsRAMLimit then
  begin
    lblCores.Font.Color := clRed;
    lblCores.Caption := lblCores.Caption + ' ' + _('RAM knapp!');
  end
  else
    lblCores.Font.Color := clDefault;
end;

{ Gerät und Teile gelten je nur für eine Engine }
procedure TfrmSettings.cbEngineChange(Sender: TObject);
begin
  cbDevice.Enabled := cbEngine.ItemIndex = Ord(seTurbo);
end;

procedure TfrmSettings.ShowTurboSummary;
begin
  lblTurbo.Caption := TurboTestSummary;
  if lblTurbo.Caption = '' then
    lblTurbo.Caption := _('Noch kein Vortest auf diesem PC.');
  lblTurbo.Hint := lblTurbo.Caption;
end;

{ Vortest mit der gerade gewählten Einstellung (auch vor OK) }
procedure TfrmSettings.btnVortestClick(Sender: TObject);
var
  S: TStemSettings;
begin
  S := DefaultStemSettings;
  LoadToolSettings(S);
  S.TurboDevice := TTurboDevice(cbDevice.ItemIndex);
  ShowTurboTest(S);
  ShowTurboSummary;
end;

procedure TfrmSettings.btnDefaultsClick(Sender: TObject);
begin
  ShowPrefs(DefaultStemPrefs);
  chkAutoUpdate.Checked := True;
end;

{ Farben aus einer echten Traktor-Pro-4-Stem-Datei (Atom 'stem', Version 2):
  Drums #FD6C38, Bass #D232F4, Other #00FFAC, Vocals #45DAFD.
  Gilt erst bei OK, wie alle Werte in diesem Fenster. }
procedure TfrmSettings.btnTraktorColorsClick(Sender: TObject);
const
  TRAKTOR_COLORS: array[0..3] of string =
    ('#FD6C38', '#D232F4', '#00FFAC', '#45DAFD');
var
  I: Integer;
begin
  for I := 0 to 3 do
    clrStem[I].ButtonColor := HexToCol(TRAKTOR_COLORS[I]);
end;

procedure TfrmSettings.btnProgDirClick(Sender: TObject);
begin
  OpenDocument(ExtractFilePath(StemIniFileName));
end;

function ShowSettingsDialog(var P: TStemPrefs; BesideInput: Boolean;
  const FFmpegExe, DemucsDir, ModelsDir: string): Boolean;
var
  F: TfrmSettings;
begin
  F := TfrmSettings.CreateSettings(BesideInput, FFmpegExe, DemucsDir, ModelsDir);
  try
    F.SetPrefs(P);
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      P := F.GetPrefs;
      F.SaveProgramPrefs;
    end;
  finally
    F.Free;
  end;
end;

end.
