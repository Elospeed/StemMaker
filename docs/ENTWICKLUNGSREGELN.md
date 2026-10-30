# Entwicklungsregeln – Elospeed StemMaker

Verbindliche Regeln für alle, die an diesem Repository arbeiten (Menschen und Werkzeuge). **Vor jeder Arbeit an der Oberfläche (Fenster, Dialoge, Layout) diese Datei lesen.** Hintergrund und Einzelfälle stehen im [Entwicklungslog](ENTWICKLUNGSLOG.md).

Die Regeln gelten gleich für alle Elospeed-Programme (StemMaker mit allen AddOns, WinKeeper, LedPreResistor, Network Ping Tool und jedes neue Programm).

## 1. Windows-Skalierung (DPI) – gilt für jedes Fenster

**Warum:** Im Oktober 2026 waren mehrere Programme bei 125–200 % Windows-Skalierung kaputt: Fenster höher als der Bildschirm, Mindestgrösse gleich Startgrösse (Fenster liess sich nicht verkleinern), Inhalte überlappten, Knöpfe doppelt so breit. Gemeldet hat es ein Benutzer, nicht unser Test. Das darf nicht nochmals passieren, auch nicht in neuen Programmen.

**Ziel:** Jedes Fenster jedes Programms (auch AddOns, Dialoge, Meldungen) sieht bei **100 %, 125 %, 150 % und 200 %** richtig aus.

### Regeln

1. **Keine festen Pixelwerte in eigenem Code**, der nach dem Aufbau des Fensters läuft (Ansichtswechsel, `SetBounds`, Constraints, Fenstergrössen, Abstände). Immer umrechnen: `Scale96ToForm` / `ScaleDesignToForm`.
2. **Nichts doppelt skalieren.** Lazarus rechnet jedes Fenster (auch aus `CreateNew`) erst in `AfterConstruction` um, *nach* Konstruktor und `OnCreate`. Feste Pixel im Konstruktor sind darum richtig; Werte, die dort schon mit `Screen.PixelsPerInch` oder echten Textbreiten entstehen, werden nochmals vergrössert. Solche Werte auf 96 dpi zurückrechnen.
3. **Gemeinsame Skalierungs-Unit verwenden** (`src/uskalierung.pas`), nicht neu erfinden. Sie begrenzt jedes Fenster beim Anzeigen auf den freien Bildschirm. Dialoge, die mit `TForm.CreateNew` erzeugt und *danach* aufgebaut werden, vor `ShowModal` mit `SkaliereDialog(F)` umrechnen. Wenn der Konstruktor schon mit `Scale96ToForm` rechnet, gleich nach `inherited CreateNew` `StelleAufBildschirmDPI(Self)` aufrufen.
4. **Nie grösser als der freie Bildschirm** (`Screen.WorkAreaHeight`/`WorkAreaWidth`, echter Rahmen inklusive). Prüfungen «passt auf den Bildschirm» erst in `FormShow` mit den echten Grössen.
5. **Mindestgrösse kleiner als die Startgrösse** und passend für den Bildschirm. Reicht der Platz trotzdem nicht: Inhalt in eine `TScrollBox` (Bildlaufleiste) statt abgeschnittener Elemente.
6. **Elemente wachsen mit dem Fenster** (Anker, `Align`). Keine `akRight`-Anker im Konstruktor, solange der Parent noch per `Align` wächst. Versteckte `alTop`-Panels werden nicht neu ausgerichtet: Breite setzen, bevor rechts verankerte Elemente umgehängt werden.
7. **Vergrössern/Maximieren nur, wo Inhalte wirklich mitwachsen.** Ansichten mit festem Layout bekommen eine feste Grösse ohne Maximieren-Knopf.
8. **Gespeicherte Werte in 96-dpi-Einheiten** (Fenstergrösse, Positionen, Spaltenbreiten), beim Laden umrechnen. Sonst wächst das Fenster bei jedem Start oder nach einem Skalierungswechsel.

### Test – vor jedem PR mit GUI-Änderung und vor jedem Release

- Unter Wine mit **100 % und 150 %** testen, bei Platzproblemen auch **200 %** (Full HD, 1920×1080). Screenshots zur Kontrolle.
- 150 % einstellen: `wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 144 /f` (100 % = 96, 125 % = 120, 200 % = 192), danach Programm neu starten.
- Alle Fenster und Ansichten öffnen, auch Ansichtswechsel zur Laufzeit und den Start mit jeder gespeicherten Ansicht.
- Im PR schreiben, bei welchen Stufen getestet wurde.

**Hier im Repo:** Die Regel gilt auch für StemPlayer, StemTagger, StemDecks, Stem51 und TurboTest unter `src/AddOns/`. Die AddOns binden dieselbe `src/uskalierung.pas` ein.
