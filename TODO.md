# TODO – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Die kurze Liste für den Alltag: **Was muss als Nächstes getestet, entschieden oder gebaut werden?**
Der grössere Plan steht in der [ROADMAP](ROADMAP.md), Erledigtes im [CHANGELOG](CHANGELOG.md).

Regel: Wird etwas erledigt, kommt es hier raus und ins CHANGELOG. Kommt eine neue Aufgabe dazu, wird sie hier eingetragen.

Zuletzt aktualisiert: 6. Oktober 2026

---

## 🧪 Speedy testet

- [ ] **Release-ZIP 1.7 testen** (neue ZIP mit den Fehlerkorrekturen aus dem Wine-Test kommt nach dem Merge): `StemMaker-1.7.zip` in einen neuen Ordner entpacken und starten. Erststart-Fenster (Text passt?), eine Datei umwandeln (Explorer geht mit der fertigen Datei auf, Club-Pegel und Bass-Fix an), „Anhören“ öffnet den StemPlayer 1.3, Info → Lizenzen. Fenster schliessen geht sofort zu. Die Update-Prüfung lässt sich erst mit 1.7.1 echt testen (unter Wine mit Test-Server geprüft).
- [ ] **Lange Pfade (über 260 Zeichen):** einen sehr tief verschachtelten Ordner mit einer MP3 anlegen (Pfad länger als 260 Zeichen) und umwandeln. Unter Wine nicht prüfbar, im Manifest fehlt `longPathAware`. Geht es nicht, wird das nachgebaut.
- [ ] **Hörvergleich v3 gegen v4:** denselben Track mit `hdemucs_mmi` (v3) und dem Standard-Modell umwandeln und in Traktor vergleichen (Vocals solo, Instrumental, Drums). Ergebnis entscheidet unten über das Standard-Modell.
  Nacheinander umwandeln, nicht gleichzeitig. Achtung: Die fertige Datei heisst bei beiden Modellen gleich (`Song.stem.mp4`). Nach dem ersten Lauf die Datei umbenennen (z. B. `Song v4.stem.mp4`) oder für den zweiten Lauf einen anderen Zielordner wählen, sonst wird sie übersprungen bzw. überschrieben.

- [ ] **Erste automatisch gebaute Testversion:** `StemMaker.exe` und `StemPlayer.exe` aus dem Vor-Release des Build-PRs unter Windows kurz starten (Links in [docs/TESTVERSIONEN.md](docs/TESTVERSIONEN.md)). Bestätigt, dass der Build auf GitHub genauso funktioniert wie der von Hand.

## 🧑‍⚖️ Speedy entscheidet oder macht von Hand

- [ ] **v3 als Standard-Modell?** – erst nach dem Hörvergleich oben.
- [ ] **Prüfsummen der htdemucs_ft-Modelle** (ohne Eile): v4 und v3 stehen in `update.json`. Die vier ft-Dateien fehlen noch, weil sie auf Speedys PC nicht geladen sind. Wer sie hat: Prüfsummen schicken, dann kommen sie dazu.
- [ ] **Release 1.7 anlegen:** Tag `v1.7`, Titel „Elospeed StemMaker 1.7“, `StemMaker-1.7.zip` anhängen, als neuestes Release markieren. Danach Bescheid geben, dann wird `update.json` auf 1.7 gestellt (siehe [docs/UPDATE-JSON.md](docs/UPDATE-JSON.md)).

## 🔨 Elospeed baut als Nächstes

Reihenfolge = Vorschlag, Speedy kann umstellen.

1. [ ] **StemPlayer: Deutsch/Englisch** über `lang\` und Einstellungen in `StemMaker.ini`, wie StemCLI.
2. [ ] **StemPlayer: High-DPI** – saubere Darstellung bei 125 % / 150 % Bildschirm-Skalierung.

Kleinigkeit ohne Eile: Im StemPlayer springt zweimal sehr schnell Pfeiltaste nur einmal um 5 s (schon seit 1.1).

## 🔀 Offene Pull Requests

- Projektseite (Ordner `site/`, Englisch und Deutsch, mit Screenshots).
- Tags vollständig übernehmen: BPM, Tonart, Label und ISRC aus der Quelldatei in die Stem-Datei.
