{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : stemcli.lpr  (Programm StemCLI - Kommandozeilen-Version)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  StemCLI macht genau das Gleiche wie StemMaker.exe, nur ohne Fenster.
  Praktisch für Batch-Dateien, die Windows-Aufgabenplanung oder
  "Senden an". Die Arbeit selbst erledigt dieselbe Unit uStemJob.

  AUFRUF

    StemCLI <Datei|Ordner> [weitere ...] [Optionen]

  OPTIONEN

    -o <Ordner>      Ausgabeordner (Standard: neben der Originaldatei)
    -m ht|ft|v3      Modell: htdemucs (Standard) / htdemucs_ft / v3
    -t <Zahl>        Anzahl paralleler Teile für demucs
    -f aac|alac      Audio-Format (Standard aac)
    -b <kbit>        AAC-Bitrate (Standard 256)
    --overwrite      vorhandene *.stem.mp4 überschreiben
    --keep           Temp-Ordner behalten (zur Fehlersuche)
    --no-normalize   Lautstärke NICHT angleichen (Standard: Club-Pegel)
    --no-bassfix     Tiefbass NICHT von Other nach Bass verschieben
    --check <Datei>  nur prüfen: Spuren + Stem-Infos einer *.stem.mp4 zeigen
    --accept         Haftungsausschluss und Lizenzhinweise bestätigen
                     (einmal pro PC nötig, wie im Fenster von StemMaker)
    --ffmpeg <exe> / --demucs <Ordner> / --models <Ordner>
                     andere Werkzeug-Pfade

  Rückgabewert (ERRORLEVEL): 0 = alles OK, 1 = falscher Aufruf,
                             2 = mindestens eine Datei fehlgeschlagen,
                             3 = Haftungsausschluss noch nicht bestätigt
  ============================================================================ }
program StemCLI;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, LazFileUtils, FileUtil, IniFiles, uStemMP4, uStemJob, uPower,
  uLang, uLicense;

{$R *.res}           // Programmsymbol + Versionsinfo

type
  { kleine Hilfsklasse, weil OnLog/OnProgress Methoden eines Objekts
    sein müssen ("of object") }
  TCli = class
    LastPct: Integer;              // -1 = gerade keine Fortschrittszeile offen
    procedure DoLog(const Msg: string);
    procedure DoProgress(Percent: Integer; const Stage: string);
  end;

{ Protokollzeile ausgeben. War gerade eine Fortschrittszeile offen,
  zuerst eine neue Zeile beginnen. }
procedure TCli.DoLog(const Msg: string);
begin
  if LastPct >= 0 then
  begin
    WriteLn;
    LastPct := -1;
  end;
  WriteLn(Msg);
end;

{ Fortschritt in EINER Zeile anzeigen: #13 springt an den Zeilenanfang
  zurück, so wird die Zeile immer überschrieben statt neue anzuhängen }
procedure TCli.DoProgress(Percent: Integer; const Stage: string);
begin
  if Percent <> LastPct then
  begin
    Write(#13'  ', Stage, ': ', Percent: 3, ' %      ');
    LastPct := Percent;
  end;
end;

var
  S: TStemSettings;
  Files: TStringList;
  Found: TStringList;
  Cli: TCli;
  Job: TStemJob;
  I, J, OK, Failed, Skipped: Integer;
  A, OutF, Err: string;
  KeepAwake: Boolean;
  Pw: TPowerRun;
  Slept: QWord;
  Ini: TIniFile;
  LangC: string;
begin
  KeepAwake := True;
  { Standardwerte + Werkzeug-Pfade aus StemMaker.ini (falls vorhanden) }
  S := DefaultStemSettings;
  LoadToolSettings(S);
  { Sprache wie im Hauptprogramm: [Main] Language aus StemMaker.ini,
    fehlt der Eintrag -> Sprache von Windows }
  LangC := '';
  if FileExists(StemIniFileName) then
  begin
    Ini := TIniFile.Create(StemIniFileName);
    try
      LangC := Ini.ReadString('Main', 'Language', '');
    finally
      Ini.Free;
    end;
  end;
  if LangC = '' then
    LangC := LangSystemDefault;
  LangLoad(LangC);

  { Haftungsausschluss/Lizenz: einmal pro PC bestätigen (siehe uLicense).
    Wer StemMaker.exe auf diesem PC schon bestätigt hat, wird nicht gefragt.
    Sonst: Text zeigen und "--accept" verlangen - eine Rückfrage per
    Tastatur würde Batch-Dateien und die Aufgabenplanung blockieren. }
  for I := 1 to ParamCount do
    if ParamStr(I) = '--accept' then
      TermsSaveAccepted(StemIniFileName);
  if not TermsAccepted(StemIniFileName) then
  begin
    WriteLn(TermsTitle);
    WriteLn;
    WriteLn(TermsText);
    WriteLn;
    WriteLn(_('Einverstanden? Dann StemCLI einmal mit --accept aufrufen ' +
      '(oder StemMaker.exe starten und dort bestätigen).'));
    Halt(3);
  end;
  if (ParamCount = 1) and (ParamStr(1) = '--accept') then
  begin
    WriteLn(_('Bestätigt - StemCLI ist auf diesem PC freigegeben.'));
    Halt(0);
  end;
  Files := TStringList.Create;
  Cli := TCli.Create;
  Cli.LastPct := -1;
  OK := 0;
  Failed := 0;
  Skipped := 0;
  try
    { ---- Parameter auswerten ------------------------------------------- }
    I := 1;
    while I <= ParamCount do
    begin
      A := ParamStr(I);
      if (A = '-o') and (I < ParamCount) then begin Inc(I); S.OutputDir := ParamStr(I); end
      else if (A = '-t') and (I < ParamCount) then begin Inc(I); S.Threads := StrToIntDef(ParamStr(I), S.Threads); end
      else if (A = '-b') and (I < ParamCount) then
      begin
        { "-b auto" = wie die Quelle (Standard), "-b 256" = feste Bitrate }
        Inc(I);
        if LowerCase(ParamStr(I)) = 'auto' then
          S.AACAuto := True
        else
        begin
          S.AACAuto := False;
          S.AACBitrate := StrToIntDef(ParamStr(I), 256);
        end;
      end
      else if (A = '-f') and (I < ParamCount) then
      begin
        Inc(I);
        if LowerCase(ParamStr(I)) = 'alac' then S.Codec := scALAC else S.Codec := scAAC;
      end
      else if (A = '-m') and (I < ParamCount) then
      begin
        Inc(I);
        A := LowerCase(ParamStr(I));
        if A = 'ft' then S.Model := smHTDemucsFT
        else if A = 'v3' then S.Model := smHDemucsV3
        else S.Model := smHTDemucs;
      end
      else if (A = '--ffmpeg') and (I < ParamCount) then begin Inc(I); S.FFmpegExe := ParamStr(I); end
      else if (A = '--demucs') and (I < ParamCount) then begin Inc(I); S.DemucsDir := ParamStr(I); end
      else if (A = '--models') and (I < ParamCount) then begin Inc(I); S.ModelsDir := ParamStr(I); end
      else if A = '--overwrite' then S.Overwrite := True
      else if A = '--keep' then S.KeepTemp := True
      else if A = '--no-normalize' then S.Normalize := False
      else if A = '--no-bassfix' then S.BassFix := False
      else if A = '--accept' then        // schon oben ausgewertet
      else if A = '--no-awake' then KeepAwake := False
      else if (A = '--check') and (I < ParamCount) then
      begin
        { nur prüfen und sofort beenden }
        Inc(I);
        WriteLn(_('Spuren : '), CountTracks(ParamStr(I)));
        WriteLn(_('Stem   : '), ReadStemJSON(ParamStr(I)));
        Halt(0);
      end
      else if DirectoryExists(A) then
      begin
        { Ordner: alle Audiodateien darin (ohne Unterordner),
          vorhandene Stem-Dateien auslassen }
        Found := FindAllFiles(A, '*.*', False);
        try
          for J := 0 to Found.Count - 1 do
            if IsSupportedInput(Found[J]) and
               (Pos('.stem.', LowerCase(Found[J])) = 0) then
              Files.Add(Found[J]);
        finally
          Found.Free;
        end;
      end
      else
        Files.Add(A);              // einzelne Datei
      Inc(I);
    end;

    { keine Dateien -> kurze Hilfe }
    if Files.Count = 0 then
    begin
      WriteLn(Format(_('StemCLI %s (Elospeed StemMaker) - erzeugt Traktor Stem-Dateien (*.stem.mp4)'), ['1.6']));
      WriteLn(_('Aufruf: StemCLI <datei|ordner> [...] [-o ausgabeordner] [-m ht|ft|v3]'));
      WriteLn(_('        [-t teile] [-f aac|alac] [-b auto|kbit] [--overwrite] [--keep]'));
      WriteLn(_('        [--no-awake]  (PC darf während der Arbeit in den Ruhezustand)'));
      WriteLn(_('        [--no-normalize] [--no-bassfix]  (Klang-Optionen ausschalten)'));
      WriteLn(_('        StemCLI --check datei.stem.mp4'));
      WriteLn(_('        StemCLI --accept  (Haftungsausschluss/Lizenz bestätigen, einmal pro PC)'));
      Halt(1);
    end;

    { ---- PC wach halten (wie im Hauptprogramm, siehe uPower) ----------- }
    PowerRestoreAfterCrash(StemIniFileName);
    if PowerOnBattery then
      WriteLn(_('Hinweis: Der PC läuft auf Akku - am Netzteil geht es schneller.'));
    Pw := PowerBeginRun(KeepAwake, StemIniFileName);
    if Pw.SchemeSet then
      WriteLn(Format(_('Energiesparplan vorübergehend: %s -> %s'), [Pw.OldName, Pw.NewName]));

    { ---- Dateien nacheinander umwandeln -------------------------------- }
    try
    for I := 0 to Files.Count - 1 do
    begin
      Job := TStemJob.Create(S);
      try
        Job.OnLog := @Cli.DoLog;
        Job.OnProgress := @Cli.DoProgress;
        if Job.Run(Files[I], OutF, Err) then
          Inc(OK)
        else if Job.Skipped then
          Inc(Skipped)
        else
          Inc(Failed);
      finally
        Job.Free;
      end;
    end;
    finally
      { auch bei Strg+C-freiem Fehlerabbruch: alles zurückstellen }
      PowerEndRun(Pw, StemIniFileName);
    end;
    Slept := PowerSleptMS(Pw);
    if Slept > 0 then
      WriteLn(Format(_('Hinweis: Der PC war ca. %d min im Ruhezustand.'), [Slept div 60000]));
    if Cli.LastPct >= 0 then WriteLn;
    WriteLn(Format(_('Fertig: %d erfolgreich, %d übersprungen, %d fehlgeschlagen'),
      [OK, Skipped, Failed]));
    if Failed > 0 then
      ExitCode := 2;
  finally
    Cli.Free;
    Files.Free;
  end;
end.
