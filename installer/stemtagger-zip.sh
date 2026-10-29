#!/usr/bin/env bash
# Baut das eigenständige ZIP für den StemTagger (läuft im Workflow
# "Release erstellen", siehe .github/workflows/release.yml, geht aber auch lokal).
# In StemMaker selbst ist der StemTagger als AddOn schon dabei; dieses ZIP ist
# für alle, die nur die Tags ihrer Stem-Dateien bearbeiten wollen.
#
#   installer/stemtagger-zip.sh <StemTagger.exe> <Ausgabeordner>
#
# Inhalt (Ordner StemTagger\):
#   StemTagger.exe, LIESMICH.txt (DE), README.txt (EN), LICENSE.txt,
#   lang\*.po (Englisch, Spanisch; Deutsch steckt in der Exe)
# Die Version kommt aus APP_VER in src/AddOns/StemTagger/taggerform.pas.
#
# Ergebnis: <Ausgabeordner>/StemTagger-<Version>.zip
set -euo pipefail

EXE=$(realpath "$1"); mkdir -p "$2"; AUS=$(realpath "$2")
REPO=$(realpath "$(dirname "$0")/..")
QUELLE="$REPO/src/AddOns/StemTagger"
VERSION=$(sed -n "s/^ *APP_VER *= *'\(.*\)';.*/\1/p" "$QUELLE/taggerform.pas" | head -n 1 | tr -d '\r')
[ -n "$VERSION" ] || { echo "APP_VER in taggerform.pas nicht gefunden"; exit 1; }

ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT
ZIEL="$ARBEIT/StemTagger"
mkdir -p "$ZIEL/lang"

# Textdateien mit Windows-Zeilenenden (Notepad)
crlf() { sed 's/\r$//; s/$/\r/' "$1" > "$2"; }
cp "$EXE" "$ZIEL/StemTagger.exe"
crlf "$QUELLE/LIESMICH.txt" "$ZIEL/LIESMICH.txt"
crlf "$QUELLE/README.txt"   "$ZIEL/README.txt"
crlf "$REPO/LICENSE"        "$ZIEL/LICENSE.txt"
cp "$REPO"/src/lang/*.po "$ZIEL/lang/"

ZIP="$AUS/StemTagger-$VERSION.zip"
rm -f "$ZIP"
(cd "$ARBEIT" && { python -c "import sys, shutil; shutil.make_archive(sys.argv[1], 'zip', '.', 'StemTagger')" "${ZIP%.zip}" 2>/dev/null ||
  python3 -c "import sys, shutil; shutil.make_archive(sys.argv[1], 'zip', '.', 'StemTagger')" "${ZIP%.zip}"; })
ls -l "$ZIP"
