{ ============================================================================
  StemMaker-Turbo-Test  -  kleiner Geschwindigkeitstest für StemMaker 2.0
  (Turbo-Engine StemOnnx), zum Weitergeben an Tester. Ohne StemMaker selbst,
  ohne Installation: Vortest, ein echter Song, Bericht zum Kopieren/Mailen,
  am Ende wird alles gelöscht.

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    TurboTest.lpr    dieses Hauptprogramm
    testform.pas     Fenster, Ablauf, Bericht, Aufräumen
    paket.sh         baut das ZIP (Exe + engine\ + musik\ + LIESMICH)
  Mitbenutzt aus src\: udownload.pas (Modell laden, SHA-256), uload.pas
  (Auslastung), ulog.pas (Rechner-Infos).
  ============================================================================ }
program TurboTest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, testform,
  uSkalierung;   // kein Fenster grösser als der freie Bildschirm (DPI)

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'StemMaker Turbo-Test';
  Application.Initialize;
  Application.CreateForm(TTestForm, MainForm);
  Application.Run;
end.
