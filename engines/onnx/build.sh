#!/usr/bin/env bash
# Baut StemOnnx.exe für Windows (64 Bit) mit mingw unter Linux und legt
# alles, was auf den Windows-PC gehört, in dist/StemOnnx/.
#
# Aufruf:  ./build.sh            (im Ordner engines/onnx)
# Braucht: x86_64-w64-mingw32-gcc-posix (Paket gcc-mingw-w64-x86-64-posix),
#          curl, unzip, sha256sum
#
# ONNX Runtime und DirectML kommen als fertige Pakete von nuget.org (beide von
# Microsoft). Die Prüfsummen stehen hier fest drin: ein verändertes Paket
# bricht den Build ab.
set -euo pipefail
cd "$(dirname "$0")"

ORT_VERSION=1.24.4
ORT_SHA256=57e9f11b73437bef7a309496135d4c1f96b1a8e9ddba60013fa27bfc1d788681
DML_VERSION=1.15.4
DML_SHA256=4e7cb7ddce8cf837a7a75dc029209b520ca0101470fcdf275c1f49736a3615b9

CACHE=build/pakete
DIST=dist/StemOnnx
mkdir -p "$CACHE"

# Paket laden (nur wenn noch nicht da) und Prüfsumme kontrollieren
hole() {  # name version sha256
  local name=$1 ver=$2 sha=$3 datei="$CACHE/$1.$2.nupkg"
  if [ ! -f "$datei" ]; then
    echo "Lade $name $ver ..."
    curl -fsSL -o "$datei.tmp" "https://api.nuget.org/v3-flatcontainer/$name/$ver/$name.$ver.nupkg"
    mv "$datei.tmp" "$datei"
  fi
  echo "$sha  $datei" | sha256sum -c --quiet - || { echo "FEHLER: Prüfsumme von $datei stimmt nicht"; exit 1; }
  rm -rf "$CACHE/$name"
  unzip -q -o "$datei" -d "$CACHE/$name"
}
hole microsoft.ml.onnxruntime.directml "$ORT_VERSION" "$ORT_SHA256"
hole microsoft.ai.directml "$DML_VERSION" "$DML_SHA256"
ORT="$CACHE/microsoft.ml.onnxruntime.directml"
DML="$CACHE/microsoft.ai.directml"

echo "Baue StemOnnx.exe ..."
rm -rf "$DIST"
mkdir -p "$DIST/lizenzen"
# -municode: Einstieg über wmain (Pfade mit Umlauten), -static: keine mingw-DLLs nötig.
# Die Warnungen "redefined" kommen aus den ONNX-Runtime-Headern und sind harmlos.
x86_64-w64-mingw32-gcc-posix -O2 -Wall -municode -static \
  -I "$ORT/build/native/include" \
  -o "$DIST/StemOnnx.exe" src/stemonnx.c 2>&1 | { grep -v -e 'redefined' -e 'sal.h' -e 'previous definition' \
  -e 'In file included' -e '^ *from ' -e '^ *[0-9]* | ' -e '^ *| ' || true; }
test -f "$DIST/StemOnnx.exe"

cp "$ORT/runtimes/win-x64/native/onnxruntime.dll" \
   "$ORT/runtimes/win-x64/native/onnxruntime_providers_shared.dll" "$DIST/"
cp "$DML/bin/x64-win/DirectML.dll" "$DIST/"
cp modell/htdemucs-geruest.onnx modell/htdemucs-geruest.txt "$DIST/"
cp test/Test-starten.bat "$DIST/"
cp "$ORT/LICENSE" "$DIST/lizenzen/ONNXRuntime-LICENSE.txt"
cp "$ORT/ThirdPartyNotices.txt" "$DIST/lizenzen/ONNXRuntime-ThirdPartyNotices.txt"
cp "$DML/LICENSE.txt" "$DIST/lizenzen/DirectML-LICENSE.txt"
cp "$DML/ThirdPartyNotices.txt" "$DIST/lizenzen/DirectML-ThirdPartyNotices.txt"
cp ../../LICENSE "$DIST/lizenzen/StemMaker-LICENSE.txt"

( cd "$DIST" && sha256sum StemOnnx.exe *.dll htdemucs-geruest.* > PRUEFSUMMEN.txt )
echo "Fertig: $DIST"
ls -la "$DIST"
