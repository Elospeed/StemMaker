#!/usr/bin/env bash
# Baut das eigenständige Download-ZIP für den StemPacker (StemPacker.exe).
# Läuft auf dem Windows-Rechner von GitHub in Git-Bash (siehe .github/workflows/build.yml),
# geht aber auch unter Linux.
#
#   src/AddOns/StemPacker/stempacker-zip.sh <StemPacker.exe> <Ausgabeordner>
#
# Inhalt (Ordner StemPacker\):
#   StemPacker.exe, LIESMICH.txt (DE), README.txt (EN), LICENSE.txt,
#   StemPacker-User-Guide.pdf (englische Anleitung mit Bildern, Quelle in anleitung/),
#   Example\ (3 kurze Testton-Songs im 5.1-DVD-Namensschema, hier erzeugt),
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
cp "$HIER/anleitung/StemPacker-User-Guide.pdf" "$ZIEL/"

# Beispiel im Namensschema 5.1-DVD: Downmix\Song (DOWNMIX #1).wav und
# Channels\Song (A..D).wav, je 5 Sekunden Testton (A und D Stereo, B und C Mono)
TESTFF="${FFMPEG_TEST:-$ZIEL/tools/ffmpeg.exe}"
BSP="$ZIEL/Example"
mkdir -p "$BSP/Downmix" "$BSP/Channels"
winpfad() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
i=0
for SONG in "Song One" "Song Two" "Song Three"; do
  i=$((i + 1))
  MSYS_NO_PATHCONV=1 "$TESTFF" -hide_banner -loglevel error -y -f lavfi \
    -i "sine=frequency=$((200 + i * 60)):sample_rate=48000:duration=5" -ac 2 \
    "$(winpfad "$BSP/Downmix/$SONG (DOWNMIX #1).wav")"
  k=0
  for C in A B C D; do
    k=$((k + 1))
    KAN=1; if [ "$C" = A ] || [ "$C" = D ]; then KAN=2; fi
    MSYS_NO_PATHCONV=1 "$TESTFF" -hide_banner -loglevel error -y -f lavfi \
      -i "sine=frequency=$((k * 150 + i * 20)):sample_rate=48000:duration=5" -ac $KAN \
      "$(winpfad "$BSP/Channels/$SONG ($C).wav")"
  done
done
crlf "$HIER/anleitung/Example-README.txt" "$BSP/How-to-use-the-example.txt"

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
