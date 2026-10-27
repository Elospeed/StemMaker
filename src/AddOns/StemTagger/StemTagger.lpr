{ ============================================================================
  Elospeed StemTagger  -  Titel, Interpret, Cover und weitere Tags in
  Traktor-Stem-Dateien (.stem.mp4) setzen, ohne die Stem-Daten anzufassen.

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    StemTagger.lpr   dieses Hauptprogramm
    taggerform.pas   Fenster und Bedienung
    coverbild.pas    Cover-Bilder prüfen, umwandeln, verkleinern
    ..\..\ustemmp4.pas  Tags lesen/schreiben (gemeinsam mit StemMaker)
    StemTagger.ico   Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemTagger;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, taggerform;

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemTagger';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
