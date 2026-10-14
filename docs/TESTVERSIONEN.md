# Testversionen

🇬🇧 *This file is kept in German. English readers: see the [README](../README.md).*

Testversionen sind fertig gebaute Programme zum **Ausprobieren**, bevor sie in ein offizielles Release kommen.
Sie werden automatisch von **GitHub Actions** gebaut, aber **nicht mehr öffentlich auf GitHub veröffentlicht** (keine Vor-Releases `test-main` / `test-pr-<Nummer>` mehr).
Der Workflow steht in [`.github/workflows/build.yml`](../.github/workflows/build.yml).

## Wie es abläuft

1. Jeder Pull Request und jeder Push auf `main` baut StemMaker, StemCLI, StemPlayer, die Test-AddOns und ein Test-Setup auf Windows. Schlägt der Build fehl, ist der PR rot.
2. Die fertigen Dateien hängen als **Artefakt** am Build-Lauf unter *Actions* (nur mit GitHub-Login, 14 Tage), samt `SHA256SUMS.txt`.
3. Wer testet, bekommt die Exes als **ZIP mit Anleitung** im privaten Projektordner. Vorher werden die Prüfsummen kontrolliert und die Programme kurz unter Wine gestartet.

Alte Vor-Releases mit Tag `test-...` löscht der Job `aufraeumen` im Workflow automatisch.

## So testen

- **StemMaker:** `StemMaker.exe` in einer Kopie der StemMaker-Installation ersetzen. Einstellungen, Liste, Logs, Modelle und ffmpeg bleiben erhalten.
- **StemPlayer:** `StemPlayer.exe` in den Ordner `AddOns\` kopieren, damit `tools\ffmpeg.exe` gefunden wird.
- **StemCLI:** neben `StemMaker.exe` legen.
- **Installer:** `StemMaker-Setup-Test.exe` installiert nach `%LOCALAPPDATA%\Programs\StemMaker`, Version z. B. `1.7-test`. Der Build hat das Setup vorher schon auf Windows still installiert, drüberinstalliert und deinstalliert (`installer/setup-testen.ps1`).

Die Exes sind nicht signiert. Windows SmartScreen warnt deshalb: „Weitere Informationen“ → „Trotzdem ausführen“ (Details in der [LIESMICH](../LIESMICH.md#windows-warnung-der-computer-wurde-durch-windows-geschützt)).

## Gut zu wissen

- Die Update-Prüfung in StemMaker liest nur `update.json` und bietet Testversionen nie an.
- Offizielle Releases (z. B. `v1.7` mit dem vollständigen ZIP) werden weiterhin von Hand angelegt.
- Testversionen gehören nicht ins Repository (früher Ordner `Temp/`): jede eingecheckte Exe bliebe für immer im Git-Verlauf.
