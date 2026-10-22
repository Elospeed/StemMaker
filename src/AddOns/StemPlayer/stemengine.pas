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

  Loop A-B (ab 1.2):
    - Die GUI setzt LoopStart (A) und LoopEnd (B) in Frames und erhöht danach
      LoopSerial. Der Thread übernimmt beide Werte, sobald sich LoopSerial
      ändert (so passen A und B immer zusammen).
    - Beim Lesen wird genau bei B auf A zurückgesprungen, mitten im Puffer,
      also ohne Lücke (Frame-genau). Damit es am Übergang nicht knackt, wird
      kurz vor B aus- und nach A wieder eingeblendet (LOOP_FADE, ca. 1,5 ms).
    - Ein Loop "fängt" die Wiedergabe nur, wenn sie von vorne an B ankommt.
      Wer hinter B springt, hört einfach weiter bis zum Ende.
    - Weil durch den Rücksprung die Geräteposition nicht mehr einfach
      "Startpunkt + gespielte Frames" ist, merkt sich der Thread für jedes
      Stück Audio, das er an Windows schickt, wo es in der Datei herkommt
      (FSeg). Daraus wird die hörbare Position zurückgerechnet (MapPosition).

  Scrubbing (ab 1.3):
    - Solange die GUI Scrubbing = True setzt (Welle in der Lupe wird mit der
      Maus gezogen), folgt ein eigener Lesekopf FScrubPos der Mausposition
      ScrubTarget. Er bewegt sich nicht sprunghaft, sondern so schnell wie
      die Maus (gemessen an der echten Zeit, geglättet), dazu ein kleiner
      Anteil, der den Abstand zum Ziel aufholt (wie ein Plattenteller unter
      der Hand): schnell gezogen = schneller und höher, langsam = tief,
      rückwärts = rückwärts. Der Kopf läuft nicht über die Hand hinaus,
      Maus still = nach wenigen Puffern Stille. Ob die Maus steht, merkt der
      Thread an der Zeit seit der letzten Bewegung (mindestens 30 ms bzw.
      das Doppelte des letzten Abstands zwischen zwei Bewegungen): dann
      wird im nächsten Puffer sofort ausgeblendet, statt langsam
      auszulaufen.
    - Läuft der Kopf mehr als SCRUB_MAXLEAD hinterher (sehr schnell
      gezogen, über der Höchstgeschwindigkeit), springt er nach (vorher
      ein Puffer aus-, danach einblenden). Sonst würde er nach dem
      Anhalten noch lange weiterlaufen.
    - Loslassen bei Pause: erst ausblenden, dann zwei stille Puffer und
      etwas warten, bis Windows alles abgespielt hat, erst dann neu
      aufsetzen (kein Knacken, kein abgeschnittenes Ausblenden).
    - Loslassen beim Abspielen: wie bei einer Platte, die man loslässt.
      Der letzte Scrub-Puffer beschleunigt auf normale Geschwindigkeit,
      danach liest die normale Wiedergabe genau an dieser Stelle weiter,
      ohne die Warteschlange zu leeren (keine Lücke).
      Startet Scrubbing während der Wiedergabe, läuft der Kopf erst mit
      normaler Geschwindigkeit weiter und folgt dann der Hand (keine Lücke).
    - Gelesen wird mit linearer Interpolation zwischen zwei Samples, damit
      krumme Geschwindigkeiten sauber klingen. Geschwindigkeit und Lautstärke
      werden pro Puffer linear übergeblendet -> keine Knackser.
    - Kleinere Puffer und weniger davon in der Warteschlange (SCRUB_FRAMES,
      SCRUB_QUEUE), damit der Ton der Maus möglichst wenig hinterherhinkt.
    - Läuft auch bei Pause (das Gerät spielt nur fürs Scrubbing). Beim
      Loslassen bleibt es dann an ScrubTarget pausiert.

  Die GUI schreibt nur einfache Werte (Gain, Mode, Playing, SeekTo, Loop...)
  und liest Position und Pegel. Das sind einzelne 32/64-Bit-Werte, die auf x86/x64
  atomar gelesen/geschrieben werden -> kein Locking nötig.

  Versionen:
    1.0  (01.10.2026)  Erste Version
    1.1  (02.10.2026)  unverändert (nur Kommentare ergänzt)
    1.2  (21.10.2026)  Loop A-B: nahtloser Rücksprung von B nach A
    1.3  (22.10.2026)  Scrubbing: Ton beim Ziehen der Welle in der Lupe,
                       nahtlos zurück in die Wiedergabe beim Loslassen
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
  LOOP_FADE     = 64;         // Frames Aus-/Einblenden am Loop-Übergang (~1,5 ms)
  SEG_MAX       = 512;        // gemerkte Audio-Stücke (~12 s, siehe MapPosition)
  SCRUB_FRAMES  = 512;        // Puffergrösse beim Scrubbing (~12 ms)
  SCRUB_QUEUE   = 6;          // so viele Puffer beim Scrubbing in der Warteschlange
                              // (3 waren unter Windows zu wenig: alle 50 ms 14 ms Lücke)
  SCRUB_LAG     = 2205;       // Abstand zum Ziel wird in ~50 ms aufgeholt
  SCRUB_AHEAD   = 1536;       // so weit darf der Kopf der Maus vorauslaufen (x Geschw.)
  SCRUB_MAXLEAD = 4410;       // mehr als 0,1 s hinter der Maus -> nachspringen
  SCRUB_MAXRATE = 4.0;        // höchstens 4-fache Geschwindigkeit
  SCRUB_STILL   = 30;         // ms ohne Mausbewegung = Maus steht (mindestens)

type
  { Wiedergabemodus }
  TPlayMode = (
    pmStems,      // Stems gemischt (mit Mute/Solo/Fader)
    pmMaster,     // Originalmix aus Spur 0 (zum A/B-Vergleich)
    pmResidual    // Original minus Summe aller Stems = was bei der Trennung "fehlt"
  );

  { Ein Stück Audio, das an Windows geschickt wurde: ab Stream-Frame Stream
    (gezählt seit dem letzten Reset, wie waveOutGetPosition) kommen Len
    Frames aus der Datei ab Frame. Len = 0 heisst Stille am Dateiende. }
  TAudioSeg = record
    Stream, Frame, Len: Int64;
  end;

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
    { --- Loop --- }
    FLoopA      : Int64;            // übernommener Punkt A (-1 = kein Loop)
    FLoopB      : Int64;            // übernommener Punkt B (-1 = kein Loop)
    FLoopSerial : Integer;          // zuletzt übernommener Stand von LoopSerial
    FStreamPos  : Int64;            // an Windows geschickte Frames seit Reset
    FWrapStream : Int64;            // Stream-Frame des letzten Rücksprungs (-1 = keiner)
    FFadeLeft   : Integer;          // noch einzublendende Frames nach dem Rücksprung
    FEnv        : array[0..BUF_FRAMES-1] of Single;  // Hüllkurve des Puffers (Blende)
    FSeg        : array[0..SEG_MAX-1] of TAudioSeg;  // Ringpuffer, siehe TAudioSeg
    FSegHead    : Integer;          // nächster freier Platz
    FSegCount   : Integer;          // belegte Plätze
    { --- Scrubbing --- }
    FScrubOn    : Boolean;          // Scrubbing läuft gerade
    FScrubPos   : Double;           // Lesekopf in Frames (mit Nachkommastellen)
    FScrubRate  : Double;           // Geschwindigkeit des letzten Puffers
    FScrubAmp   : Single;           // Lautstärke des letzten Puffers (0..1)
    FScrubVel   : Double;           // geglättete Mausgeschwindigkeit (Frames pro Frame)
    FScrubLast  : Int64;            // ScrubTarget beim letzten Puffer
    FScrubTime  : Int64;            // Zeitpunkt (QueryPerformanceCounter) dazu
    FScrubEnd   : Boolean;          // letzter Puffer: auf Stille ausblenden
    FScrubJump  : Boolean;          // im nächsten Puffer nachspringen (dieser blendet aus)
    FScrubIn    : array[0..TRACK_MAX] of array of SmallInt;  // gelesener Block
    FScrubMoved : Int64;            // Zeitpunkt der letzten Mausbewegung
    FScrubGap   : Int64;            // Abstand der letzten beiden Mausbewegungen
    FScrubHand  : Boolean;          // letzter Puffer: auf normale Geschwindigkeit (Loslassen beim Abspielen)
    procedure OpenDevice;
    procedure CloseDevice;
    procedure FillBuffer(Idx: Integer);
    procedure FillScrub(Idx: Integer);
    procedure MixAndWrite(Idx, Frames: Integer);
    procedure StartScrub;
    procedure StopScrub;
    function  WaitFreeBuffer: Integer;
    procedure DoSeek(Frame: Int64);
    procedure ApplyLoop;
    procedure AddSegment(AStream, AFrame, ALen: Int64);
    function  MapPosition(Dev: Int64): Int64;
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
    LoopStart  : Int64;                          // Punkt A in Frames
    LoopEnd    : Int64;                          // Punkt B; Loop aktiv, wenn LoopEnd > LoopStart >= 0
    LoopSerial : Integer;                        // nach jeder Loop-Änderung erhöhen
    Scrubbing  : Boolean;                        // Welle wird gezogen -> Ton folgt ScrubTarget
    ScrubTarget: Int64;                          // Stelle unter dem roten Strich der Lupe
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
  LoopStart := -1;
  LoopEnd := -1;
  LoopSerial := 0;
  FLoopA := -1;
  FLoopB := -1;
  FLoopSerial := 0;
  FStreamPos := 0;
  FWrapStream := -1;
  FFadeLeft := 0;
  FSegHead := 0;
  FSegCount := 0;
  Scrubbing := False;
  ScrubTarget := 0;
  FScrubOn := False;
  for i := 0 to TRACK_MAX do
    SetLength(FScrubIn[i], (Round(SCRUB_MAXRATE * SCRUB_FRAMES) + 8) * CHANNELS);
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
  { Gerätezähler steht wieder auf 0 -> Zuordnung neu beginnen }
  FStreamPos := 0;
  FWrapStream := -1;
  FFadeLeft := LOOP_FADE;     // nach jedem Sprung kurz einblenden (kein Knacken)
  FSegHead := 0;
  FSegCount := 0;
end;

{ Neue Loop-Werte von der GUI übernehmen.
  Die nächsten ~140 ms Audio liegen schon bei Windows in der Warteschlange.
  Passen sie nicht mehr zum neuen Loop, wird an der hörbaren Stelle neu
  aufgesetzt (ein kurzer, kaum hörbarer Neustart der Puffer):
    - ein Rücksprung zum alten A ist schon eingereiht (Loop aus/verschoben)
    - der neue Punkt B liegt vor der Leseposition, die hörbare Position
      aber im Loop oder knapp dahinter. Das ist der Normalfall, wenn B an
      der gerade gespielten Stelle gesetzt wird: die Engine hat dann schon
      über B hinaus gelesen und würde den Loop verpassen. Liegt die hörbare
      Position schon hinter B (bis 0,5 s, so viel kann B "zu spät" kommen),
      geht es gleich bei A weiter. }
procedure TStemEngine.ApplyLoop;
var
  A, B, Pos: Int64;
  Need: Boolean;
begin
  FLoopSerial := LoopSerial;      // zuerst den Stand, dann die Werte lesen
  A := LoopStart;
  B := LoopEnd;
  if (A < 0) or (B <= A) or (B > FTotalFrames) then
  begin
    A := -1;
    B := -1;
  end;
  FLoopA := A;
  FLoopB := B;
  Pos := PlayPos;
  Need := (FWrapStream >= 0) and (FWrapStream > DevicePosition);
  if (B > 0) and (FReadPos >= B) and (Pos >= A) and (Pos < B + SAMPLE_RATE div 2) then
  begin
    if Pos >= B then Pos := A;
    Need := True;
  end;
  if Need then DoSeek(Pos);
end;

procedure TStemEngine.AddSegment(AStream, AFrame, ALen: Int64);
begin
  FSeg[FSegHead].Stream := AStream;
  FSeg[FSegHead].Frame := AFrame;
  FSeg[FSegHead].Len := ALen;
  FSegHead := (FSegHead + 1) mod SEG_MAX;
  if FSegCount < SEG_MAX then Inc(FSegCount);
end;

{ Geräteposition (Frames seit Reset) -> Position in der Datei.
  Gesucht wird das neueste Stück, das bei oder vor Dev beginnt.
  Normalerweise liegt das Gerät nur die ~6 Puffer der Warteschlange zurück.
  Manche Treiber (z.B. unter Wine) melden Puffer aber schon als fertig, wenn
  sie erst in einem eigenen grossen Puffer liegen. Darum werden viele Stücke
  gemerkt, und ist Dev noch älter, wird vom ältesten Stück zurückgerechnet. }
function TStemEngine.MapPosition(Dev: Int64): Int64;
var
  k, i: Integer;
begin
  Result := FBasePos + Dev;
  for k := 0 to FSegCount - 1 do
  begin
    i := (FSegHead - 1 - k + SEG_MAX) mod SEG_MAX;
    Result := FSeg[i].Frame - (FSeg[i].Stream - Dev);  // falls keins passt
    if Result < 0 then Result := 0;
    if FSeg[i].Stream <= Dev then
    begin
      if Dev - FSeg[i].Stream < FSeg[i].Len then
        Result := FSeg[i].Frame + (Dev - FSeg[i].Stream)
      else
        Result := FSeg[i].Frame + FSeg[i].Len;
      Exit;
    end;
  end;
end;

{ Liest einen Block aus allen Spuren und mischt ihn in Puffer Idx. }
procedure TStemEngine.FillBuffer(Idx: Integer);
var
  t, n, k, Filled, Chunk, Wraps: Integer;
  Limit: Int64;
  LoopOn: Boolean;
begin
  for t := 0 to TRACK_MAX do
    FillChar(FIn[t], SizeOf(FIn[t]), 0);   // fehlende Spuren / Dateiende = Stille
  for n := 0 to BUF_FRAMES - 1 do FEnv[n] := 1;

  { Puffer in Stücken füllen: bis zum Dateiende oder, wenn ein Loop aktiv ist
    und die Leseposition davor liegt, bis Punkt B. Bei B geht es im selben
    Puffer bei A weiter. }
  Filled := 0;
  Wraps := 0;
  while Filled < BUF_FRAMES do
  begin
    LoopOn := (FLoopB > 0) and (FReadPos < FLoopB);
    if LoopOn then Limit := FLoopB else Limit := FTotalFrames;
    Chunk := BUF_FRAMES - Filled;
    if FReadPos + Chunk > Limit then Chunk := Limit - FReadPos;
    if Chunk <= 0 then Break;                // Dateiende

    { Alle Spuren lesen }
    for t := 0 to TRACK_MAX do
      if FFiles[t] <> nil then
      begin
        FFiles[t].Position := FReadPos * BYTES_PER_FRM;
        FFiles[t].Read(FIn[t][Filled * CHANNELS], Chunk * BYTES_PER_FRM);
      end;
    AddSegment(FStreamPos + Filled, FReadPos, Chunk);

    { Nach einem Rücksprung die ersten Frames einblenden }
    n := Filled;
    while (FFadeLeft > 0) and (n < Filled + Chunk) do
    begin
      FEnv[n] := (LOOP_FADE - FFadeLeft + 1) / (LOOP_FADE + 1);
      Dec(FFadeLeft);
      Inc(n);
    end;

    Inc(FReadPos, Chunk);
    Inc(Filled, Chunk);

    { Punkt B erreicht -> zurück zu A }
    if LoopOn and (FReadPos >= FLoopB) then
    begin
      { die letzten Frames vor B ausblenden (soweit sie in diesem Puffer sind) }
      for k := 1 to LOOP_FADE do
        if (Filled - k >= 0) and ((k - 1) / LOOP_FADE < FEnv[Filled - k]) then
          FEnv[Filled - k] := (k - 1) / LOOP_FADE;
      FReadPos := FLoopA;
      FWrapStream := FStreamPos + Filled;
      FFadeLeft := LOOP_FADE;
      Inc(Wraps);
      if Wraps > 8 then Break;   // Schutz gegen winzige Loops
    end;
  end;
  { Rest des Puffers ist Stille am Dateiende }
  if Filled < BUF_FRAMES then
    AddSegment(FStreamPos + Filled, FTotalFrames, 0);
  MixAndWrite(Idx, BUF_FRAMES);
end;

{ Scrubbing beginnt: alte Warteschlange verwerfen, Lesekopf auf das Ziel,
  Gerät laufen lassen (auch wenn die Wiedergabe pausiert ist). }
procedure TStemEngine.StartScrub;
var i: Integer;
begin
  FScrubOn := True;
  FScrubEnd := False;
  FScrubJump := False;
  FScrubHand := False;
  FScrubLast := ScrubTarget;
  QueryPerformanceCounter(FScrubTime);
  FScrubMoved := FScrubTime;
  FScrubGap := 0;
  if Playing then
  begin
    { Wiedergabe lief: an der hörbaren Stelle mit normalem Tempo weiter, die
      Hand bremst dann ab (wie bei einer Platte) -> keine Lücke }
    FScrubPos := PlayPos;
    FScrubRate := 1;
    FScrubAmp := 1;
    FScrubVel := 1;
  end
  else
  begin
    FScrubPos := ScrubTarget;
    FScrubRate := 0;
    FScrubAmp := 0;
    FScrubVel := 0;
  end;
  if FWave <> 0 then
  begin
    waveOutReset(FWave);
    for i := 0 to BUF_COUNT - 1 do FQueued[i] := False;
    waveOutRestart(FWave);
    FPausedDev := False;
  end;
  { Gerätezähler steht nach dem Reset wieder auf 0 -> Zuordnung neu }
  FStreamPos := 0;
  FWrapStream := -1;
  FSegHead := 0;
  FSegCount := 0;
  PlayPos := Round(FScrubPos);
end;

{ Wartet auf einen freien Puffer (höchstens 50 ms), -1 = keiner frei }
function TStemEngine.WaitFreeBuffer: Integer;
var
  i: Integer;
  T0: QWord;
begin
  T0 := GetTickCount64;
  repeat
    Result := -1;
    for i := 0 to BUF_COUNT - 1 do
    begin
      if FQueued[i] and ((FHdr[i].dwFlags and WHDR_DONE) <> 0) then
        FQueued[i] := False;
      if (Result < 0) and not FQueued[i] then Result := i;
    end;
    if Result < 0 then WaitForSingleObject(FEvent, 5);
  until (Result >= 0) or (GetTickCount64 - T0 > 50);
end;

{ Scrubbing endet.
  Beim Abspielen: ein letzter Puffer beschleunigt auf normale
  Geschwindigkeit, danach liest FillBuffer genau dort weiter. Die
  Warteschlange bleibt, also keine Lücke.
  Bei Pause: ausblenden, zwei stille Puffer dahinter, warten bis Windows
  alles abgespielt hat (WHDR_DONE kommt schon, wenn der Puffer im Mixer
  liegt, darum noch etwas länger), dann an ScrubTarget pausiert aufsetzen. }
procedure TStemEngine.StopScrub;
var
  i, k: Integer;
  T0: QWord;
  Busy: Boolean;
begin
  for i := 0 to BUF_COUNT - 1 do
    if FQueued[i] and ((FHdr[i].dwFlags and WHDR_DONE) <> 0) then
      FQueued[i] := False;

  if Playing then
  begin
    k := WaitFreeBuffer;
    if k >= 0 then
    begin
      FScrubHand := True;
      FillScrub(k);
      FScrubHand := False;
    end;
    FScrubOn := False;
    { normale Wiedergabe setzt an der Stelle des Lesekopfs fort }
    FReadPos := Round(FScrubPos);
    if FReadPos < 0 then FReadPos := 0;
    if FReadPos > FTotalFrames then FReadPos := FTotalFrames;
    FBasePos := FReadPos;
    PlayPos := FReadPos;
    EndReached := False;
    FWrapStream := -1;
    FFadeLeft := 0;
    AddSegment(FStreamPos, FReadPos, 0);
    Exit;
  end;

  { Pause: Ausblend-Puffer und zwei stille Puffer anhängen. Beim Ziehen
    sind alle Puffer in der Warteschlange, darum jeweils auf einen freien
    warten (sonst fehlt das Ausblenden und es knackt). }
  FScrubEnd := True;
  for i := 1 to 3 do
  begin
    k := WaitFreeBuffer;
    if k >= 0 then FillScrub(k);
  end;
  FScrubEnd := False;
  T0 := GetTickCount64;
  repeat
    Busy := False;
    for i := 0 to BUF_COUNT - 1 do
      if FQueued[i] and ((FHdr[i].dwFlags and WHDR_DONE) = 0) then Busy := True;
    if Busy then WaitForSingleObject(FEvent, 5);
  until (not Busy) or (GetTickCount64 - T0 > 200);
  Sleep(40);   // Rest im Windows-Mixer ausspielen lassen
  FScrubOn := False;
  DoSeek(ScrubTarget);
end;

{ Ein Scrub-Puffer: Der Lesekopf läuft mit einer Geschwindigkeit, die vom
  Abstand zum Ziel abhängt, und wird über den Puffer von der alten zur
  neuen Geschwindigkeit übergeblendet. Gelesen wird der Block, den der
  Lesekopf dabei überstreicht, danach wird zwischen zwei Samples linear
  interpoliert. Die Lautstärke folgt der Geschwindigkeit (Maus still =
  Stille), so entsteht kein Knacken beim Anhalten. }
procedure TStemEngine.FillScrub(Idx: Integer);
var
  t, n, c, Cnt: Integer;
  R0, R1, Rate, P, Lo, Hi, Fr: Double;
  A0, A1: Single;
  First, Last, Idx0, Target, QNow, Freq: Int64;
  S0, S1: Integer;
  Dt, Inst, Goal: Double;
  Jump: Boolean;
  Still, StillLimit: Int64;
begin
  { Mausgeschwindigkeit seit dem letzten Puffer, gemessen an der echten Zeit
    (die Puffer entstehen nicht ganz gleichmässig), geglättet }
  Target := ScrubTarget;
  QueryPerformanceCounter(QNow);
  QueryPerformanceFrequency(Freq);
  Dt := (QNow - FScrubTime) / Freq * SAMPLE_RATE;       // vergangene Zeit in Frames
  if Dt < 1 then Dt := 1;
  if (Dt > SAMPLE_RATE div 10) then Dt := SAMPLE_RATE div 10;
  Inst := (Target - FScrubLast) / Dt;
  { Mausbewegung merken: Zeitpunkt und Abstand zur vorigen }
  if Target <> FScrubLast then
  begin
    FScrubGap := QNow - FScrubMoved;
    FScrubMoved := QNow;
  end;
  { Steht die Maus? Länger als SCRUB_STILL ms bzw. doppelt so lange wie der
    letzte Abstand zwischen zwei Bewegungen (langsames Ziehen meldet
    seltener), höchstens 120 ms }
  Still := (QNow - FScrubMoved) * 1000 div Freq;
  StillLimit := 2 * FScrubGap * 1000 div Freq;
  if StillLimit < SCRUB_STILL then StillLimit := SCRUB_STILL;
  if StillLimit > 120 then StillLimit := 120;
  { schneller abbremsen als beschleunigen: Maus still = bald Stille }
  if Abs(Inst) < Abs(FScrubVel) then
    FScrubVel := FScrubVel + (Inst - FScrubVel) * 0.5
  else
    FScrubVel := FScrubVel + (Inst - FScrubVel) * 0.3;
  if FScrubVel > SCRUB_MAXRATE then FScrubVel := SCRUB_MAXRATE;
  if FScrubVel < -SCRUB_MAXRATE then FScrubVel := -SCRUB_MAXRATE;
  FScrubLast := Target;
  FScrubTime := QNow;

  { Zu weit hinter der Maus -> nachspringen. Damit der Sprung nicht knackt:
    diesen Puffer noch am alten Ort ausblenden, im nächsten springen und
    wieder einblenden. }
  Jump := Abs(Target - FScrubPos) > SCRUB_MAXLEAD;
  if FScrubJump then
  begin
    if Target > FScrubPos then FScrubPos := Target - SCRUB_MAXLEAD div 2
    else FScrubPos := Target + SCRUB_MAXLEAD div 2;
    FScrubAmp := 0;
    Jump := False;
  end;
  FScrubJump := Jump;

  R0 := FScrubRate;
  R1 := FScrubVel + (Target - FScrubPos) / SCRUB_LAG;
  if R1 > SCRUB_MAXRATE then R1 := SCRUB_MAXRATE;
  if R1 < -SCRUB_MAXRATE then R1 := -SCRUB_MAXRATE;
  { Nicht über die Hand hinauslaufen: Ziel ist die Mausstelle plus das,
    was sie bei der aktuellen Geschwindigkeit in diesem Puffer noch
    zurücklegt (SCRUB_AHEAD, Mausmeldungen kommen nicht in jedem Puffer).
    Steht die Maus, bleibt der Kopf dort stehen (Stille).
    Die Geschwindigkeit ändert sich im Puffer linear von R0 nach R1, der
    Weg ist also (R0 + R1) / 2 * SCRUB_FRAMES. }
  Goal := Target + FScrubVel * SCRUB_AHEAD - FScrubPos;
  if Goal >= 0 then
  begin
    if R1 > 2 * Goal / SCRUB_FRAMES - R0 then R1 := 2 * Goal / SCRUB_FRAMES - R0;
    if R1 < 0 then R1 := 0;
  end
  else
  begin
    if R1 < 2 * Goal / SCRUB_FRAMES - R0 then R1 := 2 * Goal / SCRUB_FRAMES - R0;
    if R1 > 0 then R1 := 0;
  end;
  if Abs(R1) < 0.02 then R1 := 0;
  { Maus steht -> in diesem Puffer anhalten und ausblenden }
  if (Still > StillLimit) and not FScrubHand then
  begin
    R1 := 0;
    FScrubVel := 0;
  end;
  { Loslassen beim Abspielen: auf normale Geschwindigkeit (Platte läuft weiter) }
  if FScrubHand then R1 := 1;
  { Pause-Ende: stille Puffer hinter dem Ausblenden, Kopf steht }
  if FScrubEnd and (FScrubAmp = 0) then
  begin
    R0 := 0;
    R1 := 0;
  end;
  A0 := FScrubAmp;
  A1 := Abs(R1) / 0.3;                   // ab 0,3-facher Geschwindigkeit volle Lautstärke
  if A1 > 1 then A1 := 1;
  if FScrubEnd or FScrubJump then A1 := 0;   // Loslassen / Sprung: ausblenden
  if FScrubHand then A1 := 1;

  { Bereich, den der Lesekopf überstreicht (Geschwindigkeit ändert sich linear) }
  P := FScrubPos;
  Lo := P; Hi := P;
  for n := 0 to SCRUB_FRAMES - 1 do
  begin
    P := P + R0 + (R1 - R0) * n / SCRUB_FRAMES;
    if P < Lo then Lo := P;
    if P > Hi then Hi := P;
  end;
  First := Trunc(Lo) - 1;
  if First < 0 then First := 0;
  Last := Trunc(Hi) + 2;
  if Last > FTotalFrames - 1 then Last := FTotalFrames - 1;
  Cnt := Last - First + 1;
  if Cnt > Length(FScrubIn[0]) div CHANNELS then Cnt := Length(FScrubIn[0]) div CHANNELS;

  for t := 0 to TRACK_MAX do
  begin
    FillChar(FScrubIn[t][0], Length(FScrubIn[t]) * SizeOf(SmallInt), 0);
    if (FFiles[t] <> nil) and (Cnt > 0) then
    begin
      FFiles[t].Position := First * BYTES_PER_FRM;
      FFiles[t].Read(FScrubIn[t][0], Cnt * BYTES_PER_FRM);
    end;
  end;

  { Interpolieren }
  P := FScrubPos;
  for n := 0 to SCRUB_FRAMES - 1 do
  begin
    Rate := R0 + (R1 - R0) * n / SCRUB_FRAMES;
    P := P + Rate;
    if P < 0 then P := 0;
    if P > FTotalFrames - 1 then P := FTotalFrames - 1;
    Idx0 := Trunc(P) - First;
    Fr := P - Trunc(P);
    if Idx0 < 0 then begin Idx0 := 0; Fr := 0; end;
    if Idx0 > Cnt - 2 then begin Idx0 := Cnt - 2; Fr := 1; end;
    if Idx0 < 0 then Idx0 := 0;
    for t := 0 to TRACK_MAX do
      for c := 0 to CHANNELS - 1 do
      begin
        S0 := FScrubIn[t][Idx0 * CHANNELS + c];
        S1 := FScrubIn[t][(Idx0 + 1) * CHANNELS + c];
        FIn[t][n * CHANNELS + c] := SmallInt(Round(S0 + (S1 - S0) * Fr));
      end;
    FEnv[n] := A0 + (A1 - A0) * n / (SCRUB_FRAMES - 1);   // letzter Frame genau A1
  end;

  FScrubPos := P;
  FScrubRate := R1;
  FScrubAmp := A1;
  PlayPos := Round(FScrubPos);
  MixAndWrite(Idx, SCRUB_FRAMES);
end;

{ Mischt die gelesenen Spuren (FIn, Frames lang) mit Gain-Rampe und
  Hüllkurve FEnv in Puffer Idx und schickt ihn an Windows. }
procedure TStemEngine.MixAndWrite(Idx, Frames: Integer);
var
  t, n: Integer;
  G0, G1, Step: array[0..TRACK_MAX] of Single;
  PkTrack: array[0..TRACK_MAX] of Integer;
  PkL, PkR: Integer;
  Acc, G: Single;
  V, Smp: Integer;
  Vol: Single;
  M: TPlayMode;
  Clips: Integer;
begin
  for t := 0 to TRACK_MAX do PkTrack[t] := 0;
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
    Step[t] := (G1[t] - G0[t]) / Frames;
    FCurGain[t] := G1[t];
  end;

  PkL := 0; PkR := 0; Clips := 0;
  for n := 0 to Frames * CHANNELS - 1 do
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
    V := Round(Acc * FEnv[n div CHANNELS]);
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

  Inc(FStreamPos, Frames);
  { Immer einen ganzen Puffer schreiben (Rest ist Stille) }
  FHdr[Idx].dwBufferLength := Frames * BYTES_PER_FRM;
  FHdr[Idx].dwFlags := FHdr[Idx].dwFlags and not WHDR_DONE;
  waveOutWrite(FWave, @FHdr[Idx], SizeOf(TWaveHdr));
  FQueued[Idx] := True;
end;

procedure TStemEngine.Execute;
var
  i, Queued: Integer;
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

    { Scrubbing: eigener Ablauf mit kleinen Puffern, solange gezogen wird }
    if Scrubbing then
    begin
      if not FScrubOn then StartScrub;
      Queued := 0;
      for i := 0 to BUF_COUNT - 1 do
      begin
        if FQueued[i] and ((FHdr[i].dwFlags and WHDR_DONE) <> 0) then
          FQueued[i] := False;
        if FQueued[i] then Inc(Queued);
      end;
      for i := 0 to BUF_COUNT - 1 do
        if (not FQueued[i]) and (Queued < SCRUB_QUEUE) then
        begin
          FillScrub(i);
          Inc(Queued);
        end;
      WaitForSingleObject(FEvent, 5);
      Continue;
    end
    else if FScrubOn then
      StopScrub;

    { Sprung angefordert? }
    S := SeekTo;
    if S >= 0 then
    begin
      SeekTo := -1;
      DoSeek(S);
    end;

    { Loop geändert? }
    if LoopSerial <> FLoopSerial then ApplyLoop;

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

    { Hörbare Position: Gerätezähler über die gemerkten Stücke in die Datei umrechnen }
    Pos := MapPosition(DevicePosition);
    if Pos > FTotalFrames then Pos := FTotalFrames;
    PlayPos := Pos;
    if (FReadPos >= FTotalFrames) and (Pos >= FTotalFrames) then
      EndReached := True;

    { Warten, bis Windows einen Puffer zurückgibt (oder max. 20 ms) }
    WaitForSingleObject(FEvent, 20);
  end;
end;

end.
