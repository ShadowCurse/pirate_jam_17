#!/bin/bash

zig build -Dshipping -Dtarget=wasm32-emscripten --sysroot "emsdk/upstream/emscripten" -Doptimize=ReleaseSmall 

cd wasm

emcc \
  -Os \
  -sFULL-ES3=1 \
  -sMIN_WEBGL_VERSION=2 \
  -sMAX_WEBGL_VERSION=2 \
  -sASSERTIONS=1 \
  -sMALLOC='emmalloc' \
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
  --embed-file ../resources@/resources \
  -sERROR_ON_UNDEFINED_SYMBOLS=0 \
  ../zig-out/lib/* \
  ../../SDL/build/libSDL3.a \
  -o \
  pirate_jam_17.js

wasm-opt -Os --all-features --enable-bulk-memory-opt pirate_jam_17.wasm -o pirate_jam_17.wasm

zip -r ../wasm.zip .
