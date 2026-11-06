#!/usr/bin/env bash
# Baut aus einem Release-ZIP die Linux-AppImage (Beta): StemMaker für Windows
# + mitgeliefertes Wine. Läuft im Workflow "Linux-AppImage" (appimage.yml),
# geht aber auch lokal auf Linux.
#
#   installer/linux/appimage-bauen.sh <StemMaker-x.y.zip> <Version> <Ausgabeordner>
#
# Ergebnis: <Ausgabeordner>/StemMaker-<Version>-x86_64.AppImage
#
# Wine: portable Ausgabe von Kron4ek/Wine-Builds (unverändertes Wine, LGPL,
# gebaut für glibc 2.25 und neuer, läuft also auch auf älteren Distros).
# Nur 64 Bit (StemMaker und alle Werkzeuge sind 64-Bit-Programme), die
# 32-Bit-Teile und die Debug-Infos werden weggelassen: 645 MB -> ca. 170 MB,
# gepackt ca. 40 MB. Version und Prüfsumme fest, damit jeder Bau gleich ist.
set -euo pipefail

WINE_VER="10.0"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VER}/wine-${WINE_VER}-amd64-wow64.tar.xz"
WINE_SHA="aeebbbf239e548f0136f1cd72a2e109dd9a572a8f703da3c09fa40d74d5c255f"
WINE_SRC="https://dl.winehq.org/wine/source/10.0/wine-${WINE_VER}.tar.xz"
# Versuch Grafikkarte (nur mit STEMMAKER_GPU=vkd3d aktiv): D3D12 und DXGI über Vulkan
VKD3D_VER="3.0"
VKD3D_URL="https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${VKD3D_VER}/vkd3d-proton-${VKD3D_VER}.tar.zst"
VKD3D_SHA="842b20e40b765107bf5ca9c8077fea2428375efc9c53ef38547ec55ca365002f"
DXVK_VER="2.7.1"
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VER}/dxvk-${DXVK_VER}.tar.gz"
DXVK_SHA="d85ce7c79f57ecd765aaa1b9e7007cb875e6fde9f6d331df799bce73d513ce87"
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage"

ZIP=$(realpath "$1"); VERSION="$2"
mkdir -p "$3"; AUS=$(realpath "$3")
HIER=$(realpath "$(dirname "$0")")
REPO=$(realpath "$HIER/../..")
ARBEIT=$(mktemp -d)
APPDIR="$ARBEIT/StemMaker.AppDir"
mkdir -p "$APPDIR"

echo "== StemMaker aus $ZIP"
python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$ZIP" "$ARBEIT/zip"
mv "$ARBEIT/zip/StemMaker" "$APPDIR/StemMaker"
# Quelltext und Bauskripte braucht die AppImage nicht (liegen im ZIP und auf GitHub)
rm -rf "$APPDIR/StemMaker/src" "$APPDIR/StemMaker/demucs-build" "$APPDIR/StemMaker/lang-tools"
echo "$VERSION" > "$APPDIR/StemMaker/APPIMAGE_VERSION"

echo "== Wine $WINE_VER"
curl -sSfL -o "$ARBEIT/wine.tar.xz" "$WINE_URL"
echo "$WINE_SHA  $ARBEIT/wine.tar.xz" | sha256sum -c -
tar -xf "$ARBEIT/wine.tar.xz" -C "$ARBEIT"
mv "$ARBEIT/wine-${WINE_VER}-amd64-wow64" "$APPDIR/wine"
W="$APPDIR/wine"
rm -rf "$W/lib/wine/i386-unix" "$W/lib/wine/i386-windows" "$W/include" "$W/share/man" "$W/share/applications"
# Werkzeuge zum Programmieren mit Wine braucht niemand
for f in function_grep.pl widl winebuild winecpp winedump wineg++ winegcc winemaker wmc wrc; do
  rm -f "$W/bin/$f"
done
# Debug-Infos entfernen (nur Grösse, am Verhalten ändert das nichts)
find "$W/lib/wine/x86_64-windows" -type f -print0 | xargs -0 x86_64-w64-mingw32-strip --strip-debug 2>/dev/null || true
find "$W/lib/wine/x86_64-unix" -type f -name '*.so' -print0 | xargs -0 strip --strip-debug 2>/dev/null || true

echo "== vkd3d-proton $VKD3D_VER + DXVK $DXVK_VER (Versuch Grafikkarte)"
mkdir -p "$APPDIR/gpu"
curl -sSfL -o "$ARBEIT/vkd3d.tar.zst" "$VKD3D_URL"
echo "$VKD3D_SHA  $ARBEIT/vkd3d.tar.zst" | sha256sum -c -
tar --zstd -xf "$ARBEIT/vkd3d.tar.zst" -C "$ARBEIT"
cp "$ARBEIT/vkd3d-proton-$VKD3D_VER/x64/d3d12.dll" "$ARBEIT/vkd3d-proton-$VKD3D_VER/x64/d3d12core.dll" "$APPDIR/gpu/"
curl -sSfL -o "$ARBEIT/dxvk.tar.gz" "$DXVK_URL"
echo "$DXVK_SHA  $ARBEIT/dxvk.tar.gz" | sha256sum -c -
tar -xzf "$ARBEIT/dxvk.tar.gz" -C "$ARBEIT"
cp "$ARBEIT/dxvk-$DXVK_VER/x64/dxgi.dll" "$APPDIR/gpu/"

echo "== Lizenzen"
mkdir -p "$APPDIR/licenses"
curl -sSfL -o "$APPDIR/licenses/Wine-LICENSE.txt" "https://raw.githubusercontent.com/wine-mirror/wine/wine-${WINE_VER}/LICENSE"
curl -sSfL -o "$APPDIR/licenses/Wine-COPYING.LIB.txt" "https://raw.githubusercontent.com/wine-mirror/wine/wine-${WINE_VER}/COPYING.LIB"
curl -sSfL -o "$APPDIR/licenses/vkd3d-proton-LICENSE.txt" "https://raw.githubusercontent.com/HansKristian-Work/vkd3d-proton/v${VKD3D_VER}/LICENSE"
curl -sSfL -o "$APPDIR/licenses/DXVK-LICENSE.txt" "https://raw.githubusercontent.com/doitsujin/dxvk/v${DXVK_VER}/LICENSE"
sed -e "s|@VKD3D_VER@|$VKD3D_VER|g" -e "s|@VKD3D_URL@|$VKD3D_URL|g" -e "s|@DXVK_VER@|$DXVK_VER|g" -e "s|@DXVK_URL@|$DXVK_URL|g" \
    -e "s|@WINE_VER@|$WINE_VER|g" -e "s|@WINE_SRC@|$WINE_SRC|g" -e "s|@WINE_URL@|$WINE_URL|g" \
  "$HIER/LIESMICH-LINUX.txt" > "$APPDIR/LIESMICH-LINUX.txt"

echo "== Startskript, Symbol, Desktop-Datei"
install -m 755 "$HIER/AppRun" "$APPDIR/AppRun"
cp "$HIER/stemmaker.desktop" "$APPDIR/stemmaker.desktop"
convert "$REPO/art/stemmaker_icon_1024.png" -resize 256x256 "$APPDIR/stemmaker.png"
cp "$APPDIR/stemmaker.png" "$APPDIR/.DirIcon"

echo "== AppImage packen"
TOOL="$ARBEIT/appimagetool"
curl -sSfL -o "$TOOL" "$TOOL_URL"
chmod +x "$TOOL"
ZIEL="$AUS/StemMaker-$VERSION-x86_64.AppImage"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream --comp zstd "$APPDIR" "$ZIEL"
chmod +x "$ZIEL"
du -h "$ZIEL"
rm -rf "$ARBEIT"
