#!/usr/bin/env bash
set -euo pipefail

TOP=synth
BUILD_DIR=build

mkdir -p "$BUILD_DIR"

verilator \
    --timing \
    --trace \
    -Wall \
    --cc ../src/newsynth.v \
    --top-module ${TOP} \
    --exe sim_main.cpp \
    -Mdir "$BUILD_DIR" \
    -CFLAGS "-O3 -std=c++17"

make -C "$BUILD_DIR" -f V${TOP}.mk CXX=g++ OPT_FAST="-O3"

echo
echo "Built executable:"
echo "  ${BUILD_DIR}/V${TOP}"
echo
echo "Example run:"
echo "  ${BUILD_DIR}/V${TOP} 2.0 dac_output.bin"
