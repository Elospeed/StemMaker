{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulicense.pas  (Unit uLicense, ohne Oberfläche)
  Version : 1.7
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Vor der ersten Benutzung muss man den Haftungsausschluss und die
  Lizenzhinweise einmal bestätigen (Häkchen + Knopf). Diese Unit enthält:
    - den Text (Deutsch, übersetzt über lang\*.po)
    - die PC-Kennung
    - Lesen/Schreiben der Bestätigung in StemMaker.ini

  Das Fenster dazu liegt in uLicenseUI (StemMaker), StemCLI fragt in der
  Konsole. Beide nutzen diese Unit - deshalb hier keine LCL.

  PC-KENNUNG
  Windows legt bei der Installation eine eindeutige Nummer an:
    HKLM\SOFTWARE\Microsoft\Cryptography  Wert "MachineGuid"
  Gespeichert wird NICHT diese Nummer selbst, sondern nur ein Hash
  (SHA-1 von "Elospeed.StemMaker:" + Nummer). Wird der StemMaker-Ordner
  auf einen anderen PC kopiert, passt der Hash nicht mehr und die Frage
  kommt erneut.
  Das ist KEIN Kopierschutz (die MIT-Lizenz erlaubt Kopieren ausdrücklich),
  sondern nur die erneute Bestätigung auf jedem PC.

  In der INI ([Main]):
    TermsPC       Hash der PC-Kennung bei der Bestätigung
    TermsVersion  Stand des Textes (TERMS_VERSION). Wird der Text später
                  wesentlich geändert, TERMS_VERSION erhöhen -> alle
                  bestätigen einmal neu.
    TermsDate     Datum der Bestätigung (nur zur Info)
  ============================================================================ }
unit uLicense;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, sha1, uLang
  {$IFDEF WINDOWS}, Registry{$ENDIF};

const
  TERMS_VERSION = 1;

{ Hash der PC-Kennung (40 Zeichen hex) }
function MachineIdHash: string;

{ Wurde auf diesem PC schon bestätigt? }
function TermsAccepted(const IniName: string): Boolean;

{ Bestätigung für diesen PC speichern }
procedure TermsSaveAccepted(const IniName: string);

{ Überschrift und Text (in der aktuellen Sprache) }
function TermsTitle: string;
function TermsText: string;

implementation

{ Die Windows-Installationsnummer lesen. Ein 64-Bit-Programm liest den
  64-Bit-Teil der Registry; KEY_WOW64_64KEY sorgt dafür, dass das auch
  ein 32-Bit-Build täte. Klappt das nicht, wird der Computername genommen
  (besser als gar nichts). }
function RawMachineId: string;
{$IFDEF WINDOWS}
var
  Reg: TRegistry;
{$ENDIF}
begin
  Result := '';
  {$IFDEF WINDOWS}
  Reg := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Cryptography') then
    try
      Result := Reg.ReadString('MachineGuid');
    except
      Result := '';
    end;
  finally
    Reg.Free;
  end;
  {$ENDIF}
  if Result = '' then
    Result := 'PC:' + GetEnvironmentVariable('COMPUTERNAME') +
      GetEnvironmentVariable('HOSTNAME');
end;

function MachineIdHash: string;
begin
  Result := LowerCase(SHA1Print(SHA1String('Elospeed.StemMaker:' + RawMachineId)));
end;

function TermsAccepted(const IniName: string): Boolean;
var
  Ini: TIniFile;
begin
  Result := False;
  if not FileExists(IniName) then Exit;
  Ini := TIniFile.Create(IniName);
  try
    Result := (Ini.ReadInteger('Main', 'TermsVersion', 0) >= TERMS_VERSION) and
      SameText(Ini.ReadString('Main', 'TermsPC', ''), MachineIdHash);
  finally
    Ini.Free;
  end;
end;

procedure TermsSaveAccepted(const IniName: string);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteString('Main', 'TermsPC', MachineIdHash);
      Ini.WriteInteger('Main', 'TermsVersion', TERMS_VERSION);
      Ini.WriteString('Main', 'TermsDate', FormatDateTime('yyyy-mm-dd', Now));
    finally
      Ini.Free;
    end;
  except
    { INI nicht schreibbar (z.B. schreibgeschützter Ordner) - dann kommt
      die Frage beim nächsten Start eben wieder }
  end;
end;

function TermsTitle: string;
begin
  Result := _('Bitte vor der ersten Benutzung lesen');
end;

{ Der Text. Absätze mit Leerzeile getrennt, Überschriften in GROSS, damit
  er im Fenster (Textfeld) und in der Konsole gleich gut lesbar ist. }
function TermsText: string;
begin
  Result :=
    _('HAFTUNGSAUSSCHLUSS') + LineEnding +
    _('StemMaker wird kostenlos und ohne jede Gewährleistung bereitgestellt ' +
    '("wie besehen"). Die Benutzung erfolgt auf eigenes Risiko. Soweit gesetzlich ' +
    'zulässig, haftet Elospeed nicht für Schäden oder Datenverlust, die durch die ' +
    'Benutzung entstehen. Lege von wichtigen Dateien vorher eine Sicherung an.') +
    LineEnding + LineEnding +
    _('RECHTE AN DER MUSIK') + LineEnding +
    _('Wandle nur Musik um, an der du die nötigen Rechte hast, z. B. selbst ' +
    'gekaufte Titel für den eigenen Gebrauch. Für das Einhalten von Urheberrecht ' +
    'und den Nutzungsbedingungen von Shops und Streaming-Diensten bist du selbst ' +
    'verantwortlich.') +
    LineEnding + LineEnding +
    _('LIZENZEN') + LineEnding +
    _('StemMaker ist Open Source unter der MIT-Lizenz (© 2026 Elospeed). ' +
    'Fremde Bestandteile:') + LineEnding +
    _('- demucs.cpp von Sevag Hanssian (MIT) - die Trenn-Programme in tools\') + LineEnding +
    _('- FFmpeg (LGPL) - wird beim ersten Start heruntergeladen') + LineEnding +
    _('- Demucs-Modelle von Meta AI Research - werden von der Originalquelle ' +
    'heruntergeladen, nicht mit StemMaker verteilt. Die Lizenz der trainierten ' +
    'Modelle ist nicht abschliessend geklärt (ursprünglich für Forschungszwecke), ' +
    'deshalb nur für nicht-kommerzielle Nutzung gedacht.') + LineEnding +
    _('Alle Details: Info -> Lizenzen sowie LICENSE und THIRD-PARTY-NOTICES.md ' +
    'im StemMaker-Ordner.') +
    LineEnding + LineEnding +
    _('Traktor und STEMS sind Marken der Native Instruments GmbH. StemMaker ist ' +
    'ein unabhängiges Projekt und steht in keiner Verbindung zu Native Instruments.') +
    LineEnding + LineEnding +
    _('Diese Bestätigung gilt für diesen PC. Wird der StemMaker-Ordner auf einen ' +
    'anderen PC kopiert, kommt diese Frage dort noch einmal.');
end;

end.
