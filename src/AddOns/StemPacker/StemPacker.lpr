{ ============================================================================
  Elospeed StemPacker  -  fertige Spuren (Master + 4 Stems pro Song) ohne
  KI im Stapel zu Traktor-Stem-Dateien (.stem.mp4) zusammensetzen.

  Autor : Elospeed  ·  ko-fi.com/elospeed
  Stand : 14.11.2026
  ----------------------------------------------------------------------------
  ÄNDERUNGEN
    0.3.1 (mit StemMaker 2.4), 14.11.2026: Design wie StemMaker
                     (PackDesignAnwenden), F1-Hilfe
    frühere Versionen: siehe ÄNDERUNGEN in packerform.pas
  ----------------------------------------------------------------------------

  Projektaufbau:
    StemPacker.lpr      dieses Hauptprogramm
    packerform.pas      Fenster und Bedienung
    packmatch.pas       Songs finden (Ordner + Namensmuster)
    packjob.pas         ffmpeg-Aufruf pro Song
    packdetect.pas      Benennung der Dateien erkennen (Einfach-Modus)
    upackdesign.pas     hell oder dunkel wie StemMaker
    uhilfe.pas          "?" und F1: Anleitung im Browser (Kopie)
    uwine.pas           läuft es unter Wine? (Kopie)
    ustatusdraw.pas     Statusspalte und Ko-fi-Knopf zeichnen (Kopie)
    ..\..\ustemmp4.pas  Stem-Block schreiben (gemeinsam mit StemMaker)
    StemPacker.ico      Programmsymbol (wird über die .lpi eingebunden)
  ============================================================================ }
program StemPacker;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uPackDesign, packerform,
  uHilfe;                                                  // F1 öffnet das Kapitel StemPacker der Anleitung

{$R *.res}   // Symbol, Versionsinfo und Manifest (von Lazarus erzeugt)

begin
  RequireDerivedFormResource := False;                     // Formular wird im Code aufgebaut (keine .lfm)
  Application.Scaled := True;
  Application.Title := 'Elospeed StemPacker';
  { Hell/Dunkel wie StemMaker: vor dem ersten Fenster (siehe uPackDesign) }
  PackDesignAnwenden;
  Application.Initialize;
  HilfeTasteEinrichten;                                    // F1 in allen Fenstern (uHilfe)
  Application.CreateForm(TPackerForm, MainPacker);
  Application.Run;
end.
