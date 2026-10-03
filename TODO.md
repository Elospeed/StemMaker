# TODO – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Die kurze Liste für den Alltag: **Was muss als Nächstes getestet, entschieden oder gebaut werden?**
Der grössere Plan steht in der [ROADMAP](ROADMAP.md), Erledigtes im [CHANGELOG](CHANGELOG.md).

Regel: Wird etwas erledigt, kommt es hier raus und ins CHANGELOG. Kommt eine neue Aufgabe dazu, wird sie hier eingetragen.

Zuletzt aktualisiert: 3. Oktober 2026

---

## 🧪 Speedy testet

- [ ] **Traktor Pro 4:** Stem-Dateien aus StemMaker 1.6 in Traktor laden und prüfen (Spuren, Farben, Namen, Abspielen). Danach kann der Beta-Hinweis oben in README/LIESMICH weg.
- [ ] **Hörvergleich v3 gegen v4:** denselben Track mit `hdemucs_mmi` (v3) und dem Standard-Modell umwandeln und in Traktor vergleichen (Vocals solo, Instrumental, Drums). Ergebnis entscheidet unten über das Standard-Modell.

## 🧑‍⚖️ Speedy entscheidet oder macht von Hand

- [ ] **v3 als Standard-Modell?** – erst nach dem Hörvergleich oben.
- [ ] **Testversionen künftig wo?** Weiter im Ordner `Temp/` im Repo (bleibt für immer im Git-Verlauf) oder als GitHub-Pre-Release (Download neben dem Code). Empfehlung: Pre-Releases.
- [ ] **ffmpeg-Release anlegen**, sobald die feste ffmpeg-Version für 1.7 vorbereitet ist (Releases erstellt Speedy selbst).

## 🔨 Claude baut als Nächstes

Reihenfolge = Vorschlag, Speedy kann umstellen.

1. [ ] **StemPlayer in StemMaker einbinden:** Knopf „Anhören“ im Hauptfenster, öffnet die fertige Stem-Datei in `AddOns\StemPlayer.exe`.
2. [ ] **StemPlayer: Deutsch/Englisch** über `lang\` und Einstellungen in `StemMaker.ini`, wie StemCLI.
3. [ ] **StemPlayer: High-DPI** – saubere Darstellung bei 125 % / 150 % Bildschirm-Skalierung.
4. [ ] **1.7: Update-Prüfung beim Start** über `update.json` (Details in der [ROADMAP](ROADMAP.md)).
5. [ ] **1.7: feste ffmpeg-Version + SHA-256-Prüfsummen** für alle Downloads, Download-Adressen in `update.json`.
6. [ ] **1.7: THIRD-PARTY-NOTICES im Info-Fenster** anzeigen.

Kleinigkeit ohne Eile: Im StemPlayer springt zweimal sehr schnell Pfeiltaste nur einmal um 5 s (schon seit 1.1).

## 🔀 Offene Pull Requests

- Keine. (Stand: 3. Oktober 2026 – PR #1 bis #5 sind gemergt.)
