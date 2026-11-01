#!/usr/bin/env bash
# Baut das eigenständige Download-ZIP für den StemPacker (StemPacker.exe).
# Läuft auf dem Windows-Rechner von GitHub in Git-Bash (siehe .github/workflows/build.yml),
# geht aber auch unter Linux.
#
#   src/AddOns/StemPacker/stempacker-zip.sh <StemPacker.exe> <Ausgabeordner>
#
# Inhalt (Ordner StemPacker\):
#   StemPacker.exe, LIESMICH.txt (DE), README.txt (EN), LICENSE.txt,
#   lang\*.po (Englisch, Spanisch; Deutsch steckt in der Exe),
#   tools\ffmpeg.exe + Lizenz und Quellcode-Hinweis (LGPL-Build aus unserem
#   Release ffmpeg-9.0.2, Prüfsumme wird kontrolliert).
# Keine KI-Modelle: der StemPacker trennt nichts, er verpackt nur.
# Die Version kommt aus APP_VER in packerform.pas.
#
# Ergebnis: <Ausgabeordner>/StemPacker-<Version>.zip
set -euo pipefail

EXE=$(realpath "$1"); mkdir -p "$2"; AUS=$(realpath "$2")
HIER=$(cd "$(dirname "$0")" && pwd)
REPO=$(realpath "$HIER/../../..")
VERSION=$(sed -n "s/^ *APP_VER *= *'\(.*\)';.*/\1/p" "$HIER/packerform.pas" | head -n 1 | tr -d '\r')
[ -n "$VERSION" ] || { echo "APP_VER in packerform.pas nicht gefunden"; exit 1; }

FFMPEG_URL="https://github.com/Elospeed/StemMaker/releases/download/ffmpeg-9.0.2/ffmpeg-9.0.2-win64-lgpl.zip"
FFMPEG_SHA="d350ded1fd523fdae90064c11b954497d2ba8f9ef3b10a2447f6717acc210af0"

ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT
ZIEL="$ARBEIT/StemPacker"
mkdir -p "$ZIEL/tools" "$ZIEL/lang"

PY=$(command -v python || command -v python3)

# ffmpeg holen und Prüfsumme kontrollieren
curl -sSfL -o "$ARBEIT/ffmpeg.zip" "$FFMPEG_URL"
echo "$FFMPEG_SHA  $ARBEIT/ffmpeg.zip" | sha256sum -c -
"$PY" - "$ARBEIT/ffmpeg.zip" "$ARBEIT/ff" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
FF="$ARBEIT/ff/ffmpeg-9.0.2-win64-lgpl"
cp "$FF/ffmpeg.exe" "$ZIEL/tools/ffmpeg.exe"

# Textdateien mit Windows-Zeilenenden (Notepad)
crlf() { sed 's/\r$//; s/$/\r/' "$1" > "$2"; }
crlf "$FF/LICENSE.txt"           "$ZIEL/tools/FFMPEG-LICENSE.txt"
crlf "$FF/QUELLCODE-SOURCE.txt"  "$ZIEL/tools/FFMPEG-SOURCE.txt"
crlf "$HIER/LIESMICH.txt"        "$ZIEL/LIESMICH.txt"
crlf "$HIER/README.txt"          "$ZIEL/README.txt"
crlf "$REPO/LICENSE"             "$ZIEL/LICENSE.txt"
cp "$REPO"/src/lang/*.po "$ZIEL/lang/"
cp "$EXE" "$ZIEL/StemPacker.exe"

ZIPNAME="$AUS/StemPacker-$VERSION.zip"
rm -f "$ZIPNAME"
"$PY" - "$ARBEIT" "$ZIPNAME" <<'PY'
import os, sys, zipfile
basis, ziel = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(ziel, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for ordner, _, dateien in os.walk(os.path.join(basis, "StemPacker")):
        for d in sorted(dateien):
            pfad = os.path.join(ordner, d)
            z.write(pfad, os.path.relpath(pfad, basis))
PY
echo "Fertig: $ZIPNAME"
