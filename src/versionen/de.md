# Versionsverlauf

Kurzfassung für den Reiter „Versionen“ im Info-Fenster, neueste Version oben.
Wird in StemMaker.exe eingebaut. Pro Release einen Abschnitt „## <Version> – <Datum>“
hier, in en.md und in es.md ergänzen (der Release-Workflow prüft das).
Nur Punkte, die Nutzer merken, kurz und ohne technische Einzelheiten.

## 2.0 – 26. Oktober 2026
- Neue Turbo-Engine: die Stems werden auf der CPU etwa 6- bis 10-mal schneller getrennt, gleiche Qualität
- Mit passender Grafikkarte (NVIDIA, AMD, Intel) nur noch Sekunden pro Song (Beta)
- Ein kurzer Vortest beim ersten Start misst CPU und Grafikkarte und sagt, wie lange ein Song etwa dauert
- Die bisherige Engine bleibt wählbar und springt automatisch ein, falls Turbo bei einer Datei scheitert
- Lange DJ-Mixe brauchen viel weniger Arbeitsspeicher

## 1.9 – 23. Oktober 2026
- StemMaker gibt es jetzt auch auf Spanisch (danke an David GJ für die Übersetzung)
- Neuer Reiter „Danke“ unter „Info“ mit allen, die mitgeholfen haben
- StemPlayer: Loop A-B, ein Abschnitt wird nahtlos wiederholt
- StemPlayer: Lupe zum genauen Setzen des Loops, mit Zeitraster und Zoom
- StemPlayer: Scrubbing, beim Ziehen der Welle hört man den Ton wie bei einer Schallplatte
- StemPlayer spricht jetzt Deutsch, Englisch und Spanisch (wie in StemMaker eingestellt)

## 1.8.1 – 20. Oktober 2026
- Titel, Interpret, Album und BPM aus OGG- und Opus-Dateien landen jetzt in der Stem-Datei
- Fenstertitel sagt „aus Audiodateien“ statt „aus MP3“

## 1.8 – 18. Oktober 2026
- Hauptfenster mit Farbe: Fortschrittsbalken in der Liste, Häkchen und Stem-Farbpunkte bei fertigen Dateien
- StemPlayer 1.5: Wellenform pro Stem, Solo wie am DJ-Mixer
- „Nochmals konvertieren“ wandelt wirklich nochmals um, abgebrochene Songs zählen nicht mehr als Fehler
- Vorhandene Stem-Datei geht beim Überschreiben nicht mehr verloren
- Viele kleine Fehler behoben

## 1.7.1 – 14. Oktober 2026
- Neues Fenster „Weitere Einstellungen“ (Zahnrad)
- Symbol neben der Uhr: Fortschritt und Meldung, wenn alles fertig ist
- Knopf „Traktor-Farben“ für die Stem-Farben
- Installer (Setup.exe) neben dem ZIP
- Fehlerbericht senden (nur wenn du willst, nichts geht automatisch weg)
- Sauberer Abbruch beim Herunterfahren von Windows, klare Meldung bei zu langen Pfaden
- StemPlayer 1.4 und sicherere Downloads

## 1.7 – 6. Oktober 2026
- „Anhören“ im StemPlayer und „Ordner nach der Umwandlung öffnen“
- Club-Pegel (Lautstärke angleichen) und Bass-Fix
- BPM, Tonart, Label und ISRC werden in die Stem-Datei übernommen
- Update-Prüfung beim Start und „Nach Updates suchen“ im Info-Fenster
- StemPlayer 1.3 im Design „Traktor Dark“ mit Stumm, Solo und Regler pro Stem
- Viele Fehler behoben

## 1.6 – 2. Oktober 2026
- Erste öffentliche Version auf GitHub
- Ganze Sammlungen umwandeln, die Liste wird nach Absturz oder Neustart fortgesetzt
- PC danach herunterfahren (mit Countdown)
- Deutsch und Englisch
- Umlaute in Dateinamen funktionieren überall

## 1.5
- PC bleibt während der Umwandlung wach, Energiesparplan wird vorübergehend auf Leistung gestellt
- Neues Programm-Icon und neuer Name „Elospeed StemMaker“

## 1.4
- Alle Prozessorkerne werden genutzt, auf älteren PCs etwa doppelt so schnell

## 1.0 – 1.3
- Audiodateien werden zu Traktor-Stem-Dateien mit Master, Drums, Bass, Other und Vox
- Startfenster prüft alles und lädt ffmpeg und das Trenn-Modell selbst herunter
- StemCLI als Kommandozeilen-Version
