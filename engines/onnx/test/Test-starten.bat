@echo off
rem StemOnnx-Test: eine MP3 (oder WAV, FLAC ...) auf diese Datei ziehen.
rem Trennt den Song zweimal: 1. automatisch (Grafikkarte, wenn sie richtig und
rem schneller rechnet), 2. nur mit der CPU. Die Zeiten stehen danach in
rem ergebnis.txt, die Stems in stems-auto und stems-cpu.
rem
rem Braucht das Modell von StemMaker (models\ggml-model-htdemucs-4s-f16.bin)
rem und ffmpeg.exe (StemMaker\tools). Beides wird im installierten StemMaker
rem gesucht oder kann hier in den Ordner kopiert werden.
setlocal
chcp 65001 >nul
cd /d "%~dp0"
if "%~1"=="" (
  echo Bitte eine Musikdatei auf Test-starten.bat ziehen.
  pause
  exit /b 1
)

rem StemMaker-Ordner suchen (Installation pro Benutzer, für alle, oder daneben)
set "SM="
for %%D in ("%LOCALAPPDATA%\Programs\StemMaker" "%ProgramFiles%\StemMaker" "%~dp0..\StemMaker") do (
  if not defined SM if exist "%%~D\StemMaker.exe" set "SM=%%~D"
)

set "FF="
if exist "ffmpeg.exe" set "FF=%~dp0ffmpeg.exe"
if not defined FF if defined SM if exist "%SM%\tools\ffmpeg.exe" set "FF=%SM%\tools\ffmpeg.exe"
if not defined FF (
  echo FEHLER: ffmpeg.exe nicht gefunden. Bitte aus StemMaker\tools hierher kopieren.
  pause
  exit /b 1
)

set "MODELL="
if exist "ggml-model-htdemucs-4s-f16.bin" set "MODELL=%~dp0ggml-model-htdemucs-4s-f16.bin"
if not defined MODELL if defined SM if exist "%SM%\models\ggml-model-htdemucs-4s-f16.bin" set "MODELL=%SM%\models\ggml-model-htdemucs-4s-f16.bin"
if not defined MODELL (
  echo FEHLER: Modell ggml-model-htdemucs-4s-f16.bin nicht gefunden.
  echo Bitte StemMaker einmal starten, damit es das Modell lädt, oder die Datei hierher kopieren.
  pause
  exit /b 1
)

echo Wandle "%~nx1" in WAV um ...
"%FF%" -hide_banner -loglevel error -y -i "%~1" -vn -ac 2 -ar 44100 -c:a pcm_s16le "eingang.wav"
if errorlevel 1 (
  echo FEHLER beim Umwandeln.
  pause
  exit /b 1
)

echo.
echo ===== 1. Durchlauf: automatisch (Grafikkarte oder CPU) =====
StemOnnx.exe "%MODELL%" eingang.wav stems-auto --ergebnis ergebnis.txt
echo.
echo ===== 2. Durchlauf: nur CPU =====
StemOnnx.exe "%MODELL%" eingang.wav stems-cpu --geraet cpu --ergebnis ergebnis.txt
echo.
echo ===== Ergebnis (steht auch in ergebnis.txt) =====
type ergebnis.txt
del eingang.wav
echo.
pause
