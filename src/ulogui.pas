{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ulogui.pas  (Unit uLogUI)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Fängt alle Fehler im Programm ab, die sonst nur als Meldungsfenster
  erscheinen würden, und schreibt sie mit "Aufrufkette" ins Log - also
  WO im Code der Fehler passiert ist (Datei + Zeilennummer).
  Danach erscheint eine verständliche Meldung auf Deutsch.

  Das steht in einer eigenen Unit, weil es die Oberfläche (Unit Forms)
  braucht. uLog selbst bleibt ohne Oberfläche, damit auch die
  Kommandozeilen-Version StemCLI sie benutzen kann.
  ============================================================================ }
unit uLogUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Dialogs, uLog, uLang;

{ Fehler-Abfangen einschalten (einmal beim Programmstart aufrufen) }
procedure LogInstallExceptionHandler;

implementation

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
  MessageDlg(_('Unerwarteter Fehler'),
    _('Es ist ein unerwarteter Fehler aufgetreten:') + LineEnding + LineEnding +
    E.Message + LineEnding + LineEnding +
    _('Die Details stehen im Log:') + LineEnding + ExtractFileName(LogFileName) +
    LineEnding + LineEnding +
    _('StemMaker läuft weiter. Falls etwas nicht mehr richtig funktioniert, ' +
    'bitte das Programm neu starten.'), mtError, [mbOK], 0);
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
