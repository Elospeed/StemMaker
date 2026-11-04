{ ============================================================================
  StemTagger  -  Tags in Traktor-Stem-Dateien (.stem.mp4) lesen und schreiben
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : ump4tags.pas  (Unit uMp4Tags)
  Herkunft: Tag-Teil von ustemmp4.pas aus Elospeed StemMaker (dort werden die
            Stem-Dateien erzeugt). Hier ist nur das Lesen und Ändern der
            Tags drin, das Erzeugen der 'stem'-Box gehört zu StemMaker.
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Eine Traktor-Stem-Datei ist eine normale MP4-Datei mit 5 Audiospuren
  (Master + Drums + Bass + Other + Vocals). Damit Traktor sie als "Stem"
  erkennt, stehen zwei Zusatzinfos in der Datei:

    1. Eine Box namens 'stem' (Pfad: moov/udta/stem) mit einem kleinen
       JSON-Text: Namen und Farben der 4 Stems, Kompressor/Limiter.
    2. Den Tag TAUT = "STEM" in den normalen iTunes-Tags (moov/udta/meta/ilst).

  Beides darf beim Taggen auf keinen Fall verloren gehen.

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
        udta          Benutzerdaten: 'stem'-Box
          meta/ilst   iTunes-Tags (Titel, Artist, Cover, ...)

  Wir lesen nur die (kleine) 'moov'-Box ein, ändern darin die Tag-Liste
  und schreiben die Datei neu. Die großen Audiodaten ('mdat') werden nur
  1:1 kopiert.

  Stolperstein: In den Spuren stehen Positionsangaben ("Chunk-Offsets"),
  wo in der Datei die Audiodaten liegen. Liegt 'moov' VOR 'mdat' und wird
  'moov' größer oder kleiner, verschieben sich die Audiodaten. Dann müssen
  alle diese Positionsangaben um die Differenz korrigiert werden - das
  macht ShiftChunkOffsets.

  TAGS LESEN UND SCHREIBEN

  ReadMp4Tags / WriteMp4Tags lesen und ändern die normalen iTunes-Tags
  (Titel, Interpret, Cover, ...) in moov/udta/meta/ilst. Alles andere
  bleibt Byte für Byte erhalten: die 5 Spuren, die 'stem'-Box, TAUT und
  Tags, die wir nicht kennen. Vor dem Ersetzen wird die neue Datei geprüft
  (gleiche Spurenzahl, gleicher Stem-JSON), sonst bleibt das Original.
  ============================================================================ }
unit uMp4Tags;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

{ Liest den JSON-Text aus der 'stem'-Box wieder aus ('' = keine vorhanden).
  Praktisch zum Prüfen - funktioniert auch mit gekauften NI-Stems. }
function ReadStemJSON(const FileName: string): string;

{ Zählt die Spuren ('trak'-Boxen). Eine gültige Stem-Datei hat 5. }
function CountTracks(const FileName: string): Integer;

{ Ersetzt die Datei Target durch NewFile, ohne dass zwischendurch beide
  weg sein können. Klappt auch, wenn NewFile auf einem anderen Laufwerk
  liegt (dann wird kopiert). False = nichts ersetzt, die alte Datei ist
  (wenn es sie gab) noch da. }
function ReplaceFileSafe(const NewFile, Target: string): Boolean;

{ ---------------------------------------------------------------------------
  Tags bearbeiten (AddOn StemTagger)
  --------------------------------------------------------------------------- }
type
  { Die Felder, die der StemTagger kennt. Alle als Text:
    tfTrack z.B. '3' oder '3/12', tfBpm z.B. '128', tfCover nicht als Text,
    sondern als Bild in TMp4Tags.Cover. }
  TMp4TagField = (tfTitle, tfArtist, tfAlbum, tfAlbumArtist, tfGenre,
                  tfYear, tfTrack, tfBpm, tfKey, tfLabel, tfComment, tfCover);
  TMp4TagFields = set of TMp4TagField;

  TMp4Tags = record
    Text : array[TMp4TagField] of string;  // UTF-8, '' = nicht gesetzt
    Cover: TBytes;                         // JPEG oder PNG, leer = kein Cover
  end;

{ Liest die Tags. False = Datei nicht lesbar (Grund in ErrMsg). }
function ReadMp4Tags(const FileName: string; out Tags: TMp4Tags;
  out ErrMsg: string): Boolean;

{ Schreibt NUR die Felder aus Fields (leerer Text bzw. leeres Cover =
  Tag entfernen). Alle anderen Tags, die Spuren und die 'stem'-Box bleiben
  unverändert. Die neue Datei wird vor dem Ersetzen geprüft. Das Cover
  muss JPEG oder PNG sein. }
function WriteMp4Tags(const FileName: string; const Tags: TMp4Tags;
  Fields: TMp4TagFields; out ErrMsg: string): Boolean;

{ Ist das Bild JPEG oder PNG? (nur diese beiden kennt das MP4-Cover) }
function IsMp4CoverImage(const Img: TBytes): Boolean;

{ Name eines alten ID3v1-Genres (0 = Blues ... 79 = Hard Rock),
  '' = unbekannte Nummer. Gebraucht für MP4 ('gnre') und MP3 (TCON "(17)"). }
function Id3GenreName(N: Integer): string;

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
        { Aufbau: 4 Byte Version/Flags, 4 Byte Anzahl, dann je 4 Byte Position.
          Die Anzahl wird gegen die Länge geprüft: eine kaputte Datei darf
          nicht dazu führen, dass hinter dem Ende gelesen wird. N = 0 wird
          übersprungen (N - 1 wäre bei LongWord sonst riesig). }
        N := GetBE32(Box.Payload, 4);
        if Int64(N) > (Length(Box.Payload) - 8) div 4 then
          raise Exception.Create('stco-Tabelle ist kürzer als angegeben');
        if N > 0 then
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
        if Int64(N) > (Length(Box.Payload) - 8) div 8 then
          raise Exception.Create('co64-Tabelle ist kürzer als angegeben');
        if N > 0 then
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
  MakeFreeformTag - baut einen Freiform-Tag ("----")

  Für Werte, für die es keinen offiziellen 4-Zeichen-Tag gibt (z.B. die
  Tonart), benutzen alle Programme denselben Trick von iTunes: eine Box
  namens '----' mit drei Unter-Boxen:

      ----
        mean   4 Byte Version/Flags + "com.apple.iTunes"
        name   4 Byte Version/Flags + Name des Werts, z.B. "initialkey"
        data   wie bei MakeTextTag: Typ 1 (UTF-8) + Sprache + Text

  So schreiben es Mp3tag, Mixed In Key, Serato und rekordbox - die
  Tonart landet damit dort, wo DJ-Programme sie suchen.
  --------------------------------------------------------------------------- }
const
  ITUNES_MEAN = 'com.apple.iTunes';

{ Hilfsfunktion: eine Unter-Box 'mean'/'name'/'data' als Bytes }
function SubBox(const Typ: RawByteString; const Flags: LongWord;
  const Text: UTF8String; WithLang: Boolean): TBytes;
var
  Head, L: Integer;
begin
  if WithLang then Head := 16 else Head := 12;
  L := Length(Text);
  Result := nil;
  SetLength(Result, Head + L);
  PutBE32(Result, 0, Head + L);                 // Größe der Unter-Box
  Move(Typ[1], Result[4], 4);                   // Typ
  PutBE32(Result, 8, Flags);                    // Version 0 + Flags
  if WithLang then
    PutBE32(Result, 12, 0);                     // nur 'data': Sprache (0 = egal)
  if L > 0 then
    Move(Text[1], Result[Head], L);
end;

function MakeFreeformTag(const Name: RawByteString;
  const Text: UTF8String): TBox;
var
  Mean, Nam, Data, All: TBytes;
  P: SizeInt;
begin
  Result := TBox.Create('----');
  Mean := SubBox('mean', 0, ITUNES_MEAN, False);
  Nam  := SubBox('name', 0, Name, False);
  Data := SubBox('data', 1, Text, True);        // Flags 1 = UTF-8-Text
  All := nil;
  SetLength(All, Length(Mean) + Length(Nam) + Length(Data));
  P := 0;
  Move(Mean[0], All[P], Length(Mean)); Inc(P, Length(Mean));
  Move(Nam[0],  All[P], Length(Nam));  Inc(P, Length(Nam));
  Move(Data[0], All[P], Length(Data));
  Result.Payload := All;
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

{ ---------------------------------------------------------------------------
  Datei sicher ersetzen

  Früher: Ziel löschen, dann die neue Datei hinschieben. Ging das Hinschieben
  schief (anderes Laufwerk und Platte voll), waren alte UND neue Datei weg.
  Jetzt in drei Schritten, von denen jeder rückgängig gemacht werden kann:
    1. neue Datei als "<Ziel>.neu" neben das Ziel bringen
       (umbenennen, oder kopieren wenn sie auf einem anderen Laufwerk liegt)
    2. altes Ziel in "<Ziel>.alt" umbenennen
    3. "<Ziel>.neu" in "<Ziel>" umbenennen, danach "<Ziel>.alt" löschen
  Umbenennen im selben Ordner braucht keinen Platz und klappt praktisch
  immer. Scheitert trotzdem ein Schritt, wird der alte Zustand
  wiederhergestellt.
  --------------------------------------------------------------------------- }

{ Datei Byte für Byte kopieren (ohne FileUtil, diese Unit soll schlank
  bleiben). Bei einem Fehler wird die halbe Kopie wieder gelöscht. }
function CopyFileRaw(const Src, Dst: string): Boolean;
var
  InS, OutS: TFileStream;
begin
  Result := False;
  try
    InS := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
    try
      OutS := TFileStream.Create(Dst, fmCreate);
      try
        OutS.CopyFrom(InS, 0);           // 0 = ganze Datei
      finally
        OutS.Free;
      end;
    finally
      InS.Free;
    end;
    Result := True;
  except
    { z.B. Platte voll: halbe Kopie wegräumen }
    if FileExists(Dst) then
      DeleteFile(Dst);
  end;
end;

function ReplaceFileSafe(const NewFile, Target: string): Boolean;
var
  NewSide, Bak: string;
  Copied: Boolean;
begin
  Result := False;
  NewSide := Target + '.neu';
  Bak := Target + '.alt';

  { 1. neue Datei neben das Ziel bringen (Reste eines früheren Versuchs
       vorher wegräumen) }
  if FileExists(NewSide) then
    DeleteFile(NewSide);
  Copied := False;
  if not RenameFile(NewFile, NewSide) then
  begin
    if not CopyFileRaw(NewFile, NewSide) then
      Exit;                              // Ziel unverändert
    Copied := True;
  end;

  { 2. + 3. altes Ziel beiseitelegen, neue Datei an seinen Platz }
  if FileExists(Target) then
  begin
    if FileExists(Bak) then
      DeleteFile(Bak);
    if not RenameFile(Target, Bak) then
    begin
      { altes Ziel lässt sich nicht bewegen (z.B. gerade in Traktor offen):
        neue Datei dorthin zurück, wo sie herkam }
      if Copied then
        DeleteFile(NewSide)
      else
        RenameFile(NewSide, NewFile);
      Exit;
    end;
    if not RenameFile(NewSide, Target) then
    begin
      RenameFile(Bak, Target);           // alten Zustand wiederherstellen
      if Copied then
        DeleteFile(NewSide)
      else
        RenameFile(NewSide, NewFile);
      Exit;
    end;
    DeleteFile(Bak);
  end
  else if not RenameFile(NewSide, Target) then
  begin
    if Copied then
      DeleteFile(NewSide)
    else
      RenameFile(NewSide, NewFile);
    Exit;
  end;

  { kopiert statt umbenannt: das Original auf dem anderen Laufwerk ist
    jetzt überflüssig }
  if Copied then
    DeleteFile(NewFile);
  Result := True;
end;

{ ---------------------------------------------------------------------------
  Tags bearbeiten (AddOn StemTagger)

  Ein Tag in 'ilst' ist eine Box mit dem Tag-Namen (z.B. #$A9'nam' für den
  Titel). Darin steckt eine 'data'-Box:
      4 Byte  Typ    (1 = UTF-8-Text, 0 = Zahlen, 13 = JPEG, 14 = PNG,
                      21 = Ganzzahl)
      4 Byte  Sprache (0)
      Wert
  Freiform-Tags ('----') haben davor noch 'mean' und 'name' (siehe
  MakeFreeformTag). Wir zerlegen die Tag-Box beim Lesen selbst; in TBox
  bleibt sie als rohe Bytes.
  --------------------------------------------------------------------------- }
const
  { welcher 4-Byte-Tag zu welchem Feld gehört ('' = Freiform bzw. Cover) }
  TagAtom: array[TMp4TagField] of RawByteString = (
    #$A9'nam', #$A9'ART', #$A9'alb', 'aART', #$A9'gen',
    #$A9'day', 'trkn', 'tmpo', '', #$A9'pub', #$A9'cmt', 'covr');
  KEY_NAME = 'initialkey';   // Freiform-Name der Tonart (so schreibt es auch StemMaker)

  { Die alten ID3v1-Genres: manche Programme speichern das Genre als Nummer
    im Tag 'gnre' (Nummer + 1). Nur zum Lesen. }
  Id3Genres: array[0..79] of string = (
    'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge',
    'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
    'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
    'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient',
    'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical',
    'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
    'AlternRock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
    'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
    'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
    'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 'Christian Rap',
    'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
    'Psychadelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal',
    'Acid Punk', 'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
    'Hard Rock');

{ Zerlegt den Inhalt einer Tag-Box in ihre Unter-Boxen und liefert die
  erste 'data'-Box (Typ und Wert). Bei '----' auch den Namen aus 'name'.
  False = keine brauchbare 'data'-Box. }
function ParseTagBox(Box: TBox; out DataType: LongWord; out Value: TBytes;
  out FreeName: RawByteString): Boolean;
var
  P, Sz, L: Int64;
  T: RawByteString;
  B: TBytes;
begin
  Result := False;
  DataType := 0;
  Value := nil;
  FreeName := '';
  B := Box.Payload;
  P := 0;
  SetLength(T, 4);
  while P + 8 <= Length(B) do
  begin
    Sz := GetBE32(B, P);
    if (Sz < 8) or (P + Sz > Length(B)) then
      Exit;                          // kaputt -> lieber nichts lesen
    Move(B[P + 4], T[1], 4);
    if (T = 'name') and (Sz >= 12) then
    begin
      SetLength(FreeName, Sz - 12);
      if Sz > 12 then
        Move(B[P + 12], FreeName[1], Sz - 12);
    end
    else if (T = 'data') and (Sz >= 16) and not Result then
    begin
      DataType := GetBE32(B, P + 8) and $FFFFFF;   // ohne Versions-Byte
      L := Sz - 16;
      SetLength(Value, L);
      if L > 0 then
        Move(B[P + 16], Value[0], L);
      Result := True;
    end;
    Inc(P, Sz);
  end;
end;

{ Bytes als Text (UTF-8, ohne Umwandlung) }
function BytesToStr(const B: TBytes): string;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then
    Move(B[0], Result[1], Length(B));
end;

{ Tag-Box mit beliebigem Inhalt (Typ + Bytes) bauen, z.B. für Cover/trkn }
function MakeDataTag(const Name: RawByteString; DataType: LongWord;
  const Value: TBytes): TBox;
var
  Data: TBytes;
  L: Integer;
begin
  Result := TBox.Create(Name);
  L := Length(Value);
  Data := nil;
  SetLength(Data, 16 + L);
  PutBE32(Data, 0, 16 + L);
  Data[4] := Ord('d'); Data[5] := Ord('a'); Data[6] := Ord('t'); Data[7] := Ord('a');
  PutBE32(Data, 8, DataType);         // Version 0 + Typ
  PutBE32(Data, 12, 0);               // Sprache
  if L > 0 then
    Move(Value[0], Data[16], L);
  Result.Payload := Data;
end;

{ Gehört diese Tag-Box zu Feld F? }
function BoxIsField(Box: TBox; F: TMp4TagField): Boolean;
var
  DT: LongWord;
  V: TBytes;
  N: RawByteString;
begin
  if F = tfKey then
    Result := (Box.BoxType = '----') and ParseTagBox(Box, DT, V, N) and
              (LowerCase(N) = KEY_NAME)
  else if F = tfGenre then
    Result := (Box.BoxType = TagAtom[F]) or (Box.BoxType = 'gnre')
  else
    Result := Box.BoxType = TagAtom[F];
end;

function IsMp4CoverImage(const Img: TBytes): Boolean;
begin
  Result := (Length(Img) > 4) and
    (((Img[0] = $FF) and (Img[1] = $D8)) or                     // JPEG
     ((Img[0] = $89) and (Img[1] = $50) and (Img[2] = $4E) and (Img[3] = $47))); // PNG
end;

function Id3GenreName(N: Integer): string;
begin
  if (N >= Low(Id3Genres)) and (N <= High(Id3Genres)) then
    Result := Id3Genres[N]
  else
    Result := '';
end;

{ Zahl aus einem Text holen ('128.4' -> 128, '3/12' -> 3), -1 = keine }
function LeadingInt(const S: string; out Rest: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  Rest := '';
  I := 1;
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do
  begin
    if Result < 0 then Result := 0;
    if Result < 100000 then
      Result := Result * 10 + Ord(S[I]) - Ord('0');
    Inc(I);
  end;
  Rest := Copy(S, I, MaxInt);
end;

{ Die ilst-Box der moov-Box suchen. Create = anlegen, falls es keine gibt. }
function FindIlst(Moov: TBox; Create: Boolean): TBox;
var
  Udta, Meta: TBox;
begin
  Result := nil;
  Udta := Moov.Find('udta');
  if Udta = nil then
  begin
    if not Create then Exit;
    Udta := TBox.Create('udta');
    Udta.IsContainer := True;
    Moov.Children.Add(Udta);
  end;
  Meta := Udta.Find('meta');
  if Meta = nil then
  begin
    if not Create then Exit;
    Meta := MakeMetaBox;
    Udta.Children.Add(Meta);
  end;
  Result := Meta.Find('ilst');
  if (Result = nil) and Create then
  begin
    Result := TBox.Create('ilst');
    Result.IsContainer := True;
    Meta.Children.Add(Result);
  end;
end;

function ReadMp4Tags(const FileName: string; out Tags: TMp4Tags;
  out ErrMsg: string): Boolean;
var
  S: TFileStream;
  Tops: TTopBoxArray;
  Moov, Ilst, Box: TBox;
  Idx, I, N: Integer;
  F: TMp4TagField;
  DT: LongWord;
  V: TBytes;
  FName: RawByteString;
  Txt: string;
begin
  Result := False;
  ErrMsg := '';
  for F := Low(TMp4TagField) to High(TMp4TagField) do
    Tags.Text[F] := '';
  Tags.Cover := nil;
  Moov := nil;
  try
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Tops := ScanTopLevel(S);
      Moov := LoadMoov(S, Tops, Idx);
      Ilst := FindIlst(Moov, False);
      if Ilst <> nil then
        for I := 0 to Ilst.Children.Count - 1 do
        begin
          Box := TBox(Ilst.Children[I]);
          if not ParseTagBox(Box, DT, V, FName) then
            Continue;
          for F := Low(TMp4TagField) to High(TMp4TagField) do
          begin
            if not BoxIsField(Box, F) then
              Continue;
            case F of
              tfCover:
                if (Length(Tags.Cover) = 0) and IsMp4CoverImage(V) then
                  Tags.Cover := V;
              tfTrack:
                if Length(V) >= 6 then
                begin
                  N := (V[2] shl 8) or V[3];
                  Txt := '';
                  if N > 0 then Txt := IntToStr(N);
                  N := (V[4] shl 8) or V[5];
                  if (N > 0) and (Txt <> '') then Txt := Txt + '/' + IntToStr(N);
                  Tags.Text[F] := Txt;
                end;
              tfBpm:
                if Length(V) >= 1 then
                begin
                  if Length(V) = 1 then N := V[0] else N := (V[0] shl 8) or V[1];
                  if N > 0 then Tags.Text[F] := IntToStr(N);
                end;
              tfGenre:
                if Box.BoxType = 'gnre' then
                begin
                  { Nummer nur nehmen, wenn kein Text-Genre da ist }
                  if (Tags.Text[F] = '') and (Length(V) >= 2) then
                  begin
                    N := ((V[0] shl 8) or V[1]) - 1;
                    if (N >= Low(Id3Genres)) and (N <= High(Id3Genres)) then
                      Tags.Text[F] := Id3Genres[N];
                  end;
                end
                else
                  Tags.Text[F] := BytesToStr(V);
            else
              Tags.Text[F] := BytesToStr(V);
            end;
          end;
        end;
      Result := True;
    finally
      S.Free;
    end;
  except
    on E: Exception do
      ErrMsg := E.Message;
  end;
  Moov.Free;
end;

{ Die geänderten Felder in die ilst-Box übernehmen }
procedure ApplyTags(Ilst: TBox; const Tags: TMp4Tags; Fields: TMp4TagFields);
var
  F: TMp4TagField;
  I, Track, Total, Bpm: Integer;
  Txt, Rest, Rest2: string;
  V: TBytes;
begin
  for F := Low(TMp4TagField) to High(TMp4TagField) do
  begin
    if not (F in Fields) then
      Continue;
    { alte Einträge dieses Felds entfernen }
    for I := Ilst.Children.Count - 1 downto 0 do
      if BoxIsField(TBox(Ilst.Children[I]), F) then
        Ilst.Children.Delete(I);
    Txt := Trim(Tags.Text[F]);
    V := nil;
    case F of
      tfCover:
        if Length(Tags.Cover) > 0 then
        begin
          if not IsMp4CoverImage(Tags.Cover) then
            raise Exception.Create('Cover ist kein JPEG/PNG');
          if Tags.Cover[0] = $FF then
            Ilst.Children.Add(MakeDataTag('covr', 13, Tags.Cover))
          else
            Ilst.Children.Add(MakeDataTag('covr', 14, Tags.Cover));
        end;
      tfTrack:
        begin
          Track := LeadingInt(Txt, Rest);
          Total := -1;
          Rest := Trim(Rest);
          if (Rest <> '') and (Rest[1] = '/') then
            Total := LeadingInt(Copy(Rest, 2, MaxInt), Rest2);
          if Track > 0 then
          begin
            if Track > 65535 then Track := 65535;
            if Total > 65535 then Total := 65535;
            if Total < 0 then Total := 0;
            SetLength(V, 8);
            FillChar(V[0], 8, 0);
            V[2] := Byte(Track shr 8); V[3] := Byte(Track);
            V[4] := Byte(Total shr 8); V[5] := Byte(Total);
            Ilst.Children.Add(MakeDataTag('trkn', 0, V));
          end;
        end;
      tfBpm:
        begin
          { Kommazahl runden (tmpo kennt nur ganze BPM) }
          Bpm := LeadingInt(Txt, Rest);
          if (Bpm >= 0) and (Length(Rest) >= 2) and (Rest[1] in ['.', ',']) and
             (Rest[2] in ['5'..'9']) then
            Inc(Bpm);
          if Bpm > 65535 then Bpm := 65535;
          if Bpm > 0 then
          begin
            SetLength(V, 2);
            V[0] := Byte(Bpm shr 8); V[1] := Byte(Bpm);
            Ilst.Children.Add(MakeDataTag('tmpo', 21, V));
          end;
        end;
      tfKey:
        if Txt <> '' then
          Ilst.Children.Add(MakeFreeformTag(KEY_NAME, Txt));
    else
      if Txt <> '' then
        Ilst.Children.Add(MakeTextTag(TagAtom[F], Txt));
    end;
  end;
end;

function WriteMp4Tags(const FileName: string; const Tags: TMp4Tags;
  Fields: TMp4TagFields; out ErrMsg: string): Boolean;
var
  Src, Dst: TFileStream;
  Tops: TTopBoxArray;
  MoovIdx, I, OldTracks: Integer;
  Moov, Udta, StemBox: TBox;
  OldMoovEnd, Delta, ExpectSize: Int64;
  NewMoov: TMemoryStream;
  TmpName, OldJSON: string;
begin
  Result := False;
  ErrMsg := '';
  TmpName := FileName + '.tagtmp';
  Moov := nil;
  NewMoov := TMemoryStream.Create;
  try
    try
      Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      try
        { --- 1. moov laden und merken, wie die Datei vorher war ---------- }
        Tops := ScanTopLevel(Src);
        Moov := LoadMoov(Src, Tops, MoovIdx);
        OldTracks := 0;
        for I := 0 to Moov.Children.Count - 1 do
          if TBox(Moov.Children[I]).BoxType = 'trak' then
            Inc(OldTracks);
        OldJSON := '';
        Udta := Moov.Find('udta');
        if Udta <> nil then
        begin
          StemBox := Udta.Find('stem');
          if StemBox <> nil then
            OldJSON := BytesToStr(StemBox.Payload);
        end;

        { --- 2. Tags ändern ----------------------------------------------- }
        ApplyTags(FindIlst(Moov, True), Tags, Fields);

        { --- 3. Positionsangaben korrigieren (wie beim Erzeugen in StemMaker) ----- }
        OldMoovEnd := Tops[MoovIdx].Offset + Tops[MoovIdx].Size;
        Delta := Moov.TotalSize - Tops[MoovIdx].Size;
        if (Delta <> 0) and (MoovIdx < High(Tops)) then
          ShiftChunkOffsets(Moov, OldMoovEnd, Delta);
        Moov.WriteTo(NewMoov);
        ExpectSize := Src.Size + Delta;

        { --- 4. neue Datei: vor moov + neue moov + nach moov -------------- }
        Dst := TFileStream.Create(TmpName, fmCreate);
        try
          Src.Position := 0;
          if Tops[MoovIdx].Offset > 0 then
            Dst.CopyFrom(Src, Tops[MoovIdx].Offset);
          NewMoov.Position := 0;
          Dst.CopyFrom(NewMoov, NewMoov.Size);
          if OldMoovEnd < Src.Size then
          begin
            Src.Position := OldMoovEnd;
            Dst.CopyFrom(Src, Src.Size - OldMoovEnd);
          end;
          if Dst.Size <> ExpectSize then
            raise Exception.Create('Neue Datei hat die falsche Größe');
        finally
          Dst.Free;
        end;
      finally
        Src.Free;
      end;

      { --- 5. neue Datei prüfen, bevor das Original ersetzt wird --------- }
      if CountTracks(TmpName) <> OldTracks then
        raise Exception.Create('Prüfung: Spurenzahl hat sich geändert');
      if ReadStemJSON(TmpName) <> OldJSON then
        raise Exception.Create('Prüfung: Stem-Daten haben sich geändert');

      if not ReplaceFileSafe(TmpName, FileName) then
        raise Exception.Create('Originaldatei kann nicht ersetzt werden (offen in einem anderen Programm?)');
      Result := True;
    except
      on E: Exception do
      begin
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

end.
