# TODO – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Die kurze Liste für den Alltag: **Was muss als Nächstes getestet, entschieden oder gebaut werden?**
Der grössere Plan steht in der [ROADMAP](ROADMAP.md), Erledigtes im [CHANGELOG](CHANGELOG.md).

Regel: Wird etwas erledigt, kommt es hier raus und ins CHANGELOG. Kommt eine neue Aufgabe dazu, wird sie hier eingetragen.

Zuletzt aktualisiert: 4. Oktober 2026

---

## 🧪 Speedy testet

- [ ] **Anhören und Ordner öffnen (1.7):** Testversion `Temp/StemMaker/1.7-anhoeren/StemMaker.exe` in den StemMaker-Ordner kopieren (neben die alte Exe, `AddOns\StemPlayer.exe` muss da sein). Eine Datei umwandeln: Danach geht der Explorer mit der fertigen Datei markiert auf. „Anhören“ startet den StemPlayer mit dem Öffnen-Dialog in diesem Ordner, Doppelklick in der Liste öffnet die Datei direkt. Dafür den neuen StemPlayer 1.3 aus `Temp/StemPlayer/1.3/` nach `AddOns\` kopieren.
- [ ] **Club-Pegel und Bass-Fix:** Testversion umwandeln lassen (beide Häkchen sind an) und in Traktor anhören: grosse Wellenformen? Bass voller? Mit und ohne Häkchen vergleichen.
- [ ] **StemMaker lässt sich nach der Konvertierung nicht beenden:** Testversion `Temp/StemMaker/1.6.1-test/StemMaker.exe` ausprobieren: Dateien hinzufügen, umwandeln, Fenster schliessen. Es muss sofort zugehen.
- [ ] **Hörvergleich v3 gegen v4:** denselben Track mit `hdemucs_mmi` (v3) und dem Standard-Modell umwandeln und in Traktor vergleichen (Vocals solo, Instrumental, Drums). Ergebnis entscheidet unten über das Standard-Modell.
  Nacheinander umwandeln, nicht gleichzeitig. Achtung: Die fertige Datei heisst bei beiden Modellen gleich (`Song.stem.mp4`). Nach dem ersten Lauf die Datei umbenennen (z. B. `Song v4.stem.mp4`) oder für den zweiten Lauf einen anderen Zielordner wählen, sonst wird sie übersprungen bzw. überschrieben.

## 🧑‍⚖️ Speedy entscheidet oder macht von Hand

- [ ] **v3 als Standard-Modell?** – erst nach dem Hörvergleich oben.
- [ ] **Testversionen künftig wo?** Weiter im Ordner `Temp/` im Repo (bleibt für immer im Git-Verlauf) oder als GitHub-Pre-Release (Download neben dem Code). Empfehlung: Pre-Releases.
- [ ] **ffmpeg-Release anlegen**, sobald die feste ffmpeg-Version für 1.7 vorbereitet ist (Releases erstellt Speedy selbst).

## 🔨 Elospeed baut als Nächstes

Reihenfolge = Vorschlag, Speedy kann umstellen.

1. [ ] **StemPlayer: Deutsch/Englisch** über `lang\` und Einstellungen in `StemMaker.ini`, wie StemCLI.
2. [ ] **StemPlayer: High-DPI** – saubere Darstellung bei 125 % / 150 % Bildschirm-Skalierung.
3. [ ] **1.7: Update-Prüfung beim Start** über `update.json` (Details in der [ROADMAP](ROADMAP.md)).
4. [ ] **1.7: feste ffmpeg-Version + SHA-256-Prüfsummen** für alle Downloads, Download-Adressen in `update.json`.
5. [ ] **1.7: THIRD-PARTY-NOTICES im Info-Fenster** anzeigen.
6. [ ] **1.7: Erststart-Dialog** mit Haftungsausschluss und Lizenzhinweis (Häkchen + Bestätigen), gebunden an die PC-Kennung.
7. [ ] **Beta-Hinweis** oben in README und LIESMICH entfernen (Traktor-Test ist erledigt).

Kleinigkeit ohne Eile: Im StemPlayer springt zweimal sehr schnell Pfeiltaste nur einmal um 5 s (schon seit 1.1).

## 🔀 Offene Pull Requests

- Anhören im StemPlayer und Ordner öffnen nach der Umwandlung (Testversion, Speedy testet).
