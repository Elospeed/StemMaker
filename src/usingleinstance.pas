{ ============================================================================
  StemMaker  -  Traktor-Stem-Dateien aus MP3 erstellen
  ----------------------------------------------------------------------------
  Autor   : Elospeed
  Datei   : usingleinstance.pas  (Unit uSingleInstance)
  Version : 1.6
  ----------------------------------------------------------------------------
  WORUM GEHT ES HIER?

  StemMaker darf nur EINMAL gleichzeitig laufen. Zwei StemMaker teilen sich
  nämlich (wenn sie im selben Ordner liegen) dieselben Dateien:

    - StemMaker_queue.txt   Die Warteschlange. Der zweite StemMaker liest
                            beim Start die Liste des ersten ein (inkl. der
                            Datei, die gerade läuft) und beide überschreiben
                            sie danach ständig gegenseitig.
    - StemMaker.ini         Einstellungen, gelerntes Tempo, gesicherter
                            Energiesparplan. Der zweite Start hält den vom
                            ersten umgestellten Energiesparplan für einen
                            "Absturz-Rest" und stellt ihn mitten in der
                            Arbeit des ersten zurück.
    - logs\                 Der zweite Start hält das laufende Log des
                            ersten für ein abgestürztes und hängt einen
                            Absturz-Vermerk an.
    - *.stem.mp4            Der Name der fertigen Datei hängt nicht vom
                            Modell ab - beide würden dieselbe Datei
                            schreiben (oder der zweite überspringt sie).

  Dazu kommt: demucs nutzt schon bei einem Lauf alle Kerne und viel RAM.
  Zwei Läufe gleichzeitig sind nicht schneller, nur doppelt so voll.

  WIE FUNKTIONIERT DIE SPERRE?
  Beim Start legen wir bei Windows einen "Mutex" mit festem Namen an (ein
  benanntes Sperr-Objekt, das es pro Windows-Anmeldung nur einmal gibt).
  Meldet Windows "gibt es schon", läuft bereits ein StemMaker. Dann:
    1. Hinweis anzeigen (Deutsch/Englisch über lang\)
    2. das Fenster des laufenden StemMaker nach vorne holen
    3. dieser zweite Start beendet sich sofort wieder

  Den Mutex müssen wir nie selbst freigeben: Windows räumt ihn auf, sobald
  das Programm endet - auch nach einem Absturz oder über den Task-Manager.
  Eine "hängengebliebene" Sperre kann es also nicht geben.

  Die Sperre gilt für StemMaker.exe, nicht für StemCLI.exe und nicht für
  den StemPlayer.
  ============================================================================ }
unit uSingleInstance;

{$mode objfpc}{$H+}

interface

{ True  = wir sind der einzige StemMaker -> normal weiterstarten.
  False = es läuft schon einer. Der Hinweis wurde schon angezeigt und das
          andere Fenster nach vorne geholt -> Programm sofort beenden.
  Aufruf ganz am Anfang (nach Application.Initialize, vor allem anderen),
  damit der zweite Start nichts an Log, INI oder Warteschlange anfasst. }
function SingleInstanceCheck(const IniName: string): Boolean;

implementation

uses
  SysUtils, IniFiles, Forms, Dialogs, uLang {$IFDEF WINDOWS}, Windows{$ENDIF};

{$IFDEF WINDOWS}
const
  { "Local\" = gilt pro Windows-Anmeldung. Meldet sich am selben PC ein
    zweiter Benutzer an, darf der seinen eigenen StemMaker starten. }
  MUTEX_NAME = 'Local\Elospeed.StemMaker.EinzigeInstanz';
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  TQueryFullProcessImageNameW = function(hProcess: THandle; dwFlags: DWORD;
    lpExeName: PWideChar; var lpdwSize: DWORD): BOOL; stdcall;

var
  GMutex: THandle = 0;        // bleibt offen, solange das Programm läuft

  { Ergebnis der Fenstersuche (EnumWindows ruft eine Funktion pro Fenster
    auf, darum über globale Variablen) }
  GFoundWnd  : HWND = 0;      // bestes Fenster zum Nach-vorne-Holen
  GIconicWnd : HWND = 0;      // minimiertes Fenster (Taskleiste), falls vorhanden
  GExeName   : string = '';   // z.B. 'stemmaker.exe' (klein geschrieben)

{ Dateiname der Exe eines anderen Prozesses (nur der Name, klein), '' bei
  Fehler. QueryFullProcessImageNameW gibt es ab Vista - dynamisch geladen,
  damit es auf exotischen Systemen keinen Startfehler gibt. }
function ProcessExeName(Pid: DWORD): string;
var
  QueryName: TQueryFullProcessImageNameW;
  H: THandle;
  Buf: array[0..MAX_PATH] of WideChar;
  Len: DWORD;
  W: WideString;
begin
  Result := '';
  Pointer(QueryName) := GetProcAddress(GetModuleHandle('kernel32.dll'),
    'QueryFullProcessImageNameW');
  if not Assigned(QueryName) then Exit;
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if H = 0 then Exit;
  try
    Len := Length(Buf);
    if QueryName(H, 0, @Buf[0], Len) then
    begin
      SetString(W, PWideChar(@Buf[0]), Len);
      Result := LowerCase(ExtractFileName(UTF8Encode(W)));
    end;
  finally
    CloseHandle(H);
  end;
end;

{ wird von EnumWindows für jedes Hauptfenster auf dem Bildschirm aufgerufen }
function EnumProc(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var
  Pid: DWORD;
  R: TRect;
begin
  Result := True;                                  // weitersuchen
  Pid := 0;
  GetWindowThreadProcessId(Wnd, @Pid);
  if (Pid = 0) or (Pid = GetCurrentProcessId) then Exit;
  if not IsWindowVisible(Wnd) then Exit;
  if ProcessExeName(Pid) <> GExeName then Exit;

  { Ein Programm aus Lazarus hat neben dem Hauptfenster noch ein
    unsichtbares "Anwendungsfenster" (Grösse 0, Eintrag in der Taskleiste).
    Ist StemMaker minimiert, muss man dieses wiederherstellen. }
  if IsIconic(Wnd) and (GIconicWnd = 0) then
    GIconicWnd := Wnd;

  { Zum Nach-vorne-Holen nehmen wir ein richtiges Fenster (mit Grösse).
    Ist gerade ein Dialog offen (z.B. die Startprüfung), ist nur dieser
    "enabled" - dann nehmen wir den, sonst klickt man ins Leere. }
  GetWindowRect(Wnd, R);
  if (R.Right - R.Left <= 0) or (R.Bottom - R.Top <= 0) then Exit;
  if (GFoundWnd = 0) or (IsWindowEnabled(Wnd) and not IsWindowEnabled(GFoundWnd)) then
    GFoundWnd := Wnd;
end;

{ das Fenster des laufenden StemMaker suchen und nach vorne holen }
procedure BringOtherInstanceToFront;
begin
  GFoundWnd := 0;
  GIconicWnd := 0;
  GExeName := LowerCase(ExtractFileName(ParamStr(0)));
  EnumWindows(@EnumProc, 0);
  if GIconicWnd <> 0 then
    ShowWindow(GIconicWnd, SW_RESTORE);            // aus der Taskleiste holen
  if (GFoundWnd <> 0) and IsIconic(GFoundWnd) then
    ShowWindow(GFoundWnd, SW_RESTORE);
  { Wir sind gerade vom Benutzer gestartet worden und dürfen deshalb ein
    anderes Fenster in den Vordergrund holen (Windows erlaubt das nur dem
    Programm, das gerade "vorne" ist). }
  if GFoundWnd <> 0 then
    SetForegroundWindow(GFoundWnd)
  else if GIconicWnd <> 0 then
    SetForegroundWindow(GIconicWnd);
end;
{$ENDIF}

{ Sprache für den Hinweis aus der INI laden - OHNE das Auswahlfenster vom
  ersten Start (das hat der laufende StemMaker längst erledigt). }
procedure LoadLanguageQuiet(const IniName: string);
var
  Ini: TIniFile;
  Code: string;
begin
  Code := '';
  try
    Ini := TIniFile.Create(IniName);
    try
      Code := Ini.ReadString('Main', 'Language', '');
    finally
      Ini.Free;
    end;
  except
    Code := '';
  end;
  if Code = '' then
    Code := LangSystemDefault;
  if not LangLoad(Code) then
    LangLoad('de');
end;

function SingleInstanceCheck(const IniName: string): Boolean;
begin
  Result := True;
  {$IFDEF WINDOWS}
  GMutex := CreateMutexW(nil, False, PWideChar(WideString(MUTEX_NAME)));
  if GMutex = 0 then
    Exit;            // Sperre geht nicht (sehr selten) -> lieber normal starten
  if GetLastError <> ERROR_ALREADY_EXISTS then
    Exit;            // wir sind der Erste

  { es läuft schon ein StemMaker }
  Result := False;
  CloseHandle(GMutex);
  GMutex := 0;
  LoadLanguageQuiet(IniName);
  MessageDlg(_('StemMaker läuft schon'),
    _('StemMaker ist bereits geöffnet. Es kann immer nur ein StemMaker ' +
      'gleichzeitig laufen, weil sich zwei die Warteschlange, die ' +
      'Einstellungen und die fertigen Dateien teilen würden.') + LineEnding +
      LineEnding +
    _('Das offene Fenster wird jetzt nach vorne geholt. Weitere Dateien ' +
      'einfach dort zur Liste hinzufügen.'),
    mtInformation, [mbOK], 0);
  BringOtherInstanceToFront;
  {$ENDIF}
end;

end.
