{ ============================================================================
  Elospeed StemTagger  -  Titel, Interpret, Cover und weitere Tags in
  Traktor-Stem-Dateien (.stem.mp4) setzen, ohne die Stem-Daten anzufassen.

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    StemTagger.lpr   dieses Hauptprogramm
    taggerform.pas   Fenster und Bedienung
    coverbild.pas    Cover-Bilder prüfen, umwandeln, verkleinern
    ump4tags.pas     Tags in .stem.mp4 lesen/schreiben
    djcontrols.pas,
    djextra.pas      dunkle Knöpfe, Schalter, Auswahllisten (wie StemPlayer)
    ulang.pas        Übersetzungen (lang\*.po)
    ustatusdraw.pas  Ko-fi-Knopf zeichnen
    uskalierung.pas  Hilfen für die Windows-Skalierung (DPI)
    uwine.pas        unter Wine (Linux) normales Fenster mit Minimieren
    StemTagger.ico   Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemTagger;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, taggerform,
  uWine;   // unter Wine (Linux-AppImage): normales Fenster mit Minimieren

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemTagger';
  Application.Initialize;
  WineFensterEinrichten;   // nur unter Wine: Hauptfenster besitzt den Taskleisten-Knopf
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
