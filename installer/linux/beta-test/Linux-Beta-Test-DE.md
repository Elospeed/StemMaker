# StemMaker für Linux (Beta) – Testanleitung

Danke, dass du die Linux-Version von StemMaker ausprobierst! Sie ist eine **Beta**: Es ist die normale Windows-Version, die in einer einzigen Datei (AppImage) mit einem eingebauten Wine läuft. Du musst nichts installieren, Wine auch nicht.

Dauer: etwa 20–30 Minuten.

## Was du brauchst
- Ein 64-Bit-Linux (getestet: Ubuntu 24.04, Debian 12, Fedora, Arch)
- Etwa 1 GB freien Platz (Programm + Modell, das beim ersten Start geladen wird)
- Internet beim ersten Start
- Ein, zwei eigene Songs (MP3, FLAC oder WAV)

## 1. Herunterladen und starten
1. Das ZIP **StemMaker-2.2.1-beta1-Linux-Test.zip** entpacken (Download: https://github.com/Elospeed/StemMaker/releases/tag/v2.2.1-linux-beta1). Darin liegen die AppImage, diese Anleitung (DE/EN) und `SHA256SUMS.txt` zum Prüfen (`sha256sum -c SHA256SUMS.txt`).
2. Datei ausführbar machen: rechte Maustaste → Eigenschaften → „Als Programm ausführen“ erlauben. Oder im Terminal:
   ```
   chmod +x StemMaker-2.2.1-beta1-x86_64.AppImage
   ./StemMaker-2.2.1-beta1-x86_64.AppImage
   ```
3. Startet sie nicht und es erscheint etwas mit **FUSE**: bei Ubuntu 24.04 `sudo apt install libfuse2t64` ausführen, bei älteren Ubuntu/Debian `sudo apt install libfuse2`.

Der erste Start dauert länger (Wine richtet sich ein, ca. 30 s). Deine Daten liegen danach in `~/.local/share/StemMaker-Wine/`.

## 2. Was bitte prüfen

| # | Test | Worauf achten |
|---|---|---|
| 1 | **Erster Start** | Sprachwahl, Lizenz-Hinweis, Modell-Download laufen durch? |
| 2 | **Fenster** | Ist alles lesbar und nicht abgeschnitten? Lässt sich das Fenster **minimieren**, vergrössern, verkleinern? Zeigt das Dock / die Taskleiste das StemMaker-Symbol? |
| 3 | **Umwandlung** | Einen Song hinzufügen („Dateien hinzufügen“ oder ins Fenster ziehen) und umwandeln. Läuft es durch? Wie lange hat es gedauert (steht im Log)? |
| 4 | **Drag & Drop** | Datei aus deinem Dateimanager in StemMaker ziehen. Klappt das? |
| 5 | **StemPlayer** | Rechts auf die Kachel StemPlayer klicken, die fertige .stem.mp4 öffnen und abspielen. Kommt **Ton**? Knackst oder stockt er? Spuren stummschalten, Loop A-B ausprobieren. |
| 6 | **StemTagger** | Kachel StemTagger, die .stem.mp4 öffnen, z. B. Genre ändern, speichern, erneut öffnen: ist die Änderung da? |
| 7 | **Turbo (optional)** | In den Einstellungen Turbo einschalten und nochmals umwandeln. Unter Linux rechnet Turbo zurzeit nur auf der CPU. |
| 8 | **DJ-Software (optional)** | Die .stem.mp4 in Traktor (falls vorhanden) oder Mixxx 2.6 öffnen. Werden die 4 Spuren erkannt? |

## 3. Was du mir bitte zurückschickst
Am liebsten als Beitrag in den [GitHub-Diskussionen](https://github.com/Elospeed/StemMaker/discussions) oder per Mail an elospeed.dev@gmail.com:

- Deine **Distribution und Version** (z. B. „Ubuntu 24.04, GNOME, Wayland“) und den Desktop (GNOME, KDE, …)
- Prozessor und Arbeitsspeicher (grob reicht)
- Pro Test oben: **geht / geht nicht / komisch**, kurz was passiert ist
- Gern **Screenshots**, besonders wenn etwas falsch aussieht
- Bei Fehlern das Log: im Info-Fenster der Knopf „Fehlerbericht senden...“, oder die neueste Datei aus `~/.local/share/StemMaker-Wine/prefix/drive_c/StemMaker/logs/`
- Startet die AppImage gar nicht: im Terminal starten und den Text, der erscheint, kopieren

## Bekannte Punkte (bitte nicht als Fehler melden)
- **Turbo** nutzt unter Linux noch **nicht die Grafikkarte**, nur die CPU.
- **„Ordner öffnen“** zeigt den einfachen Dateimanager von Wine statt deinem eigenen.
- Die **Dialoge** (Dateien öffnen, Speichern) sehen aus wie unter Windows, deine Linux-Ordner findest du unter Laufwerk **Z:**.
- **Japanische Dateinamen**: dafür die Noto-CJK-Schriften installieren (Ubuntu/Debian: `fonts-noto-cjk`).
- In einer **virtuellen Maschine** kann der Ton stocken; auf einem echten PC sollte das nicht passieren. Wenn doch, bitte melden.
- **Symbol im Dock**: das richtige StemMaker-Symbol erscheint sicher erst, wenn die AppImage ins System eingebunden ist (z. B. mit „Gear Lever“ oder „AppImageLauncher“). Direkt gestartet kann ein allgemeines Symbol erscheinen.

Danke! Speedy · Elospeed
StemMaker: https://elospeed.github.io/StemMaker/ · Alle Tools: https://elospeed.github.io/
