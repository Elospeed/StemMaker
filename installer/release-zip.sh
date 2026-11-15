#!/usr/bin/env bash
# Stellt das Release-ZIP einer neuen Version zusammen (läuft im Workflow
# "Release erstellen", siehe .github/workflows/release.yml, geht aber auch lokal).
#
#   installer/release-zip.sh <altes ZIP> <Ordner mit neuen Exes> <Version> <Ausgabeordner> [<StemOnnx>] [<Hilfe>]
#
# <altes ZIP>   das letzte Release-ZIP (aus update.json). Daraus kommen die Teile,
#               die nicht im Repository liegen: demucs.cpp in tools\ und der
#               Ordner models\ mit dem Hinweis.
# <Exes>        frisch gebaute StemMaker.exe, StemCLI.exe, StemPlayer.exe, StemTagger.exe und StemPacker.exe
# <Version>     z. B. 1.7.2
# <StemOnnx>    (ab 2.0) frisch gebauter Ordner von engines/onnx/build.sh
#               (dist/StemOnnx). Kommt nach tools\onnx\ und ersetzt dort alles.
# <Hilfe>       (ab 2.4) Ordner mit de.html, en.html, es.html von
#               docs/handbuch/build.py --hilfe. Kommt nach hilfe\.
#
# Aufbau wie bisher: alles im Ordner StemMaker\, StemCLI, StemPlayer und StemTagger
# unter AddOns\, dazu Quelltext (Hauptprogramm, StemPlayer, StemTagger),
# Sprachdateien und Doku.
# Alle Dateien, die es auch im Repository gibt, kommen aus dem aktuellen Stand.
#
# Ergebnis: <Ausgabeordner>/StemMaker-<Version>.zip
set -euo pipefail

ALT=$(realpath "$1"); EXES=$(realpath "$2"); VERSION="$3"
ONNX="${5:-}"; [ -n "$ONNX" ] && ONNX=$(realpath "$ONNX")
HILFE="${6:-}"; [ -n "$HILFE" ] && HILFE=$(realpath "$HILFE")
mkdir -p "$4"; AUS=$(realpath "$4")
REPO=$(realpath "$(dirname "$0")/..")
ARBEIT=$(mktemp -d)

# altes ZIP entpacken (Python statt unzip/7z, das gibt es überall)
python -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$ALT" "$ARBEIT" 2>/dev/null ||
  python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$ALT" "$ARBEIT"
Z="$ARBEIT/StemMaker"
[ -f "$Z/StemMaker.exe" ] || { echo "Im alten ZIP fehlt StemMaker/StemMaker.exe"; exit 1; }

# 1. Dateien, die es auch im Repository gibt, auf den aktuellen Stand bringen
(cd "$Z" && find . -type f ! -name '*.exe') | while read -r f; do
  if [ -f "$REPO/$f" ]; then cp "$REPO/$f" "$Z/$f"; fi
done

# 2. Quelltext: Hauptprogramm (ohne andere AddOns), StemPlayer, StemTagger und StemPacker, neue Dateien inklusive
(cd "$REPO" && git ls-files src | grep -v '^src/AddOns/'; cd "$REPO" && git ls-files src/AddOns/StemPlayer src/AddOns/StemTagger src/AddOns/StemPacker) |
while read -r f; do
  mkdir -p "$Z/$(dirname "$f")"
  cp "$REPO/$f" "$Z/$f"
done

# 3. Sprachdateien, neue Exes, Hinweise zu StemPlayer, StemTagger und StemPacker
cp "$REPO"/src/lang/*.po "$REPO"/src/lang/*.pot "$Z/lang/"
cp "$EXES/StemMaker.exe" "$Z/"
cp "$EXES/StemCLI.exe" "$EXES/StemPlayer.exe" "$EXES/StemTagger.exe" "$EXES/StemPacker.exe" "$Z/AddOns/"
cp "$REPO/src/AddOns/StemPlayer/LIESMICH.txt" "$Z/AddOns/StemPlayer-LIESMICH.txt"
cp "$REPO/src/AddOns/StemTagger/LIESMICH.txt" "$Z/AddOns/StemTagger-LIESMICH.txt"
cp "$REPO/src/AddOns/StemTagger/README.txt" "$Z/AddOns/StemTagger-README.txt"
cp "$REPO/src/AddOns/StemPacker/LIESMICH.txt" "$Z/AddOns/StemPacker-LIESMICH.txt"
cp "$REPO/src/AddOns/StemPacker/README.txt" "$Z/AddOns/StemPacker-README.txt"
cp "$REPO/src/AddOns/StemPacker/StemPacker-User-Guide.pdf" "$Z/AddOns/"

# 3b. Turbo (StemOnnx): Exe, ONNX Runtime, DirectML, Gerüst, Lizenzen.
#     Die Test-Batch für Entwickler kommt nicht mit.
if [ -n "$ONNX" ]; then
  [ -f "$ONNX/StemOnnx.exe" ] || { echo "In $ONNX fehlt StemOnnx.exe"; exit 1; }
  rm -rf "$Z/tools/onnx"
  mkdir -p "$Z/tools/onnx"
  cp -r "$ONNX"/. "$Z/tools/onnx/"
  rm -f "$Z/tools/onnx/Test-starten.bat"
fi

# 3c. Hilfe (ab 2.4): "?" und F1 öffnen hilfe\<Sprache>.html
if [ -n "$HILFE" ]; then
  for L in de en es; do
    [ -f "$HILFE/$L.html" ] || { echo "In $HILFE fehlt $L.html"; exit 1; }
  done
  rm -rf "$Z/hilfe"
  mkdir -p "$Z/hilfe"
  cp "$HILFE"/*.html "$Z/hilfe/"
fi

# 4. packen
ZIP="$AUS/StemMaker-$VERSION.zip"
rm -f "$ZIP"
(cd "$ARBEIT" && { python -c "import sys, shutil; shutil.make_archive(sys.argv[1], 'zip', '.', 'StemMaker')" "${ZIP%.zip}" 2>/dev/null ||
  python3 -c "import sys, shutil; shutil.make_archive(sys.argv[1], 'zip', '.', 'StemMaker')" "${ZIP%.zip}"; })
rm -rf "$ARBEIT"
ls -l "$ZIP"
