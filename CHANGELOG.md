# Changelog – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Was erledigt ist, pro Version, neueste oben. Was gerade läuft und geplant ist, steht in der [ROADMAP](ROADMAP.md).
Die technischen Hintergründe (Fehler und wie sie gelöst wurden) stehen im [Entwicklungslog](docs/ENTWICKLUNGSLOG.md).

---

## Unveröffentlicht

### StemMaker (kommt mit der nächsten Version)
- StemMaker liess sich manchmal nicht beenden („Keine Rückmeldung“). Ursache: Die Längen-Abfrage im Hintergrund (ffmpeg) konnte bei MP3s mit vielen Tags für immer hängen, und beim Schliessen wartete StemMaker darauf. Jetzt wird die ffmpeg-Ausgabe laufend gelesen, die Abfrage bricht nach 30 Sekunden oder beim Schliessen sofort ab.
- Nur ein StemMaker gleichzeitig: Ein zweiter Start zeigt den Hinweis „StemMaker läuft schon“ (Deutsch/Englisch) und holt das offene Fenster nach vorne. Vorher störten sich zwei laufende StemMaker gegenseitig (gemeinsame Warteschlange, Einstellungen, Logs und gleicher Name der fertigen Datei). Am 3. Oktober 2026 von Speedy unter Windows getestet, funktioniert (PR #7).
- Traktor-Pro-4-Test erledigt (Speedy, 3. Oktober 2026): Stem-Dateien aus StemMaker spielen in Traktor.
- Log pro Datei: Dateigröße, Größe der fertigen Stem-Datei und Tempo in „Sekunden pro Minute Musik“ mit Modell. Die Zusammenfassung zeigt das Tempo über alle Dateien.
- Lautheit der Master-Spur jeder fertigen Stem-Datei wird gemessen und geloggt (integrierte Lautheit in LUFS, Umfang in LU, True Peak in dBFS; Hinweis bei True Peak über 0 dBFS). Die Datei selbst wird nicht verändert.
- Neue Datei `logs\statistik.csv`: eine Zeile pro umgewandelter Datei (Größe, Länge, Quelle, Modell, Teile/Kerne, Umwandlungszeit, s pro Musikminute, RAM, Lautheit, CPU, Ergebnis) zum Auswerten in Excel. Grundlage für eine spätere Zeitschätzung vor grossen Ordnern.
- Log-Statistik und Lautheit am 3. Oktober 2026 von Speedy unter Windows getestet (i5-2500, v3, 8-min-Track): alle Werte im Log und in `statistik.csv` stimmen (PR #8).
- Neu: **Lautstärke angleichen (Club-Pegel)**, standardmässig an. Alle 5 Spuren werden gemeinsam angehoben, bis die lauteste Spitze (Master, Stems und Stem-Summe) bei ca. −1 dB liegt. Kein Limiter. Leise Quellen bekommen in Traktor dadurch grosse, lesbare Wellenformen. Abschaltbar im Fenster und mit `--no-normalize` in StemCLI.
- Neu: **Bass-Fix**, standardmässig an. Tiefbass unter 80 Hz wandert von „Other“ in den Bass-Stem (Tiefpass vorwärts und rückwärts, damit die Phase stimmt; Summe aller Stems bleibt gleich). Hintergrund: Vergleich mit Traktor Pro 4 am 4. Oktober 2026 – danach liegen Bass- und Other-Pegel wie bei Traktor. Abschaltbar im Fenster und mit `--no-bassfix`.
- Neu: **Anhören** – startet `AddOns\StemPlayer.exe`, der Öffnen-Dialog zeigt gleich den Ordner der zuletzt umgewandelten Datei. Doppelklick auf eine fertige Datei in der Liste öffnet genau diese Datei im Player.
- Neu: **Ordner nach der Umwandlung öffnen**, standardmässig an. Der Explorer geht auf und markiert die zuletzt fertige Stem-Datei, so kann man sie direkt in Traktor ziehen. Nicht, wenn danach heruntergefahren wird.
- „Ordner öffnen“ zeigt bei markierter Zeile genau deren Stem-Datei im Explorer.
- Neu: **Erststart-Fenster** mit Haftungsausschluss, Hinweis zu den Rechten an der Musik und Lizenzhinweisen (Deutsch/Englisch). Häkchen setzen und bestätigen, sonst startet StemMaker nicht. Gilt pro PC (Hash der Windows-Installationsnummer in `StemMaker.ini`); wird der Ordner auf einen anderen PC kopiert, kommt die Frage erneut. StemCLI verlangt dafür einmal `--accept`.
- Neu: **Update-Prüfung beim Start** über `update.json` im Repository (im Hintergrund, max. 5 s, abschaltbar). Fenster „Jetzt aktualisieren / Später / Diese Version überspringen“. Das Update-ZIP wird mit SHA-256 geprüft, die laufende Exe wird zu `.exe.old` und beim nächsten Start weggeräumt. INI, Warteschlange, Logs, Modelle und ffmpeg bleiben. Nie während einer Umwandlung, danach Neustart von selbst.
- **Feste ffmpeg-Version** (9.0.2, LGPL, 56 statt 170 MB) aus einem eigenen Release statt täglich „latest“, mit SHA-256-Prüfung. Auch die Modelle werden geprüft, sobald ihre Prüfsummen in `update.json` stehen. Download-Adressen stehen jetzt in `update.json` (Anleitung: `docs/UPDATE-JSON.md`).
- Info-Fenster mit zwei Reitern: **Anleitung** und **Lizenzen** (Haftungsausschluss, `LICENSE`, `THIRD-PARTY-NOTICES.md`).

### StemPlayer 1.3 (AddOn) – 4. Oktober 2026
- Ordner als Parameter: Der Öffnen-Dialog startet gleich in diesem Ordner (für „Anhören“ in StemMaker).

### StemPlayer 1.2 (AddOn) – 3. Oktober 2026
- Neues Aussehen „Traktor Dark“: dunkles Design, Stem-Farben wie in Traktor, eigene gezeichnete Regler (PR #2).
- Am 3. Oktober 2026 von Speedy unter Windows getestet, funktioniert; kommt so in die nächste StemMaker-Version.

### StemPlayer 1.1 (AddOn) – 2. Oktober 2026
- Test-Player für `.stem.mp4`: pro Stem Stumm, Solo und Lautstärke-Regler, Pegelanzeigen.
- A/B-Vergleich mit dem Original und Modus „Rest“ (Original minus Summe der Stems) – zeigt, was bei der Trennung verloren geht.
- Liegt als `AddOns\StemPlayer.exe` im StemMaker-Ordner. Quellcode unter `src/AddOns/StemPlayer/` (PR #1).

### Repository
- `TODO.md`: kurze Liste, was als Nächstes getestet, entschieden oder gebaut wird.
- `ROADMAP.md` und `CHANGELOG.md` angelegt (PR #3).
- Ordner `Temp/` für Testversionen, darin `StemPlayer/1.2/StemPlayer.exe` (PR #4).
- README: Beta-Hinweis (Traktor-Pro-4-Test läuft noch). Am 4. Oktober 2026 wieder entfernt, der Test ist erledigt.
- Entwicklungslog und Ideen-Liste unter `docs/`.
- Ko-fi-Spenden-Knopf (`.github/FUNDING.yml`).
- Sprach-Links oben in README und LIESMICH.
- README/LIESMICH: Abschnitt zur Windows-SmartScreen-Warnung (warum sie kommt, „Trotzdem ausführen“, ZIP „Zulassen“, Download prüfen) (PR #5).

---

## 1.6 – 2. Oktober 2026 (erste öffentliche Version auf GitHub)
- Ganze Sammlungen umwandeln: Warteschlange wird laufend gespeichert und nach Absturz/Neustart fortgesetzt.
- Option „PC danach herunterfahren“ mit Countdown.
- Mehrsprachig: Deutsch und Englisch (`lang\`, gettext-`.po`), auch in StemCLI.
- Zeitschätzung aus den Song-Längen.
- StemCLI liest jetzt `StemMaker.ini` (Fehler seit 1.0) und läuft auch aus dem Unterordner `AddOns\`.
- Umlaute in Dateinamen (z. B. „Tiësto“) funktionieren überall.

## 1.5 – Energie, Icon, Name
- PC bleibt während der Konvertierung wach (kein Ruhezustand mehr mitten im Track); Standby wird im Log erkannt.
- Energiesparplan bzw. Windows-11-Energiemodus wird vorübergehend auf Leistung gestellt (ca. 8 % schneller) und danach – auch nach Absturz – zurückgesetzt.
- „Auto“ begrenzt die Anzahl Teile zusätzlich nach Arbeitsspeicher.
- Windows 11 wird richtig erkannt.
- „Threads“ heisst jetzt „Teile“, mit Anzeige der genutzten Kerne.
- „AAC automatisch“: Bitrate richtet sich nach der Quelle (192–320 kbit/s).
- Neues Programm-Icon (vier Balken in den Stem-Farben).
- Neuer Anzeigename „Elospeed StemMaker“.

## 1.4 – Tempo auf älteren PCs
- Alle echten Prozessorkerne werden genutzt (vorher pauschal halbiert).
- Zusätzliche AVX-Version von demucs; Auswahl AVX2 → AVX → generic.
- Bessere Restzeit-Schätzung.
- Ergebnis auf einem i5-2500: 12 min Musik in 1:22 h statt ~2:45 h.

## 1.0 – 1.3 – Grundlagen
- MP3 (und WAV, FLAC, AIFF, M4A, OGG) → Traktor-Stem-Datei mit Master + Drums, Bass, Other, Vox.
- demucs.cpp für Windows gebaut, komplett statisch gelinkt (keine DLLs, keine Installation).
- Startfenster prüft alles und lädt ffmpeg und Trenn-Modell selbst herunter.
- StemCLI als Kommandozeilen-Version.
- Log in Echtzeit mit Absturz- und Fehler-Erkennung; die letzten 20 Logs bleiben erhalten.
