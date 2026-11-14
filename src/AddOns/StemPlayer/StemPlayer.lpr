{ ============================================================================
  Elospeed StemPlayer  -  Testplayer für Traktor-Stem-Dateien (.stem.mp4)
  aus Elospeed StemMaker. Mute / Solo / Lautstärke pro Stem.

  Autor : Elospeed  ·  ko-fi.com/elospeed
  Stand : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    1.8.6 (mit StemMaker 2.4), 14.11.2026: dunkle Titelleiste,
                     F1-Hilfe
    frühere Versionen: siehe Liste "Versionen" in playerform.pas
  ----------------------------------------------------------------------------

  Projektaufbau:
    StemPlayer.lpr   dieses Hauptprogramm
    playerform.pas   Fenster, Bedienung, ffmpeg-Aufruf, Temp-Ordner
    stemengine.pas   Audio-Thread: Mischen + Ausgabe über Windows-waveOut
    mp4stem.pas      liest Spuranzahl, Stem-Namen und -Farben aus der MP4
    djcontrols.pas   selbst gezeichnete Buttons, Fader und LED-Meter (DJ-Look)
    wellenform.pas   Wellenformen und Lupe
    bildtakt.pas     Abspielkopf im Takt des Monitors
    ..\..\udunklerrahmen.pas, ..\..\uhilfe.pas, ..\..\uwine.pas
                     gemeinsam mit StemMaker: Titelleiste, Hilfe, Wine
    StemPlayer.ico   Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemPlayer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, playerform,
  uWine,                                                   // unter Wine (Linux-AppImage): normales Fenster mit Minimieren
  uDunklerRahmen,                                          // dunkle Titelleiste passend zum dunklen Fenster
  uHilfe;                                                  // F1 öffnet das Kapitel StemPlayer der Anleitung

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;                     // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemPlayer';
  Application.Initialize;
  WineFensterEinrichten;                                   // nur unter Wine: Hauptfenster besitzt den Taskleisten-Knopf
  DunkleRahmenEinrichten;                                  // Windows 10/11: Titelleiste dunkel statt weiss
  HilfeTasteEinrichten;                                    // F1 in allen Fenstern (uHilfe)
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
