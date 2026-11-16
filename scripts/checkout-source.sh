#!/usr/bin/env bash
set -euo pipefail

# Default: the final correction freeze for the wstETH / Morpho V2 cycle.
#   (no flag)   fe3d3d0e + accepted preliminary remediation and verification overlays
#   --audited   0c7766e0 — identity audited by the August 2026 engagement
#   --base      dab4dbe5 — pre-remediation July audit base
# The final correction delta is in docs/audit/history/SCOPE_DELTA_2026-08-09.md;
# the broader delta from the audited identity is in
# docs/audit/history/SCOPE_DELTA_2026-08-07.md.
SOURCE_REPO="${SOURCE_REPO:-https://github.com/deltaforesight/jpydf-v2.git}"
FREEZE_COMMIT="fe3d3d0e182b8189202dee3a3db8103bd0df1de7"
AUDITED_COMMIT="0c7766e0a935b3dd99111349ef84e69c1a07da38"
BASE_COMMIT="dab4dbe5251f980a3af347cba20351513b026e7b"
AUDIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_PATCHES=(
  "evidence/external-audit/preliminary-2026-08/patches/m-01.patch"
  "evidence/external-audit/preliminary-2026-08/patches/m-02.patch"
  "evidence/external-audit/preliminary-2026-08/patches/l-01.patch"
  "evidence/external-audit/preliminary-2026-08/patches/l-02.patch"
  "evidence/external-audit/preliminary-2026-08/patches/l-03.patch"
  "evidence/external-audit/preliminary-2026-08/patches/vault-recertification.patch"
)
OVERLAY_SHA256=(
  "39f739b0decc81d98566b5ae63693284b6a8db99b9ddb927f92ccadbfbd5e94a"
  "1ceefb01fdfd4ef7367e2c9be4ef78710d76bea9bf2ccd1f086e966b86f905d0"
  "e8874e6444acfcf2535f3b9201d4f48bbf26c45b91c615c731fcb102906ecd06"
  "8f837c1b27c1cfce209c1a3c99b71b5c0e515b8a9704f877cbd3a4818da51562"
  "e8bb2af7da03ddb88e023b1c866e7db39eb24c70ac681ce1eb268117d826041b"
  "e19fd52e89a7dc539508e492ed4cb9eb49022d10eb61f3cacdca9d4d76848e8a"
)

if [ "${1:-}" = "--base" ]; then
  shift
  SOURCE_COMMIT="${SOURCE_COMMIT:-$BASE_COMMIT}"
elif [ "${1:-}" = "--audited" ]; then
  shift
  SOURCE_COMMIT="${SOURCE_COMMIT:-$AUDITED_COMMIT}"
else
  SOURCE_COMMIT="${SOURCE_COMMIT:-$FREEZE_COMMIT}"
fi
TARGET_DIR="${1:-jpydf-v2-source}"

if [ -e "$TARGET_DIR" ]; then
  echo "Target already exists: $TARGET_DIR" >&2
  exit 1
fi

git clone "$SOURCE_REPO" "$TARGET_DIR"
git -C "$TARGET_DIR" checkout "$SOURCE_COMMIT"
git -C "$TARGET_DIR" submodule update --init --recursive

RESOLVED="$(git -C "$TARGET_DIR" rev-parse HEAD)"
overlay_count=0
if [ "$RESOLVED" = "$FREEZE_COMMIT" ]; then
  for i in "${!OVERLAY_PATCHES[@]}"; do
    rel="${OVERLAY_PATCHES[$i]}"
    patch="${AUDIT_ROOT}/${rel}"
    actual_sha="$(shasum -a 256 "$patch" | cut -d' ' -f1)"
    if [ "$actual_sha" != "${OVERLAY_SHA256[$i]}" ]; then
      echo "Overlay hash mismatch: $rel" >&2
      exit 1
    fi
    git -C "$TARGET_DIR" apply --check "$patch"
    git -C "$TARGET_DIR" apply "$patch"
    echo "Applied audit overlay: $rel"
    overlay_count=$((overlay_count + 1))
  done
fi

echo "Checked out $SOURCE_REPO at $RESOLVED plus $overlay_count overlay(s) in $TARGET_DIR"
