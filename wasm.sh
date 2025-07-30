#!/bin/bash

zig build -Dshipping -Dtarget=wasm32-emscripten --sysroot "emsdk/upstream/emscripten" -Doptimize=ReleaseSmall 

cd wasm

emcc \
  -Os \
  -sFULL-ES3=1 \
  -sMIN_WEBGL_VERSION=2 \
  -sMAX_WEBGL_VERSION=2 \
  -sASSERTIONS=1 \
  -sERROR_ON_UNDEFINED_SYMBOLS=0 \
  -sMALLOC='emmalloc' \
  -sABORTING_MALLOC=0 \
  -sSTACK_SIZE=1mb \
  -sALLOW_MEMORY_GROWTH=1 \
  -sUSE_OFFSET_CONVERTER=1 \
  -sGL_ENABLE_GET_PROC_ADDRESS \
  -sFORCE_FILESYSTEM=1 \
  --embed-file ../resources@/resources \
  ../zig-out/lib/* \
  ../../SDL/build/libSDL3.a \
  -o \
  pirate_jam_17.js

wasm-opt -Os --all-features --enable-bulk-memory-opt pirate_jam_17.wasm -o pirate_jam_17.wasm

zip -r ../wasm.zip .
