#!/usr/bin/env bash
# Conformance check: MATLAB binding vs conformance/expected/*.json.
# Run: bash conformance/check_matlab.sh   (exit 0 = pass)
# Uses MATLAB when installed, else GNU Octave (the binding targets the
# MATLAB/Octave-compatible language subset; CI runs real MATLAB).
set -e
cd "$(dirname "$0")/.."
if command -v matlab >/dev/null 2>&1; then
  matlab -batch "run('conformance/check_matlab.m')"
else
  octave --no-init-file --eval "run('conformance/check_matlab.m')"
fi
