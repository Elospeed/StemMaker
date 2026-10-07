{ ============================================================================
  mp4stem.pas  -  Liest die Struktur einer Traktor-Stem-Datei (.stem.mp4)

  Autor   : Elospeed
  Lizenz  : frei (wie Elospeed StemMaker)

  Eine Traktor-Stem-Datei ist eine normale MP4-Datei mit 5 Audiospuren:
      Spur 0 = Master (Originalmix)
      Spur 1 = Drums
      Spur 2 = Bass
      Spur 3 = Other / Synth
      Spur 4 = Vocals
  Zusätzlich steht unter moov/udta/stem ein JSON-Block mit den Namen und
  Farben der Stems (und den Mastering-DSP-Einstellungen für Traktor).

  Diese Unit liest OHNE externe Tools:
    - wie viele Audiospuren ('soun'-Tracks) die Datei hat
    - Namen und Farben der 4 Stems aus dem 'stem'-JSON
  Fehlt der JSON-Block, werden die Traktor-Standardnamen/-farben verwendet.

  Versionen:
    1.0  (01.10.2026)  Erste Version
    1.1  (02.10.2026)  unverändert (nur Kommentare ergänzt)
    1.2  (06.10.2026)  CheckStemFile: prüft vor dem Laden, ob die Datei
                       wirklich eine Stem-Datei ist (MP4 mit mind. 5 Audiospuren)
  ============================================================================ }
unit mp4stem;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, fpjson, jsonparser;

const
  STEM_COUNT = 4;  // Traktor-Stems haben immer genau 4 Spuren + Master

type
  TStemInfo = record
    AudioTracks : Integer;                           // Anzahl Audiospuren in der Datei
    HasStemBox  : Boolean;                           // 'stem'-JSON gefunden?
    Names       : array[0..STEM_COUNT-1] of string;  // Stem-Namen
    Colors      : array[0..STEM_COUNT-1] of TColor;  // Stem-Farben
    Json        : string;                            // Roh-JSON (zur Info)
  end;

{ Liest die Stem-Infos. Gibt False zurück, wenn die Datei kein gültiges MP4 ist
  (Info ist dann trotzdem mit Standardwerten gefüllt). }
function ReadStemInfo(const FileName: string; out Info: TStemInfo): Boolean;

{ Prüft, ob die Datei eine abspielbare Stem-Datei ist:
    - ein MP4-Container (sonst z.B. MP3, WAV, ZIP oder umbenannte Datei)
    - mit mindestens 5 Audiospuren (Master + 4 Stems)
  Gibt bei False in Reason eine Meldung für den Benutzer zurück
  (Deutsch und Englisch untereinander, der Player hat noch keine
  Sprachumschaltung). Info ist danach wie bei ReadStemInfo gefüllt. }
function CheckStemFile(const FileName: string; out Info: TStemInfo;
  out Reason: string): Boolean;

implementation

const
  { Traktor-Standardbelegung, falls kein 'stem'-JSON vorhanden ist }
  DefaultNames : array[0..STEM_COUNT-1] of string =
    ('Drums', 'Bass', 'Other', 'Vocals');
  DefaultColors: array[0..STEM_COUNT-1] of TColor =
    ($3D3DFC, $0094FF, $FFD100, $C0FF00);   // TColor ist $BBGGRR!

type
  TBoxHeader = record
    Typ     : string[4];  // 4-Zeichen-Typ, z.B. 'moov'
    Start   : Int64;      // Dateiposition des Box-Anfangs
    Size    : Int64;      // Gesamtgrösse inkl. Header
    Payload : Int64;      // Dateiposition der Nutzdaten (nach dem Header)
  end;

{ --- Big-Endian-Helfer (MP4 speichert alles Big-Endian) --------------------- }

function ReadU32BE(S: TStream): Cardinal;
var B: array[0..3] of Byte;
begin
  S.ReadBuffer(B, 4);
  Result := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or
            (Cardinal(B[2]) shl 8) or Cardinal(B[3]);
end;

function ReadU64BE(S: TStream): QWord;
begin
  Result := QWord(ReadU32BE(S)) shl 32;
  Result := Result or ReadU32BE(S);
end;

{ Liest einen Box-Header an der aktuellen Position. Limit = Ende des Elternbox. }
function ReadBox(S: TStream; Limit: Int64; out Box: TBoxHeader): Boolean;
var
  Sz: Int64;
  T : array[0..3] of Char;
begin
  Result := False;
  Box.Start := S.Position;
  if Box.Start + 8 > Limit then Exit;
  Sz := ReadU32BE(S);
  S.ReadBuffer(T, 4);
  Box.Typ := T[0] + T[1] + T[2] + T[3];
  if Sz = 1 then                       // 64-Bit-Grösse folgt
    Sz := Int64(ReadU64BE(S))
  else if Sz = 0 then                  // Box geht bis zum Ende des Elternbox
    Sz := Limit - Box.Start;
  Box.Payload := S.Position;
  Box.Size := Sz;
  { Plausibilitätsprüfung, damit kaputte Dateien keine Endlosschleife erzeugen }
  if (Sz < (Box.Payload - Box.Start)) or (Box.Start + Sz > Limit) then Exit;
  Result := True;
end;

{ Sucht in einem Bereich eine Kindbox mit bestimmtem Typ. }
function FindChild(S: TStream; FromPos, ToPos: Int64; const Typ: string;
  out Box: TBoxHeader): Boolean;
var B: TBoxHeader;
begin
  Result := False;
  S.Position := FromPos;
  while ReadBox(S, ToPos, B) do
  begin
    if B.Typ = Typ then
    begin
      Box := B;
      Exit(True);
    end;
    S.Position := B.Start + B.Size;
  end;
end;

{ Prüft, ob ein 'trak' eine Audiospur ist (mdia/hdlr mit handler_type 'soun'). }
function IsSoundTrack(S: TStream; const Trak: TBoxHeader): Boolean;
var
  Mdia, Hdlr: TBoxHeader;
  H: array[0..3] of Char;
begin
  Result := False;
  if not FindChild(S, Trak.Payload, Trak.Start + Trak.Size, 'mdia', Mdia) then Exit;
  if not FindChild(S, Mdia.Payload, Mdia.Start + Mdia.Size, 'hdlr', Hdlr) then Exit;
  { hdlr: 1 Byte Version + 3 Byte Flags + 4 Byte pre_defined, dann handler_type }
  S.Position := Hdlr.Payload + 8;
  S.ReadBuffer(H, 4);
  Result := (H = 'soun');
end;

{ '#RRGGBB' -> TColor ($BBGGRR) }
function HexToColor(const Hex: string; Default: TColor): TColor;
var
  V: LongInt;
  H: string;
begin
  Result := Default;
  H := Trim(Hex);
  if (Length(H) = 7) and (H[1] = '#') then
    if TryStrToInt('$' + Copy(H, 2, 6), V) then
      Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

// Wertet das Traktor-JSON aus: {"stems":[{"name":"Drums","color":"#FD3B3B"},...]}
procedure ParseStemJson(var Info: TStemInfo);
var
  Root : TJSONData;
  Arr  : TJSONArray;
  Item : TJSONObject;
  i    : Integer;
begin
  try
    Root := GetJSON(Info.Json);
  except
    Exit;  // ungültiges JSON -> Standardwerte bleiben
  end;
  try
    if (Root is TJSONObject) and
       (TJSONObject(Root).Find('stems', jtArray) <> nil) then
    begin
      Arr := TJSONObject(Root).Arrays['stems'];
      for i := 0 to Arr.Count - 1 do
      begin
        if i >= STEM_COUNT then Break;
        if not (Arr.Items[i] is TJSONObject) then Continue;
        Item := TJSONObject(Arr.Items[i]);
        Info.Names[i]  := Item.Get('name', Info.Names[i]);
        Info.Colors[i] := HexToColor(Item.Get('color', ''), Info.Colors[i]);
      end;
    end;
  finally
    Root.Free;
  end;
end;

function ReadStemInfo(const FileName: string; out Info: TStemInfo): Boolean;
var
  S    : TFileStream;
  Top, Child, StemBox: TBoxHeader;
  MoovEnd: Int64;
  Raw  : RawByteString;
  i    : Integer;
  FoundMoov: Boolean;
begin
  Result := False;
  { Standardwerte vorbelegen }
  Info.AudioTracks := 0;
  Info.HasStemBox := False;
  Info.Json := '';
  for i := 0 to STEM_COUNT - 1 do
  begin
    Info.Names[i] := DefaultNames[i];
    Info.Colors[i] := DefaultColors[i];
  end;

  try
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    Exit;
  end;
  try
    try
      { 1) 'moov' auf oberster Ebene suchen (kann vor oder nach 'mdat' liegen) }
      FoundMoov := FindChild(S, 0, S.Size, 'moov', Top);
      if not FoundMoov then Exit;
      MoovEnd := Top.Start + Top.Size;

      { 2) Alle Kinder von 'moov' durchgehen: 'trak' zählen, 'udta' auswerten }
      S.Position := Top.Payload;
      while ReadBox(S, MoovEnd, Child) do
      begin
        if Child.Typ = 'trak' then
        begin
          if IsSoundTrack(S, Child) then Inc(Info.AudioTracks);
        end
        else if Child.Typ = 'udta' then
        begin
          if FindChild(S, Child.Payload, Child.Start + Child.Size, 'stem', StemBox) then
          begin
            SetLength(Raw, StemBox.Start + StemBox.Size - StemBox.Payload);
            S.Position := StemBox.Payload;
            if Length(Raw) > 0 then S.ReadBuffer(Raw[1], Length(Raw));
            { JSON ist evtl. mit Nullbytes aufgefüllt -> abschneiden }
            i := Pos(#0, Raw);
            if i > 0 then SetLength(Raw, i - 1);
            Info.Json := Raw;
            Info.HasStemBox := True;
          end;
        end;
        S.Position := Child.Start + Child.Size;
      end;

      if Info.HasStemBox then ParseStemJson(Info);
      Result := True;
    except
      Result := False;  // defekte Datei: Standardwerte bleiben
    end;
  finally
    S.Free;
  end;
end;

function CheckStemFile(const FileName: string; out Info: TStemInfo;
  out Reason: string): Boolean;
const
  HINT_DE = 'Der StemPlayer spielt nur Traktor-Stem-Dateien (.stem.mp4) ab,' + LineEnding +
            'z.B. die von Elospeed StemMaker erzeugten.';
  HINT_EN = 'StemPlayer only plays Traktor stem files (.stem.mp4),' + LineEnding +
            'e.g. those created by Elospeed StemMaker.';
begin
  Result := False;
  Reason := '';
  if not ReadStemInfo(FileName, Info) then
  begin
    { Kein 'moov'-Block gefunden oder Datei nicht lesbar }
    Reason := 'Das ist keine Stem-Datei (kein MP4-Format).' + LineEnding +
              HINT_DE + LineEnding + LineEnding +
              'This is not a stem file (not in MP4 format).' + LineEnding +
              HINT_EN;
    Exit;
  end;
  if Info.AudioTracks < STEM_COUNT + 1 then
  begin
    { Normales MP4/M4A (1 Spur) oder Video ohne Stems }
    Reason := Format('Das ist keine Stem-Datei: Sie hat %d Audiospur(en), ' +
              'eine Stem-Datei hat %d (Master + %d Stems).',
              [Info.AudioTracks, STEM_COUNT + 1, STEM_COUNT]) + LineEnding +
              HINT_DE + LineEnding + LineEnding +
              Format('This is not a stem file: it has %d audio track(s), ' +
              'a stem file has %d (master + %d stems).',
              [Info.AudioTracks, STEM_COUNT + 1, STEM_COUNT]) + LineEnding +
              HINT_EN;
    Exit;
  end;
  Result := True;
end;

end.
