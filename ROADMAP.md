# Roadmap – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Woran gerade gearbeitet wird und was als Nächstes geplant ist. Fertiges wandert ins [CHANGELOG](CHANGELOG.md).
Die kurze Liste „was ist als Nächstes zu tun“ (Tests, Entscheidungen, nächste Bauschritte) steht in der [TODO](TODO.md).
Die lange Ideen-Sammlung (ohne Zusage) steht in [docs/IDEEN.md](docs/IDEEN.md).

Zuletzt aktualisiert: 4. Oktober 2026

---

## 🔨 In Arbeit

- **StemPlayer aus StemMaker starten und Ordner öffnen** – Knopf „Anhören“, Doppelklick in der Liste, Explorer mit der fertigen Datei nach der Umwandlung (Testversion, Speedy testet).
- **Update-Prüfung über `update.json`, feste ffmpeg-Version, SHA-256 für alle Downloads** (gebaut, ffmpeg-Release ist online).
- **Erststart-Fenster** (Haftungsausschluss, Lizenzen, einmal pro PC) und **Info → Lizenzen** (Testversion, Speedy testet).

## 📋 Geplant für Version 1.7

Alles gebaut, siehe „In Arbeit“. Offen ist nur noch das Release 1.7 von Speedy (ffmpeg-Release ist seit 5. Oktober 2026 online).

## 📋 Geplant für den StemPlayer

- Deutsch/Englisch über `lang\` wie StemMaker.
- Einstellungen in `StemMaker.ini` (wie StemCLI).
- Saubere Darstellung bei hoher Bildschirm-Skalierung (High-DPI).
- Später: Wellenform-Anzeige, Loop A–B.

## ❓ Offene Entscheidungen

- **v3 (hdemucs_mmi) als Standard-Modell?** – fast doppelt so schnell. Entscheidung nach Hörvergleich in Traktor.
- **Testversionen:** weiter im Ordner `Temp/` oder als GitHub-Pre-Release?

## ⏸️ Zurückgestellt

- **„Summe der Stems = Original“** (Other = Original − Drums − Bass − Vocals) – bleibt vorerst wie bisher, evtl. in einer späteren Version (Entscheidung vom 3. Oktober 2026).

## 💡 Später / Ideen

- Einzelnen Stem (z. B. Vocals oder Drum-Beat) als eigene MP3/WAV exportieren – für Traktor Remix Decks und Loops.
- Hotcues und Beatgrid aus Traktors `collection.nml` übernehmen.
- Grafikkarte (ONNX Runtime + DirectML) und Mel-Band RoFormer für sauberere Vocals.
- Weitere Sprachen.
- Code-Signing: vorerst nicht (Entscheidung 03.10.2026, Kosten lohnen sich im Anfangsstadium nicht). Stattdessen Hinweis zur Windows-Warnung in README/LIESMICH.

Mehr in [docs/IDEEN.md](docs/IDEEN.md).
