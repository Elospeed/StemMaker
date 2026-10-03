# Temp – Testversionen

Hier liegen fertig kompilierte Programme zum **Ausprobieren**, bevor sie in ein offizielles Release kommen.

Aufbau: `Temp/<Anwendung>/<Version>/`

| Ordner | Inhalt |
|---|---|
| `StemPlayer/1.2/` | StemPlayer 1.2 mit neuem Design „Traktor Dark“ (PR #2) |

## StemPlayer testen

`StemPlayer.exe` in den Ordner `AddOns\` einer StemMaker-Installation kopieren, damit `tools\ffmpeg.exe` gefunden wird. Alternativ irgendwo hinlegen, dann fragt der Player beim ersten Öffnen einmal nach ffmpeg.exe.

## Hinweise

- Das sind Testversionen, nicht signiert. Windows SmartScreen kann deshalb warnen.
- Jede exe, die hier eingecheckt wird, bleibt dauerhaft im Git-Verlauf, auch wenn sie später gelöscht wird. Deshalb nur kleine Programme hier ablegen und alte Versionen nicht immer wieder ersetzen.
