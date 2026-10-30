# Changelog – Elospeed StemMaker

🇬🇧 *This file is kept in German. English readers: see the [README](README.md).*

Was erledigt ist, pro Version, neueste oben.
Die technischen Hintergründe (Fehler und wie sie gelöst wurden) stehen im [Entwicklungslog](docs/ENTWICKLUNGSLOG.md).

---

## Unveröffentlicht

### StemPlayer 1.8.1
- **Fenster bei Anzeigeskalierung (125 %, 150 %, 200 %):** Der StemPlayer war bei grosser Skalierung in Windows höher als der Bildschirm, die Höhe liess sich nicht ändern und Master, Fusszeile und Ko-fi-Knopf waren abgeschnitten. Im CD-Player lagen Knöpfe übereinander (CUE über dem Jogwheel, Fader über den SOLO-Pads), und rechts und unten war ein Teil abgeschnitten. Jetzt passt das Fenster auf den Bildschirm, und alle Elemente sitzen auch bei grosser Skalierung an ihrem Platz.
- **Wellenformen wachsen mit dem Fenster:** In der Ansicht Wellenform lässt sich das Fenster frei vergrössern und auch maximieren, die vier Stem-Wellen werden dabei höher oder flacher, alles Waagrechte wird breiter. Kompakt hat eine feste Höhe, der CD-Player eine feste Grösse (dort gibt es keinen Maximieren-Knopf mehr, statt leerer Fläche um feste Elemente).
- **Passt eine Ansicht nicht auf den Bildschirm** (z. B. CD-Player bei 150 % auf einem Full-HD-Laptop), startet der StemPlayer in einer kleineren Ansicht und sagt beim Umschalten, warum es nicht geht.

## 2.1 – 29. Oktober 2026

### StemMaker
- **„Anhören“ spielt die fertige Datei gleich ab:** Der StemPlayer öffnet die markierte oder zuletzt umgewandelte Stem-Datei direkt, ohne Öffnen-Fenster.
- **Kein Explorer-Fenster mehr nach der Umwandlung:** Das Häkchen „Ordner nach der Umwandlung öffnen“ ist jetzt aus. Wer die Datei gleich in Traktor ziehen will, setzt es wieder oder klickt „Ordner öffnen“.
- **Rechtsklick-Menü in der Dateiliste:** Rechtsklick auf eine Zeile bietet „Anhören“ (spielt eine fertige Datei im StemPlayer ab, wie der Doppelklick) und „Aus Liste entfernen“. Die Entf-Taste entfernt die markierten Zeilen ebenfalls. Erstellte Stem-Dateien bleiben dabei erhalten.
- **Reiter „Versionen“ im Info-Fenster:** Zeigt pro Version in Stichworten, was neu ist, was verbessert und was behoben wurde, neueste oben, auf Deutsch, Englisch oder Spanisch. Die ausführliche Fassung bleibt dieser CHANGELOG auf GitHub.
- **AddOn-Leiste statt Knopf „Anhören“:** Rechts neben der Dateiliste steht jetzt eine schmale Leiste mit einem Knopf pro AddOn, mit Symbol und Namen. „StemPlayer“ spielt wie bisher „Anhören“ die markierte oder zuletzt umgewandelte Datei ab, „StemTagger“ öffnet die markierten fertigen Dateien im StemTagger. Doppelklick und Rechtsklick in der Liste funktionieren weiter.
- **„Tags bearbeiten...“ im Rechtsklick-Menü:** öffnet die markierten fertigen Stem-Dateien im neuen StemTagger.
- **Fenstergrösse bei Anzeigeskalierung:** Bei 125 %, 150 % oder 200 % Skalierung in Windows wurde das Hauptfenster bei jedem Start grösser. Die Grösse wird jetzt unabhängig von der Skalierung gespeichert.

### StemTagger 1.0 (neues AddOn)
- **Tags und Cover für Stem-Dateien:** `AddOns\StemTagger.exe` setzt Titel, Interpret, Album, Genre, Jahr, Label, Kommentar und Cover in `.stem.mp4`-Dateien, also das, was Traktor und Mixxx anzeigen und wonach man dort sucht. Gedacht vor allem für Stem-Dateien ohne Tags. BPM und Tonart ermitteln Traktor und Mixxx beim Analysieren selbst; Werte, die schon in der Datei stehen, bleiben erhalten.
- **Viele Dateien auf einmal:** Ordner laden, mehrere Zeilen markieren und z.B. Album oder Cover für alle setzen. Felder mit unterschiedlichen Werten zeigen „<verschieden>“ und bleiben pro Datei erhalten, solange man sie nicht ändert.
- **Cover bequem:** Bild aufs Fenster ziehen, aus dem Browser kopieren und mit Strg+V einfügen oder Datei wählen. Grosse Bilder werden auf Wunsch auf 1000 px verkleinert, BMP und GIF in JPEG umgewandelt. Das Cover lässt sich auch wieder als Bild speichern.
- **Genre mit Auswahlliste:** aus rund 50 Musikstilen wählen oder selbst eintippen, beim Tippen wird ergänzt („tech h“ wird „Tech House“).
- **Dunkles Design wie der StemPlayer:** kompaktes Fenster, dunkle Liste und Felder, die markierte Zeile mit grünem Streifen, Status farbig (grün fertig, orange es fehlt etwas, gelb geändert). Sicherungskopie und Cover-Verkleinern sind LED-Schalter: rot aus, grün an.
- **Spaltenbreiten:** Rand zwischen zwei Spalten ziehen ändert die Breite, Doppelklick passt die Spalte an den Text an. Die Spalten wachsen mit dem Fenster mit, die Breiten bleiben beim nächsten Start erhalten.
- **Tooltip an jedem Feld**, der sagt, was hineingehört.
- **Fehlendes auf einen Blick:** Die Spalte Status zeigt „Ohne Tags“ oder „Ohne Cover“. Klick auf eine Spaltenüberschrift sortiert die Liste.
- **Interpret/Titel aus Dateiname** füllt beide Felder aus Namen wie „Interpret - Titel.stem.mp4“.
- **Stems bleiben unangetastet:** Neu geschrieben wird nur die Tag-Liste. Audio, die vier Stems, die Stem-Beschreibung und Traktors eigene Daten bleiben bytegenau gleich. Nach dem Schreiben prüft der StemTagger die neue Datei, bevor sie die alte ersetzt. Eine Sicherungskopie `.bak` lässt sich einschalten. Nach dem Laden eines Ordners erklärt ein Hinweis, was sich ändert und was nicht, und vor dem Speichern mehrerer Dateien fragt der StemTagger nach. Getestet in Traktor Pro 4 und Mixxx 2.6 Beta.
- **Auch einzeln:** Wer StemMaker nicht braucht, lädt den StemTagger als eigenes kleines ZIP von der Release-Seite.
- Deutsch, Englisch und Spanisch.

### StemPlayer 1.8
- **Neues Design CD-Player im DJ-Look:** Neben KOMPAKT und WELLENFORM gibt es jetzt den **CD-Player**. Die Ansicht wählst du oben in einem Ausklapp-Menü, so bleibt die Fläche übersichtlich. Er kann dasselbe wie die normale Ansicht, sieht nur anders aus. Die Wahl bleibt beim nächsten Start erhalten.
- **CD-Player:** Display mit Zeit, Restzeit und den Wellenformen aller Stems, ein Jogwheel (der blaue Ring zeigt die Restzeit, mit der Maus gedreht hört man den Ton wie bei einer Platte unter der Hand), runde Knöpfe CUE und Play/Pause und grosse Stem-Pads zum Stummschalten und für Solo.
- **Loop-Spur:** Lupe und Loop-Knöpfe A, B, AN und × wie in der normalen Ansicht.
- **Lupe bei grosser Anzeigeskalierung:** Bei 150 % oder 200 % Skalierung in Windows waren die Zeiten unter der Lupe unten abgeschnitten und die Loop-Fähnchen A und B zu klein für ihren Buchstaben. Beides richtet sich jetzt nach der Schriftgrösse.

## 2.0 – 26. Oktober 2026

### StemMaker – Turbo-Engine
- **Turbo trennt viel schneller:** Die Stems werden jetzt mit ONNX Runtime getrennt statt mit demucs.cpp. Gleiches Modell (htdemucs bzw. htdemucs_ft), gleiche Qualität, aber auf der CPU je nach PC etwa 6- bis 10-mal schneller (Werkstatt-PC mit i5-2500: 52 statt 440 bis 584 Sekunden pro Songminute; auf einem i5-750 von 2009 dauert ein 4-Minuten-Song rund 8 Minuten statt 1 Stunde 20). Mit einer passenden Grafikkarte sind es nur noch Sekunden (RTX 4060 Ti: ein 3-Minuten-Song in etwa 26 Sekunden, ganzer Ablauf).
- **Grafikkarte, wenn sie mitmacht (Beta):** StemMaker probiert die Grafikkarte (NVIDIA, AMD, Intel über DirectML, ohne Zusatz-Installation) an einem Abschnitt des Songs aus und nimmt sie nur, wenn sie richtig und schneller als die CPU rechnet. Sonst rechnet die CPU. Fällt die Karte mitten im Song aus, rechnet die CPU weiter.
- **Vortest beim ersten Start:** Ein Fenster misst CPU und Grafikkarte, zeigt mit Fortschrittsbalken und Stichworten, was gerade getestet wird, und sagt am Ende, wie StemMaker auf diesem PC rechnet und wie lange ein 3-Minuten-Track etwa dauert. Jeder Schritt landet im Log und im Fehlerbericht. Nach einem neuen Grafiktreiber oder einer neuen Karte kommt der Vortest von selbst wieder, sonst jederzeit unter „Weitere Einstellungen“ → „Vortest ...“.
- **Klassisch bleibt:** demucs.cpp lässt sich unter „Weitere Einstellungen“ → „Engine“ wieder wählen. Scheitert Turbo bei einer Datei, trennt demucs.cpp diese Datei automatisch, die Liste läuft weiter. hdemucs_mmi (v3) rechnet immer klassisch.
- **Lange DJ-Mixe brauchen wenig Arbeitsspeicher:** Turbo schreibt die Stems während der Rechnung weg, statt den ganzen Song im Speicher zu halten.
- **Log zeigt die Engine:** Pro Datei steht im Log, ob Turbo (und auf welchem Gerät) oder demucs.cpp getrennt hat, ebenso in der Zusammenfassung und in `statistik.csv`.
- Die Zeit-Schätzung lernt das Tempo von Turbo und Klassisch getrennt.
- Die vier htdemucs_ft-Modelle werden beim Herunterladen jetzt wie die anderen Modelle mit einer Prüfsumme kontrolliert.
- Das Release-ZIP ist dadurch etwa 16 MB grösser (ONNX Runtime und DirectML von Microsoft in `tools\onnx\`). Die Telemetrie von ONNX Runtime ist abgeschaltet.

## 1.9 – 23. Oktober 2026

### StemMaker – neue Sprache
- **Spanisch:** StemMaker gibt es jetzt auch auf Spanisch. Auswählen beim ersten Start oder unter „Weitere Einstellungen“ → „Sprache:“. Danke an **David GJ** für die Übersetzung! Alle Helfer stehen jetzt unter „Info“ im neuen Reiter „Danke“.

### StemPlayer 1.6
- **Loop A-B:** Ein Abschnitt wird endlos wiederholt, so wie ein Loop in Traktor. Praktisch, um eine Stelle mit Mute und Solo genau zu prüfen, z. B. ob in den Vocals noch Drums durchklingen. Punkt A und B setzt man mit den Knöpfen oder den Tasten A und B an der aktuellen Stelle, oder man zieht den Bereich mit der rechten Maustaste in einer Wellenform auf. Der Rücksprung ist nahtlos. Taste L schaltet den Loop aus und wieder an, die Rücktaste löscht ihn. Der Loop-Bereich ist in allen Wellenformen grün hinterlegt.
- **Lupe zum genauen Setzen:** Unter der Original-Wellenform zeigt ein breiter Streifen nur wenige Sekunden rund um die Abspielstelle, mit Zeitraster. Darin zieht man den Loop mit der rechten Maustaste auf (Anfang und Ende rasten am Raster ein, mit Shift frei), verschiebt die Marken A und B mit der Maus und zoomt mit dem Mausrad. Mit gedrückter linker Maustaste zieht man die Welle unter dem roten Strich hin und her, um eine Stelle genau anzufahren (auch bei Pause). Mit den Pfeiltasten verschiebt man den ganzen Loop, Shift+Pfeil macht ihn breiter (Shift+links zieht den Anfang nach links, Shift+rechts das Ende nach rechts), Strg+Pfeil macht ihn schmaler. Je weiter man hineinzoomt, desto feiner werden die Schritte (bis 2 ms).

### StemPlayer 1.7
- **Deutsch, Englisch und Spanisch:** Der StemPlayer spricht jetzt dieselbe Sprache wie StemMaker. Eine eigene Einstellung braucht es nicht, er übernimmt die Sprache, die in StemMaker gewählt ist.
- **Scrubbing:** Zieht man in der Lupe die Welle mit der linken Maustaste, hört man den Ton wie bei einer Schallplatte unter der Hand: schnell gezogen hoch, langsam tief, rückwärts gezogen rückwärts, Maus still = Stille. Geht beim Abspielen und bei Pause. Lässt man beim Abspielen los, läuft die Musik an der Stelle ohne Lücke weiter.

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
