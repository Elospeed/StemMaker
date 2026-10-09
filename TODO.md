# TODO – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Die kurze Liste für den Alltag: **Was muss als Nächstes getestet, entschieden oder gebaut werden?**
Der grössere Plan steht in der [ROADMAP](ROADMAP.md), Erledigtes im [CHANGELOG](CHANGELOG.md).

Regel: Wird etwas erledigt, kommt es hier raus und ins CHANGELOG. Kommt eine neue Aufgabe dazu, wird sie hier eingetragen.

Zuletzt aktualisiert: 9. Oktober 2026

---

## 🧪 Speedy testet

- [ ] **Release 1.7 testen** (ZIP von der Release-Seite): `StemMaker-1.7.zip` in einen neuen Ordner entpacken und starten. Erststart-Fenster (Text passt?), eine Datei umwandeln (Explorer geht mit der fertigen Datei auf, Club-Pegel und Bass-Fix an), „Anhören“ öffnet den StemPlayer 1.3, Info → Lizenzen. Fenster schliessen geht sofort zu. Die Update-Prüfung lässt sich erst mit 1.7.1 echt testen (unter Wine mit Test-Server geprüft).
- [ ] **Hörvergleich v3 gegen v4:** denselben Track mit `hdemucs_mmi` (v3) und dem Standard-Modell umwandeln und in Traktor vergleichen (Vocals solo, Instrumental, Drums). Ergebnis entscheidet unten über das Standard-Modell.
  Nacheinander umwandeln, nicht gleichzeitig. Achtung: Die fertige Datei heisst bei beiden Modellen gleich (`Song.stem.mp4`). Nach dem ersten Lauf die Datei umbenennen (z. B. `Song v4.stem.mp4`) oder für den zweiten Lauf einen anderen Zielordner wählen, sonst wird sie übersprungen bzw. überschrieben.

- [ ] **StemPlayer 1.4: falsche Datei reinziehen** (Testversion aus dem Vor-Release `test-main`, Links in [docs/TESTVERSIONEN.md](docs/TESTVERSIONEN.md)): einen Track laden und abspielen, dann eine MP3, ein normales MP4-Video und einen Ordner reinziehen. Erwartet: jedes Mal eine Meldung (DE/EN), der Track spielt weiter. Danach eine echte `.stem.mp4` reinziehen, die lädt wie gewohnt.
- [ ] **Erste automatisch gebaute Testversion:** `StemMaker.exe` und `StemPlayer.exe` aus dem Vor-Release des Build-PRs unter Windows kurz starten (Links in [docs/TESTVERSIONEN.md](docs/TESTVERSIONEN.md)). Bestätigt, dass der Build auf GitHub genauso funktioniert wie der von Hand.

## 🧑‍⚖️ Speedy entscheidet oder macht von Hand

- [ ] **v3 als Standard-Modell?** – erst nach dem Hörvergleich oben.
- [ ] **Projektseite einschalten:** Settings → Pages → Source „GitHub Actions“. Danach läuft der Workflow „Projektseite“ und die Seite ist unter https://elospeed.github.io/StemMaker/ erreichbar. Anschliessend in der Google Search Console als URL-Präfix anmelden und `sitemap.xml` einreichen.
- [ ] **StemMaker bei winget einreichen:** Manifest für 1.7 und Schritt-für-Schritt-Anleitung liegen im Projektordner (`winget/`). Erst lokal mit `winget install --manifest` testen (dabei schauen, ob die SmartScreen-Warnung ausbleibt), dann Pull Request in `microsoft/winget-pkgs`. Jede neue Version braucht danach ein neues Manifest.
- [ ] **Prüfsummen der htdemucs_ft-Modelle** (ohne Eile): v4 und v3 stehen in `update.json`. Die vier ft-Dateien fehlen noch, weil sie auf Speedys PC nicht geladen sind. Wer sie hat: Prüfsummen schicken, dann kommen sie dazu.

## 🔨 Elospeed baut als Nächstes

Reihenfolge = Vorschlag, Speedy kann umstellen.

1. [ ] **StemPlayer: Deutsch/Englisch** über `lang\` und Einstellungen in `StemMaker.ini`, wie StemCLI.
2. [ ] **StemPlayer: High-DPI** – saubere Darstellung bei 125 % / 150 % Bildschirm-Skalierung.
3. [ ] **Eigener Datenordner bei winget-Installation** (vor 1.7.1): `winget upgrade` und `winget uninstall` löschen den ganzen Programmordner, also auch ffmpeg, Modelle, `StemMaker.ini`, Warteschlange und `logs\statistik.csv`. Liegt StemMaker unter `\WinGet\Packages\`, sollen diese Dateien nach `%LOCALAPPDATA%\StemMaker\`. Die eingebaute Update-Funktion verweist dann auf `winget upgrade`.

Kleinigkeit ohne Eile: Im StemPlayer springt zweimal sehr schnell Pfeiltaste nur einmal um 5 s (schon seit 1.1).

## 🔀 Offene Pull Requests

- Installer (Inno Setup): Setup-Exe neben dem ZIP, für winget.
- Ideen: „Stem-Werkstatt“ als eigenes AddOn (eigene Stems verpacken, Stem-Datei zerschneiden, 5.1 auf vier Decks), nur IDEEN.md.
