# Vergleicht zwei Ordner mit Stems (je drums, bass, other, vocals im Dateinamen).
# Ausgabe je Stem: Abstand in dB (Signal / Abweichung). Über 50 dB ist nur
# noch Rundung, nicht hörbar.
#
# Aufruf:  python3 stems_vergleichen.py <ordner-a> <ordner-b-referenz>
import os, sys
import numpy as np, soundfile as sf


def finde(ordner, name):
    for f in sorted(os.listdir(ordner)):
        if name in f and f.lower().endswith('.wav'):
            return os.path.join(ordner, f)
    sys.exit(f'{name} fehlt in {ordner}')


for nm in ['drums', 'bass', 'other', 'vocals']:
    a, _ = sf.read(finde(sys.argv[1], nm), dtype='float64')
    b, _ = sf.read(finde(sys.argv[2], nm), dtype='float64')
    n = min(len(a), len(b))
    d = a[:n] - b[:n]
    db = 10 * np.log10((b[:n] ** 2).sum() / max((d ** 2).sum(), 1e-30))
    print(f'{nm:7s} {db:6.1f} dB   grösste Abweichung {np.abs(d).max():.2e}')
