; Inno-Setup-Skript für StemMaker (Setup-Exe neben dem ZIP).
;
; Warum ein Installer zusätzlich zum ZIP:
; - Startmenü-Eintrag und Eintrag unter "Apps & Features" (Deinstallieren).
; - winget kann das Setup als Typ "inno" installieren und aktualisieren. Dabei
;   bleiben Modelle, ffmpeg, Einstellungen und Logs erhalten. Beim ZIP-Paket
;   löscht winget bei jedem Upgrade den ganzen Ordner.
;
; Installiert wird NUR für den aktuellen Benutzer, ohne Administratorrechte, nach
;   %LOCALAPPDATA%\Programs\StemMaker
; StemMaker schreibt in seinen eigenen Ordner (models\, logs\, StemMaker.ini,
; tools\ffmpeg.exe, Warteschlange) und aktualisiert sich dort auch selbst. Unter
; "C:\Program Files" ginge das ohne Adminrechte nicht. Deshalb gibt es bewusst
; keine Auswahl "für alle Benutzer".
;
; Übersetzen (Inno Setup 6):
;   ISCC.exe /DAppVersion=1.7 /DSourceDir=C:\pfad\StemMaker installer\StemMaker.iss
; SourceDir = entpackter Inhalt des Release-ZIPs (der Ordner mit StemMaker.exe).
; Das fertige Setup landet in installer\Output\StemMaker-<Version>-Setup.exe.
; Der GitHub-Build (.github/workflows/build.yml) macht das automatisch.

#ifndef AppVersion
  #error "AppVersion fehlt, z. B. ISCC /DAppVersion=1.7 ..."
#endif
; Dateiname des fertigen Setups (ohne .exe); der Test-Build setzt einen eigenen
#ifndef OutputName
  #define OutputName "StemMaker-" + AppVersion + "-Setup"
#endif
; Versionsnummer in den Datei-Eigenschaften der Setup-Exe, nur Ziffern und Punkte
#ifndef VersionNum
  #define VersionNum AppVersion
#endif
#ifndef SourceDir
  #error "SourceDir fehlt, z. B. ISCC /DSourceDir=C:\pfad\StemMaker ..."
#endif

[Setup]
; Feste ID der App. NIE ändern: Windows und winget erkennen daran eine bestehende
; Installation (Registry-Schlüssel ...\Uninstall\{B0A07F78-...}_is1).
AppId={{B0A07F78-C1C4-4721-8EBD-C7CEC8A2258E}
AppName=StemMaker
AppVersion={#AppVersion}
AppVerName=StemMaker {#AppVersion}
AppPublisher=Elospeed
AppPublisherURL=https://github.com/Elospeed/StemMaker
AppSupportURL=https://github.com/Elospeed/StemMaker/issues
AppUpdatesURL=https://github.com/Elospeed/StemMaker/releases
VersionInfoVersion={#VersionNum}
; nur für den aktuellen Benutzer, ohne UAC-Abfrage; {autopf} = %LOCALAPPDATA%\Programs
PrivilegesRequired=lowest
DefaultDirName={autopf}\StemMaker
DisableProgramGroupPage=yes
DisableDirPage=auto
; StemMaker ist eine reine 64-Bit-Anwendung
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename={#OutputName}
SetupIconFile=..\src\StemMaker.ico
UninstallDisplayIcon={app}\StemMaker.exe
UninstallDisplayName=StemMaker
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Läuft StemMaker oder der StemPlayer noch, schliesst das Setup sie vorher (bei
; stiller Installation, z. B. "winget upgrade", ohne Nachfrage). Kein AppMutex:
; der würde eine stille Installation abbrechen, solange StemMaker offen ist.
CloseApplications=yes
RestartApplications=no
; Sprache des Setups nach der Windows-Sprache, ohne Nachfrage. Passt keine,
; nimmt Inno die erste Sprache der Liste, deshalb steht Englisch oben.
ShowLanguageDialog=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
de.StartPlayer=StemPlayer (Stem-Dateien anhören)
en.StartPlayer=StemPlayer (listen to stem files)
de.AskDeleteData=Sollen auch die heruntergeladenen Modelle, ffmpeg, die Einstellungen und die Logs gelöscht werden?%n%nBei „Nein“ bleiben sie im Ordner%n%1%nund werden bei einer späteren Installation wieder benutzt.
en.AskDeleteData=Also delete the downloaded models, ffmpeg, the settings and the logs?%n%nIf you choose "No", they stay in the folder%n%1%nand are used again by a later installation.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Alles aus dem Release-Ordner, ausser Quelltext und Entwickler-Werkzeugen
; (die stehen im ZIP und auf GitHub). Benutzerdateien (StemMaker.ini, models\*.bin,
; tools\ffmpeg.exe, logs\) sind im Release nicht enthalten und werden deshalb
; bei einem Update nie überschrieben.
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
  Excludes: "\src,\demucs-build,\art,\lang-tools,*.old,\_update_tmp"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\StemMaker"; Filename: "{app}\StemMaker.exe"
Name: "{autoprograms}\{cm:StartPlayer}"; Filename: "{app}\AddOns\StemPlayer.exe"
Name: "{autodesktop}\StemMaker"; Filename: "{app}\StemMaker.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\StemMaker.exe"; Description: "{cm:LaunchProgram,StemMaker}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Reste der eingebauten Update-Funktion (alte Exes, abgebrochenes Update)
Type: files; Name: "{app}\*.old"
Type: files; Name: "{app}\AddOns\*.old"
Type: filesandordirs; Name: "{app}\_update_tmp"

[Code]
{ Beim Deinstallieren: Die grossen Downloads (Modelle, ffmpeg) und die Einstellungen
  hat StemMaker selbst angelegt, nicht das Setup. Ohne Nachfrage bleiben sie liegen.
  Wer von Hand deinstalliert, wird gefragt. Bei einer stillen Deinstallation
  (z. B. "winget uninstall") wird nichts gefragt und nichts davon gelöscht.
  Gelöscht werden nur diese bekannten Dateien und Ordner, nie der ganze Ordner:
  Hat jemand als Ziel einen Ordner mit eigenen Dateien gewählt, bleiben die heil. }
procedure DeleteUserData(const AppDir: String);
begin
  DelTree(AppDir + '\models', True, True, True);
  DelTree(AppDir + '\logs', True, True, True);
  DeleteFile(AppDir + '\tools\ffmpeg.exe');
  DeleteFile(AppDir + '\StemMaker.ini');
  DeleteFile(AppDir + '\AddOns\StemPlayer.ini');
  DeleteFile(AppDir + '\StemMaker_queue.txt');
  { leere Ordner wegräumen, volle bleiben stehen }
  RemoveDir(AppDir + '\tools');
  RemoveDir(AppDir + '\AddOns');
  RemoveDir(AppDir);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir: String;
begin
  if (CurUninstallStep = usPostUninstall) and not UninstallSilent then
  begin
    AppDir := ExpandConstant('{app}');
    if not DirExists(AppDir) then
      Exit;
    if MsgBox(FmtMessage(CustomMessage('AskDeleteData'), [AppDir]),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DeleteUserData(AppDir);
  end;
end;
