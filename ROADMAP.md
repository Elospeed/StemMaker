# Roadmap – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Woran gerade gearbeitet wird und was als Nächstes geplant ist. Fertiges wandert ins [CHANGELOG](CHANGELOG.md).
Die kurze Liste „was ist als Nächstes zu tun“ (Tests, Entscheidungen, nächste Bauschritte) steht in der [TODO](TODO.md).
Die lange Ideen-Sammlung (ohne Zusage) steht in [docs/IDEEN.md](docs/IDEEN.md).

Zuletzt aktualisiert: 4. Oktober 2026

---

## 🔨 In Arbeit

- **StemPlayer aus StemMaker starten und Ordner öffnen** – Knopf „Anhören“, Doppelklick in der Liste, Explorer mit der fertigen Datei nach der Umwandlung (Testversion, Speedy testet).

## 📋 Geplant für Version 1.7

- **Update-Prüfung beim Start** – liest `update.json` aus dem Repository (max. 5 s, abschaltbar). Dialog „Jetzt / Später / Version überspringen“, Download mit Prüfsumme, laufende Exe wird zu `.exe.old`. INI, Warteschlange, Logs, Modelle und ffmpeg bleiben erhalten. Nie während einer Konvertierung.
- **Feste ffmpeg-Version** als eigene Release im Repository (mit Lizenztext und Quellcode, LGPL) statt täglich „latest“.
- **SHA-256-Prüfsummen** für alle Downloads (ffmpeg, Modelle, Updates).
- **Download-Adressen in `update.json`** – zieht eine Datei um, muss nur diese Datei auf GitHub geändert werden.
- **THIRD-PARTY-NOTICES im Info-Fenster** anzeigen.
- **Erststart-Dialog** mit Haftungsausschluss und Lizenzhinweis (MIT, demucs, ffmpeg, Modelle). Häkchen setzen und bestätigen, gebunden an die PC-Kennung: Wird der Ordner auf einen anderen PC kopiert, kommt die Frage erneut (kein Kopierschutz).

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
