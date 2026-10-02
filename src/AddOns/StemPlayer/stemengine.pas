{ ============================================================================
  stemengine.pas  -  Audio-Engine für den Elospeed StemPlayer

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Prinzip:
    - ffmpeg hat vorher jede Spur der .stem.mp4 als rohes PCM
      (44.1 kHz, Stereo, 16 Bit signed little endian) in eine Temp-Datei
      dekodiert:  Spur 0 = Master, Spur 1..4 = Stems.
    - Dieser Thread liest die Temp-Dateien blockweise, mischt die Stems mit
      den aktuellen Lautstärken (Mute/Solo/Fader) zusammen und gibt das
      Ergebnis über die Windows-API waveOut aus (winmm.dll, in jedem Windows
      vorhanden -> keine zusätzlichen DLLs nötig).
    - Wenige kleine Puffer (~23 ms) -> Mute/Solo reagiert praktisch sofort.
    - Lautstärkeänderungen werden pro Puffer linear gerampt -> keine Klicks.

  Die GUI schreibt nur einfache Werte (Gain, Mode, Playing, SeekTo) und liest
  Position und Pegel. Das sind einzelne 32/64-Bit-Werte, die auf x86/x64
  atomar gelesen/geschrieben werden -> kein Locking nötig.

  Versionen:
    1.0  (01.10.2026)  Erste Version
    1.1  (02.10.2026)  unverändert (nur Kommentare ergänzt)
  ============================================================================ }
unit stemengine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, MMSystem;

const
  SAMPLE_RATE   = 44100;
  CHANNELS      = 2;
  BYTES_PER_FRM = 4;          // 2 Kanäle * 16 Bit
  TRACK_MAX     = 4;          // 0 = Master, 1..4 = Stems
  BUF_FRAMES    = 1024;       // Frames pro Puffer (~23 ms)
  BUF_COUNT     = 6;          // Anzahl Puffer in der Warteschlange (~140 ms)

type
  { Wiedergabemodus }
  TPlayMode = (
    pmStems,      // Stems gemischt (mit Mute/Solo/Fader)
    pmMaster,     // Originalmix aus Spur 0 (zum A/B-Vergleich)
    pmResidual    // Original minus Summe aller Stems = was bei der Trennung "fehlt"
  );

  { TStemEngine }

  TStemEngine = class(TThread)
  private
    FFiles      : array[0..TRACK_MAX] of TFileStream;
    FTrackCount : Integer;          // vorhandene Spuren (Master + Stems)
    FTotalFrames: Int64;            // Länge in Frames (kürzeste Spur)
    FWave       : HWAVEOUT;
    FEvent      : THandle;
    FHdr        : array[0..BUF_COUNT-1] of TWaveHdr;
    FBuf        : array[0..BUF_COUNT-1] of array[0..BUF_FRAMES*CHANNELS-1] of SmallInt;
    FQueued     : array[0..BUF_COUNT-1] of Boolean;
    FIn         : array[0..TRACK_MAX] of array[0..BUF_FRAMES*CHANNELS-1] of SmallInt;
    FReadPos    : Int64;            // nächste zu lesende Frame-Position
    FBasePos    : Int64;            // Frame-Position beim letzten Reset/Seek
    FCurGain    : array[0..TRACK_MAX] of Single;  // Gain des letzten Puffers (für Rampe)
    FPausedDev  : Boolean;
    FOpenError  : string;
    procedure OpenDevice;
    procedure CloseDevice;
    procedure FillBuffer(Idx: Integer);
    procedure DoSeek(Frame: Int64);
    function  DevicePosition: Int64;
  protected
    procedure Execute; override;
  public
    { --- von der GUI geschrieben --- }
    Gain       : array[0..TRACK_MAX] of Single;  // Zielgain je Spur (0..1), bereits inkl. Mute/Solo
    MasterVol  : Single;                         // Gesamtlautstärke 0..1
    Mode       : TPlayMode;
    Playing    : Boolean;
    SeekTo     : Int64;                          // >=0 -> Sprung anfordern, -1 = nichts
    { --- vom Thread geschrieben --- }
    PlayPos    : Int64;                          // aktuell hörbare Position in Frames
    Peak       : array[0..TRACK_MAX] of Single;  // Pegel je Spur (vor Fader) 0..1
    OutPeak    : array[0..1] of Single;          // Ausgangspegel L/R 0..1
    ClipCount  : Integer;                        // Anzahl übersteuerter Samples (Summe)
    EndReached : Boolean;

    { RawFiles[0] = Master, RawFiles[1..4] = Stems. Leere Einträge = Spur fehlt. }
    constructor Create(const RawFiles: array of string);
    destructor Destroy; override;

    property TotalFrames: Int64 read FTotalFrames;
    property TrackCount: Integer read FTrackCount;
    property OpenError: string read FOpenError;
  end;

implementation

{ TStemEngine }

constructor TStemEngine.Create(const RawFiles: array of string);
var
  i: Integer;
  Frames: Int64;
begin
  inherited Create(True);          // erst angehalten erzeugen
  FreeOnTerminate := False;
  FTotalFrames := High(Int64);
  FTrackCount := 0;
  for i := 0 to TRACK_MAX do
  begin
    FFiles[i] := nil;
    Gain[i] := 1.0;
    FCurGain[i] := 1.0;
    Peak[i] := 0;
    if (i <= High(RawFiles)) and (RawFiles[i] <> '') and FileExists(RawFiles[i]) then
    begin
      FFiles[i] := TFileStream.Create(RawFiles[i], fmOpenRead or fmShareDenyNone);
      Frames := FFiles[i].Size div BYTES_PER_FRM;
      if Frames < FTotalFrames then FTotalFrames := Frames;
      Inc(FTrackCount);
    end;
  end;
  if FTrackCount = 0 then FTotalFrames := 0;
  MasterVol := 1.0;
  Mode := pmStems;
  Playing := False;
  SeekTo := -1;
  PlayPos := 0;
  FReadPos := 0;
  FBasePos := 0;
  ClipCount := 0;
  EndReached := False;
  FEvent := CreateEvent(nil, False, False, nil);
  OpenDevice;
  Start;
end;

destructor TStemEngine.Destroy;
var i: Integer;
begin
  Terminate;
  if FEvent <> 0 then SetEvent(FEvent);
  WaitFor;
  CloseDevice;
  if FEvent <> 0 then CloseHandle(FEvent);
  for i := 0 to TRACK_MAX do FreeAndNil(FFiles[i]);
  inherited Destroy;
end;

procedure TStemEngine.OpenDevice;
var
  Fmt: TWaveFormatEx;
  i  : Integer;
  R  : MMRESULT;
begin
  FWave := 0;
  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.wFormatTag      := WAVE_FORMAT_PCM;
  Fmt.nChannels       := CHANNELS;
  Fmt.nSamplesPerSec  := SAMPLE_RATE;
  Fmt.wBitsPerSample  := 16;
  Fmt.nBlockAlign     := BYTES_PER_FRM;
  Fmt.nAvgBytesPerSec := SAMPLE_RATE * BYTES_PER_FRM;
  Fmt.cbSize          := 0;

  { CALLBACK_EVENT: Windows setzt FEvent, sobald ein Puffer fertig gespielt ist }
  R := waveOutOpen(@FWave, WAVE_MAPPER, @Fmt, DWORD_PTR(FEvent), 0, CALLBACK_EVENT);
  if R <> MMSYSERR_NOERROR then
  begin
    FWave := 0;
    FOpenError := Format('Audiogerät konnte nicht geöffnet werden (waveOutOpen Fehler %d).', [R]);
    Exit;
  end;
  { Gerät pausieren, damit nichts spielt, bevor die GUI "Play" drückt }
  waveOutPause(FWave);
  FPausedDev := True;

  for i := 0 to BUF_COUNT - 1 do
  begin
    FillChar(FHdr[i], SizeOf(TWaveHdr), 0);
    FHdr[i].lpData := @FBuf[i][0];
    FHdr[i].dwBufferLength := BUF_FRAMES * BYTES_PER_FRM;
    waveOutPrepareHeader(FWave, @FHdr[i], SizeOf(TWaveHdr));
    FQueued[i] := False;
  end;
end;

procedure TStemEngine.CloseDevice;
var i: Integer;
begin
  if FWave = 0 then Exit;
  waveOutReset(FWave);                 // alle Puffer sofort zurückgeben
  for i := 0 to BUF_COUNT - 1 do
    waveOutUnprepareHeader(FWave, @FHdr[i], SizeOf(TWaveHdr));
  waveOutClose(FWave);
  FWave := 0;
end;

{ Liefert die hörbare Position (Frames seit letztem Reset) }
function TStemEngine.DevicePosition: Int64;
var T: TMMTime;
begin
  Result := 0;
  if FWave = 0 then Exit;
  FillChar(T, SizeOf(T), 0);
  T.wType := TIME_SAMPLES;
  if waveOutGetPosition(FWave, @T, SizeOf(T)) = MMSYSERR_NOERROR then
  begin
    if T.wType = TIME_SAMPLES then
      Result := T.sample
    else if T.wType = TIME_BYTES then
      Result := T.cb div BYTES_PER_FRM;
  end;
end;

procedure TStemEngine.DoSeek(Frame: Int64);
var i: Integer;
begin
  if Frame < 0 then Frame := 0;
  if Frame > FTotalFrames then Frame := FTotalFrames;
  if FWave <> 0 then
  begin
    { Reset gibt alle Puffer zurück und setzt die Geräteposition auf 0 }
    waveOutReset(FWave);
    for i := 0 to BUF_COUNT - 1 do FQueued[i] := False;
    { Nach dem Reset ist das Gerät wieder "laufend" -> Zustand neu setzen }
    if not Playing then
    begin
      waveOutPause(FWave);
      FPausedDev := True;
    end
    else
    begin
      waveOutRestart(FWave);   // sicherstellen, dass das Gerät läuft
      FPausedDev := False;
    end;
  end;
  FReadPos := Frame;
  FBasePos := Frame;
  PlayPos := Frame;
  EndReached := False;
end;

{ Liest einen Block aus allen Spuren und mischt ihn in Puffer Idx. }
procedure TStemEngine.FillBuffer(Idx: Integer);
var
  t, n, Frames, Got: Integer;
  G0, G1, Step: array[0..TRACK_MAX] of Single;
  PkTrack: array[0..TRACK_MAX] of Integer;
  PkL, PkR: Integer;
  Acc, G: Single;
  V, Smp: Integer;
  Vol: Single;
  M: TPlayMode;
  Clips: Integer;
begin
  { Wie viele Frames gibt es noch? }
  Frames := BUF_FRAMES;
  if FReadPos + Frames > FTotalFrames then
    Frames := FTotalFrames - FReadPos;
  if Frames < 0 then Frames := 0;

  { Alle Spuren lesen (fehlende Spuren = Stille) }
  for t := 0 to TRACK_MAX do
  begin
    FillChar(FIn[t], SizeOf(FIn[t]), 0);
    PkTrack[t] := 0;
    if (FFiles[t] <> nil) and (Frames > 0) then
    begin
      FFiles[t].Position := FReadPos * BYTES_PER_FRM;
      Got := FFiles[t].Read(FIn[t][0], Frames * BYTES_PER_FRM);
      if Got < 0 then Got := 0;
    end;
  end;

  { Gain-Rampe vorbereiten: vom Gain des letzten Puffers zum aktuellen Ziel }
  M := Mode;
  Vol := MasterVol;
  for t := 0 to TRACK_MAX do
  begin
    G0[t] := FCurGain[t];
    case M of
      pmStems   : if t = 0 then G1[t] := 0 else G1[t] := Gain[t];
      pmMaster  : if t = 0 then G1[t] := 1 else G1[t] := 0;
      pmResidual: if t = 0 then G1[t] := 1 else G1[t] := -1;  // Original - Stems
    end;
    G1[t] := G1[t] * Vol;
    Step[t] := (G1[t] - G0[t]) / BUF_FRAMES;
    FCurGain[t] := G1[t];
  end;

  PkL := 0; PkR := 0; Clips := 0;
  for n := 0 to BUF_FRAMES * CHANNELS - 1 do
  begin
    Acc := 0;
    for t := 0 to TRACK_MAX do
    begin
      Smp := FIn[t][n];
      { Pegel je Spur (vor dem Fader) für die Anzeige }
      if Abs(Smp) > PkTrack[t] then PkTrack[t] := Abs(Smp);
      G := G0[t] + Step[t] * (n div CHANNELS);
      Acc := Acc + Smp * G;
    end;
    V := Round(Acc);
    if V > 32767 then begin V := 32767; Inc(Clips); end
    else if V < -32768 then begin V := -32768; Inc(Clips); end;
    FBuf[Idx][n] := SmallInt(V);
    if (n and 1) = 0 then
    begin
      if Abs(V) > PkL then PkL := Abs(V);
    end
    else if Abs(V) > PkR then PkR := Abs(V);
  end;

  { Anzeige-Werte veröffentlichen }
  for t := 0 to TRACK_MAX do Peak[t] := PkTrack[t] / 32768;
  OutPeak[0] := PkL / 32768;
  OutPeak[1] := PkR / 32768;
  if Clips > 0 then Inc(ClipCount, Clips);

  Inc(FReadPos, Frames);
  { Immer einen ganzen Puffer schreiben (Rest ist Stille) }
  FHdr[Idx].dwBufferLength := BUF_FRAMES * BYTES_PER_FRM;
  FHdr[Idx].dwFlags := FHdr[Idx].dwFlags and not WHDR_DONE;
  waveOutWrite(FWave, @FHdr[Idx], SizeOf(TWaveHdr));
  FQueued[Idx] := True;
end;

procedure TStemEngine.Execute;
var
  i: Integer;
  S: Int64;
  Pos: Int64;
begin
  while not Terminated do
  begin
    if FWave = 0 then
    begin
      Sleep(50);
      Continue;
    end;

    { Sprung angefordert? }
    S := SeekTo;
    if S >= 0 then
    begin
      SeekTo := -1;
      DoSeek(S);
    end;

    { Play/Pause umsetzen }
    if Playing and FPausedDev then
    begin
      waveOutRestart(FWave);
      FPausedDev := False;
    end
    else if (not Playing) and (not FPausedDev) then
    begin
      waveOutPause(FWave);
      FPausedDev := True;
      for i := 0 to TRACK_MAX do Peak[i] := 0;
      OutPeak[0] := 0; OutPeak[1] := 0;
    end;

    { Fertig gespielte Puffer neu füllen (auch im Pausezustand vorpuffern) }
    if FReadPos < FTotalFrames then
      for i := 0 to BUF_COUNT - 1 do
      begin
        if FQueued[i] and ((FHdr[i].dwFlags and WHDR_DONE) <> 0) then
          FQueued[i] := False;
        if (not FQueued[i]) and (FReadPos < FTotalFrames) then
          FillBuffer(i);
      end;

    { Hörbare Position = Startpunkt + Gerätezähler }
    Pos := FBasePos + DevicePosition;
    if Pos > FTotalFrames then Pos := FTotalFrames;
    PlayPos := Pos;
    if (FReadPos >= FTotalFrames) and (Pos >= FTotalFrames) then
      EndReached := True;

    { Warten, bis Windows einen Puffer zurückgibt (oder max. 20 ms) }
    WaitForSingleObject(FEvent, 20);
  end;
end;

end.
