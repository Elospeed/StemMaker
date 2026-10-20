# StemOnnx – fast separation engine (work in progress)

[Deutsch](LIESMICH.md)

StemOnnx separates songs with the same AI model as StemMaker (htdemucs = Demucs v4, also htdemucs_ft), but runs it with **ONNX Runtime** instead of demucs.cpp: on the **GPU** via DirectML (NVIDIA, AMD, Intel) or on the **CPU**, where it is about 4 to 6x faster than demucs.cpp.

**Status: separate from StemMaker.** StemMaker still uses demucs.cpp. Nothing here is wired into StemMaker until the engine is fully tested; demucs.cpp stays as the fallback afterwards.

- Same quality as the original demucs (66 to 88 dB distance to PyTorch demucs, i.e. rounding only).
- Command line compatible with demucs.cpp: `StemOnnx.exe <model> <input.wav> <outdir> [parts] [--geraet auto|gpu|cpu] [--gpu <n>] [--kerne <n>]`, writes `target_0_drums.wav` … `target_3_vocals.wav`.
- No model weights are shipped: `modell/htdemucs-geruest.onnx` is the network graph without weights. StemOnnx fills in the weights at startup from the demucs.cpp ggml file that StemMaker downloads from the original source.
- Build: `./build.sh` (Linux, mingw). Details in [LIESMICH.md](LIESMICH.md).
