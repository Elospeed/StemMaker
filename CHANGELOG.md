# Changelog – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Was erledigt ist, pro Version, neueste oben. Was gerade läuft und geplant ist, steht in der [ROADMAP](ROADMAP.md).
Die technischen Hintergründe (Fehler und wie sie gelöst wurden) stehen im [Entwicklungslog](docs/ENTWICKLUNGSLOG.md).

---

## Unveröffentlicht

### StemPlayer 1.2 (AddOn) – 3. Oktober 2026
- Neues Aussehen „Traktor Dark“: dunkles Design, Stem-Farben wie in Traktor, eigene gezeichnete Regler (PR #2).
- Von Speedy getestet, kommt so in die nächste StemMaker-Version.

### StemPlayer 1.1 (AddOn) – 2. Oktober 2026
- Test-Player für `.stem.mp4`: pro Stem Stumm, Solo und Lautstärke-Regler, Pegelanzeigen.
- A/B-Vergleich mit dem Original und Modus „Rest“ (Original minus Summe der Stems) – zeigt, was bei der Trennung verloren geht.
- Liegt als `AddOns\StemPlayer.exe` im StemMaker-Ordner. Quellcode unter `src/AddOns/StemPlayer/` (PR #1).

### Repository
- README: Beta-Hinweis (Traktor-Pro-4-Test läuft noch).
- Entwicklungslog und Ideen-Liste unter `docs/`.
- Ko-fi-Spenden-Knopf (`.github/FUNDING.yml`).
- Sprach-Links oben in README und LIESMICH.
- README/LIESMICH: Abschnitt zur Windows-SmartScreen-Warnung (warum sie kommt, „Trotzdem ausführen“, ZIP „Zulassen“, Download prüfen).

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
