#!/usr/bin/env python3
"""
StemMaker (Elospeed) - Zahnrad-Symbol für den Button "Einstellungen"

Zeichnet ein Zahnrad (8 Zähne, Loch in der Mitte) in 8-facher Grösse
und verkleinert es mit Kantenglättung auf 20, 25, 30 und 40 Pixel
(PNG mit Transparenz), je eine Grösse für 100, 125, 150 und 200 %
Windows-Skalierung (sonst bleibt das Zahnrad bei 200 % klein). Das Ergebnis wird als Pascal-Byte-Array nach
src/gearicon.inc geschrieben und dort vom Programm eingebunden -
so braucht es keine zusätzliche Datei neben der Exe.

Aufruf:  python3 art/make_gear.py
"""
import io, math, os
from PIL import Image, ImageDraw

SIZES = (20, 25, 30, 40)   # Endgrössen in Pixel (100/125/150/200 %)
SCALE = 16         # zum Zeichnen hochskaliert (Kantenglättung)
COLOR = (80, 80, 80, 255)

S = 20 * SCALE
c = S / 2
big = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(big)

teeth = 8
r_out, r_in = S * 0.48, S * 0.36     # Zahnspitze / Zahnfuss
pts = []
for i in range(teeth):
    a0 = 2 * math.pi * i / teeth - math.pi / teeth / 2   # Zähne symmetrisch oben/unten
    step = 2 * math.pi / teeth
    # Zahn: Fuss - Spitze - Spitze - Fuss (leicht schräge Flanken)
    for frac, r in ((0.00, r_in), (0.12, r_out), (0.38, r_out), (0.50, r_in)):
        a = a0 + step * frac
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
d.polygon(pts, fill=COLOR)
d.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=COLOR)
r_hole = S * 0.15
d.ellipse([c - r_hole, c - r_hole, c + r_hole, c + r_hole], fill=(0, 0, 0, 0))

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, '..', 'src', 'gearicon.inc')
with open(out, 'w', newline='\n') as f:
    f.write('{ Zahnrad-Symbol (PNG %s Pixel) - erzeugt von art/make_gear.py, nicht von Hand ändern }\n'
            % '/'.join(str(z) for z in SIZES))
    f.write('const\n')
    for size in SIZES:
        img = big.resize((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, 'PNG', optimize=True)
        data = buf.getvalue()
        lines = ['  ' + ', '.join('$%02X' % b for b in data[i:i + 16])
                 for i in range(0, len(data), 16)]
        f.write('  GEAR_PNG_%d: array[0..%d] of Byte = (\n' % (size, len(data) - 1))
        f.write(',\n'.join(lines) + '\n  );\n')
print('geschrieben:', out)
