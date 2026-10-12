#!/usr/bin/env python3
"""
StemMaker (Elospeed) - Zahnrad-Symbol für den Button "Einstellungen"

Zeichnet ein Zahnrad (8 Zähne, Loch in der Mitte) in 8-facher Grösse
und verkleinert es mit Kantenglättung auf 20x20 Pixel (PNG mit
Transparenz). Das Ergebnis wird als Pascal-Byte-Array nach
src/gearicon.inc geschrieben und dort vom Programm eingebunden -
so braucht es keine zusätzliche Datei neben der Exe.

Aufruf:  python3 art/make_gear.py
"""
import io, math, os
from PIL import Image, ImageDraw

SIZE = 20          # Endgrösse in Pixel
SCALE = 8          # zum Zeichnen hochskaliert (Kantenglättung)
COLOR = (80, 80, 80, 255)

S = SIZE * SCALE
c = S / 2
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

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

img = img.resize((SIZE, SIZE), Image.LANCZOS)
buf = io.BytesIO()
img.save(buf, 'PNG', optimize=True)
data = buf.getvalue()

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, '..', 'src', 'gearicon.inc')
lines = []
for i in range(0, len(data), 16):
    lines.append('  ' + ', '.join('$%02X' % b for b in data[i:i + 16]))
with open(out, 'w', newline='\n') as f:
    f.write('{ Zahnrad-Symbol (PNG %dx%d) - erzeugt von art/make_gear.py, nicht von Hand ändern }\n' % (SIZE, SIZE))
    f.write('const\n  GEAR_PNG: array[0..%d] of Byte = (\n' % (len(data) - 1))
    f.write(',\n'.join(lines) + '\n  );\n')
print('geschrieben:', out, len(data), 'Bytes')
