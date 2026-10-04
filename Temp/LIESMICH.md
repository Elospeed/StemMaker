# Temp – Testversionen

Hier liegen fertig kompilierte Programme zum **Ausprobieren**, bevor sie in ein offizielles Release kommen.

Aufbau: `Temp/<Anwendung>/<Version>/`

| Ordner | Inhalt |
|---|---|
| `StemMaker/1.7-anhoeren/` | StemMaker mit allem bis Club-Pegel/Bass-Fix + Knopf „Anhören“ (StemPlayer im Ordner der letzten Datei), Doppelklick in der Liste, „Ordner nach der Umwandlung öffnen“, Erststart-Fenster (Haftungsausschluss/Lizenzen), Info → Lizenzen |
| `StemPlayer/1.3/` | StemPlayer 1.3: Ordner als Parameter öffnet den Dialog gleich dort (für „Anhören“ in StemMaker) |
| `StemPlayer/1.2/` | StemPlayer 1.2 mit neuem Design „Traktor Dark“ (PR #2) |
| `StemMaker/1.7-statistik/` | StemMaker 1.6 + Sperre gegen zweiten Start + Log-Statistik (Dateigröße, Tempo, Lautheit, `logs\statistik.csv`) |
| `StemMaker/1.6-Test/` | StemMaker 1.6 mit Sperre gegen einen zweiten gleichzeitigen Start |
| `StemMaker/1.6.1-test/` | StemMaker 1.6 mit Fehlerbehebung: lässt sich wieder beenden (Längen-Abfrage hing) |

## StemMaker-Testversion

`StemMaker.exe` über die vorhandene `StemMaker.exe` einer 1.6-Installation kopieren (vorher die alte sichern). Einstellungen, Liste, Logs, Modelle und ffmpeg bleiben erhalten.

## StemPlayer testen

`StemPlayer.exe` in den Ordner `AddOns\` einer StemMaker-Installation kopieren, damit `tools\ffmpeg.exe` gefunden wird. Alternativ irgendwo hinlegen, dann fragt der Player beim ersten Öffnen einmal nach ffmpeg.exe.

## StemMaker testen

Beide Testversionen: `StemMaker.exe` in einer bestehenden StemMaker-1.6-Installation ersetzen (vorher die alte exe umbenennen, z.B. in `StemMaker-1.6.exe`). Einstellungen, Liste, Modelle und ffmpeg bleiben erhalten.

`1.6-Test/`: Die neuen Hinweistexte sind auf Deutsch; die englische Übersetzung kommt erst mit der neuen `lang\en.po` der nächsten Version.

`1.6.1-test/`: enthält nur die Fehlerbehebung beim Beenden, noch nicht die Sperre gegen einen zweiten Start. Beides zusammen kommt mit der nächsten Version.

## Hinweise

- Das sind Testversionen, nicht signiert. Windows SmartScreen warnt deshalb: „Weitere Informationen“ → „Trotzdem ausführen“ (Details in der [LIESMICH](../LIESMICH.md#windows-warnung-der-computer-wurde-durch-windows-geschützt)).
- Jede exe, die hier eingecheckt wird, bleibt dauerhaft im Git-Verlauf, auch wenn sie später gelöscht wird. Deshalb nur kleine Programme hier ablegen und alte Versionen nicht immer wieder ersetzen.
