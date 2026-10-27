#!/bin/sh
# Baut StemMaker-Turbo-Test.zip zum Weitergeben an Tester.
#   paket.sh <ordner mit StemMaker-Turbo-Test.exe> <ordner engine (onnx aus der CI)> <The-Hardline.wav> <ziel.zip>
# Das Modell kommt NICHT ins ZIP (wird nicht weitergegeben), der Test lädt es selbst.
set -e
EXE_DIR=$1; ONNX=$2; WAV=$3; ZIEL=$4
T=$(mktemp -d)
P=$T/StemMaker-Turbo-Test
mkdir -p "$P/engine" "$P/musik"
cp "$EXE_DIR/StemMaker-Turbo-Test.exe" "$P/"
for f in StemOnnx.exe onnxruntime.dll onnxruntime_providers_shared.dll DirectML.dll htdemucs-geruest.onnx htdemucs-geruest.txt; do
  cp "$ONNX/$f" "$P/engine/"
done
cp -r "$ONNX/lizenzen" "$P/engine/"
cp "$WAV" "$P/musik/The-Hardline.wav"
# LIESMICH mit Windows-Zeilenenden (Editor)
sed 's/$/\r/' "$(dirname "$0")/LIESMICH-README.txt" > "$P/LIESMICH-README.txt"
rm -f "$ZIEL"
(cd "$T" && zip -qr -9 "$ZIEL" StemMaker-Turbo-Test)
rm -rf "$T"
sha256sum "$ZIEL"
