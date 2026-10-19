{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulogui.pas  (Unit uLogUI)
  Version : wie StemMaker, siehe APP_VERSION in version.inc
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Fängt alle Fehler im Programm ab, die sonst nur als Meldungsfenster
  erscheinen würden, und schreibt sie mit "Aufrufkette" ins Log - also
  WO im Code der Fehler passiert ist (Datei + Zeilennummer).
  Danach erscheint eine verständliche Meldung auf Deutsch, mit dem Knopf
  "Fehlerbericht senden..." (Unit uReport - nur auf Wunsch des Nutzers).

  Das steht in einer eigenen Unit, weil es die Oberfläche (Unit Forms)
  braucht. uLog selbst bleibt ohne Oberfläche, damit auch die
  Kommandozeilen-Version StemCLI sie benutzen kann.
  ============================================================================ }
unit uLogUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, uLog, uLang;

{ Fehler-Abfangen einschalten (einmal beim Programmstart aufrufen) }
procedure LogInstallExceptionHandler;

implementation

uses
  uReport;

type
  { Application.OnException braucht eine Methode eines Objekts -
    deshalb diese kleine Hilfsklasse }
  TExceptionLogger = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;

var
  GExceptionLogger: TExceptionLogger = nil;

procedure TExceptionLogger.HandleException(Sender: TObject; E: Exception);
begin
  LogMarkError;                    // Log-Name endet dann auf "_FEHLER"
  LogLine('!!! UNERWARTETER FEHLER: ' + E.ClassName + ': ' + E.Message);
  LogLine('    Aufrufkette:' + LineEnding + ExceptionStackText);
  { verständliche Meldung auf Deutsch statt der englischen Standardmeldung }
  if QuestionDlg(_('Unerwarteter Fehler'),
    _('Es ist ein unerwarteter Fehler aufgetreten:') + LineEnding + LineEnding +
    E.Message + LineEnding + LineEnding +
    _('Die Details stehen im Log:') + LineEnding + ExtractFileName(LogFileName) +
    LineEnding + LineEnding +
    _('StemMaker läuft weiter. Falls etwas nicht mehr richtig funktioniert, ' +
    'bitte das Programm neu starten.'), mtError,
    [mrYes, _('Fehlerbericht senden...'), mrOK, 'OK', 'IsDefault'], 0) = mrYes then
    ShowErrorReport(LogFileName, E.ClassName + ': ' + E.Message);
end;

procedure LogInstallExceptionHandler;
begin
  if GExceptionLogger = nil then
    GExceptionLogger := TExceptionLogger.Create;
  Application.OnException := @GExceptionLogger.HandleException;
end;

finalization
  FreeAndNil(GExceptionLogger);

end.
