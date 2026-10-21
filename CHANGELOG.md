# Changelog – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Was erledigt ist, pro Version, neueste oben.
Die technischen Hintergründe (Fehler und wie sie gelöst wurden) stehen im [Entwicklungslog](docs/ENTWICKLUNGSLOG.md).

---

## Unveröffentlicht

### StemPlayer 1.6
- **Loop A-B:** Ein Abschnitt wird endlos wiederholt, so wie ein Loop in Traktor. Praktisch, um eine Stelle mit Mute und Solo genau zu prüfen, z. B. ob in den Vocals noch Drums durchklingen. Punkt A und B setzt man mit den Knöpfen oder den Tasten A und B an der aktuellen Stelle, oder man zieht den Bereich mit der rechten Maustaste in einer Wellenform auf. Der Rücksprung ist nahtlos. Taste L schaltet den Loop aus und wieder an, die Rücktaste löscht ihn. Der Loop-Bereich ist in allen Wellenformen grün hinterlegt.
- **Lupe zum genauen Setzen:** Unter der Original-Wellenform zeigt ein breiter Streifen nur wenige Sekunden rund um die Abspielstelle, mit Zeitraster. Darin zieht man den Loop mit der rechten Maustaste auf (Anfang und Ende rasten am Raster ein, mit Shift frei), verschiebt die Marken A und B mit der Maus und zoomt mit dem Mausrad. Shift+Pfeil und Strg+Pfeil verschieben A bzw. B um 10 ms.

## 1.8.1 – 20. Oktober 2026

### StemMaker – kleinere Fehler behoben
- **Tags aus OGG- und Opus-Dateien kommen mit:** Titel, Interpret, Album und BPM fehlten bisher in der Stem-Datei, wenn die Quelle eine `.ogg`- oder `.opus`-Datei war.
- **Fenstertitel und Info-Fenster** sagen jetzt „aus Audiodateien“ statt „aus MP3“, denn StemMaker nimmt auch WAV, FLAC, AIFF, M4A, AAC, OGG und Opus.

## 1.8 – 18. Oktober 2026

### StemMaker – Hauptfenster mit etwas Farbe
- **Fortschritt direkt in der Liste:** Die laufende Datei zeigt in der Spalte „Status“ einen grünen Balken mit Prozent. Wartende Dateien sind grau.
- **Fertige Dateien auf einen Blick:** Grünes Häkchen, Dauer und vier Farbpunkte für die vier Stems. Fehler stehen in Rot.
- **Farbstreifen** in den vier Stem-Farben unter der Knopfleiste (dieselben Farben wie in Traktor bzw. wie in den Einstellungen gewählt).
- **Zusammenfassung** am Ende grün, wenn alles geklappt hat, und rot, wenn etwas fehlgeschlagen ist.

### StemMaker – kleinere Fehler behoben
- **„Nochmals konvertieren?“ wandelt jetzt wirklich nochmals um:** Waren alle Dateien der Liste schon fertig und man bestätigte die Frage mit „Ja“, wurde ohne die Einstellung „Überschreiben“ jede Datei als „existiert schon“ übersprungen. Jetzt werden die Stem-Dateien neu erzeugt. Die gespeicherte Einstellung bleibt unverändert.
- **Abgebrochene Songs zählen nicht mehr als Fehler:** Die Zusammenfassung nach einem Abbruch nennt sie jetzt als „Abgebrochen“ statt unter „fehlgeschlagen“.
- **Update-Fenster lässt die Startprüfung in Ruhe:** Wer „Beim Start nach Updates suchen“ abgeschaltet hatte und von Hand nach Updates suchte, hatte sie danach wieder an. Das Häkchen zeigt jetzt die eigene Einstellung.
- **Anleitung im Info-Fenster:** Code-Blöcke zeigen nicht mehr das Wort „text“, und Pfeile wie „->“ bleiben stehen.
- **Vorhandene Stem-Datei geht nicht mehr verloren:** Beim Überschreiben wurde die alte Datei gelöscht, bevor die neue sicher am Ziel war. Ging das Kopieren schief (z. B. Ziel auf einem anderen Laufwerk und Platte voll), waren beide weg. Jetzt wird die alte erst entfernt, wenn die neue da ist.
- **Liste übersteht Stromausfall beim Speichern:** Die gemerkte Dateiliste konnte verloren gehen, wenn der Strom genau beim Speichern ausfiel. Das ist jetzt abgesichert.
- **Downloads:** Bricht ein Download wegen voller Platte ab, bleibt keine halbe `.part`-Datei mehr liegen. Der Notweg über curl hängt bei toter Verbindung nicht mehr endlos, sondern bricht nach 30 Sekunden ohne Daten ab.
- **Modelle immer mit Prüfsumme:** Steht in `update.json` für ein Modell keine Prüfsumme, nimmt StemMaker die eingebaute, statt die Datei ungeprüft zu verwenden.
- **Kein falscher Absturz-Hinweis mehr,** wenn Windows das Log beim Beenden kurz gesperrt hatte (z. B. Virenscanner).
- **Tab-Reihenfolge im Hauptfenster** geht jetzt Zeile für Zeile durch die Einstellungen.

### StemPlayer 1.5
- **Wellenform pro Stem:** Unter Drums, Bass, Other und Vocals steht die Wellenform der Spur in ihrer Stemfarbe, oben die Wellenform des Originals. Ein roter Strich läuft in allen Spuren mit, der gespielte Teil ist hell. Klicken oder Ziehen in eine Wellenform springt an diese Stelle. Stumme Stems werden grau.
- **Ansicht Kompakt / Wellenform:** Oben rechts umschaltbar (oder Taste W). Kompakt ist so klein wie bisher. Die Wahl wird gespeichert und beim nächsten Start übernommen.
- **Solo wie am DJ-Mixer:** Solo heisst jetzt „nur dieser Stem“. Ein neues Solo löst das vorherige ab. Wer mehrere Stems gleichzeitig solo hören will, hält Strg gedrückt (Strg+Klick auf S oder Strg+Shift+1–4).

## 1.7.1 – 14. Oktober 2026

### StemMaker
- **Zahnrad „Weitere Einstellungen...“:** Das Hauptfenster ist aufgeräumt. Dort bleibt nur, was man pro Umwandlung ändert (Ausgabeordner, Modell, Format, Club-Pegel, Bass-Fix, Herunterfahren). Teile, Überschreiben, Unterordner, PC wach halten, Stem-Namen und Farben, Sprache und die Update-Prüfung beim Start stehen jetzt gesammelt in einem eigenen Fenster, dazu die Pfade zu ffmpeg, demucs.cpp und den Modellen und ein Knopf „Standard wiederherstellen“. Sprache und Update-Häkchen sind dafür aus dem Info-Fenster verschwunden. Bisherige Einstellungen bleiben erhalten.
- **Knopf „Traktor-Farben“** in den Einstellungen (Gruppe Stems): setzt die vier Stem-Farben auf die Werte aus Traktors eigenen Stem-Dateien (Orange, Lila, Grün, Hellblau). Die Namen bleiben. Die Symbole neben den Stems zeigt Traktor fest nach Platz, die lassen sich nicht wählen.
- **Installer:** Neben dem ZIP gibt es `StemMaker-<Version>-Setup.exe`. Es installiert nur für den aktuellen Benutzer, ohne Administratorrechte, nach `%LOCALAPPDATA%\Programs\StemMaker`, legt Startmenü-Einträge für StemMaker und StemPlayer an und erscheint unter „Apps & Features“. Drüberinstallieren (Update) lässt Modelle, ffmpeg und Einstellungen in Ruhe. Beim Deinstallieren fragt es, ob auch diese gelöscht werden sollen. Das ZIP bleibt als portable Variante.
- **Fehlerbericht senden:** Nach einem Absturz fragt StemMaker beim nächsten Start, ob du einen Fehlerbericht schicken möchtest. Auch im Fenster „Unerwarteter Fehler“ und unter Info gibt es den Knopf „Fehlerbericht senden...“. Der Bericht wird vorher ganz angezeigt, der Benutzername ist entfernt. Er geht per Mail an Elospeed (Datei selbst anhängen) oder als öffentliches GitHub-Issue. Nichts wird automatisch gesendet.
- **Symbol neben der Uhr:** Während einer Umwandlung erscheint StemMaker im Infobereich der Taskleiste. Maus drüber zeigt den Fortschritt, Klick holt das Fenster zurück. Ist alles fertig und StemMaker nicht im Vordergrund, kommt eine Meldung (abschaltbar). Neu in den Einstellungen: „Beim Minimieren nur das Symbol neben der Uhr zeigen“ (Standard aus).
- **Windows herunterfahren während einer Umwandlung:** StemMaker bricht sauber ab, stellt den Energiesparplan zurück und merkt sich die Liste. Beim nächsten Start kommt die angefangene Datei noch einmal dran, ohne Absturz-Hinweis und ohne Frage nach einem Fehlerbericht.
- **Klare Meldung bei Pfaden über 260 Zeichen:** Windows kann längere Pfade nicht öffnen. Bisher hiess es dann „Datei nicht gefunden“ oder „Kann Zieldatei nicht schreiben“. Jetzt steht in der Liste „Pfad zu lang (… Zeichen, Windows erlaubt höchstens 259)“ mit einem Tipp, was zu tun ist. Gilt auch für StemCLI.
- **Hinweis auf übersprungene Ordner:** Liegt beim Hinzufügen eines Ordners ein Unterordner über der Grenze, fehlte die Musik darin bisher ohne Hinweis. Jetzt kommt eine Meldung, und die Ordner stehen im Log.
- **Richtige Versionsnummer unter „Apps & Features“:** Wer mit dem Setup installiert hat und dann aus StemMaker heraus aktualisiert, sah dort (und bei `winget list`) bisher weiter die alte Nummer. Jetzt passt StemMaker den Eintrag beim Start selbst an.

### Sicherheit
- **Keine ungeprüften Downloads mehr, wenn `update.json` nicht erreichbar ist:** Bisher lud StemMaker dann ffmpeg als täglich wechselndes „latest“-ZIP und die Modelle ohne Prüfsumme. Jetzt kommt ffmpeg auch in diesem Fall aus dem eigenen Release `ffmpeg-9.0.2`, und für ffmpeg sowie die Modelle v4 und v3 sind die SHA-256-Prüfsummen fest eingebaut.
- **ZIP-Pfade werden geprüft:** Einträge mit `..` oder absolutem Pfad werden beim Entpacken (Update, ffmpeg) abgewiesen.
- **Release-Seite aus `update.json`** wird nur geöffnet, wenn sie mit `https://` beginnt.

### StemPlayer 1.4
- **Falsche Dateien werden abgewiesen:** Per Drag & Drop (oder „Alle Dateien“ im Öffnen-Dialog) liess sich jede Datei laden, z. B. eine MP3 oder ein Video. Die laufende Wiedergabe brach dann ab, und es kam ein unverständlicher Fehler. Jetzt prüft der Player die Datei vorher und zeigt eine klare Meldung auf Deutsch und Englisch. Der gerade geladene Track bleibt erhalten. Ein reingezogener Ordner wird ebenfalls mit Hinweis abgewiesen.
- **CLIP sieht nicht mehr wie ein Knopf aus:** Die Übersteuerungs-Anzeige hellte sich beim Drüberfahren auf und reagierte auf Klicks wie ein Knopf. Jetzt ist sie eine flache Anzeige, die nur bei Übersteuerung rot leuchtet.

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
