{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uqueue.pas  (Unit uQueue)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Alles rund ums Umwandeln ganzer Sammlungen:

  1. WARTESCHLANGE MERKEN
     Die Dateiliste wird bei jeder Änderung in StemMaker_queue.txt
     gespeichert (neben StemMaker.ini). Stürzt StemMaker ab, wird es
     beendet oder fällt der Strom aus, ist die Liste beim nächsten Start
     wieder da - mit dem Stand, welche Dateien schon fertig sind.
     Eine Zeile pro Datei, Felder durch TAB getrennt:
        Zustand <TAB> voller Pfad <TAB> Basisordner <TAB> Länge in ms
     Zustand: w = wartet, r = lief gerade (= unterbrochen), o = fertig,
              s = übersprungen, f = Fehler, c = abgebrochen
     Basisordner: für "Unterordner nachbauen" - der Ordner, ab dem die
              Struktur übernommen wird (leer bei einzeln hinzugefügten Dateien)

  2. LÄNGE DER SONGS ERMITTELN
     Für die Zeitschätzung vor dem Start muss man wissen, wie lang die
     Songs sind. Das fragt TDurationProber im Hintergrund bei ffmpeg nach
     ("ffmpeg -i datei" schreibt "Duration: 00:05:12.34"). Pro Datei dauert
     das nur einen Sekundenbruchteil; das Fenster bleibt dabei bedienbar.

  3. TEMPO DIESES PCs LERNEN
     Nach jeder fertigen Datei wird gemerkt, wie viele Sekunden der PC pro
     Minute Musik gebraucht hat - getrennt nach Modell und Prozessor
     (StemMaker.ini, Abschnitt [Speed]). Damit wird die Schätzung "87
     Tracks, ca. 6 h 40 min" mit jedem Track genauer. Wird der Ordner auf
     einen anderen PC kopiert, gilt dort ein eigener Wert (anderer
     Prozessor-Name).
  ============================================================================ }
unit uQueue;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, Process, UTF8Process, uStemJob, uLog;

type
  TQueueEntry = record
    State : Char;      // w r o s f c (siehe oben)
    Path  : string;
    Root  : string;
    DurMS : Int64;     // 0 = noch unbekannt
  end;
  TQueueEntries = array of TQueueEntry;

  { Ergebnis einer Längen-Abfrage (läuft im Hauptthread) }
  TDurationEvent = procedure(const Path: string; DurMS: Int64) of object;

  { fragt die Länge mehrerer Dateien nacheinander bei ffmpeg ab }
  TDurationProber = class(TThread)
  private
    FFFmpeg : string;
    FPaths  : TStringList;
    FOnResult: TDurationEvent;
    FResPath: string;
    FResDur : Int64;
    procedure DoResult;
  protected
    procedure Execute; override;
  public
    constructor Create(const FFmpegExe: string; Paths: TStrings;
      OnResult: TDurationEvent);
    destructor Destroy; override;
  end;

{ Dateiname der gespeicherten Warteschlange }
function QueueFileName: string;
procedure QueueSave(const Entries: TQueueEntries);
function QueueLoad: TQueueEntries;
procedure QueueDelete;

{ Länge einer Datei in ms über ffmpeg (0 = unbekannt). Blockiert kurz. }
function ProbeDurationMS(const FFmpegExe, FileName: string): Int64;

{ gelerntes Tempo: Sekunden Rechenzeit pro Minute Musik (0 = unbekannt) }
function SpeedLoad(const IniName: string; Model: TStemModel): Double;
{ nach einer fertigen Datei: Tempo nachführen }
procedure SpeedLearn(const IniName: string; Model: TStemModel;
  WorkMS, AudioMS: Int64);
{ grobe Startwerte, solange noch nichts gelernt ist (gemessen auf einem
  i7-12700KF; auf anderen PCs entsprechend schneller/langsamer) }
function SpeedDefault(Model: TStemModel): Double;

implementation

function QueueFileName: string;
begin
  Result := ExtractFilePath(StemIniFileName) + 'StemMaker_queue.txt';
end;

{ Speichern: zuerst in eine Hilfsdatei schreiben, dann umbenennen.
  So ist die Liste nie halb geschrieben, auch wenn genau in dem Moment
  der Strom ausfällt. }
procedure QueueSave(const Entries: TQueueEntries);
var
  L: TStringList;
  I: Integer;
  Tmp: string;
begin
  if Length(Entries) = 0 then
  begin
    QueueDelete;
    Exit;
  end;
  L := TStringList.Create;
  try
    for I := 0 to High(Entries) do
      with Entries[I] do
        L.Add(State + #9 + Path + #9 + Root + #9 + IntToStr(DurMS));
    Tmp := QueueFileName + '.tmp';
    try
      L.SaveToFile(Tmp);
      if FileExists(QueueFileName) then
        SysUtils.DeleteFile(QueueFileName);
      RenameFile(Tmp, QueueFileName);
    except
      on E: Exception do
        LogLine('Warteschlange konnte nicht gespeichert werden: ' + E.Message);
    end;
  finally
    L.Free;
  end;
end;

function QueueLoad: TQueueEntries;
var
  L, F: TStringList;
  I, N: Integer;
begin
  Result := nil;
  if not FileExists(QueueFileName) then Exit;
  L := TStringList.Create;
  F := TStringList.Create;
  try
    try
      L.LoadFromFile(QueueFileName);
    except
      Exit;
    end;
    F.Delimiter := #9;
    F.StrictDelimiter := True;           // Leerzeichen in Pfaden nicht trennen
    SetLength(Result, L.Count);
    N := 0;
    for I := 0 to L.Count - 1 do
    begin
      F.DelimitedText := L[I];
      if (F.Count < 2) or (F[0] = '') or (F[1] = '') then Continue;
      Result[N].State := F[0][1];
      Result[N].Path := F[1];
      if F.Count > 2 then Result[N].Root := F[2] else Result[N].Root := '';
      if F.Count > 3 then Result[N].DurMS := StrToInt64Def(F[3], 0) else Result[N].DurMS := 0;
      Inc(N);
    end;
    SetLength(Result, N);
  finally
    F.Free;
    L.Free;
  end;
end;

procedure QueueDelete;
begin
  if FileExists(QueueFileName) then
    SysUtils.DeleteFile(QueueFileName);
end;

{ ---------------------------------------------------------------------------
  Länge über ffmpeg: "ffmpeg -hide_banner -i datei" ohne Ausgabedatei.
  ffmpeg meckert dann "At least one output file must be specified" und
  endet mit Fehlercode - das ist hier normal. Uns interessiert nur die
  Zeile "Duration: 00:05:12.34".
  --------------------------------------------------------------------------- }
function ProbeDurationMS(const FFmpegExe, FileName: string): Int64;
var
  P: TProcessUTF8;                  // UTF8-Variante: Umlaute im Pfad (Tiësto)
  Outp: TStringList;
  S: string;
  I, K: Integer;
  H, M: Integer;
  Sec: Double;
  FS: TFormatSettings;
begin
  Result := 0;
  if not FileExists(FFmpegExe) then Exit;
  P := TProcessUTF8.Create(nil);
  Outp := TStringList.Create;
  try
    P.Executable := FFmpegExe;
    P.Parameters.Add('-hide_banner');
    P.Parameters.Add('-nostdin');
    P.Parameters.Add('-i');
    P.Parameters.Add(FileName);
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole, poWaitOnExit];
    try
      P.Execute;
      Outp.LoadFromStream(P.Output);
    except
      Exit;
    end;
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    for I := 0 to Outp.Count - 1 do
    begin
      K := Pos('Duration: ', Outp[I]);
      if K = 0 then Continue;
      S := Copy(Outp[I], K + 10, 11);              // "00:05:12.34"
      if (Length(S) >= 8) and TryStrToInt(Copy(S, 1, 2), H) and
         TryStrToInt(Copy(S, 4, 2), M) and
         TryStrToFloat(Copy(S, 7, 5), Sec, FS) then
        Result := Round((H * 3600 + M * 60 + Sec) * 1000);
      Break;
    end;
  finally
    Outp.Free;
    P.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TDurationProber
  --------------------------------------------------------------------------- }
constructor TDurationProber.Create(const FFmpegExe: string; Paths: TStrings;
  OnResult: TDurationEvent);
begin
  inherited Create(True);                 // erst anlegen, Start macht der Aufrufer
  FFFmpeg := FFmpegExe;
  FPaths := TStringList.Create;
  FPaths.Assign(Paths);
  FOnResult := OnResult;
  FreeOnTerminate := False;
end;

destructor TDurationProber.Destroy;
begin
  FPaths.Free;
  inherited Destroy;
end;

procedure TDurationProber.DoResult;
begin
  if Assigned(FOnResult) then
    FOnResult(FResPath, FResDur);
end;

procedure TDurationProber.Execute;
var
  I: Integer;
begin
  for I := 0 to FPaths.Count - 1 do
  begin
    if Terminated then Exit;
    FResPath := FPaths[I];
    FResDur := ProbeDurationMS(FFFmpeg, FPaths[I]);
    if Terminated then Exit;
    Synchronize(@DoResult);
  end;
end;

{ ---------------------------------------------------------------------------
  Tempo lernen
  Schlüssel z.B. "htdemucs|12th Gen Intel(R) Core(TM) i7-12700KF"
  Wert = Sekunden Rechenzeit pro Minute Musik.
  Neuer Wert = Mittel aus altem und neuem Messwert (so wirken einzelne
  Ausreisser, z.B. wenn nebenher gespielt wurde, nicht zu stark).
  --------------------------------------------------------------------------- }
function SpeedKey(Model: TStemModel): string;
begin
  case Model of
    smHTDemucsFT: Result := 'htdemucs_ft';
    smHDemucsV3 : Result := 'hdemucs_v3';
  else
    Result := 'htdemucs';
  end;
  Result := Result + '|' + SysCPUName;
end;

function SpeedLoad(const IniName: string; Model: TStemModel): Double;
var
  Ini: TIniFile;
  FS: TFormatSettings;
begin
  Result := 0;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  try
    Ini := TIniFile.Create(IniName);
    try
      Result := StrToFloatDef(Ini.ReadString('Speed', SpeedKey(Model), '0'), 0, FS);
    finally
      Ini.Free;
    end;
  except
    Result := 0;
  end;
end;

procedure SpeedLearn(const IniName: string; Model: TStemModel;
  WorkMS, AudioMS: Int64);
var
  Ini: TIniFile;
  Old, Now_: Double;
  FS: TFormatSettings;
begin
  if (AudioMS < 30000) or (WorkMS <= 0) then
    Exit;                                 // zu kurz für eine sinnvolle Messung
  Now_ := (WorkMS / 1000) / (AudioMS / 60000);
  Old := SpeedLoad(IniName, Model);
  if Old > 0 then
    Now_ := (Old + Now_) / 2;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteString('Speed', SpeedKey(Model), FormatFloat('0.0', Now_, FS));
    finally
      Ini.Free;
    end;
  except
    { nicht schlimm - dann wird beim nächsten Mal neu gemessen }
  end;
end;

function SpeedDefault(Model: TStemModel): Double;
begin
  { Messwerte von Elospeeds i7-12700KF (12-Minuten-Track):
      htdemucs 22:16 -> ca. 111 s pro Minute Musik
      v3       12:33 -> ca.  63 s pro Minute Musik
      ft       ca. 4x htdemucs }
  case Model of
    smHTDemucsFT: Result := 440;
    smHDemucsV3 : Result := 63;
  else
    Result := 111;
  end;
end;

end.
