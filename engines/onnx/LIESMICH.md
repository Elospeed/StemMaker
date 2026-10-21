# StemOnnx – schnelle Trenn-Engine (in Arbeit)

[English](README.md)

StemOnnx trennt Songs mit demselben KI-Modell wie StemMaker (htdemucs = Demucs v4, auch htdemucs_ft), aber mit **ONNX Runtime** statt demucs.cpp:

- auf der **Grafikkarte** über DirectML (NVIDIA, AMD, Intel, ohne Zusatz-Installation)
- ohne passende Grafikkarte auf der **CPU**, dort etwa 4 bis 6x schneller als demucs.cpp

**Stand: getrennt von StemMaker.** StemMaker benutzt weiterhin demucs.cpp. Nichts in diesem Ordner wird in StemMaker eingebaut, bevor die Engine fertig getestet ist. Die bewährte demucs.cpp-Engine bleibt danach als Rückfall erhalten.

## Qualität

Gleiche Qualität wie das Original-demucs, nur schneller. Gemessen am 20.10.2026 mit Kungs – Clap Your Hands (3:10):

| Vergleich | drums | bass | other | vocals |
|---|---|---|---|---|
| StemOnnx (CPU, Windows, Werkstatt-PC) gegen Original-demucs in PyTorch | 81 dB | 67 dB | 73 dB | 88 dB |
| StemOnnx (CPU) gegen Original-demucs in PyTorch | 81 dB | 67 dB | 73 dB | 88 dB |
| StemOnnx (CPU) gegen StemGPU auf RTX 4060 Ti (16 Bit) | 73 dB | 62 dB | 66 dB | 66 dB |

Über 50 dB Abstand ist nur noch Rechen-Rundung, nicht hörbar. Zum Vergleich: demucs.cpp selbst weicht vom Original um 12 bis 24 dB ab, weil es den Song mit einem zufälligen Versatz und anders aufgeteilt rechnet. Kein Fehler, aber StemOnnx ist näher am Original.

Bewusst **nicht** benutzt, weil die Qualität leidet (Versuch vom 13.10.2026): int8, fp16, weniger Überlappung.

## Tempo

| PC | Gerät | Sekunden pro Songminute |
|---|---|---|
| Cloud, 4 Kerne (Wine) | demucs.cpp (wie StemMaker) | 195 |
| Cloud, 4 Kerne (Wine) | StemOnnx CPU | 31 |
| Werkstatt, i5-2500 (Windows, 20.10.2026) | demucs.cpp v4 (wie StemMaker) | 440 bis 584 |
| Werkstatt, i5-2500 (Windows, 20.10.2026) | StemOnnx CPU | 52 |
| i7-12700KF (StemGPU-Versuch) | CPU | 15 |
| i7-12700KF (StemGPU-Versuch) | RTX 4060 Ti | 4 |
| Clubraum-PC, zum Vergleich | Traktor Pro 4 | 47 |

## Aufruf

Die ersten vier Parameter sind dieselben wie bei demucs.cpp, damit StemMaker die Engine später einfach austauschen kann:

```
StemOnnx.exe <modell> <eingang.wav> <ausgabeordner> [teile] [--geraet auto|gpu|cpu] [--gpu <nummer>] [--kerne <anzahl>] [--ergebnis <datei>] [--neu-pruefen]
```

- `<modell>`: `ggml-model-htdemucs-4s-f16.bin` aus `StemMaker\models`, oder für htdemucs_ft der Ordner mit den 4 ft-Dateien
- `[teile]`: wird angenommen, aber nicht gebraucht (ONNX Runtime nutzt alle Kerne selbst)
- `--geraet auto` (Standard): die Grafikkarte wird nur genommen, wenn sie einen Probe-Abschnitt **richtig** (Vergleich mit der CPU, mindestens 40 dB) **und schneller** als die CPU rechnet. Sonst CPU. Der Probe-Abschnitt wird mitbenutzt, nicht weggeworfen.
- Fällt die Grafikkarte mitten im Song aus (z. B. setzt Windows eine schwache Karte zurück), rechnet StemOnnx auf der CPU weiter.
- Das Ergebnis der Prüfung merkt sich StemOnnx in `%LOCALAPPDATA%\StemOnnx\geraet.txt`, zusammen mit Name und Treiber-Version der Grafikkarte. Hat die Karte versagt, wird sie beim nächsten Start gleich übersprungen (Werkstatt-PC mit GT 1030: 1,5 statt 28,5 s Start). Hat sie bestanden, entfällt beim nächsten Start der Vergleichs-Abschnitt auf der CPU (nur noch die Plausibilitätsprüfung), das spart auf schnellen PCs 1 bis 2 s pro Song. Nach einem Treiber-Update oder mit `--neu-pruefen` wird wieder voll geprüft. Ohne echte Grafikkarte wird gar nicht erst probiert.
- Ergebnis: `target_0_drums.wav`, `target_1_bass.wav`, `target_2_other.wav`, `target_3_vocals.wav` (32-Bit-Float) wie bei demucs.cpp, Fortschritt als `( 12.345%)`-Zeilen wie bei demucs.cpp.
- hdemucs_mmi (v3) wird nicht unterstützt: Exit-Code 10, dann bleibt es bei demucs.cpp.

## Modell: wir liefern keine Gewichte mit

Im Paket liegt nur das **Gerüst** `htdemucs-geruest.onnx`: der Aufbau des Netzes ohne ein einziges Gewicht (6 MB), dazu die Liste der Gewichte `htdemucs-geruest.txt`. Beim Start liest StemOnnx die Gewichte aus der ggml-Datei, die StemMaker ohnehin von der Originalquelle lädt, und gibt sie ONNX Runtime direkt im Arbeitsspeicher. Es wird nichts auf die Festplatte geschrieben.

Geprüft: Das Gerüst aus Zufallswerten ist Knoten für Knoten identisch mit dem Gerüst aus dem echten Modell, es steckt also nichts vom Modell darin. Die Stems sind bitgenau gleich wie mit dem vollständigen ONNX-Modell aus dem StemGPU-Versuch.

## Ordner

| Pfad | Inhalt |
|---|---|
| `src/stemonnx.c` | das Programm (C, ein File, lädt onnxruntime.dll zur Laufzeit) |
| `modell/` | Gerüst und Gewichts-Liste (von `werkzeug/geruest_bauen.py` erzeugt) |
| `werkzeug/geruest_bauen.py` | baut das Gerüst neu (braucht torch, onnx, demucs, demucs-onnx, einops) |
| `werkzeug/referenz_demucs.py` | trennt mit dem Original-demucs (PyTorch) als Referenz |
| `werkzeug/stems_vergleichen.py` | Abstand zwischen zwei Stem-Ordnern in dB |
| `test/Test-starten.bat` | Test auf Windows: Musikdatei draufziehen |
| `build.sh` | baut alles nach `dist/StemOnnx/` |

## Bauen

Unter Linux mit mingw (`gcc-mingw-w64-x86-64-posix`):

```
cd engines/onnx
./build.sh
```

Das Skript lädt ONNX Runtime 1.24.4 (DirectML) und DirectML 1.15.4 von nuget.org und prüft deren Prüfsummen. Auf GitHub baut der Workflow „StemOnnx“ das Paket bei jeder Änderung in diesem Ordner.

## Herkunft

Entstanden aus dem Versuch StemGPU (12. und 13.10.2026). Die Export-Anpassungen für htdemucs stammen aus dem Paket [demucs-onnx](https://pypi.org/project/demucs-onnx/) (MIT). Demucs: Meta (MIT). ONNX Runtime und DirectML: Microsoft (Lizenzen im Paket unter `lizenzen/`).

## Offen

- Test auf mehr PCs (Grafikkarten von AMD und Intel, ältere CPUs ohne AVX2)
- htdemucs_ft mit echten ft-Modellen testen
- CUDA als Zusatz für NVIDIA (grosses Paket, nur wenn DirectML deutlich langsamer ist)
- Einbau in StemMaker als wählbare Engine mit demucs.cpp als Rückfall
