#!/usr/bin/env bash
set -euo pipefail

size_check_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$size_check_dir/.."

size_check_tmp="$(mktemp -d "${TMPDIR:-/tmp}/jpydf-contract-sizes.XXXXXX")"
cleanup() {
    rm -rf -- "$size_check_tmp"
}
trap cleanup EXIT

# `forge build --sizes` reports every artifact already present in the selected
# output directory, including tester artifacts produced by an earlier test run.
# Use an isolated output directory so the gate reflects only this production
# build instead of inheriting stale test-contract sizes from `out/`.
forge build --sizes --skip test --skip script "$@" \
    --no-cache \
    --out "$size_check_tmp/out" \
    --cache-path "$size_check_tmp/cache"
