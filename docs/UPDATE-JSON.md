# update.json – Updates, feste ffmpeg-Version und Prüfsummen

🇬🇧 *This file is kept in German.*

[`update.json`](../update.json) liegt im Hauptordner des Repositorys (Zweig `main`). Ab Version 1.7 liest StemMaker diese Datei:

- **beim Start im Hintergrund** (max. 5 Sekunden): Gibt es eine neuere Version, bietet StemMaker das Update an.
- **wenn ffmpeg oder ein Modell heruntergeladen wird**: Adresse und SHA-256-Prüfsumme kommen von hier.

Adresse, die StemMaker liest: `https://raw.githubusercontent.com/Elospeed/StemMaker/main/update.json`

Ist die Datei nicht erreichbar (offline, GitHub gestört), startet StemMaker normal. Downloads laufen dann über die eingebauten Adressen, ohne Prüfsumme.

## Aufbau

| Feld | Bedeutung |
|---|---|
| `version` | neueste Version, z. B. `1.7`. Ist sie höher als die installierte, wird das Update angeboten. |
| `date` | Datum des Releases (nur Info) |
| `page` | Release-Seite für „mehr Infos“ |
| `notes_de` / `notes_en` | „Was ist neu“ im Update-Fenster. Zeilenumbruch mit `\n`. |
| `zip_url` | Release-ZIP (gleicher Aufbau wie bisher: Ordner `StemMaker\` mit allem drin) |
| `zip_sha256` | SHA-256 des Release-ZIPs. **Leer = kein automatisches Update**, dann öffnet StemMaker nur die Release-Seite. |
| `ffmpeg.url` / `ffmpeg.sha256` | feste ffmpeg-Version (ZIP) und ihre Prüfsumme |
| `ffmpeg.entry` | Dateiname im ZIP (immer `ffmpeg.exe`) |
| `ffmpeg.size_mb`, `ffmpeg.version` | nur für Anzeige und Log |
| `models.base_url` | Ordner, aus dem die Modelle geladen werden |
| `models.sha256` | Prüfsumme pro Modelldatei. Leer = wird nicht geprüft. |

Wer in `StemMaker.ini` unter `[Download]` eine eigene Adresse einträgt (`FFmpegZipURL`, `ModelBaseURL`), behält diese – dann ohne Prüfsumme.

## Ablauf bei einem neuen Release (Beispiel 1.7)

1. Speedy erstellt das Release `v1.7` mit `StemMaker-1.7.zip` (wie bisher, **inkl. `AddOns\StemPlayer.exe`**).
2. Prüfsumme ausrechnen, z. B. in PowerShell:
   `Get-FileHash .\StemMaker-1.7.zip -Algorithm SHA256`
   (oder Elospeed rechnet sie aus dem Release aus).
3. In `update.json` eintragen: `version`, `date`, `notes_de`, `notes_en`, `zip_url`, `zip_sha256`. Committen auf `main`.
4. Ab jetzt bekommen alle StemMaker ab 1.7 beim Start das Update angeboten.

**Wichtig:** `update.json` erst ändern, wenn das Release-ZIP online ist. Sonst schlägt der Download bei allen fehl.

## Feste ffmpeg-Version

Statt täglich „latest“ von BtbN lädt StemMaker eine feste, unveränderte Kopie aus einem eigenen Release:

- Release-Tag: `ffmpeg-9.0.2`
- Datei: `ffmpeg-9.0.2-win64-lgpl.zip` (56 MB: `ffmpeg.exe`, `LICENSE.txt`, `QUELLCODE-SOURCE.txt`)
- SHA-256: `d350ded1fd523fdae90064c11b954497d2ba8f9ef3b10a2447f6717acc210af0`
- Herkunft: BtbN `ffmpeg-n9.0-latest-win64-lgpl-9.0.zip` vom 4. Oktober 2026, Version `n9.0.2-22-g46d8f462ee`. Aus dem grossen ZIP (171 MB) wurden nur `ffmpeg.exe` und der Lizenztext übernommen.

Für die LGPL gehört der Quellcode dazu: Im Release zusätzlich `https://github.com/FFmpeg/FFmpeg/archive/46d8f462ee.tar.gz` als Datei anhängen (im Browser herunterladen, dann hochladen).

Neue ffmpeg-Version später: neues Release `ffmpeg-<version>`, dann `ffmpeg.url`, `ffmpeg.sha256`, `ffmpeg.version` in `update.json` ändern. Bestehende Installationen behalten ihr ffmpeg, nur neue Downloads nehmen die neue Version.
