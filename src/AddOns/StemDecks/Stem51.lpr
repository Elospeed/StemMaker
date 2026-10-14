{ ============================================================================
  Elospeed 5.1 -> Stem  -  schlanke Variante von StemDecks
  5.1-Datei (VOB, MKV ...) reinziehen -> <Name>.stem.mp4 für Traktor,
  die vier 5.1-Teile direkt als Stems (ohne KI).

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    Stem51.lpr       dieses Hauptprogramm
    stem51form.pas   Fenster, Einstellungen, ffmpeg-Aufrufe
    surround51.pas   (mitbenutzt) 5.1 erkennen, ffmpeg-Parameter
    decklog.pas      (mitbenutzt) Sprache DE/EN und Protokoll
    ..\..\ustemmp4.pas (mitbenutzt) Stem-Block wie in StemMaker
  ============================================================================ }
program Stem51;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, stem51form;

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed 5.1 -> Stem';
  Application.Initialize;
  Application.CreateForm(TPackForm, PackForm);
  Application.Run;
end.
