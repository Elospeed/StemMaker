# Third-party components and credits

Elospeed StemMaker is © 2026 Elospeed and released under the MIT License (see `LICENSE`).
It builds on the work of the people and projects listed below. Thank you!

*Deutsch: Diese Datei listet alle fremden Bestandteile, ihre Autoren und Lizenzen auf.*

---

## Shipped with StemMaker (in the release ZIP)

### demucs.cpp – the separation programs (`tools\*.exe`)
- Author: **Sevag Hanssian (sevagh)** – https://github.com/sevagh/demucs.cpp
- License: **MIT** – © 2023 Sevag H. The full license text is included as `tools\LICENSE-demucs.cpp.txt`.
- StemMaker ships Windows builds made from the unmodified source plus a small build patch (`demucs-build/windows-build.patch`: Windows path handling, selectable CPU architecture, tests not built).
- demucs.cpp itself uses:
  - **Eigen** (linear algebra) – https://eigen.tuxfamily.org – **MPL 2.0** (source unmodified, available at the link).
  - **libnyquist** by Dimitri Diakopoulos (audio file I/O) – https://github.com/ddiakopoulos/libnyquist – **BSD 2-Clause**, with bundled decoders under their own permissive licenses (FLAC, libogg, libvorbis, opus: BSD-style; minimp3: CC0; musepack, wavpack: BSD-style).
  - **OpenMP / libgomp** and the **MinGW-w64** runtime (GCC Runtime Library Exception / permissive licenses).

### Free Pascal and Lazarus – the StemMaker program itself
- Free Pascal RTL/FCL and Lazarus LCL/LazUtils – https://www.freepascal.org, https://www.lazarus-ide.org
- License: **modified LGPL** with a static-linking exception, which allows distributing programs built with them under any license.

---

## Downloaded by StemMaker on first start (not part of this repository)

### FFmpeg – decoding and encoding (`tools\ffmpeg.exe`)
- © the **FFmpeg developers** – https://ffmpeg.org
- License: **LGPL** (StemMaker downloads the LGPL build; it is configured with `--enable-version3`, so LGPL version 3 applies).
- Windows builds by **BtbN** – https://github.com/BtbN/FFmpeg-Builds
- From version 1.7 StemMaker downloads a fixed, unmodified copy of such a build from this repository's releases (tag `ffmpeg-<version>`), checked with the SHA-256 checksum in `update.json`. The ZIP contains `ffmpeg.exe`, the license text and `QUELLCODE-SOURCE.txt` with the exact FFmpeg commit and links to the source code and the build scripts.
- FFmpeg runs as a separate program; StemMaker does not link against it.

### Demucs separation models (`models\*.bin`)
- **Demucs / Hybrid Transformer Demucs** by **Alexandre Défossez** et al., Meta AI Research – https://github.com/facebookresearch/demucs
  - A. Défossez, *Hybrid Spectrogram and Waveform Source Separation*, ISMIR 2021 MDX Workshop.
  - S. Rouard, F. Massa, A. Défossez, *Hybrid Transformers for Music Source Separation*, ICASSP 2023.
- Converted to the ggml format for demucs.cpp and hosted at **Hugging Face: Retrobear/demucs.cpp** – https://huggingface.co/datasets/Retrobear/demucs.cpp (marked MIT there).
- **Note on licensing:** The Demucs code is MIT. For the trained weights, the original author has in the past described them as provided for research purposes (they were trained with the MUSDB18 dataset, which is licensed for non-commercial use). The Hugging Face listing now shows MIT; the question is open at https://huggingface.co/adefossez/HTDemucs/discussions/1. For this reason StemMaker **does not redistribute the models** – it downloads them from their original location – and StemMaker is free, non-commercial software.
- MUSDB18: Z. Rafii, A. Liutkus, F.-R. Stöter, S. I. Mimilakis, R. Bittner, *The MUSDB18 corpus for music separation*, 2017.

---

## Inspiration and formats

- **Stemgen** by **axeldelafosse** – https://github.com/axeldelafosse/stemgen – the Python tool whose approach StemMaker follows (same stem metadata layout).
- **Stem file format / "STEMS"** and **Traktor** are trademarks of **Native Instruments GmbH**. StemMaker is an independent project and is not affiliated with or endorsed by Native Instruments.
- The default stem colors follow the Stemgen defaults.
