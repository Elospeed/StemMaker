{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : udownload.pas  (Unit uDownload)
  Version : 1.7
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
  Für Updates (ab 1.7) wird ein ganzes ZIP in einen Ordner entpackt.

  PRÜFSUMMEN (ab 1.7)

  FileSHA256 rechnet die SHA-256-Prüfsumme einer Datei über die in
  Windows eingebaute Krypto-Schnittstelle (bcrypt.dll, ab Windows Vista).
  Free Pascal 3.2 hat selbst kein SHA-256. Stimmt die Prüfsumme nicht mit
  der aus update.json überein, wird die Datei verworfen - so landet weder
  eine kaputte noch eine ausgetauschte Datei im StemMaker-Ordner.
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

{ Kleine Textdatei (z.B. update.json) holen, höchstens 1 MB.
  TimeoutMS gilt für Verbindungsaufbau und jedes Warten auf Daten. }
function HttpGetText(const URL: string; TimeoutMS: Integer; out Text, ErrMsg: string): Boolean;

{ SHA-256 einer Datei als 64 Zeichen hex (klein). '' bei Fehler. }
function FileSHA256(const FileName: string): string;

{ Ganzes ZIP nach DestDir entpacken (DestDir wird angelegt). }
function ExtractZipAll(const ZipFile, DestDir: string; out ErrMsg: string): Boolean;

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
function InternetSetOptionW(hInternet: HINTERNET; dwOption: DWORD;
  lpBuffer: Pointer; dwBufferLength: DWORD): BOOL;
  stdcall; external 'wininet.dll';

const
  INTERNET_OPTION_CONNECT_TIMEOUT = 2;
  INTERNET_OPTION_SEND_TIMEOUT    = 5;
  INTERNET_OPTION_RECEIVE_TIMEOUT = 6;

{ ---------------------------------------------------------------------------
  bcrypt.dll (Windows-Krypto, "CNG") - nur das, was für SHA-256 nötig ist
  --------------------------------------------------------------------------- }
type
  BCRYPT_HANDLE = Pointer;

function BCryptOpenAlgorithmProvider(out phAlgorithm: BCRYPT_HANDLE;
  pszAlgId, pszImplementation: PWideChar; dwFlags: ULONG): LongInt;
  stdcall; external 'bcrypt.dll';
function BCryptCloseAlgorithmProvider(hAlgorithm: BCRYPT_HANDLE; dwFlags: ULONG): LongInt;
  stdcall; external 'bcrypt.dll';
function BCryptCreateHash(hAlgorithm: BCRYPT_HANDLE; out phHash: BCRYPT_HANDLE;
  pbHashObject: Pointer; cbHashObject: ULONG; pbSecret: Pointer; cbSecret: ULONG;
  dwFlags: ULONG): LongInt; stdcall; external 'bcrypt.dll';
function BCryptHashData(hHash: BCRYPT_HANDLE; pbInput: Pointer; cbInput: ULONG;
  dwFlags: ULONG): LongInt; stdcall; external 'bcrypt.dll';
function BCryptFinishHash(hHash: BCRYPT_HANDLE; pbOutput: Pointer; cbOutput: ULONG;
  dwFlags: ULONG): LongInt; stdcall; external 'bcrypt.dll';
function BCryptDestroyHash(hHash: BCRYPT_HANDLE): LongInt; stdcall; external 'bcrypt.dll';

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
  hNet := InternetOpenW('StemMaker/1.7', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
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

{ Kleine Textdatei über WinINet holen - mit Zeitlimit, ohne .part-Datei }
function HttpGetTextWinInet(const URL: string; TimeoutMS: Integer;
  out Text, ErrMsg: string): Boolean;
var
  hNet, hUrl: HINTERNET;
  WURL: UnicodeString;
  Status: Int64;
  Buf: array[0..8191] of Byte;
  Got: DWORD;
  T: DWORD;
  MS: TMemoryStream;
begin
  Result := False;
  Text := '';
  ErrMsg := '';
  hNet := InternetOpenW('StemMaker', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then
  begin
    ErrMsg := _('Internet-Zugriff nicht möglich (WinINet)');
    Exit;
  end;
  MS := TMemoryStream.Create;
  try
    T := TimeoutMS;
    InternetSetOptionW(hNet, INTERNET_OPTION_CONNECT_TIMEOUT, @T, SizeOf(T));
    InternetSetOptionW(hNet, INTERNET_OPTION_SEND_TIMEOUT, @T, SizeOf(T));
    InternetSetOptionW(hNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @T, SizeOf(T));
    WURL := UTF8Decode(URL);
    hUrl := InternetOpenUrlW(hNet, PWideChar(WURL), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE, 0);
    if hUrl = nil then
    begin
      ErrMsg := Format(_('Verbindung fehlgeschlagen (Fehler %d)'), [GetLastError]);
      Exit;
    end;
    try
      if QueryNumber(hUrl, HTTP_QUERY_STATUS_CODE, Status) and (Status <> 200) then
      begin
        ErrMsg := Format(_('Server meldet HTTP %d'), [Status]);
        Exit;
      end;
      repeat
        Got := 0;
        if not InternetReadFile(hUrl, @Buf[0], SizeOf(Buf), Got) then
        begin
          ErrMsg := Format(_('Lesefehler beim Download (Fehler %d)'), [GetLastError]);
          Exit;
        end;
        if Got > 0 then
          MS.WriteBuffer(Buf[0], Got);
        if MS.Size > 1024 * 1024 then
        begin
          ErrMsg := 'zu gross';
          Exit;
        end;
      until Got = 0;
    finally
      InternetCloseHandle(hUrl);
    end;
    SetLength(Text, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Text[1], MS.Size);
    Result := True;
  finally
    MS.Free;
    InternetCloseHandle(hNet);
  end;
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
  HttpGetText - kleine Textdatei holen (update.json)
  --------------------------------------------------------------------------- }
function HttpGetText(const URL: string; TimeoutMS: Integer; out Text, ErrMsg: string): Boolean;
{$IFNDEF WINDOWS}
var
  Tmp: string;
  L: TStringList;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Result := HttpGetTextWinInet(URL, TimeoutMS, Text, ErrMsg);
  {$ELSE}
  { nur zum Testen unter Linux: über curl in eine Temp-Datei }
  Text := '';
  Tmp := GetTempFileName;
  Result := HttpDownloadCurl(URL, Tmp, nil, nil, ErrMsg);
  if Result then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(Tmp);
      Text := L.Text;
    finally
      L.Free;
    end;
    SysUtils.DeleteFile(Tmp);
  end;
  {$ENDIF}
end;

{ ---------------------------------------------------------------------------
  FileSHA256 - Prüfsumme in 1-MB-Stücken rechnen (auch 170-MB-Dateien
  brauchen so kaum Speicher)
  --------------------------------------------------------------------------- }
function FileSHA256(const FileName: string): string;
{$IFDEF WINDOWS}
var
  hAlg, hHash: BCRYPT_HANDLE;
  FS: TFileStream;
  Buf: array of Byte;
  N: Integer;
  Digest: array[0..31] of Byte;
  I: Integer;
  OK: Boolean;
{$ENDIF}
begin
  Result := '';
  {$IFDEF WINDOWS}
  if BCryptOpenAlgorithmProvider(hAlg, 'SHA256', nil, 0) <> 0 then
    Exit;
  try
    if BCryptCreateHash(hAlg, hHash, nil, 0, nil, 0, 0) <> 0 then
      Exit;
    try
      OK := True;
      SetLength(Buf, 1024 * 1024);
      try
        FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
        try
          repeat
            N := FS.Read(Buf[0], Length(Buf));
            if N > 0 then
              OK := OK and (BCryptHashData(hHash, @Buf[0], N, 0) = 0);
          until N <= 0;
        finally
          FS.Free;
        end;
      except
        OK := False;               // Datei nicht lesbar
      end;
      if OK and (BCryptFinishHash(hHash, @Digest[0], SizeOf(Digest), 0) = 0) then
        for I := 0 to High(Digest) do
          Result := Result + LowerCase(IntToHex(Digest[I], 2));
    finally
      BCryptDestroyHash(hHash);
    end;
  finally
    BCryptCloseAlgorithmProvider(hAlg, 0);
  end;
  {$ENDIF}
end;

{ ---------------------------------------------------------------------------
  ExtractZipAll - ganzes ZIP entpacken (für Updates)
  --------------------------------------------------------------------------- }
function ExtractZipAll(const ZipFile, DestDir: string; out ErrMsg: string): Boolean;
var
  UZ: TUnZipper;
begin
  Result := False;
  ErrMsg := '';
  UZ := TUnZipper.Create;
  try
    try
      ForceDirectories(DestDir);
      UZ.FileName := ZipFile;
      UZ.OutputPath := DestDir;
      UZ.UnZipAllFiles;
      Result := True;
    except
      on E: Exception do
        ErrMsg := Format(_('ZIP-Fehler: %s'), [E.Message]);
    end;
  finally
    UZ.Free;
  end;
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
