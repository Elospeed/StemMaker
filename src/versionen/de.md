# Versionsverlauf

Kurzfassung für den Reiter „Versionen“ im Info-Fenster, neueste Version oben.
Wird in StemMaker.exe eingebaut. Pro Release einen Abschnitt „## <Version> – <Datum>“
hier, in en.md und in es.md ergänzen (der Release-Workflow prüft das).
Darunter „### Neu“, „### Verbessert“, „### Behoben“ (nur was es gibt), je Punkt
ein kurzes Stichwort. Nur Punkte, die Nutzer merken, ohne technische Einzelheiten.

## 2.1.1 – noch nicht veröffentlicht
### Behoben
- Bei 150 % und 200 % Anzeigeskalierung waren Fenster höher als der Bildschirm (Hauptfenster, Einstellungen, StemDecks)
- Sprachwahl, Update-Fenster und Frage vor dem Herunterfahren bei Anzeigeskalierung zu klein
- Ko-fi-Knopf bei 150 % zu breit
- StemTagger 1.0.1: Spalten der Liste bei Anzeigeskalierung zu schmal
- StemPlayer 1.8.1: Fenster bei 125–200 % Anzeigeskalierung (Höhe änderbar, CD-Player richtig, Bildlaufleiste auf kleinen Bildschirmen)

## 2.1 – 29. Oktober 2026
### Neu
- StemTagger 1.0: Titel, Interpret, Album, Genre und Cover in Stem-Dateien setzen, auch für viele Dateien auf einmal
- AddOn-Leiste neben der Dateiliste: StemPlayer und StemTagger mit einem Klick
- StemPlayer 1.8: neue Ansicht CD-Player mit Jogwheel und Stem-Pads
- Reiter „Versionen“ im Info-Fenster
- Rechtsklick-Menü in der Dateiliste: Anhören, Tags bearbeiten, Aus Liste entfernen (auch Entf-Taste)
### Verbessert
- „Anhören“ spielt die fertige Datei direkt ab
- Nach der Umwandlung öffnet sich kein Explorer-Fenster mehr (einschaltbar)
### Behoben
- Hauptfenster wurde bei Anzeigeskalierung über 100 % bei jedem Start grösser
- StemPlayer: Lupe bei 150 % und 200 % Anzeigeskalierung abgeschnitten

## 2.0 – 26. Oktober 2026
### Neu
- Turbo-Engine: Stems auf der CPU etwa 6- bis 10-mal schneller, gleiche Qualität
- Grafikkarte (NVIDIA, AMD, Intel): nur noch Sekunden pro Song (Beta)
- Vortest beim ersten Start: misst CPU und Grafikkarte, sagt die Dauer pro Song voraus
### Verbessert
- Bisherige Engine weiter wählbar, springt automatisch ein, wenn Turbo scheitert
- Lange DJ-Mixe brauchen viel weniger Arbeitsspeicher
- Log zeigt pro Datei die verwendete Engine

## 1.9 – 23. Oktober 2026
### Neu
- Spanisch (Übersetzung: David GJ)
- Reiter „Danke“ im Info-Fenster
- StemPlayer: Loop A-B, nahtlos
- StemPlayer: Lupe mit Zeitraster und Zoom zum genauen Setzen des Loops
- StemPlayer: Scrubbing wie bei einer Schallplatte
### Verbessert
- StemPlayer auf Deutsch, Englisch und Spanisch (wie in StemMaker eingestellt)

## 1.8.1 – 20. Oktober 2026
### Behoben
- Tags (Titel, Interpret, Album, BPM) aus OGG und Opus fehlten in der Stem-Datei
- Fenstertitel: „aus Audiodateien“ statt „aus MP3“

## 1.8 – 18. Oktober 2026
### Neu
- Hauptfenster mit Farbe: Fortschrittsbalken in der Liste, Häkchen und Stem-Farbpunkte
- StemPlayer 1.5: Wellenform pro Stem, Ansicht Kompakt/Wellenform
### Verbessert
- StemPlayer: Solo wie am DJ-Mixer
### Behoben
- „Nochmals konvertieren“ übersprang alle Dateien
- Abgebrochene Songs zählten als Fehler
- Vorhandene Stem-Datei konnte beim Überschreiben verloren gehen
- Liste übersteht Stromausfall beim Speichern
- Diverse kleine Fehler

## 1.7.1 – 14. Oktober 2026
### Neu
- Fenster „Weitere Einstellungen“ (Zahnrad)
- Symbol neben der Uhr mit Fortschritt und Fertig-Meldung
- Knopf „Traktor-Farben“
- Installer (Setup.exe) neben dem ZIP
- Fehlerbericht senden (nur von Hand, nichts automatisch)
### Verbessert
- Sicherere Downloads (Prüfsummen fest eingebaut)
- Klare Meldung bei Pfaden über 260 Zeichen
- StemPlayer 1.4: weist falsche Dateien mit klarer Meldung ab
### Behoben
- Herunterfahren von Windows während einer Umwandlung: jetzt sauberer Abbruch
- Falsche Versionsnummer unter „Apps & Features“ nach einem Update

## 1.7 – 6. Oktober 2026
### Neu
- „Anhören“ im StemPlayer
- „Ordner nach der Umwandlung öffnen“
- Club-Pegel (Lautstärke angleichen) und Bass-Fix
- Update-Prüfung beim Start und „Nach Updates suchen“
- StemPlayer 1.3: Design „Traktor Dark“, Stumm, Solo und Regler pro Stem
### Verbessert
- Tags: auch BPM, Tonart, Label und ISRC
- Feste ffmpeg-Version mit Prüfsumme
- Log mit Lautheit und Tempo, Datei statistik.csv
### Behoben
- StemMaker liess sich manchmal nicht beenden
- Gleiche Dateinamen aus verschiedenen Ordnern gingen verloren
- demucs rechnete nach einem Absturz im Hintergrund weiter

## 1.6 – 2. Oktober 2026
### Neu
- Erste öffentliche Version auf GitHub
- Ganze Sammlungen umwandeln, Liste läuft nach Absturz oder Neustart weiter
- PC danach herunterfahren (mit Countdown)
- Deutsch und Englisch
### Behoben
- Umlaute in Dateinamen (z. B. „Tiësto“)
- StemCLI las StemMaker.ini nicht

## 1.5
### Neu
- PC bleibt während der Umwandlung wach
- Neues Programm-Icon, neuer Name „Elospeed StemMaker“
### Verbessert
- Energiesparplan während der Umwandlung auf Leistung (ca. 8 % schneller)
- AAC-Bitrate richtet sich nach der Quelle

## 1.4
### Verbessert
- Alle Prozessorkerne genutzt, auf älteren PCs etwa doppelt so schnell
- Bessere Restzeit-Schätzung

## 1.0 – 1.3
### Neu
- Audiodateien zu Traktor-Stem-Dateien (Master, Drums, Bass, Other, Vox)
- Startfenster lädt ffmpeg und das Trenn-Modell selbst herunter
- StemCLI für die Kommandozeile
