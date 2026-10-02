# StemMaker-Icon (Elospeed): 4 Balken in den Stem-Farben auf dunklem Grund.
# Wird in 1024 px gezeichnet und für jede Icon-Grösse sauber verkleinert.
from PIL import Image, ImageDraw, ImageFilter
S = 1024
def rr(d, box, r, fill): d.rounded_rectangle(box, radius=r, fill=fill)

def render():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # Hintergrund: abgerundetes Quadrat mit leichtem Verlauf
    bg = Image.new('RGBA', (S, S))
    top, bot = (38, 44, 58), (14, 16, 22)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,)
        ImageDraw.Draw(bg).line([(0, y), (S, y)], fill=c)
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((24, 24, S - 24, S - 24), radius=210, fill=255)
    img.paste(bg, (0, 0), mask)
    # feiner heller Rand
    ImageDraw.Draw(img).rounded_rectangle((24, 24, S - 24, S - 24), radius=210,
                                          outline=(255, 255, 255, 40), width=8)
    # 4 Stem-Balken (Drums, Bass, Other, Vox) - symmetrisch um die Mitte
    colors = [(0, 158, 115), (213, 94, 0), (204, 121, 167), (86, 180, 233)]
    heights = [0.50, 0.78, 0.62, 0.40]
    bw, gap = 140, 52
    total = 4 * bw + 3 * gap
    x0 = (S - total) // 2
    cy = S // 2
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    bars = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bars)
    for i, (c, h) in enumerate(zip(colors, heights)):
        x = x0 + i * (bw + gap)
        half = int(h * 700 / 2)
        box = (x, cy - half, x + bw, cy + half)
        rr(gd, box, bw // 2, c + (170,))
        rr(bd, box, bw // 2, c + (255,))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    img = Image.alpha_composite(img, Image.composite(glow, Image.new('RGBA', (S, S)), mask))
    img = Image.alpha_composite(img, bars)
    return img

big = render()
big.save('stemmaker_icon_1024.png')
sizes = [256, 128, 64, 48, 32, 24, 16]
# WICHTIG: bitmap_format='bmp' - Lazarus kann PNG-komprimierte Icon-Bilder
# nicht lesen ("Bitmap with unknown compression"), klassische Bitmaps schon.
big.resize((256, 256), Image.LANCZOS).save('StemMaker.ico', sizes=[(s, s) for s in sizes],
                                            bitmap_format='bmp')
# Vorschau aller Grössen nebeneinander
prev = Image.new('RGBA', (sum(sizes) + 20 * len(sizes) + 20, 300), (240, 240, 240, 255))
x = 20
for s in sizes:
    im = big.resize((s, s), Image.LANCZOS)
    prev.paste(im, (x, (300 - s) // 2), im); x += s + 20
prev.save('preview.png')
