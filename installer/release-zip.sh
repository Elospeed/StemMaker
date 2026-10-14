#!/usr/bin/env bash
# Stellt das Release-ZIP einer neuen Version zusammen (läuft im Workflow
# "Release erstellen", siehe .github/workflows/release.yml, geht aber auch lokal).
#
#   installer/release-zip.sh <altes ZIP> <Ordner mit neuen Exes> <Version> <Ausgabeordner>
#
# <altes ZIP>   das letzte Release-ZIP (aus update.json). Daraus kommen die Teile,
#               die nicht im Repository liegen: demucs.cpp in tools\ und der
#               Ordner models\ mit dem Hinweis.
# <Exes>        frisch gebaute StemMaker.exe, StemCLI.exe und StemPlayer.exe
# <Version>     z. B. 1.7.2
#
# Aufbau wie bisher: alles im Ordner StemMaker\, StemCLI und StemPlayer unter
# AddOns\, dazu Quelltext (Hauptprogramm + StemPlayer), Sprachdateien und Doku.
# Alle Dateien, die es auch im Repository gibt, kommen aus dem aktuellen Stand.
#
# Ergebnis: <Ausgabeordner>/StemMaker-<Version>.zip
set -euo pipefail

ALT=$(realpath "$1"); EXES=$(realpath "$2"); VERSION="$3"
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

# 2. Quelltext: Hauptprogramm (ohne andere AddOns) und StemPlayer, neue Dateien inklusive
(cd "$REPO" && git ls-files src | grep -v '^src/AddOns/'; cd "$REPO" && git ls-files src/AddOns/StemPlayer) |
while read -r f; do
  mkdir -p "$Z/$(dirname "$f")"
  cp "$REPO/$f" "$Z/$f"
done

# 3. Sprachdateien, neue Exes, Hinweis zum StemPlayer
cp "$REPO"/src/lang/*.po "$REPO"/src/lang/*.pot "$Z/lang/"
cp "$EXES/StemMaker.exe" "$Z/"
cp "$EXES/StemCLI.exe" "$EXES/StemPlayer.exe" "$Z/AddOns/"
cp "$REPO/src/AddOns/StemPlayer/LIESMICH.txt" "$Z/AddOns/StemPlayer-LIESMICH.txt"

# 4. packen
ZIP="$AUS/StemMaker-$VERSION.zip"
rm -f "$ZIP"
(cd "$ARBEIT" && { python -c "import sys, shutil; shutil.make_archive(sys.argv[1], 'zip', '.', 'StemMaker')" "${ZIP%.zip}" 2>/dev/null ||
  python3 -c "import sys, shutil; shutil.make_archive(sys.argv[1], 'zip', '.', 'StemMaker')" "${ZIP%.zip}"; })
rm -rf "$ARBEIT"
ls -l "$ZIP"
