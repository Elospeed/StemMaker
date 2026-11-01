{ ============================================================================
  Elospeed StemPacker  -  fertige Spuren (Master + 4 Stems pro Song) ohne
  KI im Stapel zu Traktor-Stem-Dateien (.stem.mp4) zusammensetzen.

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    StemPacker.lpr      dieses Hauptprogramm
    packerform.pas      Fenster und Bedienung
    packmatch.pas       Songs finden (Ordner + Namensmuster)
    packjob.pas         ffmpeg-Aufruf pro Song
    ..\..\ustemmp4.pas  Stem-Block schreiben (gemeinsam mit StemMaker)
    StemPacker.ico      Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemPacker;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, packerform;

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemPacker';
  Application.Initialize;
  Application.CreateForm(TPackerForm, MainPacker);
  Application.Run;
end.
