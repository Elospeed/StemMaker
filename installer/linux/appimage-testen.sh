#!/usr/bin/env bash
# Testet die Linux-AppImage: Start, ganze Umwandlung mit StemCLI und
# (wenn Xvfb + xdotool da sind) Bilder der ersten Fenster bei 100 % und 150 %.
# Läuft im Workflow "Linux-AppImage" auf mehreren Distros (Docker).
#
#   installer/linux/appimage-testen.sh <AppImage> [<Bildordner>]
#
# Braucht: python3, curl, sha256sum. Für Bilder: Xvfb, xdotool, ImageMagick.
# Ohne FUSE (Docker): APPIMAGE_EXTRACT_AND_RUN=1 wird hier gesetzt.
set -euo pipefail

AI=$(realpath "$1")
BILDER="${2:-}"; [ -n "$BILDER" ] && { mkdir -p "$BILDER"; BILDER=$(realpath "$BILDER"); }
REPO=$(realpath "$(dirname "$0")/../..")
export APPIMAGE_EXTRACT_AND_RUN=1
T=$(mktemp -d)
export HOME="$T/home"; mkdir -p "$HOME"
export STEMMAKER_DATA="$HOME/data"
C="$STEMMAKER_DATA/prefix/drive_c/StemMaker"

echo "== 1. Erster Start (Wine-Ordner anlegen, StemMaker kopieren)"
"$AI" --cli > "$T/start.log" 2>&1 || true
cat "$T/start.log"
test -f "$C/StemMaker.exe" || { echo "FEHLER: StemMaker wurde nicht in den Wine-Ordner kopiert"; exit 1; }
test -f "$C/APPIMAGE_VERSION"

echo "== 2. ffmpeg und Modell (wie beim ersten Start von StemMaker, aus update.json)"
read -r FURL FSHA MURL MSHA < <(python3 - "$REPO/update.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
m = "ggml-model-htdemucs-4s-f16.bin"
print(d["ffmpeg"]["url"], d["ffmpeg"]["sha256"], d["models"]["base_url"] + m, d["models"]["sha256"][m])
PY
)
curl -sSfL -o "$T/ffmpeg.zip" "$FURL"
echo "$FSHA  $T/ffmpeg.zip" | sha256sum -c -
python3 - "$T/ffmpeg.zip" "$C/tools/ffmpeg.exe" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
n = [x for x in z.namelist() if x.endswith("/ffmpeg.exe") or x == "ffmpeg.exe"][0]
open(sys.argv[2], "wb").write(z.read(n))
PY
curl -sSfL -o "$C/models/ggml-model-htdemucs-4s-f16.bin" "$MURL"
echo "$MSHA  $C/models/ggml-model-htdemucs-4s-f16.bin" | sha256sum -c -

echo "== 3. Testton erzeugen (20 s, Schlagzeug-artig + Bass + Ton)"
python3 - "$T/test.wav" <<'PY'
import math, random, struct, sys, wave
sr, n = 44100, 44100 * 20
w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
random.seed(1); buf = bytearray()
for i in range(n):
    t = i / sr; beat = t % 0.5
    kick = math.sin(2 * math.pi * 55 * beat) * math.exp(-beat * 18)
    hat = (random.random() * 2 - 1) * math.exp(-((t + 0.25) % 0.5) * 60) * 0.3
    bass = 0.25 * math.sin(2 * math.pi * 82.4 * t)
    tone = 0.2 * math.sin(2 * math.pi * 440 * t) * (0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * t))
    v = max(-1.0, min(1.0, 0.6 * kick + hat + bass + tone))
    s = int(v * 30000); buf += struct.pack("<hh", s, s)
w.writeframes(bytes(buf)); w.close()
PY

echo "== 4. Umwandeln mit StemCLI"
WINPFAD="Z:$(echo "$T/test.wav" | tr '/' '\\')"
"$AI" --cli "$WINPFAD" 2>&1 | grep -v "%\|THREAD" | tee "$T/cli.log" || true
grep -q "1 erfolgreich\|1 succeeded\|1 successful" "$T/cli.log" || { echo "FEHLER: Umwandlung nicht erfolgreich"; exit 1; }
test -s "$T/test.stem.mp4" || { echo "FEHLER: test.stem.mp4 fehlt"; exit 1; }
GROESSE=$(stat -c %s "$T/test.stem.mp4")
echo "test.stem.mp4: $GROESSE Bytes"
[ "$GROESSE" -gt 1000000 ] || { echo "FEHLER: Stem-Datei zu klein"; exit 1; }
# 5 Tonspuren (Master + 4 Stems)? "trak"-Kästchen im MP4 zählen
SPUREN=$(python3 -c "import sys; print(open(sys.argv[1],'rb').read().count(b'trak'))" "$T/test.stem.mp4")
echo "Spuren: $SPUREN"
[ "$SPUREN" -ge 5 ] || { echo "FEHLER: weniger als 5 Spuren"; exit 1; }

# == 5. Bilder bei 100 % und 150 % (nur wenn Xvfb + xdotool da sind)
if [ -n "$BILDER" ] && command -v Xvfb >/dev/null && command -v xdotool >/dev/null; then
  Xvfb :77 -screen 0 1920x1080x24 >/dev/null 2>&1 &
  XPID=$!
  export DISPLAY=:77
  sleep 3
  warte_fenster() {  # Fenster mit Titel $1 abwarten (max. 90 s)
    for _ in $(seq 1 90); do xdotool search --name "$1" >/dev/null 2>&1 && return 0; sleep 1; done
    return 1
  }
  for DPI in 96 144; do
    F=$(python3 -c "print($DPI/96)")
    export STEMMAKER_DATA="$HOME/data-$DPI" STEMMAKER_DPI=$DPI
    mkdir -p "$STEMMAKER_DATA/prefix/drive_c/StemMaker"
    "$AI" >/dev/null 2>&1 &
    klick() {  # Fenster-ID, x, y (Lage bei 100 %, wird mit F umgerechnet)
      eval "$(xdotool getwindowgeometry --shell "$1")"
      xdotool mousemove $((X + $(python3 -c "print(round($2*$F))"))) $((Y + $(python3 -c "print(round($3*$F))"))) click 1
    }
    if warte_fenster "Language"; then
      sleep 3; import -window root "$BILDER/${DPI}dpi-1-Sprache.png"
      klick "$(xdotool search --name "Language" | head -n 1)" 272 278   # OK
    fi
    if warte_fenster "Please|Bitte"; then
      sleep 3
      W=$(xdotool search --name "Please|Bitte" | head -n 1)
      import -window root "$BILDER/${DPI}dpi-2-Hinweise.png"
      klick "$W" 18 453; sleep 1    # Häkchen "gelesen"
      klick "$W" 377 492            # "Einverstanden - StemMaker starten"
    fi
    if warte_fenster "Traktor Stems"; then
      sleep 15; import -window root "$BILDER/${DPI}dpi-3-Hauptfenster.png"
    fi
    # alles von Wine beenden, bevor die nächste Stufe startet
    pkill -f '\.exe' 2>/dev/null || true
    pkill -f wineserver 2>/dev/null || true
    sleep 5
  done
  kill $XPID 2>/dev/null || true
  ls -la "$BILDER"
fi

echo "== AppImage-Test bestanden"
