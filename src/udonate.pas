{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udonate.pas  (Unit uDonate)
  Version : 1.7.2
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Der freundliche Spenden-Hinweis. StemMaker ist kostenlos und quelloffen,
  über Ko-fi kann man freiwillig etwas zurückgeben.

  WANN KOMMT DER HINWEIS? (seit Oktober 2026)
  Früher kam vor JEDEM Programmstart ein Spendenfenster. Das ist der
  schlechteste Moment: Wer das Programm gerade erst öffnet, hat noch nichts
  davon gehabt und klickt das Fenster nur weg (oder schaltet es für immer
  ab). Jetzt kommt der Hinweis genau dann, wenn StemMaker gerade geholfen
  hat - nach einem erfolgreichen Durchlauf, an dem eine "runde" Zahl
  fertiger Tracks erreicht wurde:

      10, 50, 100, 250, 500, 1000, danach alle 1000 Tracks

  Also höchstens ein paarmal im ganzen Leben einer Installation, nie beim
  Start, nie nach einem Durchlauf mit Fehlern und nie bei einem Abbruch.
  Der Hinweis nennt, was StemMaker schon geleistet hat (Anzahl Tracks,
  Stunden Musik), sagt ehrlich, dass dahinter ein Hobbyprojekt steckt, und
  sagt ausdrücklich, dass "nein" völlig in Ordnung ist.

    [ Kaffee spendieren ]  -> öffnet ko-fi.com/elospeed im Browser
    [ Weiter            ]  -> einfach weiter
    [x] Nicht mehr fragen   -> StemMaker.ini, [Main] HideDonate=1
                               (derselbe Schalter wie beim alten
                               Startfenster - wer es dort abgeschaltet
                               hat, wird auch hier nie gefragt)

  Im Info-Fenster gibt es "Jetzt spenden" weiterhin jederzeit.

  Zähler in StemMaker.ini, Abschnitt [Main]:
    StemsTotal       Anzahl erfolgreich erstellter Stem-Dateien (gesamt)
    StemsAudioSec    Musik-Länge dieser Dateien in Sekunden (gesamt)
    DonateMilestone  zuletzt gezeigte Marke (damit keine doppelt kommt)

  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uDonate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLIntf,
  IniFiles, uStemJob, uLog, uLang;

const
  DONATE_URL = 'https://ko-fi.com/elospeed';

{ Nach einem Durchlauf aufrufen: zählt die fertigen Tracks dazu.
  OKCount = erfolgreich erstellte Dateien, AudioMS = deren Musik-Länge.
  HappyRun = True, wenn der Durchlauf ohne Fehler und ohne Abbruch lief.
  Gibt True zurück, wenn jetzt eine neue Marke erreicht ist und der
  Hinweis gezeigt werden soll (dann ShowDonateThanks aufrufen). }
function CountStemsForDonate(OKCount: Integer; AudioMS: Int64;
  HappyRun: Boolean): Boolean;

{ Zeigt den Dank-/Spenden-Hinweis mit den aktuellen Zahlen.
  Nicht aus dem Ende-Ereignis eines Threads aufrufen (modales Fenster),
  sondern über Application.QueueAsyncCall. }
procedure ShowDonateThanks;

{ Ko-fi-Seite im Standard-Browser öffnen }
procedure OpenDonatePage;

implementation

type
  TfrmDonate = class(TForm)
  private
    chkHide: TCheckBox;
    procedure btnDonateClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
  public
    constructor CreateDonate(Stems: Integer; AudioSec: Int64);
  end;

procedure OpenDonatePage;
begin
  OpenURL(DONATE_URL);
end;

{ ---------------------------------------------------------------------------
  Marken: 10, 50, 100, 250, 500, 1000, 2000, 3000 ...
  Liefert die höchste Marke, die mit Stems Tracks erreicht ist (0 = keine).
  --------------------------------------------------------------------------- }
function MilestoneFor(Stems: Integer): Integer;
const
  MARKS: array[0..5] of Integer = (10, 50, 100, 250, 500, 1000);
var
  I: Integer;
begin
  Result := 0;
  for I := Low(MARKS) to High(MARKS) do
    if Stems >= MARKS[I] then
      Result := MARKS[I];
  if Stems >= 2000 then
    Result := (Stems div 1000) * 1000;     // ab 2000: alle 1000 Tracks
end;

{ Musik-Länge lesbar: "45 Minuten", "1 Stunde", "12 Stunden" }
function AudioText(AudioSec: Int64): string;
var
  H: Int64;
begin
  if AudioSec < 90 * 60 then
    Result := Format(_('%d Minuten'), [Integer(AudioSec div 60)])
  else
  begin
    H := (AudioSec + 30 * 60) div 3600;    // auf ganze Stunden gerundet
    Result := Format(_('%d Stunden'), [Integer(H)]);
  end;
end;

{ ---------------------------------------------------------------------------
  Zählen
  --------------------------------------------------------------------------- }
function CountStemsForDonate(OKCount: Integer; AudioMS: Int64;
  HappyRun: Boolean): Boolean;
var
  Ini: TIniFile;
  Stems, Mark: Integer;
begin
  Result := False;
  if OKCount <= 0 then Exit;
  try
    Ini := TIniFile.Create(StemIniFileName);
    try
      Stems := Ini.ReadInteger('Main', 'StemsTotal', 0) + OKCount;
      Ini.WriteInteger('Main', 'StemsTotal', Stems);
      Ini.WriteInt64('Main', 'StemsAudioSec',
        Ini.ReadInt64('Main', 'StemsAudioSec', 0) + AudioMS div 1000);

      { Hinweis nur nach einem Durchlauf ohne Fehler/Abbruch - der Moment,
        in dem StemMaker gerade sichtbar geholfen hat. Eine Marke, die bei
        einem Durchlauf mit Fehlern erreicht wurde, kommt beim nächsten
        guten Durchlauf nach. }
      if not HappyRun then Exit;
      if Ini.ReadBool('Main', 'HideDonate', False) then Exit;
      Mark := MilestoneFor(Stems);
      { Gemerkt wird die Marke erst, wenn der Hinweis wirklich erscheint
        (ShowDonateThanks). Wird StemMaker vorher geschlossen, z. B. aus
        dem Symbol neben der Uhr, kommt er beim nächsten guten Durchlauf. }
      Result := (Mark > 0) and (Mark > Ini.ReadInteger('Main', 'DonateMilestone', 0));
    finally
      Ini.Free;
    end;
  except
    { INI nicht schreibbar - dann eben kein Zähler und kein Hinweis }
    Result := False;
  end;
end;

{ ---------------------------------------------------------------------------
  Fenster aufbauen
  --------------------------------------------------------------------------- }
constructor TfrmDonate.CreateDonate(Stems: Integer; AudioSec: Int64);
var
  lblTitle, lblText, lblLink: TLabel;
  btnDonate, btnStart: TButton;
  pnlHeart: TShape;
  S: string;
begin
  inherited CreateNew(nil);
  Caption := APP_NAME + _(' - kostenlos & quelloffen');
  BorderStyle := bsDialog;
  Icon.Assign(Application.Icon);   // Programmsymbol auch in diesem Fenster
  Position := poScreenCenter;
  ClientWidth := 480;
  ClientHeight := 300;

  { kleines farbiges Element links als Blickfang (Ko-fi-Rot) }
  pnlHeart := TShape.Create(Self);
  pnlHeart.Parent := Self;
  pnlHeart.Shape := stRoundRect;
  pnlHeart.Brush.Color := $005E5AFF;     // TColor = $BBGGRR -> #FF5A5E
  pnlHeart.Pen.Style := psClear;
  pnlHeart.SetBounds(20, 22, 8, 178);

  { Titel: was StemMaker schon geleistet hat - konkret, mit Zahl }
  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := Self;
  lblTitle.SetBounds(42, 18, 420, 24);
  lblTitle.Caption := Format(_('Schon %d Tracks in Stems verwandelt'), [Stems]);
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Height := -17;

  { Der Text. Bewusst so aufgebaut:
    1. erst das, was der Benutzer schon bekommen hat (ohne Abo, ohne Upload),
    2. dann ehrlich, wer dahinter steckt (ein Mensch, Freizeit),
    3. eine kleine, konkrete Bitte (ein Kaffee, kein Betrag),
    4. und ausdrücklich: "nein" ist völlig in Ordnung.
    Punkt 4 ist kein Trick gegen den Benutzer - wer frei entscheiden darf,
    fühlt sich nicht gedrängt, und genau so soll es sich anfühlen. }
  S := '';
  if AudioSec >= 60 then
    S := Format(_('Das sind rund %s Musik, getrennt auf deinem eigenen PC - ' +
      'ohne Abo, ohne Upload, ohne Werbung.'), [AudioText(AudioSec)]) +
      LineEnding + LineEnding;
  lblText := TLabel.Create(Self);
  lblText.Parent := Self;
  lblText.AutoSize := False;
  lblText.WordWrap := True;
  lblText.SetBounds(42, 50, 420, 130);
  lblText.Caption := S +
    _('StemMaker ist mein Hobbyprojekt: ein Mensch, viele Abende. Wenn es ' +
    'dir einen Kaffee wert ist, freue ich mich riesig darüber.') +
    LineEnding + LineEnding +
    _('Und wenn nicht, ist das völlig in Ordnung. Viel Spass beim Auflegen!');

  lblLink := TLabel.Create(Self);
  lblLink.Parent := Self;
  lblLink.SetBounds(42, 182, 420, 18);
  lblLink.Caption := '- Elospeed   ·   ko-fi.com/elospeed';
  lblLink.Font.Color := clGrayText;

  chkHide := TCheckBox.Create(Self);
  chkHide.Parent := Self;
  chkHide.SetBounds(20, 266, 260, 22);
  chkHide.Caption := _('Nicht mehr fragen');

  { Buttons rechts, darunter das Häkchen }
  btnStart := TButton.Create(Self);
  btnStart.Parent := Self;
  btnStart.SetBounds(ClientWidth - 20 - 120, 216, 120, 32);
  btnStart.Caption := _('Weiter');
  btnStart.OnClick := @btnStartClick;
  btnStart.Default := True;      // Enter = einfach weiter
  btnStart.Cancel := True;       // Esc ebenso

  btnDonate := TButton.Create(Self);
  btnDonate.Parent := Self;
  btnDonate.SetBounds(ClientWidth - 20 - 120 - 10 - 160, 216, 160, 32);
  btnDonate.Caption := _('Kaffee spendieren');
  btnDonate.Font.Style := [fsBold];
  btnDonate.OnClick := @btnDonateClick;
  ActiveControl := btnStart;     // Fokus auf "Weiter" - niemand spendet aus Versehen
end;

procedure TfrmDonate.btnDonateClick(Sender: TObject);
begin
  OpenDonatePage;
  LogLine('Spenden-Hinweis: Ko-fi geöffnet');
  ModalResult := mrOK;
end;

procedure TfrmDonate.btnStartClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

{ ---------------------------------------------------------------------------
  Aufruf von außen
  --------------------------------------------------------------------------- }
procedure ShowDonateThanks;
var
  Ini: TIniFile;
  F: TfrmDonate;
  Stems: Integer;
  AudioSec: Int64;
begin
  Ini := TIniFile.Create(StemIniFileName);
  try
    if Ini.ReadBool('Main', 'HideDonate', False) then Exit;
    Stems := Ini.ReadInteger('Main', 'StemsTotal', 0);
    AudioSec := Ini.ReadInt64('Main', 'StemsAudioSec', 0);
    { Marke merken - so kommt dieselbe nie zweimal, auch wenn das Fenster
      mit dem X geschlossen wird }
    try
      Ini.WriteInteger('Main', 'DonateMilestone', MilestoneFor(Stems));
    except
      { INI nicht schreibbar - dann kommt der Hinweis eben wieder }
    end;
  finally
    Ini.Free;
  end;
  LogLine(Format('Spenden-Hinweis gezeigt (%d Tracks gesamt)', [Stems]));

  F := TfrmDonate.CreateDonate(Stems, AudioSec);
  try
    F.ShowModal;
    if F.chkHide.Checked then
    try
      Ini := TIniFile.Create(StemIniFileName);
      try
        Ini.WriteBool('Main', 'HideDonate', True);
      finally
        Ini.Free;
      end;
      LogLine('Spenden-Hinweis: "Nicht mehr fragen" gewählt');
    except
      { INI nicht schreibbar - dann kommt der Hinweis bei der nächsten Marke wieder }
    end;
  finally
    F.Free;
  end;
end;

end.
