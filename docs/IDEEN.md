# Ideen für künftige Versionen – Elospeed StemMaker

Sammlung von Ideen, grob nach Aufwand und Nutzen sortiert. Nichts davon ist versprochen – es ist eine Merkliste. Erledigtes wird ins [CHANGELOG](../CHANGELOG.md) verschoben, der aktuelle Stand steht in der [ROADMAP](../ROADMAP.md).

Legende: 🟢 klein · 🟡 mittel · 🔴 gross

---

## Als Nächstes (Version 1.7)

- 🟡 **Update-Prüfung beim Start** – `update.json` im Repository lesen (max. 5 s, abschaltbar), Dialog „Jetzt aktualisieren / Später / Version überspringen“, Download mit Prüfsumme, laufende Exe in `.exe.old` umbenennen, neue Dateien entpacken (INI, Warteschlange, Logs, Modelle, ffmpeg bleiben), Neustart. Nie während einer Konvertierung. Button „Nach Updates suchen“ im Info-Fenster.
- 🟢 **Feste ffmpeg-Version** statt täglich „latest“ – als eigene Release im Repository, mit Lizenztext und Quellcode (LGPL).
- 🟢 **Prüfsummen (SHA-256)** für alle Downloads (ffmpeg, Modelle, Updates).
- 🟢 **Download-Adressen in `update.json`** – zieht eine Datei um, wird nur diese Datei auf GitHub geändert.
- 🟢 **THIRD-PARTY-NOTICES im Info-Fenster anzeigen.**

## Entscheidungen, die noch offen sind

- 🟢 **v3 (hdemucs_mmi) als Standard?** – fast doppelt so schnell (12:33 statt 22:16 für 12 min). Erst nach Hörvergleich in Traktor (Vocals solo, Instrumental, Drums).
- 🟢 **Discussions** auf GitHub einschalten, wenn Nutzer Fragen haben.

## Zurückgestellt

- 🟢 **„Summe der Stems = Original“** – Spur „Other“ als Original minus Drums, Bass und Vocals berechnen. Alle Stems zusammen klingen dann exakt wie das Original (wie bei NUO Stems). Am 3. Oktober 2026 zurückgestellt: vorerst bleibt es wie bisher.

## Zusatzprogramme (AddOns)

- 🟢 **Einzelnen Stem exportieren** – z. B. nur Vocals oder Drum-Beat als eigene MP3/WAV, für Traktor Remix Decks und Loops.
- 🟡 **Schwester-Tool für Pioneer/Serato/Rekordbox** – einzelne Stems, Acapella/Instrumental als normale Audiodateien. Gleiche `tools\` und `models\`.
- 🟢 **„Eigene Stems verpacken“** – vorhandene Einzelspuren (z. B. aus dem Studio) ohne Trennung zu einer Traktor-Stem-Datei zusammenbauen.

## Quelltext

- 🟡 **Namenskonvention für Variablen** – am Namen sofort erkennen, ob eine Variable global (`g`), Feld der Klasse (`F`), Parameter (`A`) oder lokal (`l`) ist und welchen Typ sie hat (`bo` Boolean, `i` Integer, `s` string ...), z. B. `FboCancelled`, `AsDestFile`. Dazu ein deutscher Kommentar hinter jeder Deklaration, mit Einheit (ms, LUFS, dB). Ganzer Vorschlag mit Vor- und Nachteilen: [NAMENSKONVENTION-VORSCHLAG.md](NAMENSKONVENTION-VORSCHLAG.md). Am 5. Oktober 2026 zurückgestellt: vorerst bleibt es, wie es ist. Falls umgesetzt, erst nach dem Merge von Version 1.7 (fasst fast jede Zeile an).

## Traktor-Integration

- 🔴 **Hotcues und Beatgrid übernehmen** – aus Traktors `collection.nml` vom MP3 auf die Stem-Datei kopieren. Vorsicht: verändert Traktors Sammlung → vorher Sicherung, nur bei geschlossenem Traktor.

## Tempo und Qualität

- 🔴 **Grafikkarte** – ONNX Runtime + DirectML (NVIDIA, AMD, Intel). Ziel: < 1 Minute pro Track. CPU-Weg bleibt als Rückfall.
- 🔴 **Mel-Band RoFormer für Vocals** – deutlich sauberere Gesangsspur; braucht den Grafikkarten-/ONNX-Weg.
- ✅ *Erledigt (Testversion, 4. Oktober 2026):* 🟢 **„Bass verstärken“ (Bass-Fix)** – nach der Trennung den Tiefbass unter ca. 80 Hz aus der Spur „Other“ herausnehmen und zur Spur „Bass“ dazugeben. Die Summe aller Stems bleibt exakt gleich. Hintergrund (Vergleich mit Traktor Pro 4, 4. Oktober 2026, Kungs – Clap Your Hands): Traktor legt den Tiefbass konsequenter in den Bass-Stem (ca. 1,6 dB lauter), bei uns bleibt ein Rest in „Other“. Mit dem Bass-Fix gemessen: Bass-Stem −37,7 → −35,5 dB (Traktor −35,8), „Other“ deutlich näher an Traktor. Als Häkchen in den Einstellungen, kostet kaum Rechenzeit.
- 🟡 **Trennqualität über Traktor-Niveau heben** – Messung 4. Oktober 2026: Traktor Pro 4 und unser Standard-Modell (htdemucs v4) liefern fast gleiche Stems (Drums und Vocals nahezu identisch, gleiche Lautheit, keine Verluste in den Höhen). Wege nach oben: htdemucs_ft als „Beste“-Stufe bewerben (eigenes Bass-Modell, ca. 4x langsamer), später RoFormer-Modelle (siehe oben). Vorerst keine Priorität.
- 🟡 **Hybrid-CPUs (Intel 12. Gen+)** – Aufteilung auf schnelle/sparsame Kerne testen (i7-12700KF: 8 P- + 4 E-Kerne).
- ✅ **Pegel „Traktor-optimiert“?** – *Erledigt (Testversion, 4. Oktober 2026):* als Option „Lautstärke angleichen (Club-Pegel)“ umgesetzt. Grund: Traktors Autogain ändert nur die Wiedergabe, leise Dateien sehen in der Wellenform winzig aus. StemMaker misst die höchste Spitze von Master und Stemsumme und hebt alle 5 Spuren um denselben Wert an (Ziel −1,5 dBFS Spitze, höchstens +24 dB), damit bleibt Summe = Master.
  - Ziel laut Speedy: **alle Stem-Dateien gleich laut.** Machbar als Option „Lautheit angleichen“: vor dem Kodieren `mix.wav` messen und alle 5 Spuren um denselben Wert ändern (Ziel z. B. −10 LUFS). Leiser machen ist problemlos. Lauter machen geht nur, bis der True Peak bei ca. −1 dBFS ankommt; mehr nur mit Limiter, der die Dynamik verändert (dann nicht mehr „wie das Original“). In Traktor mit Autogain hört man davon kaum etwas, in anderen Playern und ohne Autogain schon.
- 🟢 **Stem-Datei schneller kodieren** – die 5 AAC-Spuren parallel statt nacheinander (alter PC: 2:34 min nur fürs Kodieren).

## Sprachen und Verbreitung

- 🟢 **Weitere Sprachen** – Französisch, Italienisch, Spanisch … (`lang\StemMaker.pot` übersetzen, z. B. mit Poedit; Helfer aus der Community).
- 🟢 **Kurzes Video** – MP3 reinziehen → Stem in Traktor; für r/Traktor, NI-Forum, DJ-Gruppen.
- 🟡 **Code-Signing-Zertifikat** – vermeidet die Windows-SmartScreen-Warnung „unbekannter Herausgeber“ (kostet jährlich). *Vorerst verworfen (03.10.2026): Kosten lohnen sich jetzt nicht, kostenlose Option SignPath würde „SignPath Foundation“ statt „Elospeed“ als Herausgeber zeigen. Stattdessen Erklärung in README/LIESMICH.*
- 🟡 **Automatisch bauen mit GitHub Actions** – bei jeder neuen Version Exe und ZIP automatisch erstellen.

## Kleinigkeiten

- 🟢 Log-Datei vollständig in der gewählten Sprache (heute teils deutsch).
- 🟢 Status-Spalte in der Liste mit Farben (grün OK, rot Fehler).
- 🟢 Tempo-Messung auf dem alten i5-2500 mit Version 1.5+ wiederholen (mit Schlafsperre/Energiemodus).
