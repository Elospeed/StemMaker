{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ustemmp4.pas  (Unit uStemMP4)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Eine Traktor-Stem-Datei ist eigentlich eine ganz normale MP4-Datei mit
  5 Audiospuren (Master + Drums + Bass + Other + Vocals). Damit Traktor sie
  als "Stem" erkennt, braucht es aber noch zwei Zusatzinfos in der Datei:

    1. Eine Box namens 'stem' (Pfad: moov/udta/stem).
       Darin steht ein kleiner JSON-Text mit den Namen und Farben der
       4 Stems und ein paar Einstellungen für Kompressor/Limiter.
       -> Genau das liest Traktor aus.

    2. Den Tag TAUT = "STEM" in den normalen iTunes-Tags
       (moov/udta/meta/ilst). Stemgen schreibt den auch, also machen wir
       das der Sicherheit halber genauso.

  Das Original-Tool Stemgen macht das mit den externen Programmen MP4Box
  und mutagen (Python). Diese Unit ersetzt beides - reines Pascal, keine
  zusätzlichen Programme oder DLLs.

  WIE IST EINE MP4-DATEI AUFGEBAUT? (kurz erklärt)

  Eine MP4 besteht aus "Boxen" (auch "Atome" genannt). Jede Box hat:
      4 Byte  Größe  (inkl. Kopf, Big-Endian = höchstes Byte zuerst)
      4 Byte  Typ    (z.B. 'moov', 'trak', 'mdat')
      Inhalt         (entweder Daten oder weitere Boxen = "Container")

  Grob sieht eine Datei so aus:
      ftyp            Dateityp
      mdat            die eigentlichen Audiodaten (groß!)
      moov            Inhaltsverzeichnis: Spuren, Zeitstempel, Tags ...
        trak (x5)     eine pro Audiospur
        udta          Benutzerdaten -> hier kommt unsere 'stem'-Box hinein
          meta/ilst   iTunes-Tags (Titel, Artist, Cover, ...)

  Wir lesen also nur die (kleine) 'moov'-Box ein, hängen die 'stem'-Box
  an und schreiben die Datei neu. Die großen Audiodaten ('mdat') werden
  nur 1:1 kopiert.

  Stolperstein: In den Spuren stehen Positionsangaben ("Chunk-Offsets"),
  wo in der Datei die Audiodaten liegen. Liegt 'moov' VOR 'mdat' und wird
  'moov' größer, verschieben sich die Audiodaten nach hinten. Dann müssen
  alle diese Positionsangaben um die Differenz korrigiert werden - das
  macht ShiftChunkOffsets. (ffmpeg legt 'moov' normalerweise ans Ende,
  dann ist nichts zu korrigieren - funktioniert aber beides.)
  ============================================================================ }
unit uStemMP4;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

type
  { Name und Farbe eines Stems, so wie Traktor sie anzeigt }
  TStemInfo = record
    Name : string;   // z.B. 'Drums'
    Color: string;   // Farbe als '#RRGGBB', z.B. '#009E73'
  end;

  { immer genau 4 Stems: 0=Drums, 1=Bass, 2=Other, 3=Vocals }
  TStemInfoArray = array[0..3] of TStemInfo;

{ Liefert die Standard-Namen und -Farben (identisch mit Stemgen) }
function DefaultStemInfo: TStemInfoArray;

{ Baut den JSON-Text für die 'stem'-Box zusammen (gleicher Aufbau wie
  metadata.json von Stemgen) }
function BuildStemJSON(const Stems: TStemInfoArray): string;

{ Schreibt die 'stem'-Box und den Tag TAUT=STEM in eine bestehende MP4.
  Die Datei wird dabei ersetzt. Bei einem Fehler: Rückgabe False und die
  Fehlerbeschreibung steht in ErrMsg. }
function InjectStemMetadata(const FileName, StemJSON: string;
  out ErrMsg: string): Boolean;

{ Liest den JSON-Text aus der 'stem'-Box wieder aus ('' = keine vorhanden).
  Praktisch zum Prüfen - funktioniert auch mit gekauften NI-Stems. }
function ReadStemJSON(const FileName: string): string;

{ Zählt die Spuren ('trak'-Boxen). Eine gültige Stem-Datei hat 5. }
function CountTracks(const FileName: string): Integer;

implementation

{ ---------------------------------------------------------------------------
  Hilfsfunktionen für Big-Endian-Zahlen

  In MP4-Dateien stehen alle Zahlen im Big-Endian-Format (höchstes Byte
  zuerst). Windows/Intel rechnet intern aber Little-Endian. Diese kleinen
  Funktionen lesen bzw. schreiben 32- und 64-Bit-Zahlen byteweise in der
  richtigen Reihenfolge.
  --------------------------------------------------------------------------- }

{ 32-Bit-Zahl ab Position P aus dem Byte-Array lesen }
function GetBE32(const B: TBytes; P: SizeInt): LongWord; inline;
begin
  Result := (LongWord(B[P]) shl 24) or (LongWord(B[P + 1]) shl 16) or
            (LongWord(B[P + 2]) shl 8) or LongWord(B[P + 3]);
end;

{ 64-Bit-Zahl ab Position P lesen (= zwei 32-Bit-Hälften) }
function GetBE64(const B: TBytes; P: SizeInt): QWord; inline;
begin
  Result := (QWord(GetBE32(B, P)) shl 32) or QWord(GetBE32(B, P + 4));
end;

{ 32-Bit-Zahl an Position P ins Byte-Array schreiben }
procedure PutBE32(var B: TBytes; P: SizeInt; V: LongWord); inline;
begin
  B[P]     := Byte(V shr 24);
  B[P + 1] := Byte(V shr 16);
  B[P + 2] := Byte(V shr 8);
  B[P + 3] := Byte(V);
end;

{ 64-Bit-Zahl an Position P schreiben }
procedure PutBE64(var B: TBytes; P: SizeInt; V: QWord); inline;
begin
  PutBE32(B, P, LongWord(V shr 32));
  PutBE32(B, P + 4, LongWord(V and $FFFFFFFF));
end;

{ 32-Bit-Zahl direkt in einen Stream (Datei/Speicher) schreiben }
procedure StreamWriteBE32(S: TStream; V: LongWord);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(V shr 24); B[1] := Byte(V shr 16);
  B[2] := Byte(V shr 8);  B[3] := Byte(V);
  S.WriteBuffer(B, 4);
end;

{ 64-Bit-Zahl direkt in einen Stream schreiben }
procedure StreamWriteBE64(S: TStream; V: QWord);
begin
  StreamWriteBE32(S, LongWord(V shr 32));
  StreamWriteBE32(S, LongWord(V and $FFFFFFFF));
end;

{ Einen String 1:1 (Byte für Byte, ohne Umwandlung) in ein Byte-Array
  kopieren. Wird für den JSON-Text gebraucht. }
function BytesOfStr(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then
    Move(S[1], Result[0], Length(S));
end;

{ ---------------------------------------------------------------------------
  TBox - eine MP4-Box im Speicher

  Wir bilden die 'moov'-Box als Baum ab: jede Box ist ein TBox-Objekt.
  - Container-Boxen (moov, trak, udta, ...) haben Kinder (Children).
  - Alle anderen Boxen behalten ihren Inhalt einfach als Bytes (Payload)
    und werden später unverändert wieder geschrieben.
  So müssen wir nur die paar Boxen verstehen, die wir wirklich brauchen.
  --------------------------------------------------------------------------- }
type
  TBox = class
  public
    BoxType    : RawByteString;  // die 4 Zeichen des Typs, z.B. 'moov'
                                 // (iTunes-Tags beginnen mit Byte $A9 = '©')
    IsContainer: Boolean;        // True = enthält weitere Boxen
    Prefix     : TBytes;         // nur bei Containern: Bytes VOR den Kindern
                                 // (die 'meta'-Box hat hier 4 Byte Version/Flags)
    Payload    : TBytes;         // nur bei normalen Boxen: der Inhalt
    Children   : TFPObjectList;  // Kind-Boxen (werden automatisch freigegeben)
    constructor Create(const AType: RawByteString);
    destructor Destroy; override;
    function Find(const AType: RawByteString): TBox;
    function ContentSize: Int64;
    function TotalSize: Int64;
    procedure WriteTo(S: TStream);
  end;

const
  { In diese Box-Typen steigen wir hinab (= Container).
    Die Tags in 'ilst' selbst bleiben als rohe Bytes, die brauchen wir
    nicht im Detail. }
  ContainerTypes: array[0..8] of RawByteString =
    ('moov', 'trak', 'mdia', 'minf', 'stbl', 'udta', 'meta', 'ilst', 'edts');

{ Ist dieser Box-Typ ein Container? }
function IsContainerType(const T: RawByteString): Boolean;
var
  I: Integer;
begin
  for I := Low(ContainerTypes) to High(ContainerTypes) do
    if T = ContainerTypes[I] then
      Exit(True);
  Result := False;
end;

constructor TBox.Create(const AType: RawByteString);
begin
  inherited Create;
  BoxType := AType;
  Children := TFPObjectList.Create(True);   // True = Liste gibt Kinder frei
end;

destructor TBox.Destroy;
begin
  Children.Free;
  inherited Destroy;
end;

{ Sucht das erste direkte Kind mit dem gewünschten Typ (nil = keins da) }
function TBox.Find(const AType: RawByteString): TBox;
var
  I: Integer;
begin
  for I := 0 to Children.Count - 1 do
    if TBox(Children[I]).BoxType = AType then
      Exit(TBox(Children[I]));
  Result := nil;
end;

{ Größe des Inhalts ohne den 8-Byte-Kopf.
  Bei Containern: Prefix + Summe aller Kinder (rekursiv). }
function TBox.ContentSize: Int64;
var
  I: Integer;
begin
  if IsContainer then
  begin
    Result := Length(Prefix);
    for I := 0 to Children.Count - 1 do
      Inc(Result, TBox(Children[I]).TotalSize);
  end
  else
    Result := Length(Payload);
end;

{ Gesamtgröße inkl. Kopf. Normal ist der Kopf 8 Byte; nur bei Boxen über
  4 GB braucht es den 16-Byte-Kopf mit 64-Bit-Größe (kommt hier praktisch
  nie vor, wird aber korrekt behandelt). }
function TBox.TotalSize: Int64;
var
  C: Int64;
begin
  C := ContentSize;
  if C + 8 > High(LongWord) then
    Result := C + 16
  else
    Result := C + 8;
end;

{ Schreibt die Box (Kopf + Inhalt bzw. alle Kinder) in einen Stream }
procedure TBox.WriteTo(S: TStream);
var
  C: Int64;
  I: Integer;
begin
  C := ContentSize;
  if C + 8 > High(LongWord) then
  begin
    { großer Kopf: Größe = 1 bedeutet "echte Größe folgt als 64 Bit" }
    StreamWriteBE32(S, 1);
    S.WriteBuffer(BoxType[1], 4);
    StreamWriteBE64(S, C + 16);
  end
  else
  begin
    { normaler Kopf: 4 Byte Größe + 4 Byte Typ }
    StreamWriteBE32(S, LongWord(C + 8));
    S.WriteBuffer(BoxType[1], 4);
  end;
  if IsContainer then
  begin
    if Length(Prefix) > 0 then
      S.WriteBuffer(Prefix[0], Length(Prefix));
    for I := 0 to Children.Count - 1 do
      TBox(Children[I]).WriteTo(S);
  end
  else if Length(Payload) > 0 then
    S.WriteBuffer(Payload[0], Length(Payload));
end;

{ ---------------------------------------------------------------------------
  ParseBoxes - zerlegt einen Speicherbereich in Boxen

  Liest alle Boxen zwischen Start und Stop aus Buf und hängt sie an
  Parent.Children an. Container werden rekursiv weiter zerlegt.
  Bei kaputten Größenangaben gibt es eine Exception, damit wir nie eine
  defekte Datei schreiben.
  --------------------------------------------------------------------------- }
procedure ParseBoxes(const Buf: TBytes; Start, Stop: Int64; Parent: TBox);
var
  P, BoxSize, Hdr, ContentStart, ContentLen, PrefixLen: Int64;
  T: RawByteString;
  Box: TBox;
begin
  P := Start;
  while P + 8 <= Stop do
  begin
    { Kopf lesen: Größe + Typ }
    BoxSize := GetBE32(Buf, P);
    SetLength(T, 4);
    Move(Buf[P + 4], T[1], 4);
    Hdr := 8;
    if BoxSize = 1 then
    begin
      { Größe 1 = 64-Bit-Größe folgt direkt nach dem Typ }
      if P + 16 > Stop then
        raise Exception.Create('Defekter 64-bit Box-Header');
      BoxSize := Int64(GetBE64(Buf, P + 8));
      Hdr := 16;
    end
    else if BoxSize = 0 then
      BoxSize := Stop - P;       // Größe 0 = "geht bis zum Ende"
    if (BoxSize < Hdr) or (P + BoxSize > Stop) then
      raise Exception.CreateFmt('Ungültige Box-Größe bei Offset %d (%s)',
        [P, T]);

    ContentStart := P + Hdr;
    ContentLen := BoxSize - Hdr;
    Box := TBox.Create(T);
    Parent.Children.Add(Box);

    if IsContainerType(T) then
    begin
      Box.IsContainer := True;
      PrefixLen := 0;
      if T = 'meta' then
      begin
        { Die 'meta'-Box gibt es in zwei Varianten:
          - ISO/MP4-Variante: 4 Byte Version/Flags, danach die Kinder
          - QuickTime-Variante: Kinder beginnen sofort
          Wir erkennen das daran, ob direkt eine 'hdlr'-Box folgt. }
        if not ((ContentLen >= 8) and (Buf[ContentStart + 4] = Ord('h')) and
                (Buf[ContentStart + 5] = Ord('d')) and
                (Buf[ContentStart + 6] = Ord('l')) and
                (Buf[ContentStart + 7] = Ord('r'))) then
          PrefixLen := 4;
      end;
      if PrefixLen > ContentLen then
        PrefixLen := ContentLen;
      SetLength(Box.Prefix, PrefixLen);
      if PrefixLen > 0 then
        Move(Buf[ContentStart], Box.Prefix[0], PrefixLen);
      { Kinder dieses Containers zerlegen (Rekursion) }
      ParseBoxes(Buf, ContentStart + PrefixLen, ContentStart + ContentLen, Box);
    end
    else
    begin
      { normale Box: Inhalt einfach als Bytes aufheben }
      SetLength(Box.Payload, ContentLen);
      if ContentLen > 0 then
        Move(Buf[ContentStart], Box.Payload[0], ContentLen);
    end;
    Inc(P, BoxSize);             // weiter zur nächsten Box
  end;
end;

{ ---------------------------------------------------------------------------
  ShiftChunkOffsets - Positionsangaben der Audiodaten korrigieren

  Jede Spur hat eine Tabelle 'stco' (32 Bit) oder 'co64' (64 Bit) mit den
  Datei-Positionen ihrer Audio-Blöcke. Alle Positionen, die hinter der
  alten moov-Box liegen (>= Threshold), werden um Delta verschoben.
  Pfad: moov/trak/mdia/minf/stbl/stco
  --------------------------------------------------------------------------- }
procedure ShiftChunkOffsets(Moov: TBox; Threshold, Delta: Int64);
var
  I, J: Integer;
  Trak, Stbl, Box: TBox;
  N, K: LongWord;
  V: Int64;
begin
  for I := 0 to Moov.Children.Count - 1 do
  begin
    Trak := TBox(Moov.Children[I]);
    if Trak.BoxType <> 'trak' then
      Continue;
    { den Weg zur Tabelle suchen: trak -> mdia -> minf -> stbl }
    Stbl := Trak.Find('mdia');
    if Stbl <> nil then Stbl := Stbl.Find('minf');
    if Stbl <> nil then Stbl := Stbl.Find('stbl');
    if Stbl = nil then
      Continue;
    for J := 0 to Stbl.Children.Count - 1 do
    begin
      Box := TBox(Stbl.Children[J]);
      if (Box.BoxType = 'stco') and (Length(Box.Payload) >= 8) then
      begin
        { Aufbau: 4 Byte Version/Flags, 4 Byte Anzahl, dann je 4 Byte Position }
        N := GetBE32(Box.Payload, 4);
        for K := 0 to N - 1 do
        begin
          V := GetBE32(Box.Payload, 8 + K * 4);
          if V >= Threshold then
          begin
            V := V + Delta;
            if (V < 0) or (V > High(LongWord)) then
              raise Exception.Create('Chunk-Offset passt nicht mehr in stco');
            PutBE32(Box.Payload, 8 + K * 4, LongWord(V));
          end;
        end;
      end
      else if (Box.BoxType = 'co64') and (Length(Box.Payload) >= 8) then
      begin
        { wie stco, nur mit 8 Byte pro Position (für Dateien > 4 GB) }
        N := GetBE32(Box.Payload, 4);
        for K := 0 to N - 1 do
        begin
          V := Int64(GetBE64(Box.Payload, 8 + K * 8));
          if V >= Threshold then
            PutBE64(Box.Payload, 8 + K * 8, QWord(V + Delta));
        end;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  MakeTextTag - baut einen iTunes-Text-Tag

  Ein Tag in 'ilst' sieht so aus:
      <Name des Tags>             z.B. 'TAUT'
        <data>                    Unter-Box mit dem Wert
          4 Byte  Typ = 1         (1 = UTF-8-Text)
          4 Byte  Sprache = 0
          Text
  --------------------------------------------------------------------------- }
function MakeTextTag(const Name: RawByteString; const Text: UTF8String): TBox;
var
  Data: TBytes;
  L: Integer;
begin
  Result := TBox.Create(Name);
  L := Length(Text);
  Data := nil;
  SetLength(Data, 16 + L);
  PutBE32(Data, 0, 16 + L);           // Größe der 'data'-Box
  Data[4] := Ord('d'); Data[5] := Ord('a'); Data[6] := Ord('t'); Data[7] := Ord('a');
  PutBE32(Data, 8, 1);                // Version 0 + Flags 1 = UTF-8-Text
  PutBE32(Data, 12, 0);               // Sprache (0 = egal)
  if L > 0 then
    Move(Text[1], Data[16], L);
  Result.Payload := Data;
end;

{ ---------------------------------------------------------------------------
  MakeMetaBox - leere iTunes-Tag-Box erzeugen

  Wird nur gebraucht, falls die Datei noch gar keine Tags hat (ffmpeg
  schreibt eigentlich immer welche). Aufbau:
      meta (mit 4 Byte Version/Flags)
        hdlr  -> sagt "hier kommen iTunes-Tags" (Typ 'mdir', Hersteller 'appl')
        ilst  -> die eigentliche Tag-Liste (noch leer)
  --------------------------------------------------------------------------- }
function MakeMetaBox: TBox;
const
  HdlrPayload: array[0..24] of Byte = (
    0, 0, 0, 0,                         // Version/Flags
    0, 0, 0, 0,                         // reserviert
    Ord('m'), Ord('d'), Ord('i'), Ord('r'),   // Handler-Typ 'mdir'
    Ord('a'), Ord('p'), Ord('p'), Ord('l'),   // Hersteller 'appl'
    0, 0, 0, 0, 0, 0, 0, 0,             // reserviert
    0);                                 // leerer Name
var
  Hdlr, Ilst: TBox;
begin
  Result := TBox.Create('meta');
  Result.IsContainer := True;
  SetLength(Result.Prefix, 4);
  FillChar(Result.Prefix[0], 4, 0);
  Hdlr := TBox.Create('hdlr');
  SetLength(Hdlr.Payload, SizeOf(HdlrPayload));
  Move(HdlrPayload[0], Hdlr.Payload[0], SizeOf(HdlrPayload));
  Result.Children.Add(Hdlr);
  Ilst := TBox.Create('ilst');
  Ilst.IsContainer := True;
  Result.Children.Add(Ilst);
end;

{ ---------------------------------------------------------------------------
  Oberste Ebene der Datei durchgehen

  Wir lesen hier NICHT die ganze Datei, sondern springen nur von Box-Kopf
  zu Box-Kopf und merken uns Position, Größe und Typ. So finden wir 'moov'
  schnell, auch bei großen Dateien.
  --------------------------------------------------------------------------- }
type
  TTopBox = record
    Offset, Size: Int64;       // Position in der Datei und Größe
    BoxType: RawByteString;    // Typ, z.B. 'moov'
  end;
  TTopBoxArray = array of TTopBox;

function ScanTopLevel(S: TStream): TTopBoxArray;
var
  Hdr: array[0..15] of Byte;
  B: TBytes;
  P, FileLen, Sz: Int64;
  N: Integer;
begin
  Result := nil;
  N := 0;
  FileLen := S.Size;
  P := 0;
  B := nil;
  SetLength(B, 16);
  while P + 8 <= FileLen do
  begin
    { 8 Byte Kopf lesen }
    S.Position := P;
    S.ReadBuffer(Hdr, 8);
    Move(Hdr, B[0], 8);
    Sz := GetBE32(B, 0);
    if Sz = 1 then
    begin
      { 64-Bit-Größe: weitere 8 Byte lesen (typisch bei großem 'mdat') }
      S.ReadBuffer(Hdr[8], 8);
      Move(Hdr, B[0], 16);
      Sz := Int64(GetBE64(B, 8));
    end
    else if Sz = 0 then
      Sz := FileLen - P;       // letzte Box, geht bis Dateiende
    if (Sz < 8) or (P + Sz > FileLen) then
      raise Exception.CreateFmt('Keine gültige MP4-Struktur (Offset %d)', [P]);
    SetLength(Result, N + 1);
    Result[N].Offset := P;
    Result[N].Size := Sz;
    SetLength(Result[N].BoxType, 4);
    Move(Hdr[4], Result[N].BoxType[1], 4);
    Inc(N);
    Inc(P, Sz);                // zur nächsten Box springen
  end;
end;

{ Sucht die 'moov'-Box, lädt sie in den Speicher und zerlegt sie als Baum.
  Idx = Index der moov-Box in der Liste der obersten Ebene.
  Der Aufrufer muss das zurückgegebene Objekt selbst freigeben. }
function LoadMoov(S: TStream; const Tops: TTopBoxArray; out Idx: Integer): TBox;
var
  I: Integer;
  Buf: TBytes;
  Root: TBox;
begin
  Result := nil;
  Idx := -1;
  for I := 0 to High(Tops) do
    if Tops[I].BoxType = 'moov' then
    begin
      Idx := I;
      Break;
    end;
  if Idx < 0 then
    raise Exception.Create('Keine moov-Box gefunden - ist das eine MP4-Datei?');
  { Plausibilitätsprüfung: 'moov' ist normal einige 100 KB groß }
  if Tops[Idx].Size > 256 * 1024 * 1024 then
    raise Exception.Create('moov-Box unplausibel groß');

  Buf := nil;
  SetLength(Buf, Tops[Idx].Size);
  S.Position := Tops[Idx].Offset;
  S.ReadBuffer(Buf[0], Tops[Idx].Size);

  { Wir zerlegen den Puffer mit einer Hilfs-"Wurzel" und nehmen danach
    deren einziges Kind (= moov) heraus. }
  Root := TBox.Create('root');
  try
    Root.IsContainer := True;
    ParseBoxes(Buf, 0, Length(Buf), Root);
    if (Root.Children.Count <> 1) or (TBox(Root.Children[0]).BoxType <> 'moov') then
      raise Exception.Create('moov-Box konnte nicht gelesen werden');
    Root.Children.OwnsObjects := False;   // moov NICHT mit der Wurzel freigeben
    Result := TBox(Root.Children[0]);
  finally
    Root.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Öffentliche Funktionen
  --------------------------------------------------------------------------- }

{ Standard-Stems: gleiche Namen und Farben wie Stemgen (metadata.json) }
function DefaultStemInfo: TStemInfoArray;
begin
  Result[0].Name := 'Drums'; Result[0].Color := '#009E73';   // grün
  Result[1].Name := 'Bass';  Result[1].Color := '#D55E00';   // orange
  Result[2].Name := 'Other'; Result[2].Color := '#CC79A7';   // rosa
  Result[3].Name := 'Vox';   Result[3].Color := '#56B4E9';   // hellblau
end;

{ Macht einen Text JSON-tauglich: Anführungszeichen, Backslash und
  Steuerzeichen werden "escaped". Umlaute (UTF-8) bleiben wie sie sind. }
function JSONEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"' : Result := Result + '\"';
      '\' : Result := Result + '\\';
      #8  : Result := Result + '\b';
      #9  : Result := Result + '\t';
      #10 : Result := Result + '\n';
      #12 : Result := Result + '\f';
      #13 : Result := Result + '\r';
      #0..#7, #11, #14..#31:
            Result := Result + '\u' + IntToHex(Ord(C), 4);
    else
      Result := Result + C;
    end;
  end;
end;

{ Baut den JSON-Text für Traktor.
  Die Werte für Kompressor/Limiter sind 1:1 von Stemgen übernommen
  (beide ausgeschaltet). Die Zahlen stehen bewusst als fester Text im
  Code - so gibt es keine Probleme mit Komma/Punkt je nach
  Windows-Ländereinstellung. }
function BuildStemJSON(const Stems: TStemInfoArray): string;
var
  I: Integer;
begin
  Result :=
    '{"mastering_dsp": {"compressor": {"enabled": false, "ratio": 3, ' +
    '"output_gain": 0.5, "release": 0.300000011920929, ' +
    '"attack": 0.003000000026077032, "input_gain": 0.5, "threshold": 0, ' +
    '"hp_cutoff": 300, "dry_wet": 50}, "limiter": {"enabled": false, ' +
    '"release": 0.05000000074505806, "threshold": 0, ' +
    '"ceiling": -0.3499999940395355}}, "version": 1, "stems": [';
  { die 4 Stems in der festen Reihenfolge Drums, Bass, Other, Vocals }
  for I := 0 to 3 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + '{"color": "' + JSONEscape(Stems[I].Color) +
      '", "name": "' + JSONEscape(Stems[I].Name) + '"}';
  end;
  Result := Result + ']}';
end;

{ ---------------------------------------------------------------------------
  InjectStemMetadata - das Herzstück: macht aus einer MP4 eine Stem-Datei

  Ablauf:
    1. oberste Ebene scannen und 'moov' laden
    2. in moov/udta eine alte 'stem'-Box entfernen (falls die Datei schon
       einmal bearbeitet wurde) und die neue einfügen
    3. Tag TAUT=STEM in moov/udta/meta/ilst setzen
    4. falls nötig die Positionsangaben der Audiodaten korrigieren
    5. neue Datei schreiben:  [alles vor moov] + [neue moov] + [alles danach]
       zuerst als *.stemtmp, danach wird das Original ersetzt.
       So bleibt bei einem Fehler das Original unbeschädigt.
  --------------------------------------------------------------------------- }
function InjectStemMetadata(const FileName, StemJSON: string;
  out ErrMsg: string): Boolean;
var
  Src, Dst: TFileStream;
  Tops: TTopBoxArray;
  MoovIdx, I: Integer;
  Moov, Udta, Meta, Ilst, StemBox: TBox;
  OldMoovEnd, Delta: Int64;
  NewMoov: TMemoryStream;
  TmpName: string;
begin
  Result := False;
  ErrMsg := '';
  TmpName := FileName + '.stemtmp';
  Moov := nil;
  NewMoov := TMemoryStream.Create;
  try
    try
      Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      try
        { --- 1. Datei scannen, moov laden --------------------------------- }
        Tops := ScanTopLevel(Src);
        Moov := LoadMoov(Src, Tops, MoovIdx);

        { --- 2. udta-Box holen (oder anlegen, falls es keine gibt) -------- }
        Udta := Moov.Find('udta');
        if Udta = nil then
        begin
          Udta := TBox.Create('udta');
          Udta.IsContainer := True;
          Moov.Children.Add(Udta);
        end;

        { alte 'stem'-Box entfernen, damit sie nicht doppelt drin ist }
        for I := Udta.Children.Count - 1 downto 0 do
          if TBox(Udta.Children[I]).BoxType = 'stem' then
            Udta.Children.Delete(I);

        { --- 3. Tag TAUT = STEM (wie bei Stemgen) ------------------------ }
        Meta := Udta.Find('meta');
        if Meta = nil then
        begin
          Meta := MakeMetaBox;
          Udta.Children.Add(Meta);
        end;
        Ilst := Meta.Find('ilst');
        if Ilst = nil then
        begin
          Ilst := TBox.Create('ilst');
          Ilst.IsContainer := True;
          Meta.Children.Add(Ilst);
        end;
        for I := Ilst.Children.Count - 1 downto 0 do
          if TBox(Ilst.Children[I]).BoxType = 'TAUT' then
            Ilst.Children.Delete(I);
        Ilst.Children.Add(MakeTextTag('TAUT', 'STEM'));

        { --- die eigentliche NI-'stem'-Box -------------------------------- }
        StemBox := TBox.Create('stem');
        StemBox.Payload := BytesOfStr(StemJSON);   // JSON-Text als UTF-8-Bytes
        { als erstes Kind von udta einfügen - gleiche Reihenfolge wie bei
          Dateien von Stemgen (zuerst 'stem', dann 'meta') }
        Udta.Children.Insert(0, StemBox);

        { --- 4. Positionsangaben korrigieren, falls Daten NACH moov liegen - }
        OldMoovEnd := Tops[MoovIdx].Offset + Tops[MoovIdx].Size;
        Delta := Moov.TotalSize - Tops[MoovIdx].Size;   // um so viel wächst moov
        if (Delta <> 0) and (MoovIdx < High(Tops)) then
          ShiftChunkOffsets(Moov, OldMoovEnd, Delta);

        { neue moov-Box in den Speicher schreiben }
        Moov.WriteTo(NewMoov);

        { --- 5. neue Datei zusammensetzen --------------------------------- }
        Dst := TFileStream.Create(TmpName, fmCreate);
        try
          { alles VOR moov unverändert kopieren }
          Src.Position := 0;
          if Tops[MoovIdx].Offset > 0 then
            Dst.CopyFrom(Src, Tops[MoovIdx].Offset);
          { die neue moov }
          NewMoov.Position := 0;
          Dst.CopyFrom(NewMoov, NewMoov.Size);
          { alles NACH der alten moov unverändert kopieren }
          if OldMoovEnd < Src.Size then
          begin
            Src.Position := OldMoovEnd;
            Dst.CopyFrom(Src, Src.Size - OldMoovEnd);
          end;
        finally
          Dst.Free;
        end;
      finally
        Src.Free;
      end;

      { erst jetzt, wo alles geklappt hat, das Original ersetzen }
      if not DeleteFile(FileName) then
        raise Exception.Create('Originaldatei kann nicht ersetzt werden');
      if not RenameFile(TmpName, FileName) then
        raise Exception.Create('Umbenennen der temporären Datei fehlgeschlagen');
      Result := True;
    except
      on E: Exception do
      begin
        { Fehler: Meldung merken und die halbfertige Temp-Datei löschen }
        ErrMsg := E.Message;
        if FileExists(TmpName) then
          DeleteFile(TmpName);
      end;
    end;
  finally
    Moov.Free;
    NewMoov.Free;
  end;
end;

{ Liest den Inhalt der 'stem'-Box (den JSON-Text) aus einer Datei }
function ReadStemJSON(const FileName: string): string;
var
  S: TFileStream;
  Tops: TTopBoxArray;
  Moov, Udta, Stem: TBox;
  Idx: Integer;
begin
  Result := '';
  Moov := nil;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Tops := ScanTopLevel(S);
    Moov := LoadMoov(S, Tops, Idx);
    Udta := Moov.Find('udta');
    if Udta = nil then
      Exit;                    // keine Benutzerdaten -> kein Stem
    Stem := Udta.Find('stem');
    if (Stem = nil) or (Length(Stem.Payload) = 0) then
      Exit;                    // keine 'stem'-Box -> kein Stem
    SetLength(Result, Length(Stem.Payload));
    Move(Stem.Payload[0], Result[1], Length(Stem.Payload));
  finally
    Moov.Free;
    S.Free;
  end;
end;

{ Zählt die Audiospuren (= 'trak'-Boxen direkt in moov) }
function CountTracks(const FileName: string): Integer;
var
  S: TFileStream;
  Tops: TTopBoxArray;
  Moov: TBox;
  Idx, I: Integer;
begin
  Result := 0;
  Moov := nil;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Tops := ScanTopLevel(S);
    Moov := LoadMoov(S, Tops, Idx);
    for I := 0 to Moov.Children.Count - 1 do
      if TBox(Moov.Children[I]).BoxType = 'trak' then
        Inc(Result);
  finally
    Moov.Free;
    S.Free;
  end;
end;

end.
