{ ============================================================================
  Elospeed StemDecks  -  Machbarkeitstest: 5.1-Ton auf vier Decks
  (Deck A..D mit je 4 Stems, alle synchron, Optik wie der StemPlayer).

  Autor : Elospeed  ·  ko-fi.com/elospeed

  Projektaufbau:
    StemDecks.lpr    dieses Hauptprogramm
    deckform.pas     Fenster, Bedienung, ffmpeg/StemCLI-Aufrufe, Temp-Ordner
    deckengine.pas   Audio-Thread: 16 Spuren mischen + Ausgabe über waveOut
    surround51.pas   5.1 erkennen und in A_/B_/C_/D_ zerlegen
    ..\StemPlayer\mp4stem.pas    (mitbenutzt) Stem-Datei prüfen, Namen/Farben
    ..\StemPlayer\djcontrols.pas (mitbenutzt) Buttons, Fader, LED-Meter
    StemDecks.ico    Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemDecks;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, deckform;

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;   // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemDecks';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
