#!/bin/sh
# Cross-compiles the demucs.cpp command line tools for Windows (x64) on Linux
# (tested on Ubuntu 24.04 with mingw-w64). Result: fully static .exe files
# (only KERNEL32 + msvcrt), no DLLs needed.
#
#   sudo apt install g++-mingw-w64-x86-64-posix cmake git libeigen3-dev
#   ./build_demucs_windows.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
git clone --recurse-submodules https://github.com/sevagh/demucs.cpp demucs.cpp || true
cd demucs.cpp
git apply "$HERE/windows-build.patch"          # std::filesystem::path -> .string(), arch flag, no gtest

cat > mingw.cmake <<'T'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix)
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
T

# avx2 = fast build (CPUs since ~2013), avx = Sandy/Ivy Bridge (2011-2013),
# generic = SSE4.2 fallback for older CPUs
for V in avx2:x86-64-v3 avx:sandybridge generic:x86-64-v2; do
  N=${V%%:*}; A=${V##*:}
  cmake -S . -B build-$N -DCMAKE_TOOLCHAIN_FILE=mingw.cmake -DCMAKE_BUILD_TYPE=Release \
    -DUSE_OPENBLAS=OFF -DDEMUCS_ARCH="-march=$A" \
    -DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++" \
    -DCMAKE_CXX_STANDARD_LIBRARIES="-lkernel32 -luser32 -lshell32 -ladvapi32 -Wl,-Bstatic"
  cmake --build build-$N -j"$(nproc)" --target demucs_mt.cpp.main demucs_ft_mt.cpp.main demucs_v3_mt.cpp.main
done
echo "AVX2:    build-avx2/*.exe     -> StemMaker/tools/"
echo "AVX:     build-avx/*.exe      -> StemMaker/tools/avx/"
echo "Generic: build-generic/*.exe  -> StemMaker/tools/generic/"
