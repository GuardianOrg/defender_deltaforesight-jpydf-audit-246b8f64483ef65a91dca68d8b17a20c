#!/usr/bin/env bash
# Verifies the external-audit patch artifacts without jpydf-v2 access:
# exactly one patch per remediated finding plus explicitly documented
# verification overlays, and each patch file's SHA-256 equals its pinned note.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
count=0
for note in evidence/external-audit/findings/*.md; do
  id=$(basename "$note" .md)
  patch="evidence/external-audit/patches/$id.patch"
  pinned=$(grep -o '| Diff SHA-256 | `[0-9a-f]*` |' "$note" | grep -o '[0-9a-f]\{64\}')
  if [ -z "$pinned" ]; then echo "FAIL $id: no pinned hash in finding note"; fail=1; continue; fi
  if [ ! -f "$patch" ]; then echo "FAIL $id: missing $patch"; fail=1; continue; fi
  actual=$(shasum -a 256 "$patch" | cut -d' ' -f1)
  if [ "$actual" != "$pinned" ]; then echo "FAIL $id: hash mismatch ($actual != $pinned)"; fail=1; continue; fi
  count=$((count+1))
done

extra=$(ls evidence/external-audit/patches/*.patch | wc -l | tr -d ' ')
if [ "$extra" != "$count" ]; then echo "FAIL: $extra patch files for $count verified findings"; fail=1; fi
[ "$count" = "21" ] || { echo "FAIL: expected 21 findings, verified $count"; fail=1; }

preliminary_count=0
for note in evidence/external-audit/preliminary-2026-08/findings/*.md; do
  id=$(basename "$note" .md)
  patch="evidence/external-audit/preliminary-2026-08/patches/$id.patch"
  pinned=$(grep -o '| Patch SHA-256 | `[0-9a-f]*` |' "$note" | grep -o '[0-9a-f]\{64\}')
  if [ -z "$pinned" ]; then echo "FAIL preliminary $id: no pinned hash in finding note"; fail=1; continue; fi
  if [ ! -f "$patch" ]; then echo "FAIL preliminary $id: missing $patch"; fail=1; continue; fi
  actual=$(shasum -a 256 "$patch" | cut -d' ' -f1)
  if [ "$actual" != "$pinned" ]; then echo "FAIL preliminary $id: hash mismatch ($actual != $pinned)"; fail=1; continue; fi
  preliminary_count=$((preliminary_count+1))
done

verification_count=0
verification_note="evidence/external-audit/preliminary-2026-08/vault-recertification.md"
verification_patch="evidence/external-audit/preliminary-2026-08/patches/vault-recertification.patch"
verification_pinned=$(grep -o '| Overlay SHA-256 | `[0-9a-f]*` |' "$verification_note" | grep -o '[0-9a-f]\{64\}')
if [ -z "$verification_pinned" ]; then
  echo "FAIL Vault recertification: no pinned overlay hash"
  fail=1
elif [ ! -f "$verification_patch" ]; then
  echo "FAIL Vault recertification: missing $verification_patch"
  fail=1
else
  verification_actual=$(shasum -a 256 "$verification_patch" | cut -d' ' -f1)
  if [ "$verification_actual" != "$verification_pinned" ]; then
    echo "FAIL Vault recertification: hash mismatch ($verification_actual != $verification_pinned)"
    fail=1
  else
    verification_count=1
  fi
fi

preliminary_extra=$(ls evidence/external-audit/preliminary-2026-08/patches/*.patch | wc -l | tr -d ' ')
preliminary_expected=$((preliminary_count + verification_count))
if [ "$preliminary_extra" != "$preliminary_expected" ]; then
  echo "FAIL: $preliminary_extra preliminary patch files for $preliminary_count verified findings and $verification_count verification overlay(s)"
  fail=1
fi

[ "$fail" = "0" ] && echo "OK: $count/21 closed patches, $preliminary_count preliminary remediation patches, and $verification_count verification overlay verified"
exit "$fail"
