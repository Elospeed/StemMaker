{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udownload.pas  (Unit uDownload)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  Beim ersten Start fehlen noch ffmpeg und das Trenn-Modell. Die lädt
  StemMaker selbst aus dem Internet - ohne Setup-Skript, ohne zusätzliche
  Programme und ohne DLLs.

  WIE WIRD HERUNTERGELADEN?

  - Windows: über WinINet. Das ist die Internet-Schnittstelle, die in jedem
    Windows eingebaut ist. Vorteile:
      * HTTPS funktioniert ohne OpenSSL-DLLs
      * Weiterleitungen werden automatisch verfolgt (GitHub und
        Hugging Face leiten auf ihre Download-Server um)
      * die Proxy-Einstellungen von Windows werden übernommen
  - Falls WinINet scheitert, wird als Notlösung curl.exe versucht
    (ist bei Windows 10/11 dabei).
  - Linux (nur zum Testen): curl.

  Die Datei wird zuerst als "<Name>.part" gespeichert und erst nach
  erfolgreichem Download umbenannt. So bleibt nach einem Abbruch nie eine
  halbe Datei unter dem richtigen Namen liegen.

  ENTPACKEN

  ffmpeg gibt es nur als ZIP-Archiv. Mit der Pascal-Unit 'zipper' (gehört
  zu Free Pascal) holen wir daraus nur die eine Datei ffmpeg.exe heraus.
  ============================================================================ }
unit uDownload;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, zipper, LazFileUtils, FileUtil, UTF8Process, Process;

type
  { Fortschritt: Done = bisher geladene Bytes,
                 Total = Gesamtgröße (-1 wenn der Server sie nicht nennt) }
  TDlProgressEvent = procedure(Done, Total: Int64) of object;
  { wird regelmäßig gefragt: "soll abgebrochen werden?" }
  TDlCancelQuery = function: Boolean of object;

{ Lädt URL herunter und speichert sie als DestFile.
  Rückgabe False = Fehler oder Abbruch, der Grund steht in ErrMsg. }
function HttpDownload(const URL, DestFile: string; OnProgress: TDlProgressEvent;
  IsCancelled: TDlCancelQuery; out ErrMsg: string): Boolean;

{ Holt aus einem ZIP die erste Datei mit dem Namen EntryFileName heraus
  (egal in welchem Unterordner des ZIPs) und speichert sie als DestFile. }
function ExtractSingleFromZip(const ZipFile, EntryFileName, DestFile: string;
  out ErrMsg: string): Boolean;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} uLang;

{$IFDEF WINDOWS}

{ ---------------------------------------------------------------------------
  WinINet - die Funktionen deklarieren wir selbst direkt aus wininet.dll.
  So brauchen wir keine zusätzliche Unit und wissen genau, was aufgerufen
  wird. Die "W"-Varianten arbeiten mit Unicode.
  --------------------------------------------------------------------------- }
const
  INTERNET_OPEN_TYPE_PRECONFIG   = 0;          // Proxy wie in Windows eingestellt
  INTERNET_FLAG_RELOAD           = $80000000;  // immer frisch vom Server laden
  INTERNET_FLAG_NO_CACHE_WRITE   = $04000000;  // nicht im IE-Cache ablegen
  INTERNET_FLAG_KEEP_CONNECTION  = $00400000;
  HTTP_QUERY_CONTENT_LENGTH      = 5;          // Frage: wie groß ist die Datei?
  HTTP_QUERY_STATUS_CODE         = 19;         // Frage: HTTP-Status (200 = OK)
  HTTP_QUERY_FLAG_NUMBER         = $20000000;  // Antwort als Zahl statt Text

type
  HINTERNET = Pointer;

function InternetOpenW(lpszAgent: PWideChar; dwAccessType: DWORD;
  lpszProxy, lpszProxyBypass: PWideChar; dwFlags: DWORD): HINTERNET;
  stdcall; external 'wininet.dll';
function InternetOpenUrlW(hInternet: HINTERNET; lpszUrl, lpszHeaders: PWideChar;
  dwHeadersLength, dwFlags: DWORD; dwContext: PtrUInt): HINTERNET;
  stdcall; external 'wininet.dll';
function InternetReadFile(hFile: HINTERNET; lpBuffer: Pointer;
  dwNumberOfBytesToRead: DWORD; var lpdwNumberOfBytesRead: DWORD): BOOL;
  stdcall; external 'wininet.dll';
function InternetCloseHandle(hInternet: HINTERNET): BOOL;
  stdcall; external 'wininet.dll';
function HttpQueryInfoW(hRequest: HINTERNET; dwInfoLevel: DWORD; lpBuffer: Pointer;
  var lpdwBufferLength: DWORD; var lpdwIndex: DWORD): BOOL;
  stdcall; external 'wininet.dll';

{ Fragt eine Zahl aus der Server-Antwort ab (Status-Code, Dateigröße) }
function QueryNumber(hReq: HINTERNET; Level: DWORD; out Value: Int64): Boolean;
var
  V: DWORD;
  Len, Idx: DWORD;
begin
  V := 0;
  Len := SizeOf(V);
  Idx := 0;
  Result := HttpQueryInfoW(hReq, Level or HTTP_QUERY_FLAG_NUMBER, @V, Len, Idx);
  Value := V;
end;

{ ---------------------------------------------------------------------------
  Download über WinINet

  1. Internet-Sitzung öffnen
  2. URL öffnen (Weiterleitungen macht Windows selbst)
  3. Status prüfen (muss 200 = OK sein) und Größe abfragen
  4. in 64-KB-Stücken lesen und in die .part-Datei schreiben,
     dabei alle 150 ms den Fortschritt melden und auf Abbruch prüfen
  5. Größe kontrollieren, .part in den richtigen Namen umbenennen
  --------------------------------------------------------------------------- }
function HttpDownloadWinInet(const URL, DestFile: string; OnProgress: TDlProgressEvent;
  IsCancelled: TDlCancelQuery; out ErrMsg: string): Boolean;
var
  hNet, hUrl: HINTERNET;
  WURL: UnicodeString;
  Status, Total, Done: Int64;
  Buf: array[0..65535] of Byte;
  Got: DWORD;
  FS: TFileStream;
  PartFile: string;
  LastReport: QWord;
begin
  Result := False;
  ErrMsg := '';
  PartFile := DestFile + '.part';

  { 1. Sitzung öffnen }
  hNet := InternetOpenW('StemMaker/1.6', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then
  begin
    ErrMsg := _('Internet-Zugriff nicht möglich (WinINet)');
    Exit;
  end;
  try
    { 2. URL öffnen }
    WURL := UTF8Decode(URL);
    hUrl := InternetOpenUrlW(hNet, PWideChar(WURL), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or
      INTERNET_FLAG_KEEP_CONNECTION, 0);
    if hUrl = nil then
    begin
      ErrMsg := Format(_('Verbindung fehlgeschlagen (Fehler %d)'), [GetLastError]);
      Exit;
    end;
    try
      { 3. Status und Größe }
      if QueryNumber(hUrl, HTTP_QUERY_STATUS_CODE, Status) and (Status <> 200) then
      begin
        ErrMsg := Format(_('Server meldet HTTP %d'), [Status]);
        Exit;
      end;
      if not QueryNumber(hUrl, HTTP_QUERY_CONTENT_LENGTH, Total) then
        Total := -1;               // Größe unbekannt -> Balken ohne Prozent

      { 4. Daten lesen und speichern }
      FS := TFileStream.Create(PartFile, fmCreate);
      try
        Done := 0;
        LastReport := 0;
        repeat
          if Assigned(IsCancelled) and IsCancelled() then
          begin
            ErrMsg := _('Abgebrochen');
            Exit;
          end;
          Got := 0;
          if not InternetReadFile(hUrl, @Buf[0], SizeOf(Buf), Got) then
          begin
            ErrMsg := Format(_('Lesefehler beim Download (Fehler %d)'), [GetLastError]);
            Exit;
          end;
          if Got > 0 then
          begin
            FS.WriteBuffer(Buf[0], Got);
            Inc(Done, Got);
            { Fortschritt nicht bei jedem Stück melden, sondern max. alle
              150 ms - sonst bremst die Anzeige den Download }
            if Assigned(OnProgress) and (GetTickCount64 - LastReport > 150) then
            begin
              OnProgress(Done, Total);
              LastReport := GetTickCount64;
            end;
          end;
        until Got = 0;             // 0 Bytes gelesen = Datei ist komplett
        if Assigned(OnProgress) then
          OnProgress(Done, Total);
      finally
        FS.Free;
      end;

      { 5. Kontrolle: haben wir so viel bekommen, wie angekündigt? }
      if (Total > 0) and (Done <> Total) then
      begin
        ErrMsg := _('Download unvollständig');
        Exit;
      end;
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
    { bei Fehler/Abbruch die halbe Datei wegräumen }
    if (ErrMsg <> '') and FileExists(PartFile) then
      SysUtils.DeleteFile(PartFile);
  end;

  { alles gut: .part -> richtiger Name }
  if FileExists(DestFile) then
    SysUtils.DeleteFile(DestFile);
  Result := RenameFile(PartFile, DestFile);
  if not Result then
    ErrMsg := Format(_('Datei kann nicht gespeichert werden: %s'), [DestFile]);
end;

{$ENDIF}

{ ---------------------------------------------------------------------------
  Download mit curl (Notlösung unter Windows, Standard unter Linux)

  curl läuft als eigenes Programm. Die Gesamtgröße kennen wir dabei nicht,
  deshalb melden wir als Fortschritt einfach, wie groß die Datei schon ist.
  --------------------------------------------------------------------------- }
function HttpDownloadCurl(const URL, DestFile: string; OnProgress: TDlProgressEvent;
  IsCancelled: TDlCancelQuery; out ErrMsg: string): Boolean;
var
  P: TProcessUTF8;
  PartFile: string;
begin
  Result := False;
  ErrMsg := '';
  PartFile := DestFile + '.part';
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := FindDefaultExecutablePath('curl');   // curl im PATH suchen
    if P.Executable = '' then
    begin
      ErrMsg := _('curl nicht gefunden');
      Exit;
    end;
    { -L = Weiterleitungen folgen, --fail = bei HTTP-Fehler abbrechen,
      -s -S = still, aber Fehler anzeigen, -o = Zieldatei }
    P.Parameters.AddStrings(['-L', '--fail', '-s', '-S', '-o', PartFile, URL]);
    P.Options := [poNoConsole];
    P.Execute;
    while P.Running do
    begin
      if Assigned(IsCancelled) and IsCancelled() then
      begin
        P.Terminate(1);
        ErrMsg := _('Abgebrochen');
        Break;
      end;
      if Assigned(OnProgress) and FileExists(PartFile) then
        OnProgress(FileSize(PartFile), -1);
      Sleep(150);
    end;
    if (ErrMsg = '') and (P.ExitStatus <> 0) then
      ErrMsg := Format(_('Download fehlgeschlagen (curl %d)'), [P.ExitStatus]);
  finally
    P.Free;
  end;
  if ErrMsg <> '' then
  begin
    if FileExists(PartFile) then SysUtils.DeleteFile(PartFile);
    Exit;
  end;
  if FileExists(DestFile) then SysUtils.DeleteFile(DestFile);
  Result := RenameFile(PartFile, DestFile);
  if not Result then
    ErrMsg := Format(_('Datei kann nicht gespeichert werden: %s'), [DestFile]);
end;

{ ---------------------------------------------------------------------------
  HttpDownload - die Funktion, die von außen aufgerufen wird.
  Unter Windows zuerst WinINet, bei Fehler curl als zweiter Versuch.
  --------------------------------------------------------------------------- }
function HttpDownload(const URL, DestFile: string; OnProgress: TDlProgressEvent;
  IsCancelled: TDlCancelQuery; out ErrMsg: string): Boolean;
{$IFDEF WINDOWS}
var
  Err2: string;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Result := HttpDownloadWinInet(URL, DestFile, OnProgress, IsCancelled, ErrMsg);
  { Abbruch über die Abfrage erkennen, nicht über den (übersetzten) Text }
  if Result or (Assigned(IsCancelled) and IsCancelled()) then
    Exit;
  { zweiter Versuch mit curl.exe }
  Result := HttpDownloadCurl(URL, DestFile, OnProgress, IsCancelled, Err2);
  if Result then
    ErrMsg := ''
  else
    ErrMsg := ErrMsg + ' / ' + Err2;   // beide Fehlermeldungen anzeigen
  {$ELSE}
  Result := HttpDownloadCurl(URL, DestFile, OnProgress, IsCancelled, ErrMsg);
  {$ENDIF}
end;

{ ---------------------------------------------------------------------------
  ExtractSingleFromZip - eine einzelne Datei aus einem ZIP holen

  1. Inhaltsverzeichnis des ZIPs lesen (Examine)
  2. den Eintrag suchen, dessen Dateiname passt
     (im ffmpeg-ZIP liegt ffmpeg.exe z.B. in "ffmpeg-...-lgpl/bin/")
  3. nur diesen Eintrag in einen Hilfsordner entpacken
  4. an den Zielort verschieben, Hilfsordner löschen
  --------------------------------------------------------------------------- }
function ExtractSingleFromZip(const ZipFile, EntryFileName, DestFile: string;
  out ErrMsg: string): Boolean;
var
  UZ: TUnZipper;
  I: Integer;
  Entry, TmpDir, Extracted: string;
  L: TStringList;
begin
  Result := False;
  ErrMsg := '';
  TmpDir := ExtractFilePath(DestFile) + '_unzip_tmp' + PathDelim;
  UZ := TUnZipper.Create;
  L := TStringList.Create;
  try
    try
      { 1. Inhaltsverzeichnis }
      UZ.FileName := ZipFile;
      UZ.Examine;
      { 2. passenden Eintrag suchen (ZIPs nutzen immer '/' als Trenner) }
      Entry := '';
      for I := 0 to UZ.Entries.Count - 1 do
        if SameText(ExtractFileName(StringReplace(UZ.Entries[I].ArchiveFileName,
             '/', PathDelim, [rfReplaceAll])), EntryFileName) then
        begin
          Entry := UZ.Entries[I].ArchiveFileName;
          Break;
        end;
      if Entry = '' then
      begin
        ErrMsg := Format(_('%s nicht im ZIP gefunden'), [EntryFileName]);
        Exit;
      end;
      { 3. nur diesen einen Eintrag entpacken }
      ForceDirectories(TmpDir);
      UZ.OutputPath := TmpDir;
      L.Add(Entry);
      UZ.UnZipFiles(L);
      Extracted := TmpDir + StringReplace(Entry, '/', PathDelim, [rfReplaceAll]);
      if not FileExists(Extracted) then
      begin
        ErrMsg := _('Entpacken fehlgeschlagen');
        Exit;
      end;
      { 4. an den Zielort }
      if FileExists(DestFile) then
        SysUtils.DeleteFile(DestFile);
      if not RenameFile(Extracted, DestFile) then
        if not FileUtil.CopyFile(Extracted, DestFile) then
        begin
          ErrMsg := Format(_('Kann %s nicht schreiben'), [DestFile]);
          Exit;
        end;
      Result := True;
    except
      on E: Exception do
        ErrMsg := Format(_('ZIP-Fehler: %s'), [E.Message]);
    end;
  finally
    L.Free;
    UZ.Free;
    if DirectoryExists(TmpDir) then
      DeleteDirectory(ExcludeTrailingPathDelimiter(TmpDir), False);
  end;
end;

end.
