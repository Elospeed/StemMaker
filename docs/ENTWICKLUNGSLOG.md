# Entwicklungslog – Elospeed StemMaker

Hier steht, welche Probleme bei der Entwicklung aufgetaucht sind und wie sie gelöst wurden. Gedacht für später: damit man (oder jemand anderes) nachlesen kann, *warum* etwas so gebaut ist, und dieselben Fehler nicht nochmals macht.

Neueste Einträge oben.

---

## GitHub-Start (Oktober 2026)

| Problem | Lösung |
|---|---|
| Commits erschienen auf GitHub unter „claude“ statt unter Elospeed. | Beide Commits auf den Autor `Elospeed` (GitHub-noreply-Adresse) umgeschrieben und neu hochgeladen. Künftige Commits laufen direkt unter Elospeed. Der Kasten „Contributors“ auf der Startseite aktualisiert sich bei GitHub mit Verzögerung. |
| Spenden-Button auf GitHub fehlte. | `.github/FUNDING.yml` mit `ko_fi: elospeed` angelegt; zusätzlich in den Repository-Einstellungen „Sponsorships“ einschalten. |
| Rechtliche Frage: darf man fremde Teile im eigenen Repository haben? | demucs.cpp (MIT) und FFmpeg (LGPL, mit Lizenz + Quellcode) dürfen weitergegeben werden. Die Lizenz der Demucs-Modelle ist unklar → Modelle werden **nicht** selbst verteilt, sondern vom Originalort geladen. Alles dokumentiert in `THIRD-PARTY-NOTICES.md`. |

---

## Version 1.6 – Sammlungen, Sprachen, AddOns

| Problem | Lösung |
|---|---|
| Wunsch: ganze Sammlungen über Nacht umwandeln, auch nach Absturz weitermachen. | Warteschlange wird laufend in `StemMaker_queue.txt` gespeichert (erst in Hilfsdatei schreiben, dann umbenennen → nie halb geschrieben). Beim Start wiederhergestellt, unterbrochene Datei wird neu gemacht. |
| Das Countdown-Fenster „PC herunterfahren“ fror das ganze Programm ein. | Es wurde im Ende-Ereignis des Arbeits-Threads (`OnTerminate`) geöffnet. Ein Fenster mit eigener Warteschleife blockiert dort alles. Lösung: über `Application.QueueAsyncCall` kurz danach öffnen. **Regel: in OnTerminate nie modale Fenster.** (Gleicher Fehler wie früher beim Prüffenster nach dem Download.) |
| Mehrsprachigkeit ohne die Lesbarkeit des deutschen Codes zu verlieren. | Eigene kleine Funktion `_('deutscher Text')` + gettext-`.po`-Dateien (eigener Leser, ohne LCL → auch in StemCLI). Neue Sprache = neue `.po`-Datei in `lang\`. |
| Programmlogik hing an angezeigten Texten („OK“, „Abgebrochen“) – mit Übersetzung wäre sie kaputtgegangen. | Zustände als Zahlen im Data-Feld der Listenzeile (`ST_WAIT`, `ST_OK`, …). **Regel: nie auf übersetzte Texte prüfen.** |
| StemCLI hat nie die Einstellungen von StemMaker gelesen. | Es suchte `StemCLI.ini` statt `StemMaker.ini` (Fehler seit 1.0). Jetzt nutzen beide `StemMaker.ini` über `AppBaseDir`. |
| StemCLI im Unterordner `AddOns\` fand tools, Modelle und Sprachen nicht mehr. | `AppBaseDir`: liegt kein `tools\` neben der Exe, aber eine Ebene höher `StemMaker.exe`, gilt der Ordner darüber als Hauptordner. |
| Song-Längen für die Zeitschätzung lesen. | `ffmpeg -i datei` im Hintergrund-Thread, „Duration:“ auswerten. Prozesse immer mit `TProcessUTF8` starten (Umlaute wie „Tiësto“). |
| Unter Wine fehlte englische Ausgabe in StemCLI trotz Einstellung. | Folge des INI-Fehlers oben. |
| Compiler-Fehler `FindClose`, `GetEnvironmentVariable`. | Wenn die Unit `Windows` eingebunden ist, gleichnamige Funktionen mit `SysUtils.` qualifizieren (wie schon `DeleteFile`, `CopyFile`). |

---

## Version 1.5 – Energie, Icon, Name

| Problem | Lösung |
|---|---|
| Schneller PC brauchte 45 min statt ~22 min: 20 min Lücke im Log. | Windows ging in den **Ruhezustand**. Lösung: `SetThreadExecutionState` (Schlafsperre) während der Konvertierung. Zusätzlich Standby-Erkennung über `QueryUnbiasedInterruptTime` im Log. |
| Windows 11 stand auf „Beste Energieeffizienz“ → langsamer. | Energieplan bzw. Win11-Energiemodus vorübergehend umstellen; alten Wert vorher in der INI sichern → auch nach Absturz wird zurückgestellt. Gemessen: ~8 % schneller. |
| PCs mit wenig RAM wären mit 4 Teilen ausgelagert (8,6 GB Bedarf beim 12-min-Track). | „Auto“ begrenzt die Teile zusätzlich nach RAM: 2,3 GB pro Teil + 2 GB Reserve. |
| Windows 11 wurde als „Windows 10“ angezeigt. | Windows schreibt auch bei 11 „Windows 10“ in die Registry. Erkennung über Build-Nummer ≥ 22000. |
| „Threads“ war irreführend (gemeint sind Teile). | Umbenannt in „Teile“, daneben Anzeige „je X Kerne (Y von Z)“. |
| MP3 mit 256 kbit/s wurde unnötig mit 320 gespeichert. | „AAC automatisch“: Bitrate der Quelle (mind. 192, max. 320). |
| Icon: Fehlermeldung „Bitmap with unknown compression“ beim Start. | Pillow speichert ICO-Bilder als PNG; Lazarus kann nur klassische Bitmaps lesen → `bitmap_format='bmp'`. |
| Name „StemMaker“ zu allgemein, „Traktor“ ist eine Marke. | Anzeigename „Elospeed StemMaker“ (eine Konstante `APP_NAME`), Dateinamen bleiben `StemMaker.*`. |

---

## Version 1.4 – erster Test auf altem PC (i5-2500)

| Problem | Lösung |
|---|---|
| Nur 2 von 4 Kernen genutzt. | Kerne wurden pauschal halbiert (Hyperthreading angenommen). Jetzt echte Kerne über `GetLogicalProcessorInformation`. |
| Langsamste demucs-Version (generic) auf einer CPU mit AVX. | Zusätzliche AVX-Variante (Sandy Bridge) gebaut; Auswahl AVX2 → AVX → generic. |
| Restzeit viel zu optimistisch (1 h angezeigt, real > 2 h). | Das Dekodieren füllt die ersten Prozent in einer Sekunde. Jetzt Schätzung aus dem Tempo des aktuellen Arbeitsschritts. |
| Ergebnis | i5-2500: von ~2:45 h auf 1:22 h für 12 min Musik. AVX allein brachte dort wenig – der alte Arbeitsspeicher bremst. |

---

## Versionen 1.0 – 1.3 – Grundlagen

| Problem | Lösung |
|---|---|
| demucs.cpp liess sich nicht für Windows bauen (`std::filesystem::path` → string). | Kleiner Patch (`.string()`), siehe `demucs-build/windows-build.patch`. |
| Gebaute demucs-Programme brauchten DLLs. | Komplett statisch gelinkt (nur KERNEL32 + msvcrt). |
| Benutzer sollte kein Setup ausführen müssen. | Startfenster prüft alles und lädt ffmpeg und Modell selbst (WinINet, curl als Rückfall). |
| Hänger nach dem Download im Prüffenster. | Neu-Prüfung lief im Ende-Ereignis des Download-Threads → über einen Timer verzögert. |
| Absturz beim Freigeben des Worker-Threads. | Thread nicht im eigenen `OnTerminate` freigeben, sondern per `QueueAsyncCall` + `WaitFor`. |
| Exe 28 MB gross. | Debug-Informationen der LCL abgeschaltet → ~8 MB. |
| Unit `uLog` mit Oberfläche machte StemCLI kaputt. | Aufgeteilt: `uLog` (ohne Oberfläche) und `uLogUI`. |
| RAM-Spitze von demucs war unter Wine immer 0. | Speicher wird während der Laufzeit jede Sekunde abgefragt statt nur am Ende. |
| Abstürze sollten nachvollziehbar sein. | Log in Echtzeit, Dateiname `_LAEUFT` → beim nächsten Start `_ABSTURZ`; Fehler mit Aufrufkette (`_FEHLER`). Letzte 20 Logs bleiben. |

---

## Werkzeug-Hinweise (Entwicklungsumgebung)

- Getestet wird unter Linux mit Wine (Windows-Exe) und Xvfb (Bildschirmfotos); echte Tests auf Windows-PCs durch Elospeed mit Logs.
- `pkill -f <text>` kann die eigene Shell beenden, wenn der Text im Befehl vorkommt → Prozesse gezielt mit `pkill -x Name` beenden.
- Wine braucht nach `wineserver -k` einige Sekunden, bevor ein Fenster erscheint.
