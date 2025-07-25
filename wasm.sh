#!/bin/bash

zig build -Dtarget=wasm32-emscripten --sysroot "emsdk/upstream/emscripten" -Doptimize=ReleaseFast 

rm -r wasm/resources
mkdir wasm/resources
cp -r resources/shaders wasm/resources
cp -r resources/levels wasm/resources
cp -r resources/models wasm/resources
cp -r resources/soundtracks wasm/resources
cp -r resources/textures wasm/resources
cd wasm

emcc \
  -sFULL-ES3=1 \
  -sMIN_WEBGL_VERSION=2 \
  -sMAX_WEBGL_VERSION=2 \
  -sASSERTIONS=1 \
  -sMALLOC='dlmalloc' \
  -sFORCE_FILESYSTEM=1 \
  -sUSE_OFFSET_CONVERTER=1 \
  -sGL_ENABLE_GET_PROC_ADDRESS \
  -sEXPORTED_RUNTIME_METHODS=ccall \
  -sEXPORTED_RUNTIME_METHODS=cwrap \
  -sALLOW_MEMORY_GROWTH=1 \
  -sSTACK_SIZE=1mb \
  -sABORTING_MALLOC=0 \
  -sASYNCIFY \
  --emrun \
  --embed-file resources@/resources \
  -sERROR_ON_UNDEFINED_SYMBOLS=0 \
  ../zig-out/lib/* \
  ../../SDL/build/libSDL3.a \
  -o \
  pirate_jam_17.js

 zip -r ../wasm.zip .
