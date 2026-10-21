# Baut das htdemucs-Gerüst für StemOnnx: den Aufbau des Netzes als ONNX-Datei,
# aber OHNE Gewichte. Die Gewichte liest StemOnnx.exe beim Start aus der
# ggml-Datei von demucs.cpp. So liefern wir kein Modell mit.
#
# Aufruf:  python3 geruest_bauen.py <ausgabeordner>
# Ergebnis: htdemucs-geruest.onnx (Aufbau) + htdemucs-geruest.txt (Liste der Gewichte)
#
# Braucht: torch, onnx, demucs, demucs-onnx, einops (alle über pip).
# Es wird keine Modelldatei gebraucht: das Netz wird mit Zufallswerten
# angelegt, und die Zufallswerte werden vor dem Speichern entfernt.
#
# Die Anpassungen für den Export (fester Abschnitt, kein Zufalls-Versatz,
# Attention ohne Sonderfälle) stammen aus dem Paket demucs-onnx (MIT).
import os, sys, types
from fractions import Fraction
import torch, onnx
from einops import rearrange
from demucs.htdemucs import HTDemucs
from demucs_onnx.export.segment import coerce_segment_to_float
from demucs_onnx.export.pos_embed import disable_random_pos_shift
from demucs_onnx.export.mha import onnx_friendly_mha_forward

SEG = 343980          # 7,8 s bei 44,1 kHz (fest im Modell)


class Core(torch.nn.Module):
    """htdemucs ohne STFT/iSTFT. Eingang: Audio (mix) + Spektrum (spec),
    Ausgang: Zeitzweig (wave) + maskiertes Spektrum (spec_out).
    Die STFT rechnet StemOnnx selbst (auf der Grafikkarte brauchte sie im
    Modell zu viel Speicher). Entspricht HTDemucs.forward mit cac=True."""

    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, mix, zri):
        s = self.m
        B, C, two, Fq, T = zri.shape
        x = zri.reshape(B, C * two, Fq, T)
        mean = x.mean(dim=(1, 2, 3), keepdim=True)
        std = x.std(dim=(1, 2, 3), keepdim=True)
        x = (x - mean) / (1e-5 + std)
        xt = mix
        meant = xt.mean(dim=(1, 2), keepdim=True)
        stdt = xt.std(dim=(1, 2), keepdim=True)
        xt = (xt - meant) / (1e-5 + stdt)
        saved, saved_t, lengths, lengths_t = [], [], [], []
        for idx, encode in enumerate(s.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(s.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = s.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and s.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                emb = s.freq_emb(frs).t()[None, :, :, None].expand_as(x)
                x = x + s.freq_emb_scale * emb
            saved.append(x)
        b, c, f, t = x.shape
        x = rearrange(x, "b c f t-> b c (f t)")
        x = s.channel_upsampler(x)
        x = rearrange(x, "b c (f t)-> b c f t", f=f)
        xt = s.channel_upsampler_t(xt)
        x, xt = s.crosstransformer(x, xt)
        x = rearrange(x, "b c f t-> b c (f t)")
        x = s.channel_downsampler(x)
        x = rearrange(x, "b c (f t)-> b c f t", f=f)
        xt = s.channel_downsampler_t(xt)
        for idx, decode in enumerate(s.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = s.depth - len(s.tdecoder)
            if idx >= offset:
                tdec = s.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)
        S = len(s.sources)
        x = x.view(B, S, -1, Fq, T)
        x = x * std[:, None] + mean[:, None]
        zout = x.view(B, S, C, 2, Fq, T)
        xt = xt.view(B, S, -1, mix.shape[-1])
        xt = xt * stdt[:, None] + meant[:, None]
        return xt, zout


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    torch.manual_seed(0)
    # gleiche Einstellungen wie die ggml-Modelle von demucs.cpp (htdemucs und htdemucs_ft)
    m = HTDemucs(sources=['drums', 'bass', 'other', 'vocals'], segment=Fraction(39, 5),
                 dconv_mode=3, t_layers=5, bottom_channels=512).eval()
    # Jedes Gewicht bekommt eigene Zufallswerte. Sonst haben z. B. alle
    # LayerNorm-Gewichte den Wert 1, und der Export legt gleiche Gewichte zu
    # einem einzigen zusammen - dann fehlt StemOnnx der Platz für jedes
    # einzelne Gewicht aus der ggml-Datei.
    with torch.no_grad():
        for prm in m.parameters():
            prm.copy_(torch.randn_like(prm) * 0.01)
    coerce_segment_to_float(m)
    disable_random_pos_shift(m)
    for mod in m.modules():
        if isinstance(mod, torch.nn.MultiheadAttention):
            mod.forward = types.MethodType(onnx_friendly_mha_forward, mod)
    core = Core(m).eval()
    tmp = os.path.join(out, 'tmp-voll.onnx')
    mix = torch.randn(1, 2, SEG) * 0.1
    z = torch.randn(1, 2, 2, 2048, SEG // 1024 + 1) * 0.1
    # ohne Konstanten-Faltung: so bleibt jedes Gewicht unverändert und behält
    # seinen Namen aus dem PyTorch-Modell (= Name in der ggml-Datei).
    # ONNX Runtime faltet beim Laden selbst.
    torch.onnx.export(core, (mix, z), tmp, input_names=['mix', 'spec'],
                      output_names=['wave', 'spec_out'], opset_version=17,
                      dynamo=False, do_constant_folding=False)
    g = onnx.load(tmp)
    os.remove(tmp)
    # "m." vorne entfernen (kommt von Core.m), dann heissen die Gewichte wie in ggml
    for t in g.graph.initializer:
        assert t.name.startswith('m.'), t.name
        t.name = t.name[2:]
    for nd in g.graph.node:
        for i, x in enumerate(nd.input):
            if x.startswith('m.'):
                nd.input[i] = x[2:]
    # Gewichte entfernen: Platzhalter "extern", StemOnnx füllt sie im Speicher
    lines = ['# Gewichte im htdemucs-Gerüst: Name, Anzahl Dimensionen, Dimensionen']
    off = 0
    for t in g.graph.initializer:
        n = 1
        for d in t.dims:
            n *= d
        lines.append(f"{t.name} {len(t.dims)} {' '.join(map(str, t.dims))}")
        del t.external_data[:]
        for k, v in (('location', 'gewichte-aus-ggml'), ('offset', str(off)), ('length', str(n * 4))):
            e = t.external_data.add()
            e.key, e.value = k, v
        off += n * 4
        t.ClearField('raw_data')
        t.data_location = onnx.TensorProto.EXTERNAL
    g.producer_name = 'StemOnnx geruest_bauen.py'
    onnx.save(g, os.path.join(out, 'htdemucs-geruest.onnx'))
    with open(os.path.join(out, 'htdemucs-geruest.txt'), 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'ok: {len(lines) - 1} Gewichte ({off / 1e6:.0f} MB als float32), Gerüst in {out}')


if __name__ == '__main__':
    main()
