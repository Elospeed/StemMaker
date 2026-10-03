# Roadmap – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Woran gerade gearbeitet wird und was als Nächstes geplant ist. Fertiges wandert ins [CHANGELOG](CHANGELOG.md).
Die lange Ideen-Sammlung (ohne Zusage) steht in [docs/IDEEN.md](docs/IDEEN.md).

Zuletzt aktualisiert: 3. Oktober 2026

---

## 🔨 In Arbeit

- **StemPlayer: neues Aussehen** – Design „Traktor Dark“ (dunkel, Stem-Farben wie in Traktor).

## 📋 Geplant für Version 1.7

- **Update-Prüfung beim Start** – liest `update.json` aus dem Repository (max. 5 s, abschaltbar). Dialog „Jetzt / Später / Version überspringen“, Download mit Prüfsumme, laufende Exe wird zu `.exe.old`. INI, Warteschlange, Logs, Modelle und ffmpeg bleiben erhalten. Nie während einer Konvertierung.
- **Feste ffmpeg-Version** als eigene Release im Repository (mit Lizenztext und Quellcode, LGPL) statt täglich „latest“.
- **SHA-256-Prüfsummen** für alle Downloads (ffmpeg, Modelle, Updates).
- **Download-Adressen in `update.json`** – zieht eine Datei um, muss nur diese Datei auf GitHub geändert werden.
- **THIRD-PARTY-NOTICES im Info-Fenster** anzeigen.

## 📋 Geplant für den StemPlayer

- Knopf „Anhören“ direkt in StemMaker.
- Deutsch/Englisch über `lang\` wie StemMaker.
- Einstellungen in `StemMaker.ini` (wie StemCLI).
- Saubere Darstellung bei hoher Bildschirm-Skalierung (High-DPI).
- Später: Wellenform-Anzeige, Loop A–B.

## ❓ Offene Entscheidungen

- **v3 (hdemucs_mmi) als Standard-Modell?** – fast doppelt so schnell. Entscheidung nach Hörvergleich in Traktor.

## ⏸️ Zurückgestellt

- **„Summe der Stems = Original“** (Other = Original − Drums − Bass − Vocals) – bleibt vorerst wie bisher, evtl. in einer späteren Version (Entscheidung vom 3. Oktober 2026).

## 💡 Später / Ideen

- Einzelnen Stem (z. B. Vocals oder Drum-Beat) als eigene MP3/WAV exportieren – für Traktor Remix Decks und Loops.
- Hotcues und Beatgrid aus Traktors `collection.nml` übernehmen.
- Grafikkarte (ONNX Runtime + DirectML) und Mel-Band RoFormer für sauberere Vocals.
- Weitere Sprachen, Code-Signing.

Mehr in [docs/IDEEN.md](docs/IDEEN.md).
