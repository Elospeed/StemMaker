#!/usr/bin/env bash
# Baut die Setup-Exe aus einem StemMaker-Release-ZIP (läuft auf dem Windows-Rechner
# von GitHub in Git-Bash, siehe .github/workflows/build.yml und setup.yml).
#
#   installer/setup-bauen.sh <ZIP> <Version> <Ausgabename> [Ordner mit neuen Exes]
#
# <ZIP>          Release-ZIP, z. B. StemMaker-1.7.zip (enthält den Ordner StemMaker\)
# <Version>      z. B. 1.7 (steht dann unter "Apps & Features")
# <Ausgabename>  Dateiname des Setups ohne .exe, z. B. StemMaker-1.7-Setup
# [Exes]         optional: frisch gebaute StemMaker.exe, StemCLI.exe, StemPlayer.exe.
#                Sie ersetzen die aus dem ZIP (für die Testversionen). Dazu kommen
#                die Sprachdateien aus src/lang.
#
# Ergebnis: installer/Output/<Ausgabename>.exe
set -euo pipefail

# Pfade absolut machen, bevor wir in den installer-Ordner wechseln
ZIP=$(realpath "$1"); VERSION="$2"; NAME="$3"; NEU="${4:+$(realpath "$4")}"
cd "$(dirname "$0")"

# Inno Setup suchen; fehlt es auf dem Build-Rechner, per Chocolatey nachinstallieren
ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
if [ ! -f "$ISCC" ]; then
  echo "Inno Setup fehlt, installiere ..."
  choco install innosetup -y --no-progress
fi
[ -f "$ISCC" ] || { echo "ISCC.exe nicht gefunden"; exit 1; }

# ZIP in einen frischen Ordner entpacken
rm -rf quelle && mkdir quelle
7z x -y -oquelle "$ZIP" > /dev/null
QUELLE="quelle/StemMaker"
[ -f "$QUELLE/StemMaker.exe" ] || { echo "Im ZIP fehlt StemMaker/StemMaker.exe"; exit 1; }

if [ -n "$NEU" ]; then
  cp "$NEU/StemMaker.exe" "$QUELLE/"
  cp "$NEU/StemCLI.exe" "$NEU/StemPlayer.exe" "$QUELLE/AddOns/"
  cp ../src/lang/*.po ../src/lang/*.pot "$QUELLE/lang/"
fi

# Versionsnummer für die Datei-Eigenschaften: nur der Ziffern-Teil (1.7.1-test -> 1.7.1)
NUM=$(printf '%s' "$VERSION" | grep -oE '^[0-9]+(\.[0-9]+)*')

# MSYS2_ARG_CONV_EXCL: Git-Bash würde Schalter wie "/Q" und "/DAppVersion=..." sonst
# für Pfade halten und umschreiben (ISCC meldet dann "more than one script filename")
MSYS2_ARG_CONV_EXCL='*' "$ISCC" /Q "/DAppVersion=$VERSION" "/DVersionNum=$NUM" "/DOutputName=$NAME" \
  "/DSourceDir=$(cygpath -w "$PWD/$QUELLE")" StemMaker.iss
ls -l "Output/$NAME.exe"
