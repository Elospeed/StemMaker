# Elospeed StemMaker 1.7

**by Elospeed**

🇬🇧 **English version:** [README.md](README.md)

Macht aus MP3s (auch WAV, FLAC, AIFF, M4A, OGG) **Traktor-Stem-Dateien (`*.stem.mp4`)** mit 4 Spuren: Drums, Bass, Other (Melodie) und Vox.
Das Prinzip ist dasselbe wie bei [Stemgen](https://github.com/axeldelafosse/stemgen), nur **ohne Python** und ohne Setup: ein Lazarus-Programm, das alles Nötige beim ersten Start selbst holt.

**Warum StemMaker**

- **Nichts einzurichten:** eine 4 MB grosse Windows-EXE. Die Trennung steckt als C++-Code ([demucs.cpp](https://github.com/sevagh/demucs.cpp)) direkt drin, statt über Python zu laufen. Keine Python-Umgebung, kein PyTorch, kein CUDA-Treiber und nichts, was sich mit anderer Software beisst. Gerechnet wird auf dem Prozessor jedes 64-Bit-Windows-PCs.
- **Traktor-Format statt vier Einzeldateien:** Master und die vier Stems landen in einer `.stem.mp4` mit den NI-Stem-Metadaten, fertig für das Stem-Deck. Kein Routing von Hand, keine Zusatzsoftware für den Container, keine Traktor-Lizenz zum Umwandeln.
- **Für ganze Sammlungen gebaut:** ganze Ordner hinzufügen, vorher die geschätzte Dauer sehen, über Nacht laufen lassen. Die Liste wird nach jeder Datei gespeichert, ein Absturz oder Stromausfall kostet also einen Track und nicht den ganzen Lauf. Unterordner werden im Ausgabeordner nachgebaut.
- **Vorher reinhören:** `AddOns\StemPlayer.exe` spielt eine fertige Stem-Datei mit Stumm, Solo, Lautstärke und Pegelanzeige pro Stem und A/B gegen das Original. Kein Testimport in Traktor nötig.
- **Pegel und Bass sitzen:** Leise Dateien werden ohne Limiter auf Club-Pegel angehoben, und Tiefbass, den das Modell im Melodie-Stem lässt, wandert in den Bass-Stem.
- **Qualität:** Im direkten Vergleich mit einer Stem-Datei, die Traktor Pro 4 aus demselben Track gemacht hat, waren Drums, Kick, Gesang und Pegel praktisch gleich.
- **Deine Musik bleibt lokal:** kein Konto, keine Cloud, keine Telemetrie, nichts, was im Hintergrund läuft.

```
MP3 ──ffmpeg──► 44.1 kHz WAV ──demucs.cpp──► drums / bass / other / vocals
                                                     │
      Master + 4 Stems ──ffmpeg (AAC/ALAC)──► MP4 mit 5 Spuren
                                                     │
                       StemMaker (Pascal) ──► NI-„stem“-Metadaten ──► *.stem.mp4
```

## Loslegen

Auf der [Release-Seite](https://github.com/Elospeed/StemMaker/releases/latest) gibt es zwei Downloads mit demselben Programm:
- **`StemMaker-<Version>-Setup.exe`** (Installer): installiert nur für deinen Windows-Benutzer, ohne Administratorrechte, nach `%LOCALAPPDATA%\Programs\StemMaker`, mit Startmenü-Eintrag und Eintrag zum Deinstallieren unter „Apps & Features“. Beim Deinstallieren von Hand fragt er, ob die heruntergeladenen Modelle, ffmpeg und die Einstellungen auch weg sollen.
- **`StemMaker-<Version>.zip`** (portabel): irgendwohin entpacken, z. B. nach `C:\Tools\StemMaker` oder auf einen USB-Stick. Es wird nichts installiert.

1. Installer ausführen oder ZIP entpacken.
2. `StemMaker.exe` starten (nach dem Installer: Startmenü-Eintrag „StemMaker“). Zeigt Windows ein blaues Warnfenster, siehe [Windows-Warnung](#windows-warnung-der-computer-wurde-durch-windows-geschützt).

**Beim ersten Start auf einem PC** zeigt ein Fenster den Haftungsausschluss und die Lizenzhinweise. Häkchen setzen und **„Einverstanden - StemMaker starten“** klicken. Das kommt einmal pro PC: Wird der StemMaker-Ordner auf einen anderen PC kopiert, fragt er dort noch einmal (kein Kopierschutz, Kopieren ist nach der MIT-Lizenz erlaubt). `AddOns\StemCLI.exe` will dieselbe Bestätigung einmal mit `--accept`. Den Text findest du jederzeit wieder unter **Info → Lizenzen**.

Danach öffnet sich das **Prüffenster**. Es hakt der Reihe nach ab: Prozessor, ffmpeg, demucs, Modell und Temp-Ordner.
- **Alles grün:** Nach knapp einer Sekunde geht das Hauptfenster von selbst auf.
- **Beim allerersten Start** fehlen ffmpeg (ca. 56 MB) und das Trenn-Modell (81 MB). Ein Klick auf **„Herunterladen“** lädt beides mit Fortschrittsbalken. Jeder Download wird mit der SHA-256-Prüfsumme aus `update.json` kontrolliert; eine kaputte oder ausgetauschte Datei wird verworfen. Danach wird neu geprüft, und StemMaker startet.
- **Etwas ist rot und lässt sich nicht herunterladen** (z. B. fehlt eine demucs-Datei): Das ZIP bitte komplett neu entpacken. Über der roten Zeile steht beim Überfahren mit der Maus der genaue Grund.

**Updates:** Beim Start schaut StemMaker im Hintergrund (max. 5 Sekunden), ob es eine neuere Version gibt. Wenn ja, kommt **Jetzt aktualisieren / Später / Diese Version überspringen**. Das Update wird mit seiner SHA-256-Prüfsumme kontrolliert; Einstellungen, Liste, Logs, Modelle und ffmpeg bleiben erhalten. Nie während einer Umwandlung. Geht beim Kopieren etwas schief, dreht StemMaker alles zurück und bleibt auf der alten Version. Von Hand suchen: **Info → Nach Updates suchen** (zeigt auch eine übersprungene Version wieder an). Abschalten über das Häkchen im Update- oder Info-Fenster oder `AutoCheck=0` (siehe unten).

Wählst du im Hauptfenster ein Modell, das noch nicht installiert ist (z. B. htdemucs_ft), fragt StemMaker, ob es jetzt geladen werden soll.

## Windows-Warnung („Der Computer wurde durch Windows geschützt“)

StemMaker ist nicht digital signiert. Signier-Zertifikate kosten jedes Jahr Geld, und das lohnt sich für ein kostenloses Hobby-Projekt nicht. Deshalb zeigt Windows beim ersten Start des Installers `StemMaker-<Version>-Setup.exe`, von `StemMaker.exe`, `StemCLI.exe` oder `AddOns\StemPlayer.exe` ein blaues SmartScreen-Fenster („Der Computer wurde durch Windows geschützt“, Herausgeber „Unbekannt“). Das ist bei vielen kleinen Open-Source-Programmen so.

**So startest du es trotzdem:**
1. Im blauen Fenster auf **„Weitere Informationen“** klicken.
2. Auf **„Trotzdem ausführen“** klicken.

Windows merkt sich das, das Fenster kommt pro Programm nur einmal.

**Tipp:** Vor dem Entpacken mit der rechten Maustaste auf das heruntergeladene ZIP → **Eigenschaften** → unten das Häkchen **„Zulassen“** setzen → OK. Dann behandelt Windows die entpackten Dateien als lokal und warnt meist gar nicht.

**Wenn Windows komplett blockiert** (kein Knopf „Trotzdem ausführen“): Dann ist die intelligente App-Steuerung (Smart App Control, Windows 11) eingeschaltet. StemMaker lässt sich dann nur starten, wenn du sie unter *Windows-Sicherheit → App- & Browsersteuerung → Intelligente App-Steuerung* ausschaltest. Mach das nur, wenn du der Quelle vertraust.

**Download prüfen?**
- ZIP oder exe bei [VirusTotal](https://www.virustotal.com) hochladen. Einzelne Treffer von wenig bekannten Scannern sind bei unsignierten Programmen häufig und meist Fehlalarme.
- Wenn in den Release-Notizen eine SHA-256-Prüfsumme steht, in PowerShell vergleichen: `Get-FileHash .\StemMaker-1.7.zip` (Dateinamen anpassen).
- Der komplette Quellcode liegt in diesem Repository. Du kannst StemMaker selbst kompilieren (siehe [Selber kompilieren](#selber-kompilieren)).

## Spenden

StemMaker ist kostenlos und quelloffen. Vor dem Start erscheint ein kleines Fenster mit der Bitte um eine freiwillige Spende über [Ko-fi](https://ko-fi.com/elospeed). „Tool starten“ geht einfach weiter. Mit dem Häkchen „Beim Start nicht mehr anzeigen“ verschwindet das Fenster dauerhaft. Spenden geht danach weiterhin über **Info → Jetzt spenden**.

## Ordnerstruktur

```
StemMaker\
  StemMaker.exe          Programm (GUI)
  StemMaker.ini          Einstellungen (entsteht beim ersten Beenden)
  StemMaker_queue.txt    gespeicherte Dateiliste (Warteschlange)
  logs\                  Protokolle der letzten 20 Programmstarts
    statistik.csv        eine Zeile pro umgewandelter Datei (zum Auswerten)
  AddOns\                Zusatzprogramme für Fortgeschrittene
    StemCLI.exe          Kommandozeilen-Version (Batch/Skripte, Aufgabenplanung)
    StemPlayer.exe       Testplayer für .stem.mp4-Dateien (Mute/Solo pro Stem)
  tools\
    demucs_mt.cpp.main.exe      Trennung, Demucs v4 (AVX2-Version)
    demucs_ft_mt.cpp.main.exe   Trennung, Demucs v4 fine-tuned
    demucs_v3_mt.cpp.main.exe   Trennung, Demucs v3
    avx\...                     dieselben für CPUs mit AVX, aber ohne AVX2 (ca. 2011-2013)
    generic\...                 dieselben für noch ältere CPUs
    ffmpeg.exe                  ← wird beim ersten Start geladen
  models\
    ggml-model-htdemucs-4s-f16.bin   ← wird beim ersten Start geladen
  lang\                  Sprachdateien (gettext .po)
  src\                   kompletter Quellcode (Lazarus)
  demucs-build\          Bauanleitung für die demucs-Programme
```

Die demucs-Programme sind komplett statisch gelinkt; sie brauchen keine DLLs und keine Installation. StemMaker erkennt selbst, welche Befehle die CPU kann, und nimmt die schnellste passende Version: AVX2, AVX oder generic. Im Test war die AVX-Version gut 30 % schneller als generic.

## Bedienen

- Dateien oder ganze Ordner **ins Fenster ziehen**, oder „Dateien hinzufügen…“ bzw. „Ordner…“ benutzen. Du kannst sie auch direkt auf `StemMaker.exe` ziehen.
- **Start** verarbeitet die Liste nacheinander. „Abbrechen“ stoppt sofort und räumt die Temp-Dateien auf.
- Unter beiden Fortschrittsbalken stehen **vergangene und geschätzte Restzeit**: oben für die aktuelle Datei, unten für die ganze Liste. Gerechnet wird mit der Länge der wartenden Songs und dem Tempo dieses PCs; mit jeder fertigen Datei wird es genauer. In der Liste steht nach jedem Song, wie lange er gedauert hat, z. B. „OK (4:12)“.
- Das Ergebnis ist `Titel.stem.mp4`, standardmässig neben der Originaldatei. Alternativ wählst du einen Ausgabeordner.
- Tags und das **Cover** werden aus der Quelldatei übernommen: Titel, Artist, Album, Album-Artist, Komponist, Genre, Jahr, Titel- und CD-Nummer, Kommentar, Gruppierung, Liedtext – dazu **BPM**, **Tonart**, **Label** und **ISRC**. Traktor zeigt Titel, Artist, Album, Genre, Label und Cover gleich nach dem Import; BPM und Tonart überschreibt Traktor mit seiner eigenen Analyse.
- **Stem prüfen…** zeigt, ob eine Datei ein gültiger Stem ist (5 Spuren + Stem-Metadaten). Das klappt auch mit gekauften NI-Stems.
- Ein normaler Player spielt nur Spur 1, den Master. Die einzelnen Stems hörst du erst in Traktor.

- **Info** (oben links) zeigt diese Anleitung, die Version und den Namen des aktuellen Logs. Von dort öffnest du auch den Logs-Ordner oder spendest.
- **Log kopieren** legt das Protokoll in die Zwischenablage, z. B. um es bei einem Problem weiterzugeben.

### Ganze Sammlung umwandeln

StemMaker ist dafür gemacht, eine ganze Musiksammlung am Stück vorzubereiten, z. B. über Nacht:

- **Zeitschätzung vor dem Start:** Unter dem unteren Balken steht z. B. „87 Dateien offen, 6:12:40 Musik - Dauer ca. 11:30:00“. Die Länge der Songs liest StemMaker im Hintergrund aus. Das Tempo lernt es mit jedem fertigen Track: Steht dort „(Tempo dieses PCs)“, ist die Schätzung auf deinen Rechner abgestimmt, „(grob geschätzt)“ heisst: noch nicht gemessen.
- **Liste wird gemerkt:** Die Dateiliste mit dem Stand jeder Datei wird laufend gespeichert (`StemMaker_queue.txt`). Stürzt StemMaker ab, fällt der Strom aus oder schliesst du das Programm, ist die Liste beim nächsten Start wieder da. Mit **Start** geht es dort weiter, wo aufgehört wurde. Eine unterbrochene Datei wird neu gemacht. „Liste leeren“ löscht auch die gespeicherte Liste.
- **Unterordner im Ausgabeordner nachbauen:** Fügst du einen ganzen Ordner hinzu, z. B. `D:\Musik\House`, landet `D:\Musik\House\2024\track.mp3` als `<Ausgabeordner>\House\2024\track.stem.mp4`. Gilt nur mit eigenem Ausgabeordner.
- **PC nach Abschluss herunterfahren:** Sind alle Dateien fertig, erscheint ein 60-Sekunden-Countdown mit „Abbrechen“. Danach beendet sich StemMaker sauber und Windows fährt herunter. Das Häkchen gilt nur für den nächsten Durchlauf. Wird abgebrochen, fährt der PC nicht herunter.
- **PC wach halten** (siehe Einstellungen) verhindert, dass Windows mittendrin einschläft.
- Schon fertige Stem-Dateien werden übersprungen (ausser „vorhandene Stem-Dateien überschreiben“ ist an).

### Logs und Fehlersuche

Jeder Programmstart schreibt ein Log in den Ordner `logs`. Jede Zeile wird sofort gespeichert, deshalb ist auch nach einem Absturz alles bis zur letzten Aktion drin. Aufbewahrt werden die letzten 20 Logs.

| Dateiname endet auf | Bedeutung |
|---|---|
| `_LAEUFT.log` | StemMaker läuft gerade |
| `.log` | normal beendet |
| `_FEHLER.log` | normal beendet, aber unterwegs gab es einen Fehler |
| `_ABSTURZ.log` | unerwartet beendet (Absturz, Task-Manager, Stromausfall); wird beim nächsten Start so umbenannt |

Pro Datei steht im Log: Dateigröße, Länge, Quelle (z. B. mp3 320 kbit/s), Lautheit der Master-Spur (LUFS, Umfang, True Peak), Umwandlungszeit und das Tempo in „Sekunden pro Minute Musik“. Diese Zahl hängt nicht von der Song-Länge ab und eignet sich darum zum Vergleichen von Modellen und PCs.

Zusätzlich schreibt StemMaker für jede umgewandelte Datei eine Zeile in `logs\statistik.csv` (Datum, Datei, Größe, Länge, Modell, Kerne, Umwandlungszeit, Sekunden pro Minute Musik, RAM, Lautheit, CPU, Ergebnis). Ändern sich in einer neuen Version die Spalten, wird die alte Datei in `statistik_bis_<Datum>.csv` umbenannt. Die Datei wird nicht aufgeräumt und öffnet sich per Doppelklick in Excel oder LibreOffice (Trennzeichen `;`, Dezimal-Komma). Ist sie gerade in Excel geöffnet, fehlt die Zeile für diese Datei.

Im Log stehen:
- Rechner-Infos: Windows-Version, Prozessor, Kerne, RAM, Grafikkarte
- jeder Aufruf von ffmpeg und demucs mit allen Parametern und dem Ergebnis
- Fortschritt in 10-%-Schritten
- bei Fehlern die Aufrufkette mit Datei und Zeilennummer im Quellcode
- am Ende eines Durchlaufs eine Zusammenfassung: Gesamtzeit, Schnitt pro Track, genutzte Kerne und der höchste RAM-Bedarf von demucs

Die Grafikkarte wird nur aufgeführt. demucs.cpp rechnet ausschliesslich mit der CPU.

### Einstellungen

| Einstellung | Bedeutung |
|---|---|
| Trenn-Modell | **htdemucs**: Standard, gute Qualität. **htdemucs_ft**: beste Qualität, ca. 4× langsamer, 4 Modelldateien. **hdemucs_mmi (v3)**: schneller, etwas schlechter. |
| Teile / Auto | Wie viele Teile des Songs parallel getrennt werden. **Auto** (Standard) rechnet bei jedem Start neu: so viele Teile wie der Prozessor echte Kerne hat, höchstens 4 – und nur so viele, wie der Arbeitsspeicher verkraftet (jeder Teil braucht gut 2 GB: bei 8 GB RAM also höchstens 2). Jeder Teil nutzt zusätzlich weitere Kerne, das wird automatisch verteilt. Ohne Häkchen gilt die eingestellte Zahl. |
| Audio-Format | **AAC automatisch** (Standard): Die Stem-Datei bekommt die Bitrate der Quelle, z. B. MP3 256 → AAC 256, MP3 320 → AAC 320. Grösser bringt nichts, besser als die Quelle wird es nie. Quellen unter 192 kbit/s bekommen 192, damit beim Neu-Kodieren nichts zusätzlich verloren geht. Verlustfreie Quellen (WAV/FLAC) bekommen 320. **AAC 256**: NI-Standard, fest. **AAC 320**: fest. **ALAC**: verlustfrei, sehr gross, nur bei WAV/FLAC-Quellen sinnvoll. Im Log steht pro Datei „Quelle: mp3 320 kbit/s → Stem-Datei AAC 320 kbit/s“. |
| Stems Name/Farbe | So erscheinen die Stems in Traktor. Standard sind dieselben Farben wie bei Stemgen. |
| Lautstärke angleichen (Club-Pegel) | Standardmässig an. Leise Dateien werden angehoben, bis die lauteste Stelle knapp unter 0 dB liegt (ca. −1 dB). Alle 5 Spuren bekommen denselben Wert, ohne Limiter – die Dynamik bleibt wie im Original. Laute Club-Tracks ändern sich kaum. Vorteil: In Traktor sind die Wellenformen der Stems gross und gut lesbar (Autogain hebt nur die Wiedergabe an, nicht die Grafik). Im Log steht z. B. „Lautstärke angleichen: +11.6 dB“. |
| Bass-Fix | Standardmässig an. Den Tiefbass unter 80 Hz, den die Trennung im Stem „Other“ lässt, schiebt StemMaker in den Bass-Stem. Der Bass-Stem klingt dadurch voller, so wie bei Traktors eigenen Stems; alle Stems zusammen klingen unverändert. Bei Dateien über 20 Minuten (DJ-Mixe) wird er ausgelassen, weil er die ganze Spur im Arbeitsspeicher braucht. |
| PC wach halten | Standardmässig an. Während der Konvertierung geht der PC nicht in den Ruhezustand (der Bildschirm darf ausgehen). Steht Windows auf **Energiesparmodus** (oder bei Windows 11 der Energiemodus auf „Beste Energieeffizienz“), wird für die Dauer der Konvertierung auf mehr Leistung umgestellt. Danach ist alles wieder wie vorher, auch nach einem Absturz: Dann stellt StemMaker den alten Plan beim nächsten Start zurück. „Ausbalanciert“ wird nicht angefasst. |

### Kommandozeile (AddOns\StemCLI.exe)

Dasselbe ohne Fenster, z. B. für Batch-Dateien oder die Aufgabenplanung:
```
AddOns\StemCLI.exe "D:\Musik\Neu" -o "D:\Musik\Stems" -m ht -t 4
AddOns\StemCLI.exe track.mp3 -f alac --overwrite
AddOns\StemCLI.exe --check "track.stem.mp4"
```
Optionen: `-o ordner`, `-m ht|ft|v3`, `-t teile`, `-f aac|alac`, `-b auto|kbit` (Standard auto), `--overwrite`, `--keep` (Temp-Ordner behalten), `--no-awake` (PC darf in den Ruhezustand), `--no-normalize` (Lautstärke nicht angleichen), `--no-bassfix` (kein Bass-Fix), `--ffmpeg exe`, `--demucs ordner`, `--models ordner`.
Für die meisten ist das nicht nötig: Das Hauptfenster kann ganze Ordner, Warteschlange und Nachtläufe. StemCLI ist für Automatisierung gedacht (Batch-Dateien, Windows-Aufgabenplanung). Es nutzt dieselben Werkzeuge, Modelle, Sprache und Einstellungen (`StemMaker.ini`) wie das Hauptprogramm und lädt selbst nichts herunter; vorher muss StemMaker.exe einmal gelaufen sein.

### Testplayer (AddOns\StemPlayer.exe)

Eine fertige `.stem.mp4` ohne Traktor anhören: jeden Stem stummschalten, solo hören (auch mehrere gleichzeitig) und in der Lautstärke ändern, mit Pegelanzeigen, A/B-Vergleich mit dem Originalmix und Modus „Rest“ (Original minus Summe aller Stems), der zeigt, was bei der Trennung verloren ging. Aus StemMaker startet er mit **Anhören** (der Öffnen-Dialog zeigt gleich den Ordner der zuletzt umgewandelten Datei) oder per Doppelklick auf eine fertige Datei in der Liste. Sonst Datei öffnen, aufs Fenster ziehen oder als Parameter übergeben: `AddOns\StemPlayer.exe "Track.stem.mp4"`. Er nutzt `tools\ffmpeg.exe` von StemMaker. Quellcode: `src/AddOns/StemPlayer/`.

## Dauer

Die Trennung läuft rein auf dem Prozessor (CPU). Gemessene Werte mit einem 12-Minuten-Track (Extended Mix), umgerechnet auf einen normalen 4-Minuten-Track:

| Rechner | htdemucs (Standard) | hdemucs_mmi (v3) |
|---|---|---|
| Intel i7-12700KF (12 Kerne, 2021) | 22 min → ca. **7–8 min** pro 4-min-Track | 12,5 min → ca. **4 min** pro 4-min-Track |
| Intel i5-2500 (4 Kerne, 2011) | 1 h 22 min → ca. **27 min** pro 4-min-Track | – |

Faustregel: Auf einem aktuellen PC dauert htdemucs etwa **doppelt so lang wie der Song**, v3 etwa **so lang wie der Song**. htdemucs_ft braucht rund viermal so lang wie htdemucs. Die Zeit wächst mit der Songlänge. Grössere Mengen am besten über Nacht laufen lassen.

Ältere Prozessoren ohne AVX2 (z. B. Intel Core i 2./3. Generation) sind deutlich langsamer: Ein 12-Minuten-Track kann dort über eine Stunde dauern. Laptops auf Akku rechnen ebenfalls gebremst, StemMaker zeigt dann einen Hinweis. War der PC zwischendurch im Ruhezustand, steht das am Ende im Log.

## Wie die Stem-Datei aufgebaut ist

Gleich wie bei Stemgen mit `ni-stem`/MP4Box:
- MP4 mit 5 Audiospuren: Spur 1 ist der Master und als einzige *aktiv*, Spuren 2–5 sind Drums/Bass/Other/Vox und *deaktiviert*.
- `moov/udta/stem`: JSON mit Stem-Namen, Farben und Mastering-DSP (Kompressor/Limiter aus, gleiche Werte wie Stemgen).
- iTunes-Tags plus `TAUT = STEM`. BPM steht im Atom `tmpo`, die Tonart in `----:com.apple.iTunes:initialkey`, das Label in `©pub` und die ISRC in `----:com.apple.iTunes:ISRC` – diese vier kann ffmpeg für MP4 nicht schreiben, das macht StemMaker selbst (`uStemMP4`).

## Für Fortgeschrittene: StemMaker.ini

```ini
[Tools]
FFmpeg=D:\Programme\ffmpeg\bin\ffmpeg.exe   ; vorhandenes ffmpeg nutzen
DemucsDir=...                                ; anderer Ordner für demucs
ModelsDir=D:\Modelle                         ; Modelle woanders ablegen

[Download]
FFmpegZipURL=https://...                     ; eigene ffmpeg-Quelle (dann ohne Prüfsumme)
ModelBaseURL=https://...                     ; eigene Quelle für die Modelle

[Update]
AutoCheck=0                                  ; beim Start nicht nach Updates suchen
```

Normalerweise kommen die Download-Adressen aus [`update.json`](update.json) im Repository (feste ffmpeg-Version, Prüfsummen). Zieht eine Datei um, muss nur diese Datei auf GitHub geändert werden.

## Probleme?

- **Download klappt nicht:** Internetverbindung, Firewall oder Proxy prüfen. Notfalls von Hand laden:
  - ffmpeg: <https://www.gyan.dev/ffmpeg/builds/> („release essentials“). `ffmpeg.exe` nach `tools\` kopieren.
  - Modelle: <https://huggingface.co/datasets/Retrobear/demucs.cpp/tree/main>. Die `.bin`-Dateien nach `models\` legen.
- **demucs bricht ab:** Das Protokoll unten im Hauptfenster zeigt die letzten Zeilen der Ausgabe. Bei ungewöhnlichen Zeichen im Pfad (z. B. Japanisch) den StemMaker-Ordner in einen einfachen Pfad verschieben. Umlaute sind ok.

## Sprachen

Beim ersten Start fragt StemMaker nach der Sprache; die Windows-Sprache ist vorausgewählt. Ändern lässt sie sich jederzeit im Info-Fenster unter „Sprache:“. Die neue Sprache gilt ab dem nächsten Start.

Die Sprachdateien liegen im Ordner `lang\` (gettext, `.po`). Für eine neue Sprache `lang\StemMaker.pot` kopieren, z. B. nach `lang\fr.po`, und mit [Poedit](https://poedit.net) übersetzen.

## Selber kompilieren

- **StemMaker/StemCLI:** In Lazarus (≥ 2.2, FPC 3.2) `src\StemMaker.lpi` bzw. `src\StemCLI.lpi` öffnen und F9 drücken. Es braucht keine Zusatzpakete, nur LCL und LazUtils, die bei Lazarus dabei sind. Der Code ist ausführlich auf Deutsch kommentiert:

  | Unit | Aufgabe |
  |---|---|
  | `StemMaker.lpr` | Hauptprogramm: erst Prüffenster, dann Hauptfenster |
  | `umain.pas/.lfm` | Hauptfenster, Dateiliste, Worker-Thread |
  | `uinit.pas` | Startfenster mit Prüfungen und Download |
  | `ustemjob.pas` | Umwandlung einer Datei (ffmpeg → demucs → ffmpeg → Metadaten) |
  | `ustemmp4.pas` | schreibt die Traktor-Stem-Infos in die MP4 (reines Pascal) |
  | `udownload.pas` | Download über WinINet + ZIP entpacken |
  | `ulog.pas` | Log-Datei in Echtzeit, Absturz-Erkennung, Rechner-Infos |
  | `ulogui.pas` | fängt unerwartete Fehler ab und schreibt sie ins Log |
  | `udonate.pas` | Spendenfenster vor dem Start |
  | `uinfo.pas` | Info-Fenster |
  | `upower.pas` | PC wach halten, Energiesparplan, Akku, Ruhezustand erkennen |
  | `ulang.pas` | Mehrsprachigkeit: Funktion `_()` und `.po`-Dateien lesen |
  | `ulangui.pas` | Sprachwahl beim ersten Start, Fenster übersetzen |
  | `uqueue.pas` | Warteschlange merken, Song-Längen ermitteln, Tempo lernen |
  | `stemcli.lpr` | Kommandozeilen-Version |

- **Sprachdateien:** `lang-tools/i18n.py` sammelt alle Texte aus dem Code (`_('...')` und `.lfm`) und erzeugt `src/lang/StemMaker.pot` sowie `src/lang/en.po` (im Release in `lang\`) aus `lang-tools/en.json`.
- **Icon:** `art/make_icon.py` (Python + Pillow) zeichnet das Programmsymbol: vier Balken in den Stem-Farben. Ergebnis `StemMaker.ico` in `src\`, Lazarus baut es automatisch ein.
- **demucs.cpp für Windows:** `demucs-build/build_demucs_windows.sh` (Cross-Build unter Linux/WSL mit mingw-w64). Der Patch ändert nur 3 Dinge: `.string()` für Windows-Pfade, wählbare CPU-Architektur statt `-march=native`, und die Tests werden nicht mitgebaut.

## Entwicklung

- [Roadmap](ROADMAP.md): woran gerade gearbeitet wird und was als Nächstes kommt
- [Changelog](CHANGELOG.md): was erledigt ist, pro Version
- [TODO](TODO.md): was als Nächstes getestet, entschieden oder gebaut werden muss
- [Entwicklungslog](docs/ENTWICKLUNGSLOG.md): aufgetretene Probleme und ihre Lösungen
- [Ideen für künftige Versionen](docs/IDEEN.md)

## Lizenzen / Credits

- StemMaker: © 2026 Elospeed, MIT-Lizenz (siehe `LICENSE`).
- [demucs.cpp](https://github.com/sevagh/demucs.cpp) von Sevag Hanssian (MIT) – die Trennprogramme in `tools\`.
- Die [Demucs](https://github.com/facebookresearch/demucs)-Modelle stammen von Alexandre Défossez u. a. / Meta AI. Sie werden von ihrem Originalort geladen und von StemMaker nicht weiterverteilt – siehe Lizenzhinweis in `THIRD-PARTY-NOTICES.md`.
- [FFmpeg](https://ffmpeg.org) (LGPL, wird beim ersten Start separat aus den Releases dieses Repositorys geladen; unveränderter Windows-Build von BtbN, Version fest in `update.json`).
- Prinzip und Metadaten-Werte nach [Stemgen](https://github.com/axeldelafosse/stemgen) von axeldelafosse (MIT).
- Traktor und STEMS sind Marken von Native Instruments; StemMaker ist kein Produkt von Native Instruments.
- Vollständige Liste aller Bestandteile, Autoren und Lizenzen: **`THIRD-PARTY-NOTICES.md`**.
- Nur für Material verwenden, für das du die Rechte hast.
- **Haftungsausschluss:** StemMaker wird kostenlos und ohne jede Gewährleistung bereitgestellt („wie besehen“), Benutzung auf eigenes Risiko. Der ganze Text erscheint beim ersten Start und unter Info → Lizenzen.
