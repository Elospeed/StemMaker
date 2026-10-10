{ ============================================================================
  deckengine.pas  -  Audio-Engine für den Elospeed StemDecks-Test (4 Decks)

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Prinzip (wie stemengine.pas im StemPlayer, nur viermal so breit):
    - ffmpeg hat vorher die 4 Stems jedes Decks als rohes PCM
      (44.1 kHz, Stereo, 16 Bit signed little endian) in Temp-Dateien
      dekodiert. 4 Decks x 4 Stems = 16 Spuren.
      Spur-Nummer = Deck * 4 + Stem   (Deck 0..3 = A..D, Stem 0..3)
    - EIN Thread liest alle 16 Spuren blockweise, mischt sie und gibt sie
      über Windows-waveOut aus. Weil alle Decks im selben Puffer gemischt
      werden, laufen sie garantiert sampelgenau synchron - genau das, was
      bei einer zerlegten 5.1-Datei nötig ist (sonst verschieben sich
      Front, Center, Surround und LFE gegeneinander).
    - Fehlende Spuren (Deck leer) sind Stille.
    - Länge = längste Spur. Kürzere Spuren sind am Ende einfach still.
    - Lautstärkeänderungen werden pro Puffer linear gerampt -> keine Klicks.

  Die GUI schreibt nur einfache Werte (Gain, MasterVol, Playing, SeekTo) und
  liest Position und Pegel. Das sind einzelne 32/64-Bit-Werte, die auf x86/x64
  atomar gelesen/geschrieben werden -> kein Locking nötig.

  Versionen:
    0.1  (10.10.2026)  Erste Testversion (Machbarkeit 5.1 auf vier Decks)
  ============================================================================ }
unit deckengine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, MMSystem;

const
  SAMPLE_RATE   = 44100;
  CHANNELS      = 2;
  BYTES_PER_FRM = 4;          // 2 Kanäle * 16 Bit
  DECK_COUNT    = 4;          // Deck A..D
  STEMS_PER_DECK= 4;          // Drums, Bass, Other, Vocals
  TRACK_COUNT   = DECK_COUNT * STEMS_PER_DECK;   // 16 Spuren
  BUF_FRAMES    = 1024;       // Frames pro Puffer (~23 ms)
  BUF_COUNT     = 6;          // Anzahl Puffer in der Warteschlange (~140 ms)

type
  { TDeckEngine }

  TDeckEngine = class(TThread)
  private
    FFiles      : array[0..TRACK_COUNT-1] of TFileStream;
    FTrackCount : Integer;          // vorhandene Spuren
    FTotalFrames: Int64;            // Länge in Frames (längste Spur)
    FWave       : HWAVEOUT;
    FEvent      : THandle;
    FHdr        : array[0..BUF_COUNT-1] of TWaveHdr;
    FBuf        : array[0..BUF_COUNT-1] of array[0..BUF_FRAMES*CHANNELS-1] of SmallInt;
    FQueued     : array[0..BUF_COUNT-1] of Boolean;
    FIn         : array[0..TRACK_COUNT-1] of array[0..BUF_FRAMES*CHANNELS-1] of SmallInt;
    FReadPos    : Int64;            // nächste zu lesende Frame-Position
    FBasePos    : Int64;            // Frame-Position beim letzten Reset/Seek
    FCurGain    : array[0..TRACK_COUNT-1] of Single;  // Gain des letzten Puffers (für Rampe)
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
    Gain       : array[0..TRACK_COUNT-1] of Single;  // Zielgain je Spur (inkl. Mute + Deck-Fader)
    MasterVol  : Single;                             // Gesamtlautstärke 0..1
    Playing    : Boolean;
    SeekTo     : Int64;                              // >=0 -> Sprung anfordern, -1 = nichts
    { --- vom Thread geschrieben --- }
    PlayPos    : Int64;                              // aktuell hörbare Position in Frames
    Peak       : array[0..TRACK_COUNT-1] of Single;  // Pegel je Spur (vor dem Fader) 0..1
    OutPeak    : array[0..1] of Single;              // Ausgangspegel L/R 0..1
    ClipCount  : Integer;                            // Anzahl übersteuerter Samples (Summe)
    EndReached : Boolean;

    { RawFiles[Deck*4 + Stem]. Leere Einträge = Spur fehlt (Stille).
      StartFrame = Position, an der die Wiedergabe beginnt (nach dem
      Nachladen eines Decks läuft es an derselben Stelle weiter). }
    constructor Create(const RawFiles: array of string; StartFrame: Int64);
    destructor Destroy; override;

    property TotalFrames: Int64 read FTotalFrames;
    property TrackCount: Integer read FTrackCount;
    property OpenError: string read FOpenError;
  end;

implementation

{ TDeckEngine }

constructor TDeckEngine.Create(const RawFiles: array of string; StartFrame: Int64);
var
  i: Integer;
  Frames: Int64;
begin
  inherited Create(True);          // erst angehalten erzeugen
  FreeOnTerminate := False;
  FTotalFrames := 0;
  FTrackCount := 0;
  for i := 0 to TRACK_COUNT - 1 do
  begin
    FFiles[i] := nil;
    Gain[i] := 1.0;
    FCurGain[i] := 0;              // sanft einblenden
    Peak[i] := 0;
    if (i <= High(RawFiles)) and (RawFiles[i] <> '') and FileExists(RawFiles[i]) then
    begin
      FFiles[i] := TFileStream.Create(RawFiles[i], fmOpenRead or fmShareDenyNone);
      Frames := FFiles[i].Size div BYTES_PER_FRM;
      if Frames > FTotalFrames then FTotalFrames := Frames;
      Inc(FTrackCount);
    end;
  end;
  if StartFrame < 0 then StartFrame := 0;
  if StartFrame > FTotalFrames then StartFrame := 0;
  MasterVol := 1.0;
  Playing := False;
  SeekTo := -1;
  PlayPos := StartFrame;
  FReadPos := StartFrame;
  FBasePos := StartFrame;
  ClipCount := 0;
  EndReached := False;
  FEvent := CreateEvent(nil, False, False, nil);
  OpenDevice;
  Start;
end;

destructor TDeckEngine.Destroy;
var i: Integer;
begin
  Terminate;
  if FEvent <> 0 then SetEvent(FEvent);
  WaitFor;
  CloseDevice;
  if FEvent <> 0 then CloseHandle(FEvent);
  for i := 0 to TRACK_COUNT - 1 do FreeAndNil(FFiles[i]);
  inherited Destroy;
end;

procedure TDeckEngine.OpenDevice;
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

procedure TDeckEngine.CloseDevice;
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
function TDeckEngine.DevicePosition: Int64;
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

procedure TDeckEngine.DoSeek(Frame: Int64);
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
      waveOutRestart(FWave);
      FPausedDev := False;
    end;
  end;
  FReadPos := Frame;
  FBasePos := Frame;
  PlayPos := Frame;
  EndReached := False;
end;

{ Liest einen Block aus allen 16 Spuren und mischt ihn in Puffer Idx. }
procedure TDeckEngine.FillBuffer(Idx: Integer);
var
  t, n, Frames, Got: Integer;
  G0, Step: array[0..TRACK_COUNT-1] of Single;
  Active: array[0..TRACK_COUNT-1] of Boolean;
  PkTrack: array[0..TRACK_COUNT-1] of Integer;
  PkL, PkR: Integer;
  Acc, G1, Vol: Single;
  V, Smp, Clips: Integer;
begin
  { Wie viele Frames gibt es noch? }
  Frames := BUF_FRAMES;
  if FReadPos + Frames > FTotalFrames then
    Frames := FTotalFrames - FReadPos;
  if Frames < 0 then Frames := 0;

  Vol := MasterVol;
  for t := 0 to TRACK_COUNT - 1 do
  begin
    PkTrack[t] := 0;
    Active[t] := FFiles[t] <> nil;
    if Active[t] then
    begin
      FillChar(FIn[t], SizeOf(FIn[t]), 0);   // Rest (Spurende) = Stille
      if Frames > 0 then
      begin
        FFiles[t].Position := FReadPos * BYTES_PER_FRM;
        Got := FFiles[t].Read(FIn[t][0], Frames * BYTES_PER_FRM);
        if Got < 0 then Got := 0;
      end;
    end;
    { Gain-Rampe: vom Gain des letzten Puffers zum aktuellen Ziel }
    G0[t] := FCurGain[t];
    G1 := Gain[t] * Vol;
    Step[t] := (G1 - G0[t]) / BUF_FRAMES;
    FCurGain[t] := G1;
  end;

  PkL := 0; PkR := 0; Clips := 0;
  for n := 0 to BUF_FRAMES * CHANNELS - 1 do
  begin
    Acc := 0;
    for t := 0 to TRACK_COUNT - 1 do
      if Active[t] then
      begin
        Smp := FIn[t][n];
        { Pegel je Spur (vor dem Fader) für die Anzeige }
        if Abs(Smp) > PkTrack[t] then PkTrack[t] := Abs(Smp);
        Acc := Acc + Smp * (G0[t] + Step[t] * (n div CHANNELS));
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
  for t := 0 to TRACK_COUNT - 1 do Peak[t] := PkTrack[t] / 32768;
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

procedure TDeckEngine.Execute;
var
  i: Integer;
  S, Pos: Int64;
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
      for i := 0 to TRACK_COUNT - 1 do Peak[i] := 0;
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
