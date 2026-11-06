#!/usr/bin/env bash
# Grafikkarten-Test für die StemMaker-AppImage unter Linux (Versuch).
# Misst Turbo (StemOnnx) auf drei Wegen und schreibt alles in eine Datei:
#   1. CPU                                  (Vergleichswert)
#   2. DirectML über vkd3d-proton + DXVK    (wie Steam/Proton)
#   3. WebGPU über Vulkan                   (StemOnnx 0.5 mit onnxruntime-webgpu)
#
# Aufruf (im entpackten GPU-Testpaket, die AppImage daneben oder als Parameter):
#   ./gpu-test.sh [StemMaker-x.y-x86_64.AppImage]
# Ergebnis: gpu-test-ergebnis.txt (diese Datei an Elospeed schicken)
set -uo pipefail

HIER=$(cd "$(dirname "$0")" && pwd)
AI="${1:-$(ls "$HIER"/StemMaker-*-x86_64.AppImage 2>/dev/null | head -n 1)}"
[ -n "$AI" ] && [ -f "$AI" ] || { echo "AppImage nicht gefunden. Aufruf: ./gpu-test.sh <StemMaker-...AppImage>"; exit 1; }
AI=$(realpath "$AI"); chmod +x "$AI" 2>/dev/null
ERG="$HIER/gpu-test-ergebnis.txt"
export STEMMAKER_DATA="${STEMMAKER_DATA:-$HOME/.local/share/StemMaker-Wine}"
C="$STEMMAKER_DATA/prefix/drive_c/StemMaker"
MODELL_URL="https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/main/ggml-model-htdemucs-4s-f16.bin"
MODELL_SHA="72b17c42d308982ddb5069bc3bf48b81a5aac4cb6516e4366c0fa7cef6df0064"
winpfad() { echo "Z:$(echo "$1" | tr '/' '\\')"; }

{
  echo "StemMaker GPU-Test $(date '+%Y-%m-%d %H:%M')"
  echo "AppImage: $(basename "$AI")"
  echo "System: $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME"), Kernel $(uname -r)"
  echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs) ($(nproc) Threads)"
  command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | sed 's/^/NVIDIA: /'
  if command -v vulkaninfo >/dev/null; then
    vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName|apiVersion" | sed 's/^ */Vulkan: /'
  else
    echo "Vulkan: vulkaninfo fehlt (Paket vulkan-tools)"
  fi
} > "$ERG"
cat "$ERG"

echo "== Vorbereiten (erster Start legt den Wine-Ordner an)"
"$AI" --cli --accept >/dev/null 2>&1 || true
mkdir -p "$C/models"
M="$C/models/ggml-model-htdemucs-4s-f16.bin"
if ! echo "$MODELL_SHA  $M" | sha256sum -c --quiet - 2>/dev/null; then
  echo "Lade Modell (80 MB) ..."
  curl -sSfL -o "$M" "$MODELL_URL" || { echo "Modell-Download fehlgeschlagen" | tee -a "$ERG"; exit 1; }
fi
WAV="$HIER/test-60s.wav"
if [ ! -f "$WAV" ]; then
  python3 - "$WAV" <<'PY'
import math, random, struct, sys, wave
sr, n = 44100, 44100 * 60
w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
random.seed(1); buf = bytearray()
for i in range(n):
    t = i / sr; beat = t % 0.5
    v = 0.6 * math.sin(2 * math.pi * 55 * beat) * math.exp(-beat * 18)
    v += (random.random() * 2 - 1) * math.exp(-((t + 0.25) % 0.5) * 60) * 0.3
    v += 0.25 * math.sin(2 * math.pi * 82.4 * t) + 0.2 * math.sin(2 * math.pi * 440 * t)
    s = int(max(-1, min(1, v)) * 30000); buf += struct.pack("<hh", s, s)
w.writeframes(bytes(buf)); w.close()
PY
fi

lauf() {  # Name, Exe, weitere Parameter...
  local name=$1 exe=$2; shift 2
  local aus="$HIER/aus-$name"; rm -rf "$aus"; mkdir -p "$aus"
  echo; echo "== $name"
  { echo; echo "===== $name ====="; } >> "$ERG"
  local t0=$(date +%s)
  "$AI" --run "$exe" "$(winpfad "$M")" "$(winpfad "$WAV")" "$(winpfad "$aus")" 1 "$@" 2>&1 \
    | grep -v "THREAD\|%)" | tee -a "$ERG"
  echo "Gesamtzeit: $(( $(date +%s) - t0 )) s" | tee -a "$ERG"
}

ONNX_REL="C:\\StemMaker\\tools\\onnx\\StemOnnx.exe"
lauf "1-CPU" "$ONNX_REL" --geraet cpu
STEMMAKER_GPU=vkd3d lauf "2-DirectML-vkd3d" "$ONNX_REL" --geraet auto --neu-pruefen
STEMONNX_WEBGPU_BACKEND=Vulkan lauf "3-WebGPU-Vulkan" "$(winpfad "$HIER/StemOnnx-WebGPU/StemOnnx.exe")" --geraet webgpu
# D3D12 unter WebGPU: vkd3d-proton + DXVK neben die WebGPU-Exe legen (AppRun hat
# sie bei Lauf 2 nach C:\StemMaker\tools\onnx kopiert)
cp "$C/tools/onnx/d3d12.dll" "$C/tools/onnx/d3d12core.dll" "$C/tools/onnx/dxgi.dll" "$HIER/StemOnnx-WebGPU/" 2>/dev/null
WINEDLLOVERRIDES="d3d12,d3d12core,dxgi=n,b" STEMONNX_WEBGPU_BACKEND=D3D12 lauf "4-WebGPU-D3D12-vkd3d" "$(winpfad "$HIER/StemOnnx-WebGPU/StemOnnx.exe")" --geraet webgpu

rm -f "$HIER/StemOnnx-WebGPU/d3d12.dll" "$HIER/StemOnnx-WebGPU/d3d12core.dll" "$HIER/StemOnnx-WebGPU/dxgi.dll"
"$AI" --cli >/dev/null 2>&1 || true   # vkd3d-DLLs bei Turbo wieder entfernen (Standard)
echo
echo "Fertig. Bitte diese Datei an Elospeed schicken: $ERG"
