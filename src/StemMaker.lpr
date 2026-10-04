{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : StemMaker.lpr  (Hauptprogramm)
  Version : 1.6
  ----------------------------------------------------------------------------
  Das Hauptprogramm ist bewusst kurz:
    00. Läuft StemMaker schon? Dann dorthin wechseln und hier aufhören.
    0. Log starten, Sprache, Haftungsausschluss/Lizenz bestätigen
       (einmal pro PC), Spendenfenster zeigen (abschaltbar)
    1. Einstellungen lesen (welches Modell ist gewählt?)
    2. Startfenster mit den Prüfungen zeigen (uInit).
       Fehlt etwas, wird es dort heruntergeladen.
    3. Nur wenn das Startfenster "OK" meldet, geht das Hauptfenster auf.
       Klickt man dort "Beenden", endet das Programm hier.

  ÜBERSICHT DER UNITS
    uMain      Hauptfenster (Dateiliste, Einstellungen, Start/Abbrechen)
    uInit      Startfenster mit den Prüfungen + Download
    uStemJob   die eigentliche Umwandlung (ffmpeg -> demucs -> ffmpeg)
    uStemMP4   schreibt die Traktor-Stem-Infos in die MP4-Datei
    uDownload  Download (WinINet) und ZIP entpacken
    uLog       Log-Datei in Echtzeit, Absturz-Erkennung, Rechner-Infos
    uLogUI     fängt unerwartete Fehler ab und schreibt sie ins Log
    uDonate    Spendenfenster vor dem Start
    uLicense   Haftungsausschluss/Lizenz: Text, PC-Kennung, INI (ohne Oberfläche)
    uLicenseUI Fenster dazu (einmal pro PC bestätigen)
    uUpdate    update.json lesen, Prüfsummen, Update installieren (ohne Oberfläche)
    uUpdateUI  Update-Prüfung beim Start und Update-Fenster
    uInfo      Info-Fenster (Anleitung, Version, Spenden, Logs)
    uPower     PC wach halten, Energiesparplan, Akku, Standby-Erkennung
    uSingleInstance  nur ein StemMaker gleichzeitig (Sperre beim Start)
  ============================================================================ }
program StemMaker;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,          // unter Linux nötig für Threads
  {$ENDIF}
  Interfaces,        // bindet die LCL-Oberfläche ein (Win32 / GTK ...)
  SysUtils, Forms, uMain, uStemJob, uStemMP4, uInit, uDownload, uLog, uLogUI, uDonate, uInfo,
  uPower, uLang, uLangUI, uSingleInstance, uLicense, uLicenseUI, uUpdate, uUpdateUI;

{$R *.res}           // Programmsymbol + Versionsinfo

var
  Settings: TStemSettings;

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := APP_NAME;
  Application.Initialize;

  { 00. Läuft schon ein StemMaker? Dann Hinweis zeigen, dessen Fenster nach
        vorne holen und sofort aufhören - noch bevor Log, INI oder
        Warteschlange angefasst werden (Details in uSingleInstance). }
  if not SingleInstanceCheck(StemIniFileName) then
    Exit;

  { 0. Log-Datei anlegen (logs\StemMaker_<Datum>_LAEUFT.log) und alle
       unerwarteten Fehler mitschreiben lassen }
  LogInit;
  LogInstallExceptionHandler;
  LogLine('=== ' + APP_NAME + ' ' + APP_VERSION + ' gestartet ===');
  LogLine('Programm: ' + ParamStr(0));
  LogLine('Rechner:' + LineEnding + SystemInfoText);
  LogLine(Format('  Echte Kerne    : %d   (Auto-Einstellung: %d Teile, RAM reicht für max. %d)',
    [PhysicalCoreCount, AutoThreads, AutoThreadsRAMLimit]));
  if CpuHasAVX2 then
    LogLine('  Befehlssatz    : AVX2 -> schnelle demucs-Version')
  else if CpuHasAVX then
    LogLine('  Befehlssatz    : AVX (kein AVX2) -> mittlere demucs-Version')
  else
    LogLine('  Befehlssatz    : kein AVX -> kompatible demucs-Version');
  LogLine('  Energie        : ' + PowerInfoText);

  { 0a2. Sprache: beim allerersten Start fragen, sonst aus der INI }
  LangInitInteractive(StemIniFileName);
  LogLine('  Sprache        : ' + LangCode);

  { 0a3. Haftungsausschluss und Lizenzhinweise: einmal pro PC bestätigen
         (siehe uLicense). Abgelehnt -> StemMaker startet nicht. }
  if not EnsureTermsAccepted(StemIniFileName) then
  begin
    LogClose;
    Exit;
  end;

  { 0a4. Reste eines Updates (*.old) wegräumen }
  CleanupOldFiles(AppBaseDir);

  { 0a. Hat ein abgestürzter Lauf den Energiesparplan umgestellt und
        konnte ihn nicht mehr zurückstellen? Dann jetzt nachholen. }
  PowerRestoreAfterCrash(StemIniFileName);

  { 0b. Spendenfenster (falls nicht abgeschaltet) }
  ShowDonateDialogIfWanted;

  { 1. gewähltes Modell aus der INI holen }
  Settings := DefaultStemSettings;
  LoadToolSettings(Settings);

  { 2. + 3. erst prüfen, dann (bei OK) das Hauptfenster starten }
  if RunStartupCheck(Settings.Model, True) then
  begin
    Application.CreateForm(TfrmMain, frmMain);
    Application.Run;
  end
  else
    LogLine('Start im Prüffenster abgebrochen');

  { 4. Log normal abschließen ("_LAEUFT" verschwindet aus dem Namen).
       Kommt das Programm hier nie an (Absturz), bleibt "_LAEUFT" stehen
       und wird beim nächsten Start zu "_ABSTURZ". }
  LogClose;
end.
