# Changelog – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Was erledigt ist, pro Version, neueste oben.
Die technischen Hintergründe (Fehler und wie sie gelöst wurden) stehen im [Entwicklungslog](docs/ENTWICKLUNGSLOG.md).

---

## Unveröffentlicht

### StemMaker
- **Installer:** Neben dem ZIP gibt es `StemMaker-<Version>-Setup.exe`. Es installiert nur für den aktuellen Benutzer, ohne Administratorrechte, nach `%LOCALAPPDATA%\Programs\StemMaker`, legt Startmenü-Einträge für StemMaker und StemPlayer an und erscheint unter „Apps & Features“. Drüberinstallieren (Update) lässt Modelle, ffmpeg und Einstellungen in Ruhe. Beim Deinstallieren fragt es, ob auch diese gelöscht werden sollen. Das ZIP bleibt als portable Variante.
- **Klare Meldung bei Pfaden über 260 Zeichen:** Windows kann längere Pfade nicht öffnen. Bisher hiess es dann „Datei nicht gefunden“ oder „Kann Zieldatei nicht schreiben“. Jetzt steht in der Liste „Pfad zu lang (… Zeichen, Windows erlaubt höchstens 259)“ mit einem Tipp, was zu tun ist. Gilt auch für StemCLI.
- **Hinweis auf übersprungene Ordner:** Liegt beim Hinzufügen eines Ordners ein Unterordner über der Grenze, fehlte die Musik darin bisher ohne Hinweis. Jetzt kommt eine Meldung, und die Ordner stehen im Log.

### Sicherheit
- **Keine ungeprüften Downloads mehr, wenn `update.json` nicht erreichbar ist:** Bisher lud StemMaker dann ffmpeg als täglich wechselndes „latest“-ZIP und die Modelle ohne Prüfsumme. Jetzt kommt ffmpeg auch in diesem Fall aus dem eigenen Release `ffmpeg-9.0.2`, und für ffmpeg sowie die Modelle v4 und v3 sind die SHA-256-Prüfsummen fest eingebaut.
- **ZIP-Pfade werden geprüft:** Einträge mit `..` oder absolutem Pfad werden beim Entpacken (Update, ffmpeg) abgewiesen.
- **Release-Seite aus `update.json`** wird nur geöffnet, wenn sie mit `https://` beginnt.

### StemPlayer 1.4
- **Falsche Dateien werden abgewiesen:** Per Drag & Drop (oder „Alle Dateien“ im Öffnen-Dialog) liess sich jede Datei laden, z. B. eine MP3 oder ein Video. Die laufende Wiedergabe brach dann ab, und es kam ein unverständlicher Fehler. Jetzt prüft der Player die Datei vorher und zeigt eine klare Meldung auf Deutsch und Englisch. Der gerade geladene Track bleibt erhalten. Ein reingezogener Ordner wird ebenfalls mit Hinweis abgewiesen.

## 1.7 – 6. Oktober 2026

### StemMaker
- Neu: **Anhören** – startet den StemPlayer, der Öffnen-Dialog zeigt gleich den Ordner der zuletzt umgewandelten Datei. Doppelklick auf eine fertige Datei in der Liste öffnet genau diese Datei im Player.
- Neu: **Ordner nach der Umwandlung öffnen**, standardmässig an. Der Explorer geht auf und markiert die zuletzt fertige Stem-Datei, so kann man sie direkt in Traktor ziehen. Nicht, wenn danach heruntergefahren wird.
- „Ordner öffnen“ zeigt bei markierter Zeile genau deren Stem-Datei im Explorer.
- Neu: **Lautstärke angleichen (Club-Pegel)**, standardmässig an. Alle 5 Spuren werden gemeinsam angehoben, bis die lauteste Spitze (Master, Stems und Stem-Summe) bei ca. −1 dB liegt. Kein Limiter. Leise Quellen bekommen in Traktor dadurch grosse, lesbare Wellenformen. Abschaltbar im Fenster und mit `--no-normalize` in StemCLI.
- Neu: **Bass-Fix**, standardmässig an. Tiefbass unter 80 Hz wandert von „Other“ in den Bass-Stem, die Summe aller Stems bleibt gleich. Danach liegen Bass- und Other-Pegel wie bei Traktor Pro 4. Abschaltbar im Fenster und mit `--no-bassfix`.
- **Tags vollständig übernommen:** Neu landen auch **BPM**, **Tonart**, **Label** und **ISRC** der Quelldatei in der Stem-Datei. Titel, Artist, Album, Album-Artist, Komponist, Genre, Jahr, Titel- und CD-Nummer, Kommentar, Gruppierung, Liedtext und das Cover kamen schon vorher mit.
- Neu: **Update-Prüfung beim Start** (im Hintergrund, max. 5 s, abschaltbar). Fenster „Jetzt aktualisieren / Später / Diese Version überspringen“. Das Update wird mit SHA-256 geprüft; Einstellungen, Warteschlange, Logs, Modelle und ffmpeg bleiben. Nie während einer Umwandlung, danach Neustart von selbst.
- Neu: **„Nach Updates suchen“** im Info-Fenster, dazu das Häkchen „Beim Start nach Updates suchen“.
- **Update wird bei einem Fehler zurückgedreht:** Scheitert das Kopieren mitten drin (z. B. Virenscanner sperrt eine Datei), werden die alten Dateien wiederhergestellt.
- Ein hängender Update-Download lässt sich jetzt jederzeit abbrechen. Alle Downloads (Update, ffmpeg, Modelle) brechen nach 30 Sekunden ohne Daten ab, statt bis zu 60 Minuten zu warten.
- **Feste ffmpeg-Version** (9.0.2, LGPL, 56 statt 170 MB) statt täglich „latest“, mit SHA-256-Prüfung. Auch die Modelle v4 und v3 werden geprüft.
- Neu: **Erststart-Fenster** mit Haftungsausschluss, Hinweis zu den Rechten an der Musik und Lizenzhinweisen (Deutsch/Englisch). StemCLI verlangt dafür einmal `--accept`.
- Info-Fenster mit zwei Reitern: **Anleitung** und **Lizenzen**.
- Log pro Datei mit Dateigrösse, Grösse der fertigen Stem-Datei, Tempo und Lautheit der Master-Spur (LUFS, True Peak). Neue Datei `logs\statistik.csv` mit einer Zeile pro umgewandelter Datei zum Auswerten in Excel.
- Nur ein StemMaker gleichzeitig: Ein zweiter Start zeigt den Hinweis „StemMaker läuft schon“ und holt das offene Fenster nach vorne.
- Behoben: StemMaker liess sich manchmal nicht beenden („Keine Rückmeldung“), vor allem bei MP3s mit vielen Tags.
- Behoben: Gleiche Dateinamen aus verschiedenen Ordnern gingen bei einem gemeinsamen Ausgabeordner verloren. Jetzt heisst die spätere Datei `Intro (2).stem.mp4`, `(3)` usw. Gilt auch für StemCLI mit `-o`.
- Behoben: Nach einem Absturz rechnete demucs im Hintergrund weiter. Jetzt hören demucs und ffmpeg sofort mit auf, und liegengebliebene Arbeitsordner in `%TEMP%\StemMaker` werden beim nächsten Start gelöscht.
- Rückfragen auf Deutsch zeigen jetzt „Ja/Nein“ statt „Yes/No“.
- „Liste leeren“ fragt jetzt nach.

### StemPlayer 1.3 (liegt jetzt im ZIP unter `AddOns`)
- Neues Aussehen „Traktor Dark“: dunkles Design, Stem-Farben wie in Traktor.
- Pro Stem Stumm, Solo und Lautstärke-Regler, Pegelanzeigen.
- A/B-Vergleich mit dem Original und Modus „Rest“ (Original minus Summe der Stems): zeigt, was bei der Trennung verloren geht.
- Startet auf Wunsch gleich im richtigen Ordner (für „Anhören“ in StemMaker).

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
