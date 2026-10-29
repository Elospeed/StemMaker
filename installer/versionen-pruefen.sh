#!/usr/bin/env bash
# Prüft, ob jede Versionsnummer überall gleich ist: Konstante im Quelltext,
# Versionsinfo der Exe (.lpi: ProductVersion + Major/Minor) und erste Zeile
# von LIESMICH.txt/README.txt. Läuft bei jedem PR (build.yml) und vor jedem
# Release (release.yml). Regel: jede Änderung an einem Programm oder AddOn
# hebt dessen Version im selben PR an.
set -u
cd "$(dirname "$0")/.."
FEHLER=0

fehler() { echo "::error::$1"; FEHLER=1; NEU=1; }

# Wert eines .lpi-Eintrags wie <MinorVersionNr Value="8"/>, fehlt er, gilt 0
lpi_nr() {
  local v
  v=$(sed -n "s/.*<$2 Value=\"\([0-9]*\)\".*/\1/p" "$1" | head -n 1)
  echo "${v:-0}"
}

# $1 = Name, $2 = Version aus dem Quelltext, $3 = .lpi, $4.. = Textdateien
pruefe() {
  local name=$1 ver=$2 lpi=$3; shift 3
  NEU=0
  if [ -z "$ver" ]; then fehler "$name: keine Versionskonstante gefunden"; return; fi
  grep -q "ProductVersion=\"$ver\"" "$lpi" || fehler "$lpi hat nicht ProductVersion=\"$ver\" ($name ist $ver)"
  local major=${ver%%.*} rest=${ver#*.}
  local minor=${rest%%.*}
  [ "$(lpi_nr "$lpi" MajorVersionNr)" = "$major" ] || fehler "$lpi: MajorVersionNr passt nicht zu $ver"
  [ "$(lpi_nr "$lpi" MinorVersionNr)" = "$minor" ] || fehler "$lpi: MinorVersionNr passt nicht zu $ver"
  local txt
  for txt in "$@"; do
    [ -f "$txt" ] || continue
    head -n 1 "$txt" | grep -q " $ver\b" || fehler "$txt: erste Zeile nennt nicht Version $ver"
  done
  [ $NEU = 0 ] && echo "$name $ver ok"
}

konst() { sed -n "s/^ *$2 *= *'\([0-9.]*\)';.*/\1/p" "$1" | head -n 1 | tr -d '\r'; }

V=$(konst src/version.inc APP_VERSION)
pruefe StemMaker "$V" src/StemMaker.lpi
pruefe StemCLI "$V" src/StemCLI.lpi

A=src/AddOns
pruefe StemPlayer "$(konst $A/StemPlayer/playerform.pas APP_VER)" $A/StemPlayer/StemPlayer.lpi $A/StemPlayer/LIESMICH.txt $A/StemPlayer/README.txt
pruefe StemTagger "$(konst $A/StemTagger/taggerform.pas APP_VER)" $A/StemTagger/StemTagger.lpi $A/StemTagger/LIESMICH.txt $A/StemTagger/README.txt
pruefe StemDecks "$(konst $A/StemDecks/deckform.pas APP_VER)" $A/StemDecks/StemDecks.lpi $A/StemDecks/LIESMICH.txt $A/StemDecks/README.txt
pruefe Stem51 "$(konst $A/StemDecks/stem51form.pas APP_VER)" $A/StemDecks/Stem51.lpi

exit $FEHLER
