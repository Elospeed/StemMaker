# Referenz für die Qualitätsprüfung: trennt eine WAV-Datei mit dem
# Original-demucs (PyTorch, apply_model mit shifts=0, overlap 0.25 - genau
# das rechnet auch StemOnnx) und den Gewichten aus einer ggml-Datei.
#
# Aufruf:  python3 referenz_demucs.py <ggml-modell.bin> <eingang.wav> <ausgabeordner>
# Ergebnis: drums.wav, bass.wav, other.wav, vocals.wav (32-Bit-Float)
# Braucht: torch, demucs, soundfile, numpy
import os, struct, sys
from fractions import Fraction
import numpy as np, soundfile as sf, torch
from demucs.apply import apply_model
from demucs.htdemucs import HTDemucs

m = HTDemucs(sources=['drums', 'bass', 'other', 'vocals'], segment=Fraction(39, 5),
             dconv_mode=3, t_layers=5, bottom_channels=512, samplerate=44100)
sd = m.state_dict()
with open(sys.argv[1], 'rb') as f:
    assert struct.unpack('i', f.read(4))[0] == 0x646d6334, 'keine demucs.cpp-Modelldatei'
    while True:
        h = f.read(8)
        if len(h) < 8:
            break
        nd, ln = struct.unpack('ii', h)
        shp = struct.unpack('i' * nd, f.read(4 * nd))
        name = f.read(ln).decode()
        d = np.fromfile(f, dtype=np.float16, count=int(np.prod(shp)) if nd else 1)
        sd[name] = torch.from_numpy(d.astype(np.float32)).reshape(sd[name].shape)
m.load_state_dict(sd)
m.eval()
mix, sr = sf.read(sys.argv[2], dtype='float32')
x = torch.from_numpy(mix.T.copy())
ref = x.mean(0)
x = (x - ref.mean()) / ref.std()
with torch.no_grad():
    out = apply_model(m, x[None], shifts=0, split=True, overlap=0.25, progress=False)[0]
out = out * ref.std() + ref.mean()
os.makedirs(sys.argv[3], exist_ok=True)
for i, nm in enumerate(['drums', 'bass', 'other', 'vocals']):
    sf.write(os.path.join(sys.argv[3], nm + '.wav'), out[i].numpy().T, sr, subtype='FLOAT')
print('ok')
