{ ============================================================================
  Elospeed StemPlayer  -  Testplayer für Traktor-Stem-Dateien (.stem.mp4)
  aus Elospeed StemMaker. Mute / Solo / Lautstärke pro Stem.

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    StemPlayer.lpr   dieses Hauptprogramm
    playerform.pas   Fenster, Bedienung, ffmpeg-Aufruf, Temp-Ordner
    stemengine.pas   Audio-Thread: Mischen + Ausgabe über Windows-waveOut
    mp4stem.pas      liest Spuranzahl, Stem-Namen und -Farben aus der MP4
    djcontrols.pas   selbst gezeichnete Buttons, Fader und LED-Meter (DJ-Look)
    wellenform.pas   Wellenformen und Lupe
    bildtakt.pas     Abspielkopf im Takt des Monitors
    StemPlayer.ico   Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemPlayer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, playerform,
  uWine,   // unter Wine (Linux-AppImage): normales Fenster mit Minimieren
  uDunklerRahmen;   // dunkle Titelleiste passend zum dunklen Fenster

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemPlayer';
  Application.Initialize;
  WineFensterEinrichten;   // nur unter Wine: Hauptfenster besitzt den Taskleisten-Knopf
  DunkleRahmenEinrichten;  // Windows 10/11: Titelleiste dunkel statt weiss
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
