#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/FINAL_PRODUCTION_NSLOC.tsv"
BASE_AUDIT_COMMIT="b5265f311abc524683561b79792eab2900823fa9"
FINAL_AUDIT_COMMIT="2725216e0407a0ef4599e359a04094ae5f322624"
EXPECTED_MANIFEST_SHA256="2cf025a541ef307bd5fb59a5747304f7efda0c6adf6c814a70349f1fe2d041f7"

command -v cloc >/dev/null || { echo "cloc is required" >&2; exit 1; }
[[ "$(cloc --version)" == "2.06" ]] || {
  echo "cloc 2.06 is required for the pinned nSLOC result" >&2
  exit 1
}

[[ "$(shasum -a 256 "$MANIFEST" | awk '{print $1}')" == "$EXPECTED_MANIFEST_SHA256" ]] || {
  echo "nSLOC manifest hash mismatch" >&2
  exit 1
}

git -C "$ROOT_DIR" cat-file -e "$BASE_AUDIT_COMMIT^{commit}"
git -C "$ROOT_DIR" cat-file -e "$FINAL_AUDIT_COMMIT^{commit}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/base" "$TMP_DIR/final"

while IFS=$'\t' read -r path _class _base_nsloc _final_nsloc _delta_nsloc; do
  [[ "$path" == "path" ]] && continue
  mkdir -p "$TMP_DIR/base/$(dirname "$path")" "$TMP_DIR/final/$(dirname "$path")"
  git -C "$ROOT_DIR" show \
    "$BASE_AUDIT_COMMIT:source-snapshot/contracts/src/$path" > "$TMP_DIR/base/$path"
  git -C "$ROOT_DIR" show \
    "$FINAL_AUDIT_COMMIT:source-snapshot/contracts/src/$path" > "$TMP_DIR/final/$path"
done < "$MANIFEST"

cloc "$TMP_DIR/base" --by-file --csv --quiet > "$TMP_DIR/base.csv"
cloc "$TMP_DIR/final" --by-file --csv --quiet > "$TMP_DIR/final.csv"

awk -F '\t' 'NR > 1 {print $1 "\t" $3}' "$MANIFEST" | sort > "$TMP_DIR/expected-base.tsv"
awk -F '\t' 'NR > 1 {print $1 "\t" $4}' "$MANIFEST" | sort > "$TMP_DIR/expected-final.tsv"

awk -F ',' -v marker="$TMP_DIR/base/" '$1 == "Solidity" {
  path = $2
  start = index(path, marker)
  if (start > 0) path = substr(path, start + length(marker))
  print path "\t" $5
}' "$TMP_DIR/base.csv" | sort > "$TMP_DIR/actual-base.tsv"

awk -F ',' -v marker="$TMP_DIR/final/" '$1 == "Solidity" {
  path = $2
  start = index(path, marker)
  if (start > 0) path = substr(path, start + length(marker))
  print path "\t" $5
}' "$TMP_DIR/final.csv" | sort > "$TMP_DIR/actual-final.tsv"

diff -u "$TMP_DIR/expected-base.tsv" "$TMP_DIR/actual-base.tsv"
diff -u "$TMP_DIR/expected-final.tsv" "$TMP_DIR/actual-final.tsv"

awk -F '\t' '
  NR > 1 { files++; base += $3; final += $4; delta += $5 }
  END {
    if (files != 25 || base != 6210 || final != 6656 || delta != 446) exit 1
  }
' "$MANIFEST"

echo "final production nSLOC verification: PASS (25 files, 6210 -> 6656)"
