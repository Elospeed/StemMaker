# Namenskonvention für den StemMaker-Quelltext (Vorschlag)

Stand: 5. Oktober 2026 · nur Vorschlag. Speedy hat entschieden: vorerst bleibt der Code, wie er ist. Steht in der internen Ideenliste.

## 1. Wie es heute aussieht

Ich habe `src/` (ca. 8300 Zeilen) durchgesehen. Es gibt schon eine halbe Konvention, aber nicht durchgängig:

| Art | Heute | Beispiel aus unserem Code |
|---|---|---|
| Felder einer Klasse | `F` + Name (Pascal-Standard) | `FSettings`, `FCancelled`, `FLastPct` (umain.pas) |
| Steuerelemente | Typ-Kürzel | `btnStart`, `chkBassFix`, `cbModel`, `lblCores` |
| Parameter | ohne Kennzeichen | `URL`, `DestFile`, `OnProgress` (udownload.pas) |
| Lokale Variablen | kurz, ohne Kennzeichen | `I`, `S`, `L`, `FS`, `OK`, `Job` |
| Globale Variablen | ohne Kennzeichen | `frmMain` |
| Konstanten | GROSS_MIT_UNTERSTRICH | `APP_VERSION` |

Problem genau wie du es beschreibst: In einer langen Prozedur sieht man bei `Done`, `Total` oder `OK` nicht, ob das ein Parameter, eine lokale oder eine globale Variable ist, und auch nicht den Typ.

## 2. Vorschlag: Bereich + Typ im Namen

Aufbau: **Bereich** (1 Buchstabe) + **Typ** (klein, 1–3 Buchstaben) + **sprechender Name** (englisch, wie bisher).

### Bereich (immer)

| Präfix | Bedeutung | Beispiel |
|---|---|---|
| `g` | global (Unit-Ebene, `var` außerhalb von Prozeduren) | `gboDebugLog` |
| `F` | Feld einer Klasse (privat/protected) | `FboCancelled` |
| `A` | Parameter (Argument) | `AsDestFile` |
| `l` | lokale Variable | `lsErrText` |
| *(keins)* | Schleifenzähler `I`, `J`, `K` | `for I := 0 to ...` |
| `c` / GROSS | Konstante | `APP_VERSION` bleibt |

`F` und `A` sind in der Lazarus-/Delphi-Welt üblich (auch in der LCL selbst), daher nehme ich die statt `m_`/`p_` aus C++.

### Typ (für einfache Typen)

| Kürzel | Typ | Beispiel |
|---|---|---|
| `bo` | Boolean | `FboCancelled`, `lboOK` |
| `i` | Integer | `FiLastPct` |
| `i64` | Int64 | `liTotal` |
| `q` | QWord (Zeiten in ms) | `FqDlStart` |
| `d` | Double / Single | `ldLufs` |
| `s` | string | `AsDestFile` |
| `sl` | TStringList | `FslFiles` |
| `fs` | TFileStream | `lfsOut` |
| `o` | sonstiges Objekt (eigene Klassen) | `FoJob` (TStemJob) |
| `e` | Aufzählung (enum) | `FeSyncStatus` (TItemState) |
| `h` | Windows-Handle | `lhNet` (wie die Windows-API selbst) |

Steuerelemente behalten ihre heutigen Namen (`btnStart`, `chkBassFix` ...). Die stehen in den .lfm-Dateien und in den Ereignis-Namen; umbenennen wäre viel Risiko für nichts, und sie sind schon eindeutig.

### Vorher / nachher (aus umain.pas und udownload.pas)

```pascal
// vorher
FCancelled : Boolean;
FLastPct   : Integer;
FFiles     : TStringList;
function HttpDownload(const URL, DestFile: string; ...): Boolean;
var OK, WasSkipped: Boolean;

// nachher
FboCancelled : Boolean;      // Benutzer hat "Abbrechen" gedrückt
FiLastPct    : Integer;      // zuletzt gemeldete Prozentzahl (0..100)
FslFiles     : TStringList;  // volle Pfade der zu bearbeitenden Dateien
function HttpDownload(const AsURL, AsDestFile: string; ...): Boolean;
var lboOK, lboWasSkipped: Boolean;
```

## 3. Dokumentation der Deklarationen

Unabhängig von den Präfixen schlage ich vor:

1. **Jede** Feld-, globale und Konstanten-Deklaration bekommt einen deutschen Kommentar in derselben Zeile (`//`), bündig ausgerichtet. umain.pas macht das schon teilweise.
2. **Einheit immer nennen**, wenn es eine gibt: `// Startzeit in ms (GetTickCount64)`, `// Lautheit in LUFS`, `// Pegel in dB`.
3. **Gruppen-Überschrift** über zusammengehörigen Feldern, z. B. `// --- Daten für Synchronize aus dem Arbeits-Thread ---`.
4. Bei Prozeduren/Funktionen ein Kopf-Kommentar: was sie tut, jeder Parameter kurz, Rückgabewert.
5. Lokale Variablen nur kommentieren, wenn der Name nicht reicht.

## 4. Ehrliche Einschätzung

**Für die volle Variante (Bereich + Typ):**
- Man erkennt beim Lesen sofort Bereich und Typ, auch in GitHub im Browser oder einem einfachen Editor, wo es kein Maus-Hover gibt.
- Parameter mit `A` verhindern den klassischen Fehler, dass ein Parameter und ein Feld gleich heißen (`FileName` vs. `FFileName`).
- Passt zu deiner Art zu lesen und ist für ein Ein-Personen-Projekt völlig legitim.

**Dagegen:**
- Typ-Präfixe („ungarische Notation") gelten in der modernen Pascal-Welt als veraltet. Lazarus selbst, die RTL und fast alle Bibliotheken nutzen nur `F`, `A`, `T`, `E`, `I`. Wer später mitliest, ist das nicht gewohnt.
- Wenn sich ein Typ ändert (z. B. `Integer` → `Int64`), muss man den Namen mit ändern, sonst lügt er. Das passiert in der Praxis öfter als man denkt.
- Namen werden länger und etwas holpriger (`FslFiles`, `lboWasSkipped`).
- Einmaliger Aufwand: alle Units umbenennen (14 im Hauptprogramm plus StemPlayer), danach Build + Wine-Test.

**Meine Empfehlung:** Bereich-Präfix (`g`/`F`/`A`/`l`) überall, dazu Typ-Präfix **nur** für die einfachen Typen aus der Tabelle (bo, i, i64, q, d, s, e, h). Bei Objekten reicht ein gut gewählter Name (`FFiles`, `FJob`), da sagt der Name meist schon, was es ist. Das ist der beste Kompromiss aus Lesbarkeit und Aufwand. Wenn dir die volle Variante aber lieber ist: kein Problem, Hauptsache durchgängig.

Die Konvention würde ich als `docs/KONVENTIONEN.md` ins Repo legen, damit jede künftige Änderung sich daran hält.

## 5. Umsetzung (falls gewünscht)

- **Erst nach dem Merge von PR #13** (1.7), sonst gibt es überall Konflikte, weil die Umbenennung fast jede Zeile anfasst.
- Unit für Unit, rein mechanisch, keine Logikänderung im selben PR.
- Nach jeder Unit: Build (Windows-Cross-Build) und Test unter Wine; am Ende eine Test-exe für dich.
- AddOn StemPlayer genauso, in einem eigenen Schritt.
