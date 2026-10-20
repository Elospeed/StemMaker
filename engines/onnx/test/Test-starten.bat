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

rem Modell und ffmpeg suchen: zuerst hier im Ordner, dann im installierten
rem StemMaker (pro Benutzer oder für alle), dann im Ordner daneben.
rem Gesucht wird direkt nach den Dateien, nicht nach StemMaker.exe.
set "MODELL="
set "FF="
call :suche "%~dp0"
call :suche "%LOCALAPPDATA%\Programs\StemMaker\"
call :suche "%ProgramFiles%\StemMaker\"
call :suche "%~dp0..\StemMaker\"
call :suche "%~dp0..\"
if not defined FF for /f "delims=" %%F in ('where ffmpeg 2^>nul') do if not defined FF set "FF=%%F"
if not defined FF (
  echo FEHLER: ffmpeg.exe nicht gefunden. Bitte aus StemMaker\tools hierher kopieren.
  pause
  exit /b 1
)
if not defined MODELL (
  echo FEHLER: Modell ggml-model-htdemucs-4s-f16.bin nicht gefunden.
  echo Bitte StemMaker einmal starten, damit es das Modell lädt, oder die Datei hierher kopieren.
  pause
  exit /b 1
)
echo Modell: %MODELL%
echo ffmpeg: %FF%

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
exit /b 0

rem Unterprogramm: sucht in Ordner %1 (und dessen models\ und tools\)
:suche
if not defined MODELL if exist "%~1ggml-model-htdemucs-4s-f16.bin" set "MODELL=%~1ggml-model-htdemucs-4s-f16.bin"
if not defined MODELL if exist "%~1models\ggml-model-htdemucs-4s-f16.bin" set "MODELL=%~1models\ggml-model-htdemucs-4s-f16.bin"
if not defined FF if exist "%~1ffmpeg.exe" set "FF=%~1ffmpeg.exe"
if not defined FF if exist "%~1tools\ffmpeg.exe" set "FF=%~1tools\ffmpeg.exe"
exit /b 0
