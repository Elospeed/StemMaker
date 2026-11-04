{ ============================================================================
  StemTagger  -  Tags in MP3-Dateien (ID3v2) lesen und schreiben
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : uid3tags.pas  (Unit uId3Tags)
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  MP3-Dateien tragen ihre Tags (Titel, Interpret, Cover ...) in einem
  ID3v2-Block ganz am Anfang der Datei. Danach kommen die Audiodaten.
  Traktor legt in denselben Block eigene Daten ab: einen Frame 'PRIV'
  (neuere Versionen) oder 'GEOB' mit der Kennung "TRAKTOR4" (Beatgrid,
  Cue-Punkte, Loops, Analyse). Diese und
  alle anderen Frames, die wir nicht kennen, müssen beim Speichern Byte für
  Byte erhalten bleiben. Darum gibt es hier eigenen Code statt einer
  Fremdbibliothek: wir ändern nur die Frames der Felder, die wirklich
  geändert wurden, und lassen alles andere, wie es ist.

  WIE IST EIN ID3v2-BLOCK AUFGEBAUT? (kurz erklärt)

    Kopf, 10 Byte:
      'ID3'           Kennung
      1 Byte          Hauptversion: 2, 3 oder 4 (ID3v2.2 / v2.3 / v2.4)
      1 Byte          Unterversion (immer 0)
      1 Byte          Flags ($80 = Unsynchronisation, $40 = erweiterter Kopf,
                      $10 = Fusszeile, nur v2.4)
      4 Byte          Grösse des Blocks ohne Kopf, "synchsafe": je Byte nur
                      7 Bit, damit nie ein $FF-Byte entsteht, das ein
                      MP3-Player für den Anfang von Audio halten könnte
    danach die Frames, je Frame (v2.3 und v2.4):
      4 Byte  Kennung, z.B. 'TIT2' (Titel), 'APIC' (Bild), 'GEOB' (Objekt)
      4 Byte  Grösse des Inhalts (v2.3 normal, v2.4 synchsafe)
      2 Byte  Flags (Komprimierung, Verschlüsselung ...)
      Inhalt
    und am Ende Füllbytes (lauter Nullen), damit spätere Änderungen Platz
    haben. In ID3v2.2 (sehr alt) sind Kennung und Grösse nur 3 Byte lang.

  Text-Frames beginnen mit einem Byte für die Zeichenkodierung:
    0 = ISO-8859-1 (Latin-1), 1 = UTF-16 mit BOM, 2 = UTF-16BE (nur v2.4),
    3 = UTF-8 (nur v2.4).

  WIE WIRD GESPEICHERT?

  Immer über eine Zwischendatei: neuer ID3-Block + die Audiodaten 1:1.
  Danach wird die Zwischendatei geprüft: Audiodaten Byte für Byte gleich,
  alle übernommenen Frames (z.B. Traktors PRIV/GEOB) unverändert vorhanden und
  die geschriebenen Werte wieder lesbar. Erst dann ersetzt sie das
  Original (ReplaceFileSafe aus uMp4Tags). Ein ID3v1-Block am Dateiende
  (128 Byte 'TAG') gehört für uns zu den Audiodaten und bleibt, wie er ist.

  Geschrieben wird in derselben Hauptversion, die schon in der Datei steht
  (v2.3 oder v2.4). Hat die Datei noch keinen ID3v2-Block, entsteht v2.3,
  das können alle Programme lesen (auch der Windows-Explorer). Dateien mit
  ID3v2.2 und beschädigte Blöcke werden nur gelesen, nie geschrieben.
  ============================================================================ }
unit uId3Tags;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, uMp4Tags;

type
  { Was über den ID3-Block einer MP3 bekannt ist (für die Statusspalte) }
  TMp3Info = record
    Id3Major  : Integer;   // 0 = kein ID3v2-Block, sonst 2, 3 oder 4
    HasTraktor: Boolean;   // Traktor-Daten (PRIV/GEOB "TRAKTOR4") vorhanden
    CanWrite  : Boolean;   // False bei ID3v2.2 oder beschädigtem Block
    Problem   : string;    // warum nicht geschrieben werden kann (deutsch)
  end;

{ Endet der Name auf .mp3? }
function IsMp3File(const FileName: string): Boolean;

{ Liest die Tags einer MP3 in dieselbe Struktur wie bei MP4 (TMp4Tags).
  Fehlt ein Feld im ID3v2-Block, wird es aus einem ID3v1-Block am
  Dateiende genommen (nur Titel, Interpret, Album, Jahr, Kommentar,
  Track, Genre). False = Datei nicht lesbar (Grund in ErrMsg). }
function ReadMp3Tags(const FileName: string; out Tags: TMp4Tags;
  out Info: TMp3Info; out ErrMsg: string): Boolean;

{ Schreibt NUR die Felder aus Fields (leerer Text bzw. leeres Cover =
  Frame entfernen). Alle anderen Frames und die Audiodaten bleiben
  unverändert. Die neue Datei wird vor dem Ersetzen geprüft. Das Cover
  muss JPEG oder PNG sein. }
function WriteMp3Tags(const FileName: string; const Tags: TMp4Tags;
  Fields: TMp4TagFields; out ErrMsg: string): Boolean;

implementation

type
  { Ein Frame so, wie er in der Datei steht. Data ist der Inhalt ohne den
    Frame-Kopf; bei v2.3 schon ohne die Unsynchronisation des ganzen
    Blocks. Unbekannte Frames werden genau so wieder geschrieben. }
  TId3Frame = record
    ID   : AnsiString;   // 'TIT2', bei v2.2 drei Zeichen wie 'TT2'
    Flags: Word;         // Frame-Flags (v2.2: immer 0)
    Data : TBytes;       // Inhalt
  end;
  TId3FrameArray = array of TId3Frame;

  { pro Frame ein Ja/Nein, z.B. "dieser Frame wird ersetzt" }
  TFlagArray = array of Boolean;

  { Der ganze ID3v2-Block einer Datei }
  TId3Tag = record
    Present   : Boolean;        // Datei beginnt mit 'ID3'
    Major     : Integer;        // 2, 3 oder 4
    BodySize  : Int64;          // Grösse ohne Kopf und Fusszeile (aus dem Kopf)
    AudioStart: Int64;          // ab hier beginnen die Audiodaten
    Frames    : TId3FrameArray; // alle Frames in Datei-Reihenfolge
    Damaged   : Boolean;        // nach den Frames stand etwas anderes als Nullen
  end;

const
  { So viele Füllbytes bekommt ein neuer oder vergrösserter Block }
  PADDING_NEW = 4096;

{ ---------------------------------------------------------------------------
  Kleine Helfer
  --------------------------------------------------------------------------- }

function IsMp3File(const FileName: string): Boolean;
begin
  Result := LowerCase(ExtractFileExt(FileName)) = '.mp3';
end;

{ 4 Byte "synchsafe" (je 7 Bit) in eine Zahl umrechnen }
function SyncSafe(const B: TBytes; P: SizeInt): LongWord;
begin
  Result := (LongWord(B[P] and $7F) shl 21) or (LongWord(B[P + 1] and $7F) shl 14) or
            (LongWord(B[P + 2] and $7F) shl 7) or LongWord(B[P + 3] and $7F);
end;

function BE32(const B: TBytes; P: SizeInt): LongWord;
begin
  Result := (LongWord(B[P]) shl 24) or (LongWord(B[P + 1]) shl 16) or
            (LongWord(B[P + 2]) shl 8) or LongWord(B[P + 3]);
end;

{ Zahl als 4 Byte schreiben, synchsafe oder normal (Big-Endian) }
procedure PutSize(var B: TBytes; P: SizeInt; V: LongWord; Safe: Boolean);
begin
  if Safe then
  begin
    B[P]     := (V shr 21) and $7F;
    B[P + 1] := (V shr 14) and $7F;
    B[P + 2] := (V shr 7) and $7F;
    B[P + 3] := V and $7F;
  end
  else
  begin
    B[P]     := (V shr 24) and $FF;
    B[P + 1] := (V shr 16) and $FF;
    B[P + 2] := (V shr 8) and $FF;
    B[P + 3] := V and $FF;
  end;
end;

{ Unsynchronisation rückgängig machen: nach jedem $FF ein eingefügtes $00
  wieder entfernen }
function ReSync(const B: TBytes): TBytes;
var
  I, N: SizeInt;
begin
  Result := nil;
  SetLength(Result, Length(B));
  N := 0;
  I := 0;
  while I < Length(B) do
  begin
    Result[N] := B[I];
    Inc(N);
    if (B[I] = $FF) and (I + 1 < Length(B)) and (B[I + 1] = $00) then
      Inc(I);   // das eingefügte $00 überspringen
    Inc(I);
  end;
  SetLength(Result, N);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ Bytes anhängen }
procedure AddBytes(var Dst: TBytes; const Src: TBytes);
var
  N: SizeInt;
begin
  if Length(Src) = 0 then Exit;
  N := Length(Dst);
  SetLength(Dst, N + Length(Src));
  Move(Src[0], Dst[N], Length(Src));
end;

procedure AddByte(var Dst: TBytes; V: Byte);
begin
  SetLength(Dst, Length(Dst) + 1);
  Dst[High(Dst)] := V;
end;

procedure AddAnsi(var Dst: TBytes; const S: AnsiString);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    AddByte(Dst, Byte(S[I]));
end;

{ ---------------------------------------------------------------------------
  Text lesen und schreiben (Zeichenkodierungen)
  --------------------------------------------------------------------------- }

{ Länge eines Texts bis zum Ende-Zeichen (für Kodierung 1/2 zwei Nullbytes
  auf gerader Position). Liefert die Länge OHNE Ende-Zeichen; Next zeigt
  hinter das Ende-Zeichen. Ohne Ende-Zeichen gilt alles bis Stop. }
function TextLen(Enc: Byte; const B: TBytes; Start, Stop: SizeInt; out Next: SizeInt): SizeInt;
var
  I: SizeInt;
begin
  I := Start;
  if Enc in [1, 2] then
  begin
    while I + 1 < Stop do
    begin
      if (B[I] = 0) and (B[I + 1] = 0) then
      begin
        Next := I + 2;
        Exit(I - Start);
      end;
      Inc(I, 2);
    end;
  end
  else
    while I < Stop do
    begin
      if B[I] = 0 then
      begin
        Next := I + 1;
        Exit(I - Start);
      end;
      Inc(I);
    end;
  Next := Stop;
  Result := Stop - Start;
end;

{ UnicodeString als UTF-8 in einen normalen string. Ohne SetCodePage würde
  Free Pascal den Text in die Windows-Codepage umwandeln, wenn das
  Programm nicht schon auf UTF-8 steht (die LCL macht das, ein
  Konsolen-Test nicht). }
function ToUtf8(const W: UnicodeString): string;
var
  R: RawByteString;
begin
  R := UTF8Encode(W);
  SetCodePage(R, DefaultSystemCodePage, False);
  Result := R;
end;

{ Bytes in der angegebenen Kodierung nach UTF-8 umwandeln }
function DecodeText(Enc: Byte; const B: TBytes; Start, Len: SizeInt): string;
var
  W: UnicodeString;
  I, N: SizeInt;
  BigEndian: Boolean;
  R: RawByteString;
begin
  Result := '';
  if Len <= 0 then Exit;
  case Enc of
    0: begin
         { Latin-1: jedes Byte ist ein Zeichen U+0000..U+00FF }
         SetLength(W, Len);
         for I := 0 to Len - 1 do
           W[I + 1] := WideChar(B[Start + I]);
         Result := ToUtf8(W);
       end;
    1, 2:
       begin
         BigEndian := Enc = 2;
         I := Start;
         if (Enc = 1) and (Len >= 2) then
         begin
           { Byte-Reihenfolge steht im BOM: FF FE = Little-, FE FF = Big-Endian }
           if (B[I] = $FE) and (B[I + 1] = $FF) then begin BigEndian := True; Inc(I, 2); end
           else if (B[I] = $FF) and (B[I + 1] = $FE) then Inc(I, 2);
         end;
         N := (Start + Len - I) div 2;
         SetLength(W, N);
         for N := 1 to Length(W) do
         begin
           if BigEndian then
             W[N] := WideChar((B[I] shl 8) or B[I + 1])
           else
             W[N] := WideChar(B[I] or (B[I + 1] shl 8));
           Inc(I, 2);
         end;
         Result := ToUtf8(W);
       end;
  else
    begin
      { 3 = UTF-8 (und unbekannte Kodierungen auch so behandeln) }
      SetLength(R, Len);
      Move(B[Start], R[1], Len);
      Result := R;
    end;
  end;
end;

{ Passende Kodierung für einen Text: v2.4 UTF-8 (3). v2.3: Latin-1 (0),
  wenn alle Zeichen hineinpassen, sonst UTF-16 mit BOM (1). }
function ChooseEncoding(Major: Integer; const S: string): Byte;
var
  W: UnicodeString;
  I: Integer;
begin
  if Major >= 4 then Exit(3);
  W := UTF8Decode(S);
  for I := 1 to Length(W) do
    if Ord(W[I]) > $FF then
      Exit(1);
  Result := 0;
end;

{ Text in der Kodierung Enc an Dst anhängen, mit Terminate auch das
  Ende-Zeichen (für Beschreibungen in COMM/APIC) }
procedure AddText(var Dst: TBytes; Enc: Byte; const S: string; Terminate: Boolean);
var
  W: UnicodeString;
  I: Integer;
begin
  case Enc of
    0: begin
         W := UTF8Decode(S);
         for I := 1 to Length(W) do
           AddByte(Dst, Ord(W[I]) and $FF);
         if Terminate then AddByte(Dst, 0);
       end;
    1: begin
         W := UTF8Decode(S);
         AddByte(Dst, $FF); AddByte(Dst, $FE);   // BOM: Little-Endian
         for I := 1 to Length(W) do
         begin
           AddByte(Dst, Ord(W[I]) and $FF);
           AddByte(Dst, Ord(W[I]) shr 8);
         end;
         if Terminate then begin AddByte(Dst, 0); AddByte(Dst, 0); end;
       end;
  else
    begin
      AddAnsi(Dst, S);   // UTF-8, so wie der Text schon vorliegt
      if Terminate then AddByte(Dst, 0);
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  ID3v2-Block einlesen
  --------------------------------------------------------------------------- }

{ Ist das eine gültige Frame-Kennung (nur A-Z und 0-9)? }
function ValidFrameID(const B: TBytes; P, Len: SizeInt): Boolean;
var
  I: SizeInt;
begin
  Result := False;
  for I := P to P + Len - 1 do
    if not (Chr(B[I]) in ['A'..'Z', '0'..'9']) then
      Exit;
  Result := True;
end;

{ Liest den ID3v2-Block am Dateianfang. Ohne Block: Present = False und
  AudioStart = 0. Ausnahme bei unbekannter Version oder kaputtem Kopf. }
procedure ReadId3Tag(S: TStream; out Tag: TId3Tag);
var
  Head, Body: TBytes;
  Flags: Byte;
  P, HdrLen, IdLen: SizeInt;
  FrameSize: Int64;
  Fr: TId3Frame;
  I: SizeInt;
begin
  Tag.Present := False;
  Tag.Major := 0;
  Tag.BodySize := 0;
  Tag.AudioStart := 0;
  Tag.Frames := nil;
  Tag.Damaged := False;
  Head := nil;
  SetLength(Head, 10);
  S.Position := 0;
  if (S.Size < 10) or (S.Read(Head[0], 10) <> 10) then Exit;
  if (Head[0] <> Ord('I')) or (Head[1] <> Ord('D')) or (Head[2] <> Ord('3')) then Exit;
  if (Head[6] or Head[7] or Head[8] or Head[9]) and $80 <> 0 then
    raise Exception.Create('ID3-Kopf ist beschädigt');
  Tag.Present := True;
  Tag.Major := Head[3];
  if not (Tag.Major in [2, 3, 4]) then
    raise Exception.CreateFmt('Unbekannte ID3-Version 2.%d', [Tag.Major]);
  Flags := Head[5];
  Tag.BodySize := SyncSafe(Head, 6);
  Tag.AudioStart := 10 + Tag.BodySize;
  if (Tag.Major = 4) and (Flags and $10 <> 0) then
    Inc(Tag.AudioStart, 10);   // Fusszeile '3DI'
  if Tag.AudioStart > S.Size then
    raise Exception.Create('ID3-Block ist grösser als die Datei');

  Body := nil;
  SetLength(Body, Tag.BodySize);
  if Tag.BodySize > 0 then
    S.ReadBuffer(Body[0], Tag.BodySize);
  { v2.2/v2.3: Unsynchronisation gilt für den ganzen Block }
  if (Tag.Major < 4) and (Flags and $80 <> 0) then
    Body := ReSync(Body);

  P := 0;
  { erweiterten Kopf überspringen (er enthält nur Prüfsummen u. ä.) }
  if (Flags and $40 <> 0) and (Tag.Major >= 3) and (Length(Body) >= 4) then
  begin
    if Tag.Major = 3 then
      P := 4 + BE32(Body, 0)
    else
      P := SyncSafe(Body, 0);
  end;

  if Tag.Major = 2 then begin IdLen := 3; HdrLen := 6; end
  else begin IdLen := 4; HdrLen := 10; end;

  while P + HdrLen <= Length(Body) do
  begin
    if Body[P] = 0 then
      Break;   // Füllbytes
    if not ValidFrameID(Body, P, IdLen) then
    begin
      Tag.Damaged := True;
      Break;
    end;
    SetLength(Fr.ID, IdLen);
    Move(Body[P], Fr.ID[1], IdLen);
    if Tag.Major = 2 then
    begin
      FrameSize := (Body[P + 3] shl 16) or (Body[P + 4] shl 8) or Body[P + 5];
      Fr.Flags := 0;
    end
    else
    begin
      { v2.4 ist synchsafe. Manche Programme schreiben trotzdem eine normale
        Zahl - steht ein Byte mit gesetztem Bit 7 da, kann es nur so sein. }
      if (Tag.Major = 4) and ((Body[P + 4] or Body[P + 5] or Body[P + 6] or Body[P + 7]) and $80 = 0) then
        FrameSize := SyncSafe(Body, P + 4)
      else
        FrameSize := BE32(Body, P + 4);
      Fr.Flags := (Body[P + 8] shl 8) or Body[P + 9];
    end;
    if P + HdrLen + FrameSize > Length(Body) then
    begin
      Tag.Damaged := True;
      Break;
    end;
    Fr.Data := nil;
    SetLength(Fr.Data, FrameSize);
    if FrameSize > 0 then
      Move(Body[P + HdrLen], Fr.Data[0], FrameSize);
    SetLength(Tag.Frames, Length(Tag.Frames) + 1);
    Tag.Frames[High(Tag.Frames)] := Fr;
    Inc(P, HdrLen + FrameSize);
  end;
  { nach den Frames dürfen nur noch Füllbytes (Nullen) kommen }
  if not Tag.Damaged then
    for I := P to High(Body) do
      if Body[I] <> 0 then
      begin
        Tag.Damaged := True;
        Break;
      end;
end;

{ Inhalt eines Frames zum Auswerten: Frame-Flags berücksichtigen
  (Gruppen-Byte, Datenlänge, Unsynchronisation). False = komprimiert oder
  verschlüsselt, den Frame lassen wir dann in Ruhe. }
function FrameContent(Major: Integer; const Fr: TId3Frame; out C: TBytes): Boolean;
var
  Skip: SizeInt;
begin
  C := nil;
  Skip := 0;
  if Major = 3 then
  begin
    if Fr.Flags and $00C0 <> 0 then Exit(False);   // komprimiert / verschlüsselt
    if Fr.Flags and $0020 <> 0 then Skip := 1;      // Gruppen-Byte
  end
  else if Major = 4 then
  begin
    if Fr.Flags and $000C <> 0 then Exit(False);   // komprimiert / verschlüsselt
    if Fr.Flags and $0040 <> 0 then Inc(Skip);      // Gruppen-Byte
    if Fr.Flags and $0001 <> 0 then Inc(Skip, 4);   // Angabe der Datenlänge
  end;
  if Skip > Length(Fr.Data) then Exit(False);
  C := Copy(Fr.Data, Skip, Length(Fr.Data) - Skip);
  if (Major = 4) and (Fr.Flags and $0002 <> 0) then
    C := ReSync(C);
  Result := True;
end;

{ Text eines Text-Frames (T***). Mehrere Werte (v2.4: durch Null getrennt)
  werden mit "; " verbunden. }
function FrameText(Major: Integer; const Fr: TId3Frame): string;
var
  C: TBytes;
  P, Next, L: SizeInt;
  Part: string;
begin
  Result := '';
  if not FrameContent(Major, Fr, C) or (Length(C) < 1) then Exit;
  P := 1;
  while P < Length(C) do
  begin
    L := TextLen(C[0], C, P, Length(C), Next);
    Part := Trim(DecodeText(C[0], C, P, L));
    if Part <> '' then
    begin
      if Result <> '' then Result := Result + '; ';
      Result := Result + Part;
    end;
    if Next <= P then Break;
    P := Next;
  end;
end;

{ COMM/COM-Frame zerlegen: Beschreibung und Text }
function ParseComment(Major: Integer; const Fr: TId3Frame; out Desc, Txt: string): Boolean;
var
  C: TBytes;
  P, Next, L: SizeInt;
begin
  Desc := '';
  Txt := '';
  Result := FrameContent(Major, Fr, C) and (Length(C) >= 4);
  if not Result then Exit;
  P := 4;   // Kodierung (1) + Sprache (3)
  L := TextLen(C[0], C, P, Length(C), Next);
  Desc := DecodeText(C[0], C, P, L);
  P := Next;
  L := TextLen(C[0], C, P, Length(C), Next);
  Txt := Trim(DecodeText(C[0], C, P, L));
end;

{ APIC/PIC-Frame zerlegen: Bildart (3 = Vorderseite) und Bilddaten }
function ParsePicture(Major: Integer; const Fr: TId3Frame; out PicType: Integer;
  out Img: TBytes): Boolean;
var
  C: TBytes;
  P, Next: SizeInt;
begin
  PicType := -1;
  Img := nil;
  Result := FrameContent(Major, Fr, C) and (Length(C) >= 4);
  if not Result then Exit;
  if Major = 2 then
    P := 4   // Kodierung (1) + Bildformat (3, z.B. 'JPG')
  else
  begin
    P := 1;
    while (P < Length(C)) and (C[P] <> 0) do Inc(P);   // MIME-Typ, Latin-1
    Inc(P);
  end;
  if P >= Length(C) then Exit(False);
  PicType := C[P];
  Inc(P);
  TextLen(C[0], C, P, Length(C), Next);   // Beschreibung überspringen
  if Next > Length(C) then Exit(False);
  Img := Copy(C, Next, Length(C) - Next);
  Result := Length(Img) > 0;
end;

{ Enthält der Frame Traktors Daten? Traktor Pro 3/4 schreibt PRIV mit
  Besitzer "TRAKTOR4", ältere Versionen GEOB mit Beschreibung "TRAKTOR4". }
function IsTraktorFrame(const Fr: TId3Frame): Boolean;
var
  I, J: SizeInt;
const
  KEY = 'TRAKTOR';
begin
  Result := False;
  if ((Fr.ID <> 'PRIV') and (Fr.ID <> 'GEOB')) or (Length(Fr.Data) < Length(KEY)) then Exit;
  { Kennung bzw. Beschreibung steht weit vorne; einfach in den ersten 64 Byte suchen }
  for I := 0 to Min(64, Length(Fr.Data)) - Length(KEY) do
  begin
    J := 1;
    while (J <= Length(KEY)) and (Fr.Data[I + J - 1] = Ord(KEY[J])) do Inc(J);
    if J > Length(KEY) then Exit(True);
  end;
end;

{ ---------------------------------------------------------------------------
  Welche Frames gehören zu welchem Feld?
  --------------------------------------------------------------------------- }

{ Frame-Kennungen eines Felds: die erste wird beim Schreiben benutzt,
  alle werden beim Schreiben entfernt. Jahr: v2.4 TDRC, v2.3 TYER. }
function FieldIDs(Major: Integer; F: TMp4TagField): TStringArray;
begin
  Result := nil;
  if Major = 2 then
    case F of
      tfTitle      : Result := ['TT2'];
      tfArtist     : Result := ['TP1'];
      tfAlbum      : Result := ['TAL'];
      tfAlbumArtist: Result := ['TP2'];
      tfGenre      : Result := ['TCO'];
      tfYear       : Result := ['TYE'];
      tfTrack      : Result := ['TRK'];
      tfBpm        : Result := ['TBP'];
      tfKey        : Result := ['TKE'];
      tfLabel      : Result := ['TPB'];
    end
  else
    case F of
      tfTitle      : Result := ['TIT2'];
      tfArtist     : Result := ['TPE1'];
      tfAlbum      : Result := ['TALB'];
      tfAlbumArtist: Result := ['TPE2'];
      tfGenre      : Result := ['TCON'];
      tfYear       : if Major >= 4 then Result := ['TDRC', 'TYER'] else Result := ['TYER', 'TDRC'];
      tfTrack      : Result := ['TRCK'];
      tfBpm        : Result := ['TBPM'];
      tfKey        : Result := ['TKEY'];
      tfLabel      : Result := ['TPUB'];
    end;
end;

function InList(const ID: AnsiString; const L: TStringArray): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(L) do
    if L[I] = ID then Exit(True);
  Result := False;
end;

{ Welche Kommentar-Frames zeigen wir als "Kommentar"? Alle ohne
  Beschreibung; gibt es keinen, der erste, der nicht von iTunes ist
  (iTunNORM, iTunSMPB ... sind technische Werte, keine Kommentare). }
function CommentFrames(const Tag: TId3Tag): TFlagArray;
var
  I: Integer;
  Desc, Txt, CommID: string;
  Any: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(Tag.Frames));
  if Tag.Major = 2 then CommID := 'COM' else CommID := 'COMM';
  Any := False;
  for I := 0 to High(Tag.Frames) do
    if (Tag.Frames[I].ID = CommID) and ParseComment(Tag.Major, Tag.Frames[I], Desc, Txt) and (Desc = '') then
    begin
      Result[I] := True;
      Any := True;
    end;
  if not Any then
    for I := 0 to High(Tag.Frames) do
      if (Tag.Frames[I].ID = CommID) and ParseComment(Tag.Major, Tag.Frames[I], Desc, Txt) and
         (Pos('iTun', Desc) <> 1) then
      begin
        Result[I] := True;
        Break;
      end;
end;

{ Welche Bild-Frames sind "das Cover"? Alle mit Bildart 3 (Vorderseite);
  gibt es keins, das erste Bild überhaupt. Andere Bilder (Rückseite ...)
  bleiben beim Schreiben erhalten. }
function CoverFrames(const Tag: TId3Tag): TFlagArray;
var
  I, PT: Integer;
  Img: TBytes;
  PicID: string;
  Any: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(Tag.Frames));
  if Tag.Major = 2 then PicID := 'PIC' else PicID := 'APIC';
  Any := False;
  for I := 0 to High(Tag.Frames) do
    if (Tag.Frames[I].ID = PicID) and ParsePicture(Tag.Major, Tag.Frames[I], PT, Img) and (PT = 3) then
    begin
      Result[I] := True;
      Any := True;
    end;
  if not Any then
    for I := 0 to High(Tag.Frames) do
      if Tag.Frames[I].ID = PicID then
      begin
        Result[I] := True;
        Break;
      end;
end;

{ Genre-Text aufbereiten: "(17)" oder "17" -> "Rock", "(17)Rock" -> "Rock" }
function CleanGenre(const S: string): string;
var
  P, N: Integer;
begin
  Result := Trim(S);
  if (Length(Result) >= 3) and (Result[1] = '(') then
  begin
    P := Pos(')', Result);
    if (P > 2) and TryStrToInt(Copy(Result, 2, P - 2), N) then
    begin
      if P < Length(Result) then
        Exit(Trim(Copy(Result, P + 1, MaxInt)));   // Text nach der Nummer gilt
      if Id3GenreName(N) <> '' then
        Exit(Id3GenreName(N));
    end;
  end
  else if TryStrToInt(Result, N) and (Id3GenreName(N) <> '') then
    Result := Id3GenreName(N);
end;

{ ---------------------------------------------------------------------------
  ID3v1 (128 Byte am Dateiende) - nur zum Lesen, falls ID3v2 fehlt
  --------------------------------------------------------------------------- }

procedure ReadId3v1(S: TStream; var Tags: TMp4Tags);
var
  B: TBytes;

  function Field(P, Len: Integer): string;
  var
    L: Integer;
  begin
    L := 0;
    while (L < Len) and (B[P + L] <> 0) do Inc(L);
    Result := Trim(DecodeText(0, B, P, L));
  end;

  procedure Take(F: TMp4TagField; const V: string);
  begin
    if (Tags.Text[F] = '') and (V <> '') then
      Tags.Text[F] := V;
  end;

begin
  if S.Size < 128 then Exit;
  B := nil;
  SetLength(B, 128);
  S.Position := S.Size - 128;
  S.ReadBuffer(B[0], 128);
  if (B[0] <> Ord('T')) or (B[1] <> Ord('A')) or (B[2] <> Ord('G')) then Exit;
  Take(tfTitle, Field(3, 30));
  Take(tfArtist, Field(33, 30));
  Take(tfAlbum, Field(63, 30));
  Take(tfYear, Field(93, 4));
  if (B[125] = 0) and (B[126] <> 0) then
  begin
    { ID3v1.1: Track-Nr. im letzten Byte des Kommentars }
    Take(tfComment, Field(97, 28));
    Take(tfTrack, IntToStr(B[126]));
  end
  else
    Take(tfComment, Field(97, 30));
  Take(tfGenre, Id3GenreName(B[127]));
end;

{ ---------------------------------------------------------------------------
  Tags lesen
  --------------------------------------------------------------------------- }

{ Felder aus einem eingelesenen Block holen }
procedure TagToFields(const Tag: TId3Tag; out Tags: TMp4Tags);
var
  F: TMp4TagField;
  I, PT: Integer;
  IDs: TStringArray;
  Comm, Cov: TFlagArray;
  Desc, Txt: string;
  Img: TBytes;
begin
  for F := Low(TMp4TagField) to High(TMp4TagField) do
    Tags.Text[F] := '';
  Tags.Cover := nil;
  if not Tag.Present then Exit;
  for F := Low(TMp4TagField) to High(TMp4TagField) do
  begin
    if F in [tfComment, tfCover] then Continue;
    IDs := FieldIDs(Tag.Major, F);
    for I := 0 to High(Tag.Frames) do
      if InList(Tag.Frames[I].ID, IDs) then
      begin
        Tags.Text[F] := FrameText(Tag.Major, Tag.Frames[I]);
        if Tags.Text[F] <> '' then Break;
      end;
  end;
  Tags.Text[tfGenre] := CleanGenre(Tags.Text[tfGenre]);
  Comm := CommentFrames(Tag);
  for I := 0 to High(Tag.Frames) do
    if Comm[I] and ParseComment(Tag.Major, Tag.Frames[I], Desc, Txt) and (Txt <> '') then
    begin
      Tags.Text[tfComment] := Txt;
      Break;
    end;
  Cov := CoverFrames(Tag);
  for I := 0 to High(Tag.Frames) do
    if Cov[I] and ParsePicture(Tag.Major, Tag.Frames[I], PT, Img) and IsMp4CoverImage(Img) then
    begin
      Tags.Cover := Img;
      Break;
    end;
end;

function ReadMp3Tags(const FileName: string; out Tags: TMp4Tags;
  out Info: TMp3Info; out ErrMsg: string): Boolean;
var
  S: TFileStream;
  Tag: TId3Tag;
  I: Integer;
  F: TMp4TagField;
begin
  Result := False;
  ErrMsg := '';
  for F := Low(TMp4TagField) to High(TMp4TagField) do
    Tags.Text[F] := '';
  Tags.Cover := nil;
  Info.Id3Major := 0;
  Info.HasTraktor := False;
  Info.CanWrite := False;
  Info.Problem := '';
  try
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      ReadId3Tag(S, Tag);
      TagToFields(Tag, Tags);
      ReadId3v1(S, Tags);
      if Tag.Present then Info.Id3Major := Tag.Major;
      for I := 0 to High(Tag.Frames) do
        if IsTraktorFrame(Tag.Frames[I]) then
          Info.HasTraktor := True;
      if Tag.Present and (Tag.Major = 2) then
        Info.Problem := 'ID3v2.2 kann nur gelesen werden'
      else if Tag.Damaged then
        Info.Problem := 'ID3-Block ist beschädigt'
      else
        Info.CanWrite := True;
      Result := True;
    finally
      S.Free;
    end;
  except
    on E: Exception do
      ErrMsg := E.Message;
  end;
end;

{ ---------------------------------------------------------------------------
  Tags schreiben
  --------------------------------------------------------------------------- }

function MakeFrame(const ID: AnsiString; const Data: TBytes): TId3Frame;
begin
  Result.ID := ID;
  Result.Flags := 0;
  Result.Data := Data;
end;

{ Neuer Text-Frame: Kodierung + Text }
function MakeTextFrame(Major: Integer; const ID: AnsiString; const S: string): TId3Frame;
var
  D: TBytes;
  Enc: Byte;
begin
  D := nil;
  Enc := ChooseEncoding(Major, S);
  AddByte(D, Enc);
  AddText(D, Enc, S, False);
  Result := MakeFrame(ID, D);
end;

{ Neuer Kommentar: Kodierung, Sprache 'eng', leere Beschreibung, Text }
function MakeCommentFrame(Major: Integer; const S: string): TId3Frame;
var
  D: TBytes;
  Enc: Byte;
begin
  D := nil;
  Enc := ChooseEncoding(Major, S);
  AddByte(D, Enc);
  AddAnsi(D, 'eng');
  AddText(D, Enc, '', True);
  AddText(D, Enc, S, False);
  Result := MakeFrame('COMM', D);
end;

{ Neues Cover: Latin-1, MIME-Typ, Bildart 3 (Vorderseite), keine Beschreibung }
function MakeCoverFrame(const Img: TBytes): TId3Frame;
var
  D: TBytes;
begin
  D := nil;
  AddByte(D, 0);
  if (Length(Img) > 0) and (Img[0] = $89) then
    AddAnsi(D, 'image/png')
  else
    AddAnsi(D, 'image/jpeg');
  AddByte(D, 0);
  AddByte(D, 3);
  AddByte(D, 0);
  AddBytes(D, Img);
  Result := MakeFrame('APIC', D);
end;

{ Frames entfernen, die Remove markiert, und an der Stelle des ersten
  entfernten Frames den neuen einsetzen (sonst hinten anhängen).
  Alle anderen Frames behalten ihre Reihenfolge. }
procedure ReplaceFrames(var Frames: TId3FrameArray; const Remove: TFlagArray;
  HasNew: Boolean; const NewFrame: TId3Frame);
var
  R: TId3FrameArray;
  I, At: Integer;
begin
  R := nil;
  At := -1;
  for I := 0 to High(Frames) do
    if Remove[I] then
    begin
      if At < 0 then At := Length(R);
    end
    else
    begin
      SetLength(R, Length(R) + 1);
      R[High(R)] := Frames[I];
    end;
  if HasNew then
  begin
    if At < 0 then At := Length(R);
    SetLength(R, Length(R) + 1);
    for I := High(R) downto At + 1 do
      R[I] := R[I - 1];
    R[At] := NewFrame;
  end;
  Frames := R;
end;

{ Frames als Bytes (ohne Block-Kopf) }
function FramesToBytes(Major: Integer; const Frames: TId3FrameArray): TBytes;
var
  I: Integer;
  H: TBytes;
begin
  Result := nil;
  H := nil;
  SetLength(H, 10);
  for I := 0 to High(Frames) do
  begin
    Move(Frames[I].ID[1], H[0], 4);
    PutSize(H, 4, Length(Frames[I].Data), Major >= 4);
    H[8] := Frames[I].Flags shr 8;
    H[9] := Frames[I].Flags and $FF;
    AddBytes(Result, H);
    AddBytes(Result, Frames[I].Data);
  end;
end;

{ Sind die Bytes von A ab PosA und B ab PosB bis zum Ende gleich? }
function SameTail(A, B: TStream; PosA, PosB: Int64): Boolean;
const
  CHUNK = 1 shl 16;
var
  BufA, BufB: TBytes;
  N: Integer;
begin
  Result := False;
  if A.Size - PosA <> B.Size - PosB then Exit;
  BufA := nil;
  BufB := nil;
  SetLength(BufA, CHUNK);
  SetLength(BufB, CHUNK);
  A.Position := PosA;
  B.Position := PosB;
  repeat
    N := A.Read(BufA[0], CHUNK);
    if N = 0 then Break;
    if (B.Read(BufB[0], N) <> N) or not CompareMem(@BufA[0], @BufB[0], N) then Exit;
  until False;
  Result := True;
end;

function SameFrame(const A, B: TId3Frame): Boolean;
begin
  Result := (A.ID = B.ID) and (A.Flags = B.Flags) and SameBytes(A.Data, B.Data);
end;

function WriteMp3Tags(const FileName: string; const Tags: TMp4Tags;
  Fields: TMp4TagFields; out ErrMsg: string): Boolean;
var
  Src, Dst: TFileStream;
  Tag, Check: TId3Tag;
  Frames: TId3FrameArray;
  Remove: TFlagArray;
  F: TMp4TagField;
  IDs: TStringArray;
  I, Major: Integer;
  Body, Head: TBytes;
  NewBodySize: Int64;
  TmpName, V: string;
  NewFrame: TId3Frame;
  Fresh: TMp4Tags;
  Inf: TMp3Info;
  Err2: string;
  Changed: Boolean;
begin
  Result := False;
  ErrMsg := '';
  TmpName := FileName + '.tagtmp';
  try
    Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      { --- 1. alten Block lesen ------------------------------------------- }
      ReadId3Tag(Src, Tag);
      if Tag.Present and (Tag.Major = 2) then
        raise Exception.Create('ID3v2.2 wird nicht geschrieben (nur gelesen)');
      if Tag.Damaged then
        raise Exception.Create('ID3-Block ist beschädigt, die Datei bleibt unverändert');
      if Tag.Present then Major := Tag.Major else Major := 3;
      Tag.Major := Major;
      Frames := Copy(Tag.Frames);

      { --- 2. Frames der geänderten Felder ersetzen ----------------------- }
      for F := Low(TMp4TagField) to High(TMp4TagField) do
      begin
        if not (F in Fields) then Continue;
        Tag.Frames := Frames;   // für CommentFrames/CoverFrames
        Remove := nil;
        SetLength(Remove, Length(Frames));
        V := Trim(Tags.Text[F]);
        case F of
          tfComment:
            begin
              Remove := CommentFrames(Tag);
              if V <> '' then NewFrame := MakeCommentFrame(Major, V);
            end;
          tfCover:
            begin
              Remove := CoverFrames(Tag);
              V := '';
              if Length(Tags.Cover) > 0 then
              begin
                if not IsMp4CoverImage(Tags.Cover) then
                  raise Exception.Create('Cover muss JPEG oder PNG sein');
                NewFrame := MakeCoverFrame(Tags.Cover);
                V := 'x';
              end;
            end;
        else
          begin
            IDs := FieldIDs(Major, F);
            for I := 0 to High(Frames) do
              Remove[I] := InList(Frames[I].ID, IDs);
            if V <> '' then NewFrame := MakeTextFrame(Major, IDs[0], V);
          end;
        end;
        ReplaceFrames(Frames, Remove, V <> '', NewFrame);
      end;

      Tag.Frames := nil;

      { --- 3. neuen Block bauen ------------------------------------------- }
      Body := FramesToBytes(Major, Frames);
      { alter Platz reicht? Dann gleich gross lassen, sonst mit Reserve }
      if Tag.Present and (Length(Body) <= Tag.BodySize) then
        NewBodySize := Tag.BodySize
      else
        NewBodySize := Length(Body) + PADDING_NEW;
      if NewBodySize > $0FFFFFFF then
        raise Exception.Create('ID3-Block wird zu gross');
      Head := nil;
      SetLength(Head, 10);
      Head[0] := Ord('I'); Head[1] := Ord('D'); Head[2] := Ord('3');
      Head[3] := Major; Head[4] := 0; Head[5] := 0;
      PutSize(Head, 6, NewBodySize, True);
      I := Length(Body);
      SetLength(Body, NewBodySize);   // Rest sind Füllbytes (Nullen)
      if NewBodySize > I then
        FillChar(Body[I], NewBodySize - I, 0);

      { --- 4. Zwischendatei: Block + Audiodaten 1:1 ----------------------- }
      Dst := TFileStream.Create(TmpName, fmCreate);
      try
        Dst.WriteBuffer(Head[0], 10);
        if NewBodySize > 0 then
          Dst.WriteBuffer(Body[0], NewBodySize);
        Src.Position := Tag.AudioStart;
        if Src.Size > Tag.AudioStart then
          Dst.CopyFrom(Src, Src.Size - Tag.AudioStart);
      finally
        Dst.Free;
      end;

      { --- 5. Zwischendatei prüfen ---------------------------------------- }
      Dst := TFileStream.Create(TmpName, fmOpenRead or fmShareDenyWrite);
      try
        ReadId3Tag(Dst, Check);
        if not Check.Present or Check.Damaged or (Length(Check.Frames) <> Length(Frames)) then
          raise Exception.Create('Prüfung: neuer ID3-Block ist nicht lesbar');
        for I := 0 to High(Frames) do
          if not SameFrame(Frames[I], Check.Frames[I]) then
            raise Exception.Create('Prüfung: ein Frame hat sich verändert');
        if not SameTail(Src, Dst, Tag.AudioStart, Check.AudioStart) then
          raise Exception.Create('Prüfung: Audiodaten haben sich verändert');
      finally
        Dst.Free;
      end;
    finally
      Src.Free;
    end;

    { geschriebene Werte wieder lesen und vergleichen }
    if not ReadMp3Tags(TmpName, Fresh, Inf, Err2) then
      raise Exception.Create('Prüfung: ' + Err2);
    for F := Low(TMp4TagField) to High(TMp4TagField) do
      if F in Fields then
      begin
        if F = tfCover then
          Changed := not SameBytes(Fresh.Cover, Tags.Cover)
        else if F = tfGenre then
          Changed := Fresh.Text[F] <> CleanGenre(Tags.Text[F])
        else
          Changed := Fresh.Text[F] <> Trim(Tags.Text[F]);
        { leere Felder können aus ID3v1 nachgelesen werden - das ist kein Fehler }
        if Changed and not ((F <> tfCover) and (Trim(Tags.Text[F]) = '')) then
          raise Exception.CreateFmt('Prüfung: geschriebener Wert stimmt nicht (Feld %d)', [Ord(F)]);
      end;

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
end;

end.
