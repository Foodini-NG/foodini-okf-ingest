#!/usr/bin/env bash
# Conformance check: C++ binding vs conformance/expected/*.json.
# Run: bash conformance/check_cpp.sh   (exit 0 = pass)
# The checker itself is a ctest: cpp/tests/check_conformance.cpp
set -e
cd "$(dirname "$0")/.."
cmake -S cpp -B cpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build cpp/build --config Release
ctest --test-dir cpp/build -R conformance --output-on-failure -C Release
