# TODO – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Die kurze Liste für den Alltag: **Was muss als Nächstes getestet, entschieden oder gebaut werden?**
Der grössere Plan steht in der [ROADMAP](ROADMAP.md), Erledigtes im [CHANGELOG](CHANGELOG.md).

Regel: Wird etwas erledigt, kommt es hier raus und ins CHANGELOG. Kommt eine neue Aufgabe dazu, wird sie hier eingetragen.

Zuletzt aktualisiert: 8. Oktober 2026

---

## 🧪 Speedy testet

- [ ] **Release 1.7 testen** (ZIP von der Release-Seite): `StemMaker-1.7.zip` in einen neuen Ordner entpacken und starten. Erststart-Fenster (Text passt?), eine Datei umwandeln (Explorer geht mit der fertigen Datei auf, Club-Pegel und Bass-Fix an), „Anhören“ öffnet den StemPlayer 1.3, Info → Lizenzen. Fenster schliessen geht sofort zu. Die Update-Prüfung lässt sich erst mit 1.7.1 echt testen (unter Wine mit Test-Server geprüft).
- [ ] **Lange Pfade (über 260 Zeichen):** einen sehr tief verschachtelten Ordner mit einer MP3 anlegen (Pfad länger als 260 Zeichen) und umwandeln. Unter Wine nicht prüfbar, im Manifest fehlt `longPathAware`. Geht es nicht, wird das nachgebaut.
- [ ] **Hörvergleich v3 gegen v4:** denselben Track mit `hdemucs_mmi` (v3) und dem Standard-Modell umwandeln und in Traktor vergleichen (Vocals solo, Instrumental, Drums). Ergebnis entscheidet unten über das Standard-Modell.
  Nacheinander umwandeln, nicht gleichzeitig. Achtung: Die fertige Datei heisst bei beiden Modellen gleich (`Song.stem.mp4`). Nach dem ersten Lauf die Datei umbenennen (z. B. `Song v4.stem.mp4`) oder für den zweiten Lauf einen anderen Zielordner wählen, sonst wird sie übersprungen bzw. überschrieben.

- [ ] **StemPlayer 1.4: falsche Datei reinziehen** (Testversion aus dem Vor-Release `test-main`, Links in [docs/TESTVERSIONEN.md](docs/TESTVERSIONEN.md)): einen Track laden und abspielen, dann eine MP3, ein normales MP4-Video und einen Ordner reinziehen. Erwartet: jedes Mal eine Meldung (DE/EN), der Track spielt weiter. Danach eine echte `.stem.mp4` reinziehen, die lädt wie gewohnt.
- [ ] **Installer testen** (`StemMaker-Setup-Test.exe` aus dem Vor-Release des Installer-PRs, Links in [docs/TESTVERSIONEN.md](docs/TESTVERSIONEN.md)): installieren (SmartScreen-Warnung? Startmenü-Eintrag „StemMaker“ und „StemPlayer“ da?), StemMaker starten, Modell laden, eine Datei umwandeln. Dann das Setup noch einmal drüber installieren: Modell und Einstellungen müssen bleiben. Zum Schluss unter „Apps & Features“ deinstallieren, die Frage nach Modellen und Einstellungen mit „Ja“ beantworten: Ordner `%LOCALAPPDATA%\Programs\StemMaker` ist danach weg.
- [ ] **Erste automatisch gebaute Testversion:** `StemMaker.exe` und `StemPlayer.exe` aus dem Vor-Release des Build-PRs unter Windows kurz starten (Links in [docs/TESTVERSIONEN.md](docs/TESTVERSIONEN.md)). Bestätigt, dass der Build auf GitHub genauso funktioniert wie der von Hand.

## 🧑‍⚖️ Speedy entscheidet oder macht von Hand

- [ ] **v3 als Standard-Modell?** – erst nach dem Hörvergleich oben.
- [ ] **Projektseite einschalten:** Settings → Pages → Source „GitHub Actions“. Danach läuft der Workflow „Projektseite“ und die Seite ist unter https://elospeed.github.io/StemMaker/ erreichbar. Anschliessend in der Google Search Console als URL-Präfix anmelden und `sitemap.xml` einreichen.
- [ ] **Setup für 1.7 erzeugen** (nach dem Merge des Installer-PRs): Actions → „Setup zum Release“ → „Run workflow“, Tag `v1.7`. Der Lauf baut `StemMaker-1.7-Setup.exe`, testet es und hängt es ans Release 1.7. Ab 1.7.1 passiert das beim Veröffentlichen des Releases von selbst.
- [ ] **StemMaker bei winget einreichen:** mit dem Setup (Manifest-Typ `inno`), nicht mit dem ZIP. Beim ZIP-Paket löscht `winget upgrade` den ganzen Ordner samt Modellen und Einstellungen, beim Setup nicht. Das Manifest wird neu vorbereitet, sobald das Setup am Release hängt (die Prüfsumme steht dann in der Zusammenfassung des Workflow-Laufs). Danach Pull Request in `microsoft/winget-pkgs`, Anleitung im Projektordner (`winget/`).
- [ ] **Prüfsummen der htdemucs_ft-Modelle** (ohne Eile): v4 und v3 stehen in `update.json`. Die vier ft-Dateien fehlen noch, weil sie auf Speedys PC nicht geladen sind. Wer sie hat: Prüfsummen schicken, dann kommen sie dazu.

## 🔨 Elospeed baut als Nächstes

Reihenfolge = Vorschlag, Speedy kann umstellen.

1. [ ] **StemPlayer: Deutsch/Englisch** über `lang\` und Einstellungen in `StemMaker.ini`, wie StemCLI.
2. [ ] **StemPlayer: High-DPI** – saubere Darstellung bei 125 % / 150 % Bildschirm-Skalierung.
3. [ ] **Update-Funktion und Installer:** Nach einem Update aus StemMaker heraus zeigt „Apps & Features“ (und `winget list`) noch die alte Versionsnummer. Die Update-Funktion soll sie im Registry-Eintrag des Installers nachführen, falls StemMaker per Setup installiert wurde.

Kleinigkeit ohne Eile: Im StemPlayer springt zweimal sehr schnell Pfeiltaste nur einmal um 5 s (schon seit 1.1).

## 🔀 Offene Pull Requests

- Installer (Inno Setup): Setup-Exe neben dem ZIP, für winget.
