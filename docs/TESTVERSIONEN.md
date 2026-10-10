# Testversionen

🇬🇧 *This file is kept in German. English readers: see the [README](../README.md).*

Testversionen sind fertig gebaute Programme zum **Ausprobieren**, bevor sie in ein offizielles Release kommen.
Sie werden nicht mehr von Hand ins Repository gelegt (früher Ordner `Temp/`), sondern automatisch von **GitHub Actions** gebaut und als **Vor-Release** (Pre-release) veröffentlicht.
Der Workflow steht in [`.github/workflows/build.yml`](../.github/workflows/build.yml).

## Wo finde ich sie?

| Vor-Release | Inhalt | Wann neu gebaut |
|---|---|---|
| `test-main` | aktueller Stand von `main` | bei jedem Push / Merge auf `main` |
| `test-pr-<Nummer>` | Stand eines Pull Requests | bei jedem Push in den PR; wird gelöscht, wenn der PR geschlossen oder gemerged wird |
| `test-<Branch>` | beliebiger Branch | wenn der Workflow „Build“ unter *Actions* von Hand gestartet wird („Run workflow“) |

Direkte Links (kein Login nötig), Beispiel `test-main`:

- https://github.com/Elospeed/StemMaker/releases/download/test-main/StemMaker.exe
- https://github.com/Elospeed/StemMaker/releases/download/test-main/StemCLI.exe
- https://github.com/Elospeed/StemMaker/releases/download/test-main/StemPlayer.exe
- https://github.com/Elospeed/StemMaker/releases/download/test-main/StemMaker-Setup-Test.exe
- https://github.com/Elospeed/StemMaker/releases/download/test-main/SHA256SUMS.txt

Für einen PR einfach `test-main` durch `test-pr-<Nummer>` ersetzen, z. B. `test-pr-20`.
Alle Vor-Releases: https://github.com/Elospeed/StemMaker/releases

Zusätzlich hängt an jedem Build-Lauf unter *Actions* ein Artefakt mit denselben Dateien (30 Tage, nur mit GitHub-Login).

## So testen

- **StemMaker:** `StemMaker.exe` in einer bestehenden StemMaker-Installation ersetzen (vorher die alte Exe umbenennen, z. B. in `StemMaker-alt.exe`). Einstellungen, Liste, Logs, Modelle und ffmpeg bleiben erhalten.
- **StemPlayer:** `StemPlayer.exe` in den Ordner `AddOns\` einer StemMaker-Installation kopieren, damit `tools\ffmpeg.exe` gefunden wird.
- **StemCLI:** neben `StemMaker.exe` legen.
- **Installer:** `StemMaker-Setup-Test.exe` ausführen. Es enthält das aktuelle Release-ZIP (aus `update.json`) mit den frisch gebauten Exes und installiert nach `%LOCALAPPDATA%\Programs\StemMaker`. Unter „Apps & Features“ steht als Version z. B. `1.7-test`. Der Build hat das Setup vorher schon auf Windows still installiert, drüberinstalliert und deinstalliert (`installer/setup-testen.ps1`).

Die Exes sind nicht signiert. Windows SmartScreen warnt deshalb: „Weitere Informationen“ → „Trotzdem ausführen“ (Details in der [LIESMICH](../LIESMICH.md#windows-warnung-der-computer-wurde-durch-windows-geschützt)).
Die Prüfsummen (SHA-256) stehen in `SHA256SUMS.txt` und in der Beschreibung des Vor-Releases.

## Gut zu wissen

- Vor-Releases sind nie „neuestes Release“. Die Update-Prüfung in StemMaker liest nur `update.json` und bietet Testversionen deshalb nie an.
- Jeder neue Build ersetzt das Vor-Release mit demselben Namen. Ein Link zeigt also immer auf den letzten Stand.
- Offizielle Releases (z. B. `v1.7` mit dem vollständigen ZIP) legt Speedy weiterhin von Hand an.
- Die alten Testversionen aus `Temp/` sind aus dem Repository entfernt, liegen aber noch im Git-Verlauf.
