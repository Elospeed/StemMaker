#!/usr/bin/env bash
# Baut das fertige Download-ZIP für das Test-Tool "5.1 -> Stem" (Stem51.exe).
# Läuft auf dem Windows-Rechner von GitHub in Git-Bash (siehe .github/workflows/build.yml),
# geht aber auch unter Linux (dann FFMPEG_TEST auf ein Linux-ffmpeg setzen).
#
#   src/AddOns/StemDecks/stem51-zip.sh <Stem51.exe> <Version> <Ausgabeordner>
#
# Inhalt des ZIPs (Ordner Elospeed-5.1-Stem\):
#   Stem51.exe, README.txt (EN), LIESMICH.txt (DE), 5.1-test-file.mkv,
#   tools\ffmpeg.exe + Lizenz und Quellcode-Hinweis (LGPL-Build aus unserem
#   Release ffmpeg-9.0.2, Prüfsumme wird kontrolliert).
# Keine KI-Modelle im ZIP: das Tool braucht keine.
#
# Ergebnis: <Ausgabeordner>/Elospeed-5.1-Stem-<Version>.zip
set -euo pipefail

EXE=$(realpath "$1"); VERSION="$2"; mkdir -p "$3"; AUS=$(realpath "$3")
HIER=$(cd "$(dirname "$0")" && pwd)

FFMPEG_URL="https://github.com/Elospeed/StemMaker/releases/download/ffmpeg-9.0.2/ffmpeg-9.0.2-win64-lgpl.zip"
FFMPEG_SHA="d350ded1fd523fdae90064c11b954497d2ba8f9ef3b10a2447f6717acc210af0"

ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT
ZIEL="$ARBEIT/Elospeed-5.1-Stem"
mkdir -p "$ZIEL/tools"

# ffmpeg holen und Prüfsumme kontrollieren
curl -sSfL -o "$ARBEIT/ffmpeg.zip" "$FFMPEG_URL"
echo "$FFMPEG_SHA  $ARBEIT/ffmpeg.zip" | sha256sum -c -
python - "$ARBEIT/ffmpeg.zip" "$ARBEIT/ff" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
FF="$ARBEIT/ff/ffmpeg-9.0.2-win64-lgpl"
cp "$FF/ffmpeg.exe" "$ZIEL/tools/ffmpeg.exe"

# Textdateien mit Windows-Zeilenenden (Notepad)
crlf() { sed 's/\r$//; s/$/\r/' "$1" > "$2"; }
crlf "$FF/LICENSE.txt"            "$ZIEL/tools/FFMPEG-LICENSE.txt"
crlf "$FF/QUELLCODE-SOURCE.txt"   "$ZIEL/tools/FFMPEG-SOURCE.txt"
crlf "$HIER/Stem51-README.txt"    "$ZIEL/README.txt"
crlf "$HIER/Stem51-LIESMICH.txt"  "$ZIEL/LIESMICH.txt"
cp "$EXE" "$ZIEL/Stem51.exe"

# Testdatei wie von einer DVD: Spur 1 Stereo (AC3), Spur 2 5.1 (AC3), Spur 3 5.1 (DTS).
# Jeder Kanal hat einen eigenen Ton, so hört man sofort, ob die Zuordnung stimmt:
# vorne links 220 Hz, vorne rechts 330 Hz, Center 440 Hz, LFE 50 Hz,
# hinten links 550 Hz, hinten rechts 660 Hz. 20 Sekunden.
TESTFF="${FFMPEG_TEST:-$ZIEL/tools/ffmpeg.exe}"
# Unter Git-Bash den Ausgabepfad in einen Windows-Pfad umwandeln und die automatische
# Pfad-Umwandlung abschalten, damit die Filter-Texte unverändert bei ffmpeg ankommen.
MKV="$ZIEL/5.1-test-file.mkv"
if command -v cygpath >/dev/null; then MKV=$(cygpath -w "$MKV"); fi
TON() { echo "sine=frequency=$1:sample_rate=48000:duration=20"; }
MSYS_NO_PATHCONV=1 "$TESTFF" -hide_banner -loglevel error -y \
  -f lavfi -i "$(TON 220)" -f lavfi -i "$(TON 330)" -f lavfi -i "$(TON 440)" \
  -f lavfi -i "$(TON 50)"  -f lavfi -i "$(TON 550)" -f lavfi -i "$(TON 660)" \
  -filter_complex "[0][1][2][3][4][5]join=inputs=6:channel_layout=5.1(side)[s];[s]asplit=3[a][b][c];[a]pan=stereo|FL=FL+0.7*FC+0.7*SL|FR=FR+0.7*FC+0.7*SR[st]" \
  -map "[st]" -map "[b]" -map "[c]" \
  -c:a:0 ac3 -b:a:0 192k -c:a:1 ac3 -b:a:1 448k -c:a:2 dca -strict -2 -b:a:2 1509k \
  -metadata:s:a:0 title="Stereo" -metadata:s:a:1 title="5.1 AC3" -metadata:s:a:2 title="5.1 DTS" \
  "$MKV"

# ZIP packen (Python statt zip, das gibt es in Git-Bash nicht immer)
ZIPNAME="$AUS/Elospeed-5.1-Stem-$VERSION.zip"
rm -f "$ZIPNAME"
python - "$ARBEIT" "$ZIPNAME" <<'PY'
import os, sys, zipfile
basis, ziel = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(ziel, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for ordner, _, dateien in os.walk(os.path.join(basis, "Elospeed-5.1-Stem")):
        for d in sorted(dateien):
            pfad = os.path.join(ordner, d)
            z.write(pfad, os.path.relpath(pfad, basis))
PY
echo "Fertig: $ZIPNAME"
