# TODO – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Die kurze Liste für den Alltag: **Was muss als Nächstes getestet, entschieden oder gebaut werden?**
Der grössere Plan steht in der [ROADMAP](ROADMAP.md), Erledigtes im [CHANGELOG](CHANGELOG.md).

Regel: Wird etwas erledigt, kommt es hier raus und ins CHANGELOG. Kommt eine neue Aufgabe dazu, wird sie hier eingetragen.

Zuletzt aktualisiert: 3. Oktober 2026

---

## 🧪 Speedy testet

- [ ] **Nur ein StemMaker gleichzeitig:** Testversion [`Temp/StemMaker/1.6-Test/StemMaker.exe`](Temp/StemMaker/1.6-Test/) in eine StemMaker-1.6-Installation kopieren, StemMaker starten und ein zweites Mal starten. Erwartet: Hinweis „StemMaker läuft schon“, danach kommt das offene Fenster nach vorne (auch wenn es minimiert war).
- [ ] **Hörvergleich v3 gegen v4:** denselben Track mit `hdemucs_mmi` (v3) und dem Standard-Modell umwandeln und in Traktor vergleichen (Vocals solo, Instrumental, Drums). Ergebnis entscheidet unten über das Standard-Modell.
  Nacheinander umwandeln, nicht gleichzeitig. Achtung: Die fertige Datei heisst bei beiden Modellen gleich (`Song.stem.mp4`). Nach dem ersten Lauf die Datei umbenennen (z. B. `Song v4.stem.mp4`) oder für den zweiten Lauf einen anderen Zielordner wählen, sonst wird sie übersprungen bzw. überschrieben.

## 🧑‍⚖️ Speedy entscheidet oder macht von Hand

- [ ] **v3 als Standard-Modell?** – erst nach dem Hörvergleich oben.
- [ ] **Testversionen künftig wo?** Weiter im Ordner `Temp/` im Repo (bleibt für immer im Git-Verlauf) oder als GitHub-Pre-Release (Download neben dem Code). Empfehlung: Pre-Releases.
- [ ] **ffmpeg-Release anlegen**, sobald die feste ffmpeg-Version für 1.7 vorbereitet ist (Releases erstellt Speedy selbst).

## 🔨 Elospeed baut als Nächstes

Reihenfolge = Vorschlag, Speedy kann umstellen.

1. [ ] **StemPlayer in StemMaker einbinden:** Knopf „Anhören“ im Hauptfenster, öffnet die fertige Stem-Datei in `AddOns\StemPlayer.exe`.
2. [ ] **StemPlayer: Deutsch/Englisch** über `lang\` und Einstellungen in `StemMaker.ini`, wie StemCLI.
3. [ ] **StemPlayer: High-DPI** – saubere Darstellung bei 125 % / 150 % Bildschirm-Skalierung.
4. [ ] **1.7: Update-Prüfung beim Start** über `update.json` (Details in der [ROADMAP](ROADMAP.md)).
5. [ ] **1.7: feste ffmpeg-Version + SHA-256-Prüfsummen** für alle Downloads, Download-Adressen in `update.json`.
6. [ ] **1.7: THIRD-PARTY-NOTICES im Info-Fenster** anzeigen.
7. [ ] **Beta-Hinweis** oben in README und LIESMICH entfernen (Traktor-Test ist erledigt).

Kleinigkeit ohne Eile: Im StemPlayer springt zweimal sehr schnell Pfeiltaste nur einmal um 5 s (schon seit 1.1).

## 🔀 Offene Pull Requests

- Nur ein StemMaker gleichzeitig (Sperre beim Start) – wartet auf Speedys Test und Merge.
