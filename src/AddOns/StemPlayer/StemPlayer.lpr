{ ============================================================================
  Elospeed StemPlayer  -  Testplayer für Traktor-Stem-Dateien (.stem.mp4)
  aus Elospeed StemMaker. Mute / Solo / Lautstärke pro Stem.

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    StemPlayer.lpr   dieses Hauptprogramm
    playerform.pas   Fenster, Bedienung, ffmpeg-Aufruf, Temp-Ordner
    stemengine.pas   Audio-Thread: Mischen + Ausgabe über Windows-waveOut
    mp4stem.pas      liest Spuranzahl, Stem-Namen und -Farben aus der MP4
    StemPlayer.ico   Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemPlayer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, playerform;

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemPlayer';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
