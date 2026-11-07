# Linux-AppImage (Beta)

StemMaker für Linux = die normale Windows-Version + mitgeliefertes Wine in einer AppImage. Eine Codebasis, alle AddOns dabei.

| Datei | Zweck |
|---|---|
| `AppRun` | Startskript in der AppImage: legt den Wine-Ordner an, kopiert StemMaker hinein, startet StemMaker/StemCLI/StemPlayer/StemTagger |
| `appimage-bauen.sh` | baut aus einem Release-ZIP die AppImage (Wine, vkd3d-proton, DXVK mit festen Prüfsummen) |
| `appimage-testen.sh` | Start + ganze Umwandlung eines Testtons, auf Wunsch Bilder bei 100 % und 150 % |
| `LIESMICH-LINUX.txt` | kommt in die AppImage: Kurzanleitung + Lizenz- und Quellcode-Hinweise zu Wine |
| `gpu-test/` | Versuch Grafikkarte: misst Turbo auf CPU, DirectML über vkd3d-proton und WebGPU |

Gebaut und getestet wird im Workflow **Linux-AppImage** (`.github/workflows/appimage.yml`): automatisch bei PRs, von Hand mit Tag und „hochladen“, um die AppImage an ein Release zu hängen.

**Grafikkarte:** Standard ist CPU (Wine-eigenes D3D12 kann DirectML nicht). Mit `STEMMAKER_GPU=vkd3d` wird vkd3d-proton + DXVK nur für Turbo eingeschaltet. Ob das oder WebGPU auf echten Karten trägt, misst `gpu-test/gpu-test.sh`.

**Lizenzen:** Wine und vkd3d-proton LGPL 2.1 (unverändert, Lizenztexte + Quellcode-Links in der AppImage), DXVK zlib, onnxruntime-webgpu MIT. Demucs-Gewichte und ffmpeg werden wie unter Windows beim ersten Start geladen, nicht mitgeliefert.

## Testversion für Linux-Tester

`beta-test/testversion-packen.sh` ersetzt in einer fertigen AppImage die Programme durch neuere aus einem Build-Artefakt und packt sie mit den Testanleitungen (`beta-test/Linux-Beta-Test-DE.md`, `-EN.md`) und `SHA256SUMS.txt` in ein ZIP fürs Vor-Release.
