{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulangui.pas  (Unit uLangUI)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Der Oberflächen-Teil der Mehrsprachigkeit (siehe uLang):

  1. TranslateComponent(Form)
     Fenster aus .lfm-Dateien (z.B. das Hauptfenster) haben ihre Texte
     dort auf Deutsch stehen. Diese Prozedur geht einmal durch alle
     Bedienelemente und übersetzt Caption, Hint, TextHint, die Einträge
     von Auswahllisten und die Spaltenköpfe von Listen.

  2. Sprachwahl beim allerersten Start
     Ein kleines Fenster "Sprache / Language" mit einer Liste aller
     vorhandenen Sprachen. Vorausgewählt ist die Sprache von Windows.
     Die Wahl wird in StemMaker.ini gespeichert ([Main] Language=en).
     Ändern kann man sie später im Info-Fenster.
  ============================================================================ }
unit uLangUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TypInfo, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  IniFiles, uLang;

{ alle Texte eines Fensters (und seiner Bedienelemente) übersetzen }
procedure TranslateComponent(Root: TComponent);

{ Beim Programmstart aufrufen: Sprache aus der INI laden. Steht dort noch
  keine, wird das Auswahlfenster gezeigt und die Wahl gespeichert. }
procedure LangInitInteractive(const IniName: string);

{ gewählte Sprache in StemMaker.ini speichern ([Main] Language=en) }
procedure LangSaveChoice(const IniName, Code: string);

implementation

{ einen Text-Eigenschaft (falls vorhanden) übersetzen }
procedure TranslateProp(C: TPersistent; const PropName: string);
var
  P: PPropInfo;
  S: string;
begin
  P := GetPropInfo(C, PropName);
  if (P = nil) or not (P^.PropType^.Kind in [tkAString, tkSString, tkLString,
     tkUString, tkWString]) then Exit;
  S := GetStrProp(C, P);
  if S <> '' then
    SetStrProp(C, P, _(S));
end;

procedure TranslateComponent(Root: TComponent);
var
  I, J, Keep: Integer;
  C: TComponent;
  SL: TStrings;
begin
  if LangCode = 'de' then Exit;          // Original - nichts zu tun
  TranslateProp(Root, 'Caption');
  TranslateProp(Root, 'Hint');
  for I := 0 to Root.ComponentCount - 1 do
  begin
    C := Root.Components[I];
    TranslateProp(C, 'Caption');
    TranslateProp(C, 'Hint');
    TranslateProp(C, 'TextHint');
    TranslateProp(C, 'DialogTitle');
    { Auswahllisten: jeden Eintrag einzeln (ItemIndex bleibt erhalten) }
    if C is TCustomComboBox then
    begin
      SL := TCustomComboBox(C).Items;
      Keep := TCustomComboBox(C).ItemIndex;   // Auswahl merken ...
      for J := 0 to SL.Count - 1 do
        SL[J] := _(SL[J]);
      TCustomComboBox(C).ItemIndex := Keep;   // ... und wiederherstellen
    end;
    { Spaltenköpfe von Listen }
    if C is TListView then
      for J := 0 to TListView(C).Columns.Count - 1 do
        TListView(C).Columns[J].Caption := _(TListView(C).Columns[J].Caption);
  end;
end;

procedure LangSaveChoice(const IniName, Code: string);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteString('Main', 'Language', Code);
    finally
      Ini.Free;
    end;
  except
    { INI nicht schreibbar - dann wird beim nächsten Start nochmals gefragt }
  end;
end;

{ ---------------------------------------------------------------------------
  Das Auswahlfenster (im Code aufgebaut, keine .lfm)
  Die Texte sind absichtlich zweisprachig, weil ja noch keine Sprache
  gewählt ist.
  --------------------------------------------------------------------------- }
function ShowLanguageDialog(const Preselect: string): string;
var
  F: TForm;
  Lbl: TLabel;
  Lst: TListBox;
  Btn: TButton;
  Codes: TStringList;
  I: Integer;
begin
  Result := Preselect;
  Codes := LangAvailable;
  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Sprache / Language';
    F.BorderStyle := bsDialog;
    F.Position := poScreenCenter;
    F.ClientWidth := 340;
    F.ClientHeight := 250;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.SetBounds(16, 14, 310, 40);
    Lbl.AutoSize := False;
    Lbl.WordWrap := True;
    Lbl.Caption := 'Bitte Sprache wählen' + LineEnding + 'Please choose your language';

    Lst := TListBox.Create(F);
    Lst.Parent := F;
    Lst.SetBounds(16, 60, 308, 130);
    for I := 0 to Codes.Count - 1 do
      Lst.Items.Add(LangDisplayName(Codes[I]));
    Lst.ItemIndex := Codes.IndexOf(Preselect);
    if Lst.ItemIndex < 0 then Lst.ItemIndex := 0;

    Btn := TButton.Create(F);
    Btn.Parent := F;
    Btn.SetBounds(224, 202, 100, 32);
    Btn.Caption := 'OK';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    F.ActiveControl := Lst;

    F.ShowModal;                          // auch mit X: dann gilt die Auswahl
    if (Lst.ItemIndex >= 0) and (Lst.ItemIndex < Codes.Count) then
      Result := Codes[Lst.ItemIndex];
  finally
    F.Free;
    Codes.Free;
  end;
end;

{ Die Knöpfe und Titel der Standard-Rückfragen (MessageDlg) stammen aus
  der LCL (Unit lclstrconsts) und sind von Haus aus Englisch: "Yes/No",
  "Confirmation", "Error". Bei Deutsch werden sie hier ersetzt - sonst
  stünde unter einer deutschen Frage "Yes / No". }
function GermanLCLText(Name, Value: AnsiString; Hash: Longint;
  Arg: Pointer): AnsiString;
var
  P: Integer;
begin
  { Name kommt als "lclstrconsts.rsmbyes" - nur den Teil nach dem Punkt }
  P := LastDelimiter('.', Name);
  case LowerCase(Copy(Name, P + 1, MaxInt)) of
    'rsmbyes':          Result := '&Ja';
    'rsmbno':           Result := '&Nein';
    'rsmbok':           Result := '&OK';
    'rsmbcancel':       Result := 'Abbrechen';
    'rsmbabort':        Result := 'Abbrechen';
    'rsmbretry':        Result := '&Wiederholen';
    'rsmbignore':       Result := '&Ignorieren';
    'rsmball':          Result := '&Alle';
    'rsmbnotoall':      Result := 'Alle verneinen';
    'rsmbyestoall':     Result := '&Alle bejahen';
    'rsmbhelp':         Result := '&Hilfe';
    'rsmbclose':        Result := '&Schließen';
    'rsmtwarning':      Result := 'Warnung';
    'rsmterror':        Result := 'Fehler';
    'rsmtinformation':  Result := 'Information';
    'rsmtconfirmation': Result := 'Bestätigung';
  else
    Result := Value;                      // alles andere bleibt
  end;
end;

procedure GermanLCLStrings;
begin
  SetUnitResourceStrings('lclstrconsts', @GermanLCLText, nil);
end;

procedure LangInitInteractive(const IniName: string);
var
  Ini: TIniFile;
  Code: string;
begin
  Code := '';
  try
    Ini := TIniFile.Create(IniName);
    try
      Code := Ini.ReadString('Main', 'Language', '');
    finally
      Ini.Free;
    end;
  except
    Code := '';
  end;
  if Code = '' then
  begin
    { erster Start: fragen (Windows-Sprache vorausgewählt) }
    Code := ShowLanguageDialog(LangSystemDefault);
    LangSaveChoice(IniName, Code);
  end;
  if not LangLoad(Code) then
    LangLoad('de');                       // Datei fehlt -> Deutsch
  if LangCode = 'de' then
    GermanLCLStrings;
end;

end.
