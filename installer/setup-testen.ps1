# Prüft die Setup-Exe auf dem Windows-Rechner von GitHub, so wie winget sie benutzt:
# still installieren, Benutzerdaten anlegen, still drüberinstallieren (= Update),
# still deinstallieren. Benutzerdaten (Modelle, Einstellungen) müssen dabei bleiben.
#
#   pwsh installer/setup-testen.ps1 installer/Output/StemMaker-Setup-Test.exe

param([Parameter(Mandatory)] [string] $Setup)
$ErrorActionPreference = 'Stop'

$App = Join-Path $env:LOCALAPPDATA 'Programs\StemMaker'
$Menue = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\StemMaker.lnk'

function Fehler([string] $Text) { Write-Host "::error::$Text"; exit 1 }

function Installieren([string] $Log) {
  $p = Start-Process -FilePath $Setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$Log" -Wait -PassThru
  if ($p.ExitCode -ne 0) { Get-Content $Log -Tail 30; Fehler "Setup endete mit Code $($p.ExitCode)" }
}

# 1. Erstinstallation
Installieren "$env:RUNNER_TEMP\setup1.log"
foreach ($f in 'StemMaker.exe', 'AddOns\StemPlayer.exe', 'AddOns\StemCLI.exe', 'tools\demucs_mt.cpp.main.exe', 'lang\en.po', 'unins000.exe') {
  if (-not (Test-Path (Join-Path $App $f))) { Fehler "nach der Installation fehlt $f" }
}
if (Test-Path (Join-Path $App 'src')) { Fehler 'Quelltext-Ordner src wurde mitinstalliert' }
if (-not (Test-Path $Menue)) { Fehler 'Startmenü-Eintrag fehlt' }
Write-Host "Installiert nach $App, Startmenü-Eintrag vorhanden"

# 2. so tun, als hätte StemMaker Modelle, ffmpeg und Einstellungen angelegt
Set-Content (Join-Path $App 'models\test-modell.bin') 'Modell'
Set-Content (Join-Path $App 'tools\ffmpeg.exe') 'ffmpeg'
Set-Content (Join-Path $App 'StemMaker.ini') "[Test]`r`nWert=1"

# 3. Update = dasselbe Setup noch einmal still drüber
Installieren "$env:RUNNER_TEMP\setup2.log"
foreach ($f in 'models\test-modell.bin', 'tools\ffmpeg.exe', 'StemMaker.ini') {
  if (-not (Test-Path (Join-Path $App $f))) { Fehler "Update hat $f gelöscht" }
}
Write-Host 'Update: Modelle, ffmpeg und Einstellungen sind erhalten'

# 4. still deinstallieren (so macht es "winget uninstall")
$p = Start-Process -FilePath (Join-Path $App 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
if ($p.ExitCode -ne 0) { Fehler "Deinstallation endete mit Code $($p.ExitCode)" }
# Der Deinstaller arbeitet aus einer Kopie im Temp-Ordner weiter: kurz warten
for ($i = 0; $i -lt 60 -and (Test-Path (Join-Path $App 'StemMaker.exe')); $i++) { Start-Sleep -Seconds 1 }
if (Test-Path (Join-Path $App 'StemMaker.exe')) { Fehler 'StemMaker.exe ist nach der Deinstallation noch da' }
if (Test-Path $Menue) { Fehler 'Startmenü-Eintrag ist nach der Deinstallation noch da' }
if (-not (Test-Path (Join-Path $App 'models\test-modell.bin'))) { Fehler 'stille Deinstallation hat die Modelle gelöscht' }
Write-Host 'Deinstallation: Programm weg, Modelle bleiben (stille Deinstallation fragt nicht)'
Write-Host 'Setup-Test bestanden'
