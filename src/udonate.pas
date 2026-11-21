{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udonate.pas  (Unit uDonate)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
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

  Dazu einmal pro neuer Haupt- oder Unterversion (2.5, 2.6, nicht 2.5.1)
  nach der ersten erfolgreichen Umwandlung, mit "Danke fürs Update".
  Höchstens ein Hinweis pro Sitzung, nie beim Start, nie bei einem Abbruch
  und nie nach einem Durchlauf, in dem mehr als 10 % der Dateien
  fehlgeschlagen sind. Die Entscheidung steht in uDonateLogik.
  Der Hinweis nennt, was StemMaker schon geleistet hat (Anzahl Tracks,
  Stunden Musik), sagt ehrlich, dass dahinter ein Hobbyprojekt steckt, und
  sagt ausdrücklich, dass "nein" völlig in Ordnung ist.

    [ Kaffee spendieren ]  -> öffnet ko-fi.com/elospeed im Browser
    [ Weiter            ]  -> einfach weiter
    [x] Nicht mehr fragen   -> StemMaker.ini, [Main] HideDonate=1
                               (gilt bis zur nächsten neuen Version;
                               dann kommt der Hinweis zum Update einmal
                               und HideDonate wird zurückgesetzt)

  Im Info-Fenster gibt es "Jetzt spenden" weiterhin jederzeit.

  Zähler in StemMaker.ini, Abschnitt [Main]:
    StemsTotal       Anzahl erfolgreich erstellter Stem-Dateien (gesamt)
    StemsAudioSec    Musik-Länge dieser Dateien in Sekunden (gesamt)
    DonateMilestone  zuletzt gezeigte Marke (damit keine doppelt kommt)
    DonateHintShownFor  Version (z. B. 2.5), für die der Hinweis zum
                     Update schon kam

  Das Fenster wird im Code aufgebaut (keine .lfm-Datei).
  ============================================================================ }
unit uDonate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLIntf,
  IniFiles, uStemJob, uLog, uLang, uDonateLogik;

const
  DONATE_URL = 'https://ko-fi.com/elospeed';

{ Nach einem Durchlauf aufrufen: zählt die fertigen Tracks dazu.
  OKCount = erfolgreich erstellte Dateien, AudioMS = deren Musik-Länge.
  HappyRun = True, wenn der Durchlauf gut lief (kein Abbruch, höchstens
  10 % Fehler - entscheidet uMain.WorkerDone).
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

{$I version.inc}   // APP_VERSION

var
  { In dieser Sitzung kam schon ein Hinweis - dann keiner mehr }
  HinweisGezeigt: Boolean = False;

type
  TfrmDonate = class(TForm)
  private
    chkHide: TCheckBox;
    procedure btnDonateClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
  public
    constructor CreateDonate(Stems: Integer; AudioSec: Int64; NachUpdate: Boolean);
  end;

procedure OpenDonatePage;
begin
  OpenURL(DONATE_URL);
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
  Vorher, Stems: Integer;
  ShownFor: string;
begin
  Result := False;
  if OKCount <= 0 then Exit;
  try
    Ini := TIniFile.Create(StemIniFileName);
    try
      Vorher := Ini.ReadInteger('Main', 'StemsTotal', 0);
      Stems := Vorher + OKCount;
      Ini.WriteInteger('Main', 'StemsTotal', Stems);
      Ini.WriteInt64('Main', 'StemsAudioSec',
        Ini.ReadInt64('Main', 'StemsAudioSec', 0) + AudioMS div 1000);

      { Neue Installation (noch nie ein Track): kein "Danke fürs Update".
        Diese Version gilt als schon begrüsst, der erste Hinweis kommt
        wie bisher bei 10 Tracks. }
      ShownFor := Ini.ReadString('Main', 'DonateHintShownFor', '');
      if (Vorher = 0) and (Trim(ShownFor) = '') then
        Ini.WriteString('Main', 'DonateHintShownFor',
          ShownForWirksam(Vorher, ShownFor, APP_VERSION));
      ShownFor := ShownForWirksam(Vorher, ShownFor, APP_VERSION);

      { Hinweis nur nach einem guten Durchlauf - der Moment, in dem
        StemMaker gerade sichtbar geholfen hat. Eine Marke, die bei einem
        schlechten Durchlauf erreicht wurde, kommt beim nächsten guten nach.
        Gemerkt wird erst, wenn der Hinweis wirklich erscheint
        (ShowDonateThanks). Wird StemMaker vorher geschlossen, z. B. aus
        dem Symbol neben der Uhr, kommt er beim nächsten guten Durchlauf. }
      Result := DonateFaellig(APP_VERSION, ShownFor,
        Ini.ReadBool('Main', 'HideDonate', False), Stems,
        Ini.ReadInteger('Main', 'DonateMilestone', 0), HappyRun,
        HinweisGezeigt) <> daKeiner;
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
constructor TfrmDonate.CreateDonate(Stems: Integer; AudioSec: Int64;
  NachUpdate: Boolean);
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
  ClientHeight := 330;

  { kleines farbiges Element links als Blickfang (Ko-fi-Rot) }
  pnlHeart := TShape.Create(Self);
  pnlHeart.Parent := Self;
  pnlHeart.Shape := stRoundRect;
  pnlHeart.Brush.Color := $005E5AFF;     // TColor = $BBGGRR -> #FF5A5E
  pnlHeart.Pen.Style := psClear;
  pnlHeart.SetBounds(20, 22, 8, 208);

  { Titel: was StemMaker schon geleistet hat - konkret, mit Zahl }
  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := Self;
  lblTitle.SetBounds(42, 18, 420, 24);
  if NachUpdate then
    lblTitle.Caption := Format(_('Danke fürs Update auf StemMaker %s!'),
      [HauptVersion(APP_VERSION)])
  else
    lblTitle.Caption := Format(_('Schon %d Tracks in Stems verwandelt'), [Stems]);
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Height := -17;

  { Der Text. Bewusst so aufgebaut:
    1. erst das, was der Benutzer schon bekommen hat (ohne Abo, ohne Upload),
    2. dann ehrlich, wer dahinter steckt (ein Mensch, Freizeit),
    3. eine kleine, konkrete Bitte (ein Kaffee, kein Betrag) und wofür
       sie gut ist (dass es weitergeht),
    4. und ausdrücklich: "nein" ist völlig in Ordnung.
    Nach einem Update statt der Zahlen: StemMaker bleibt gratis.
    Punkt 4 ist kein Trick gegen den Benutzer - wer frei entscheiden darf,
    fühlt sich nicht gedrängt, und genau so soll es sich anfühlen. }
  S := '';
  if NachUpdate then
    S := _('StemMaker bleibt gratis, ohne Abo und ohne Werbung: ein ' +
      'Hobbyprojekt, ein Mensch, viele Abende.') + LineEnding + LineEnding
  else if AudioSec >= 60 then
    S := Format(_('Das sind rund %s Musik, getrennt auf deinem eigenen PC - ' +
      'ohne Abo, ohne Upload, ohne Werbung.'), [AudioText(AudioSec)]) +
      LineEnding + LineEnding;
  lblText := TLabel.Create(Self);
  lblText.Parent := Self;
  lblText.AutoSize := False;
  lblText.WordWrap := True;
  lblText.SetBounds(42, 50, 420, 160);
  if not NachUpdate then
    S := S + _('StemMaker ist mein Hobbyprojekt: ein Mensch, viele Abende.') + ' ';
  lblText.Caption := S +
    _('Wenn StemMaker dir Zeit spart, hilft ein Kaffee, dass es weitergeht.') +
    ' ☕' + LineEnding + LineEnding +
    _('Und wenn nicht, ist das völlig in Ordnung. Viel Spass beim Auflegen!');

  lblLink := TLabel.Create(Self);
  lblLink.Parent := Self;
  lblLink.SetBounds(42, 212, 420, 18);
  lblLink.Caption := '- Elospeed   ·   ko-fi.com/elospeed';
  lblLink.Font.Color := clGrayText;

  chkHide := TCheckBox.Create(Self);
  chkHide.Parent := Self;
  chkHide.SetBounds(20, 296, 260, 22);
  chkHide.Caption := _('Nicht mehr fragen');

  { Buttons rechts, darunter das Häkchen }
  btnStart := TButton.Create(Self);
  btnStart.Parent := Self;
  btnStart.SetBounds(ClientWidth - 20 - 120, 246, 120, 32);
  btnStart.Caption := _('Weiter');
  btnStart.OnClick := @btnStartClick;
  btnStart.Default := True;      // Enter = einfach weiter
  btnStart.Cancel := True;       // Esc ebenso

  btnDonate := TButton.Create(Self);
  btnDonate.Parent := Self;
  btnDonate.SetBounds(ClientWidth - 20 - 120 - 10 - 160, 246, 160, 32);
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
  NachUpdate: Boolean;
  Version: string;
begin
  if HinweisGezeigt then Exit;           // höchstens einer pro Sitzung
  Version := HauptVersion(APP_VERSION);
  Ini := TIniFile.Create(StemIniFileName);
  try
    { StemsTotal > 0 hier immer (erst nach einem Durchlauf aufgerufen) }
    NachUpdate := VersionNeuer(Version, ShownForWirksam(1,
      Ini.ReadString('Main', 'DonateHintShownFor', ''), APP_VERSION));
    if (not NachUpdate) and Ini.ReadBool('Main', 'HideDonate', False) then Exit;
    Stems := Ini.ReadInteger('Main', 'StemsTotal', 0);
    AudioSec := Ini.ReadInt64('Main', 'StemsAudioSec', 0);
    { Merken - so kommt derselbe Hinweis nie zweimal, auch wenn das
      Fenster mit dem X geschlossen wird. Die Marke wird auch beim Hinweis
      zum Update gemerkt: fallen beide zusammen, kommt nur einer. Nach
      einem Update gilt "Nicht mehr fragen" der alten Version nicht mehr. }
    try
      Ini.WriteInteger('Main', 'DonateMilestone', MilestoneFor(Stems));
      if NachUpdate then
      begin
        Ini.WriteString('Main', 'DonateHintShownFor', Version);
        Ini.WriteBool('Main', 'HideDonate', False);
      end;
    except
      { INI nicht schreibbar - dann kommt der Hinweis eben wieder }
    end;
  finally
    Ini.Free;
  end;
  HinweisGezeigt := True;
  if NachUpdate then
    LogLine(Format('Spenden-Hinweis zum Update auf %s gezeigt (%d Tracks gesamt)',
      [Version, Stems]))
  else
    LogLine(Format('Spenden-Hinweis gezeigt (%d Tracks gesamt)', [Stems]));

  F := TfrmDonate.CreateDonate(Stems, AudioSec, NachUpdate);
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
      { INI nicht schreibbar - dann kommt der Hinweis bei der nächsten Marke wieder.
        "Nicht mehr fragen" gilt bis zur nächsten neuen Version (uDonateLogik). }
    end;
  finally
    F.Free;
  end;
end;

end.
