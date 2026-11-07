#!/usr/bin/env python3
# Japanische Schrift für die Linux-AppImage verkleinern.
#
# Wine bringt keine japanische Schrift mit, und viele Linux-Systeme (z. B.
# Ubuntu ohne Sprachpaket, WSL) haben auch keine. Dann erscheint 日本語 in
# der Sprachwahl und die ganze japanische Oberfläche als Kästchen.
# Darum liegt Noto Sans JP (SIL Open Font License 1.1) in der AppImage,
# aber nur mit den Zeichen, die StemMaker braucht (ca. 0,3 MB statt 4,5 MB):
#   - alle Sonderzeichen aus den Sprachdateien (lang/*.po usw.), auch ✓
#   - zusammenhängende japanische Wörter aus den Programmen (z. B. 日本語)
#   - alle Hiragana, Katakana, japanischen Satzzeichen und Zeichen voller Breite
#
#   schrift-japanisch.py <NotoSansJP-Regular.otf> <StemMaker-Ordner> <Ziel.otf>
#
# Braucht fontTools (pip install fonttools).
import os
import re
import sys

from fontTools import subset

BEREICH = "[　-ヿ㐀-䶿一-鿿＀-￯]"
WORT = re.compile(BEREICH + "{2,}")


def zeichen_sammeln(ordner):
    zeichen = set()
    for wurzel, _, dateien in os.walk(ordner):
        for name in dateien:
            pfad = os.path.join(wurzel, name)
            if os.path.getsize(pfad) > 50_000_000:
                continue
            with open(pfad, "rb") as f:
                text = f.read().decode("utf-8", "replace")
            if name.lower().endswith((".exe", ".dll")):
                # in Programmen nur ganze Wörter, einzelne Treffer sind Zufall
                zeichen.update("".join(WORT.findall(text)))
            elif name.lower().endswith((".po", ".txt", ".md", ".ini", ".json", ".csv", ".html")):
                # aus Textdateien alle Nicht-ASCII-Zeichen (auch ✓, Pfeile usw.);
                # was die Schrift nicht hat, lässt fontTools einfach weg
                zeichen.update(c for c in text if ord(c) > 0x7F and c != "\ufffd")
    zeichen.update(chr(c) for c in range(0x3000, 0x3100))  # Satzzeichen, Hiragana, Katakana
    zeichen.update(chr(c) for c in range(0xFF01, 0xFFA0))  # volle und halbe Breite
    zeichen.update(chr(c) for c in range(0x20, 0x7F))      # ASCII
    zeichen.update(chr(c) for c in range(0xA0, 0x100))     # Latin-1
    return zeichen


def main():
    quelle, ordner, ziel = sys.argv[1:4]
    zeichen = zeichen_sammeln(ordner)
    opt = subset.Options()
    opt.layout_features = ["*"]
    opt.name_IDs = ["*"]
    opt.name_languages = ["*"]
    opt.notdef_outline = True
    opt.hinting = False
    # Zeichensatz-Bits (OS/2) wie im Original lassen: Wines Uniscribe sucht die
    # Ersatzschrift für Kanji/Kana mit ANSI_CHARSET; ohne das Latin-1-Bit nimmt
    # Wine die Schrift dort nicht, und mehrzeilige Textfelder zeigen Kästchen
    opt.prune_codepage_ranges = False
    schrift = subset.load_font(quelle, opt)
    teil = subset.Subsetter(opt)
    teil.populate(text="".join(sorted(zeichen)))
    teil.subset(schrift)
    subset.save_font(schrift, ziel, opt)
    print(f"{len(zeichen)} Zeichen, {os.path.getsize(ziel)} Bytes -> {ziel}")


if __name__ == "__main__":
    main()
