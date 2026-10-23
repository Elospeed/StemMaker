#!/usr/bin/env python3
"""Benutzerhandbuch von StemMaker als PDF bauen (Deutsch, Englisch, Spanisch).

Quelle:  de.md, en.md, es.md (Markdown) + img/<sprache>/*.png
Vorlage: vorlage.html + handbuch.css
Ablauf:  pandoc macht aus dem Markdown eine HTML-Seite, Chrome/Chromium
         druckt sie als PDF. Danach liest pdftotext, auf welcher Seite jede
         Überschrift gelandet ist, und ein zweiter Durchgang trägt die
         Seitenzahlen ins Inhaltsverzeichnis ein.

Aufruf:  python3 build.py                 alle Sprachen nach ausgabe/
         python3 build.py de              nur Deutsch
         python3 build.py --out site/handbuch

Braucht: pandoc, pdftotext (poppler-utils), Chrome oder Chromium
         (Pfad notfalls in der Umgebungsvariable CHROME), Schrift Carlito
         (Debian/Ubuntu: fonts-crosextra-carlito).
"""

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HIER = os.path.dirname(os.path.abspath(__file__))
SPRACHEN = ["de", "en", "es"]


def finde_chrome():
    """Chrome/Chromium suchen: erst $CHROME, dann die üblichen Namen."""
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    for name in ("google-chrome", "google-chrome-stable", "chromium",
                 "chromium-browser", "chrome"):
        pfad = shutil.which(name)
        if pfad:
            return pfad
    # Playwright-Chromium (Cloud-Umgebung)
    basis = "/opt/pw-browsers"
    if os.path.isdir(basis):
        for d in sorted(os.listdir(basis), reverse=True):
            pfad = os.path.join(basis, d, "chrome-linux", "chrome")
            if d.startswith("chromium-") and os.path.exists(pfad):
                return pfad
    sys.exit("Chrome/Chromium nicht gefunden (Umgebungsvariable CHROME setzen).")


def pandoc(sprache, seiten, html_datei):
    """Markdown -> HTML mit Inhaltsverzeichnis und nummerierten Kapiteln."""
    subprocess.run([
        "pandoc", os.path.join(HIER, sprache + ".md"),
        "--from", "markdown+fenced_divs+bracketed_spans+pipe_tables",
        "--to", "html5",
        "--template", os.path.join(HIER, "vorlage.html"),
        "--toc", "--toc-depth=2", "--number-sections",
        "--metadata", "lang=" + sprache, "--metadata", "pagetitle=StemMaker",
        "--variable", "seiten=" + json.dumps(seiten),
        "--output", html_datei,
    ], check=True)


def drucken(chrome, html_datei, pdf_datei):
    """HTML mit Chrome als PDF drucken (mit Lesezeichen aus den Überschriften)."""
    with tempfile.TemporaryDirectory() as profil:
        subprocess.run([
            chrome, "--headless", "--disable-gpu", "--no-sandbox",
            "--user-data-dir=" + profil,
            "--no-pdf-header-footer", "--generate-pdf-document-outline",
            "--print-to-pdf=" + pdf_datei,
            "file://" + html_datei,
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(pdf_datei):
        sys.exit("Chrome hat kein PDF geschrieben: " + pdf_datei)


def ueberschriften(html_datei):
    """(id, Nummer, Text) aller Kapitel (h1) und Abschnitte (h2) im Hauptteil."""
    text = open(html_datei, encoding="utf-8").read()
    text = text[text.index("<main>"):]
    liste = []
    for m in re.finditer(r'<h[12] [^>]*id="([^"]+)"[^>]*>(.*?)</h[12]>', text, re.S):
        inhalt = m.group(2)
        nummer = re.search(r'header-section-number">([^<]*)<', inhalt)
        rein = html.unescape(re.sub(r"<[^>]+>", "", inhalt)).strip()
        if nummer:
            rein = rein[len(nummer.group(1)):].strip()
        liste.append((m.group(1), nummer.group(1) if nummer else "", rein))
    return liste


def normal(s):
    """Für den Vergleich: nur Buchstaben und Ziffern, klein."""
    return re.sub(r"\W+", "", s, flags=re.UNICODE).lower()


def seitenzahlen(pdf_datei, liste):
    """Seite jeder Überschrift im PDF suchen (der Reihe nach, ab Seite 3)."""
    roh = subprocess.run(["pdftotext", "-layout", pdf_datei, "-"],
                         check=True, capture_output=True, text=True).stdout
    seiten = [normal(s) for s in roh.split("\f")]
    ergebnis = {}
    seite = 2                       # 0 = Titelseite, 1 = Inhaltsverzeichnis
    for ident, nummer, text in liste:
        suche = normal(nummer + text)[:40]
        for s in range(seite, len(seiten)):
            if suche in seiten[s]:
                ergebnis[ident] = s + 1
                seite = s
                break
        else:
            print("  Warnung: Seite nicht gefunden für", nummer, text)
    return ergebnis, len(seiten) - (1 if seiten and not seiten[-1] else 0)


def baue(sprache, chrome, ziel):
    print("Handbuch", sprache)
    html_datei = os.path.join(HIER, "_bau_" + sprache + ".html")
    pdf_datei = os.path.join(ziel, "StemMaker-Handbuch-" + sprache + ".pdf")
    try:
        pandoc(sprache, {}, html_datei)
        drucken(chrome, html_datei, pdf_datei)
        liste = ueberschriften(html_datei)
        seiten, anzahl = seitenzahlen(pdf_datei, liste)
        # Zweiter Durchgang mit Seitenzahlen im Inhaltsverzeichnis
        pandoc(sprache, seiten, html_datei)
        drucken(chrome, html_datei, pdf_datei)
        kontrolle, anzahl2 = seitenzahlen(pdf_datei, liste)
        if kontrolle != seiten:
            print("  Warnung: Seitenzahlen haben sich im zweiten Durchgang verschoben")
        print("  %d Seiten -> %s" % (anzahl2, pdf_datei))
    finally:
        if os.path.exists(html_datei):
            os.remove(html_datei)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sprachen", nargs="*", default=SPRACHEN)
    ap.add_argument("--out", default=os.path.join(HIER, "ausgabe"))
    args = ap.parse_args()
    ziel = os.path.abspath(args.out)
    os.makedirs(ziel, exist_ok=True)
    chrome = finde_chrome()
    for sprache in args.sprachen:
        baue(sprache, chrome, ziel)


if __name__ == "__main__":
    main()
