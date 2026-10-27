# StemOnnx – StemMaker's Turbo engine

[Deutsch](LIESMICH.md)

StemOnnx separates songs with the same AI model as StemMaker (htdemucs = Demucs v4, also htdemucs_ft), but runs it with **ONNX Runtime** instead of demucs.cpp: on the **GPU** via DirectML (NVIDIA, AMD, Intel) or on the **CPU**, where it is about 4 to 6x faster than demucs.cpp.

**Status: built into StemMaker 2.0 (version 0.4) as the default "Turbo" engine,** shipped in `tools\onnx\`. demucs.cpp stays selectable as "Classic" and takes over automatically when StemOnnx fails on a file.

- Same quality as the original demucs (66 to 88 dB distance to PyTorch demucs, i.e. rounding only).
- Command line compatible with demucs.cpp: `StemOnnx.exe <model> <input.wav> <outdir> [parts] [--geraet auto|gpu|cpu] [--gpu <n>] [--kerne <n>]`, writes `target_0_drums.wav` … `target_3_vocals.wav` while it computes (low RAM even for long DJ mixes).
- `<model> --vortest`: the pre-test StemMaker shows on first start (load time, CPU, graphics card); `--karten`: lists the graphics cards with driver version in one line. ONNX Runtime telemetry is switched off.
- No model weights are shipped: `modell/htdemucs-geruest.onnx` is the network graph without weights. StemOnnx fills in the weights at startup from the demucs.cpp ggml file that StemMaker downloads from the original source.
- Build: `./build.sh` (Linux, mingw). Details in [LIESMICH.md](LIESMICH.md).
