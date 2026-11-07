#!/usr/bin/env bash
# Linux-Testversion packen: nimmt eine fertige AppImage (z. B. Artefakt
# "StemMaker-AppImage" aus appimage.yml) und ersetzt darin die Programme
# durch neuere aus einem Build-Artefakt (build.yml, "StemMaker-Win64-...").
# Ergebnis: <Ziel>/StemMaker-<Version>-Linux-Test.zip mit AppImage,
# Testanleitungen DE/EN und SHA256SUMS.txt.
#
# Aufruf: testversion-packen.sh <alte.AppImage> <Ordner mit Exes> <Version> <Ziel>
#   Version z. B. 2.2.1-beta1 (in der AppImage als 2.2.1~beta1, damit die
#   spätere 2.2.1 sie beim Start ersetzt, siehe AppRun "sort -V")
# Braucht: unsquashfs, mksquashfs (squashfs-tools, mit zstd), zip, python3
set -euo pipefail
ALT=$(readlink -f "$1"); EXES=$(readlink -f "$2"); VER=$3; ZIEL=$(readlink -f "$4")
HIER=$(cd "$(dirname "$0")" && pwd)
ARBEIT=$(mktemp -d); trap 'rm -rf "$ARBEIT"' EXIT

# Beginn des squashfs = Ende der ELF-Laufzeit (Section-Header-Tabelle)
OFF=$(python3 - "$ALT" <<'PY'
import sys, struct
k = open(sys.argv[1], 'rb').read(64)
shoff = struct.unpack_from('<Q', k, 0x28)[0]
shentsize, shnum = struct.unpack_from('<HH', k, 0x3A)
print(shoff + shentsize * shnum)
PY
)
unsquashfs -q -o "$OFF" -d "$ARBEIT/sq" "$ALT" >/dev/null
head -c "$OFF" "$ALT" > "$ARBEIT/runtime"

(cd "$EXES" && [ -f SHA256SUMS.txt ] && sha256sum --quiet -c SHA256SUMS.txt)
A="$ARBEIT/sq/StemMaker"
cp "$EXES/StemMaker.exe" "$A/"
for e in StemPlayer StemTagger StemCLI; do cp "$EXES/$e.exe" "$A/AddOns/"; done
echo "${VER/-/\~}" > "$A/APPIMAGE_VERSION"

NAME="StemMaker-$VER-Linux-Test"
mkdir -p "$ARBEIT/$NAME" "$ZIEL"
mksquashfs "$ARBEIT/sq" "$ARBEIT/neu.sqfs" -comp zstd -b 131072 -root-owned -noappend -quiet >/dev/null
cat "$ARBEIT/runtime" "$ARBEIT/neu.sqfs" > "$ARBEIT/$NAME/StemMaker-$VER-x86_64.AppImage"
chmod +x "$ARBEIT/$NAME/StemMaker-$VER-x86_64.AppImage"
cp "$HIER"/Linux-Beta-Test-DE.md "$HIER"/Linux-Beta-Test-EN.md "$ARBEIT/$NAME/"
(cd "$ARBEIT/$NAME" && sha256sum "StemMaker-$VER-x86_64.AppImage" > SHA256SUMS.txt)
rm -f "$ZIEL/$NAME.zip"
(cd "$ARBEIT" && zip -q -r -X "$ZIEL/$NAME.zip" "$NAME")
sha256sum "$ZIEL/$NAME.zip"
