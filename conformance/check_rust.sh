#!/usr/bin/env bash
# Conformance check: Rust binding vs conformance/expected/*.json.
# Run: bash conformance/check_rust.sh   (exit 0 = pass)
# The checker itself is a cargo integration test:
#   rust/okf-ingest/tests/conformance.rs
set -e
cd "$(dirname "$0")/.."
cargo test --manifest-path rust/okf-ingest/Cargo.toml --test conformance -- --nocapture
