#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAPPING="$ROOT_DIR/PRODUCTION_COMPANION_MAPPING.tsv"
EXPECTED_SOURCE_COMMIT="1b453c10e3378390109cf42037a97b7f6de57b9e"
EXPECTED_SRC_TREE="84476d9086e89580c58918b203f4142ecd839765"
EXPECTED_TEST_TREE="65edf44aaad8ee395fa9456151fed25f40a3dfde"
RUN_BUILD=false

if [[ "${1:-}" == "--build" ]]; then
  RUN_BUILD=true
  shift
fi
if [[ $# -ne 0 && $# -ne 2 ]]; then
  echo "usage: $0 [--build] [SOURCE_CHECKOUT EXPECTED_COMMIT]" >&2
  exit 2
fi

cd "$ROOT_DIR"
[[ -f "$MAPPING" ]] || { echo "missing $MAPPING" >&2; exit 1; }

while IFS=$'\t' read -r kind source_rel audit_rel expected_object; do
  [[ "$kind" == "kind" ]] && continue
  [[ -e "$audit_rel" ]] || { echo "missing audit path: $audit_rel" >&2; exit 1; }
  if [[ "$kind" == "blob" ]]; then
    actual_object="$(git hash-object "$audit_rel")"
  elif [[ "$kind" == "tree" ]]; then
    git diff --quiet HEAD -- "$audit_rel" || {
      echo "tree verification requires committed content: $audit_rel" >&2
      exit 1
    }
    actual_object="$(git rev-parse "HEAD:$audit_rel")"
  else
    echo "unknown mapping kind: $kind" >&2
    exit 1
  fi
  [[ "$actual_object" == "$expected_object" ]] || {
    echo "audit object mismatch: $audit_rel expected=$expected_object actual=$actual_object" >&2
    exit 1
  }
done < "$MAPPING"

# Every committed file in the selected script/tool closure must itself be in
# the exact-object ledger. The source/test trees are covered by their tree rows.
while IFS= read -r audit_rel; do
  awk -F $'\t' -v path="$audit_rel" 'NR > 1 && $3 == path { found = 1 } END { exit !found }' "$MAPPING" || {
    echo "selected companion path is not mapped: $audit_rel" >&2
    exit 1
  }
done < <(git ls-files 'source-snapshot/contracts/script/**' 'source-snapshot/contracts/utils/**')

[[ "$(git rev-parse HEAD:source-snapshot/contracts/src)" == "$EXPECTED_SRC_TREE" ]]
[[ "$(git rev-parse HEAD:source-snapshot/contracts/test)" == "$EXPECTED_TEST_TREE" ]]
[[ "$(git ls-tree HEAD source-snapshot/contracts/deploy | awk '{print $1}')" == "100755" ]]
grep -q '"packageManager": "pnpm@10.4.1"' source-snapshot/contracts/package.json
grep -q '"test:production-rollback": "tsx utils/check-production-rollback.test.ts"' \
  source-snapshot/contracts/package.json
[[ -f source-snapshot/contracts/pnpm-lock.yaml ]]

if grep -R -n -E --include='*.sol' \
  'MAINNET_PILOT_CLEANUP_OVERLAY|isMainnetPilotOverlay|PILOT_MAX_JPYDF_ROUNDING_DUST|effectiveSPYieldSplit' \
  source-snapshot/contracts/src; then
  echo "pilot cleanup overlay remains in production Solidity" >&2
  exit 1
fi

if [[ $# -eq 2 ]]; then
  SOURCE_CHECKOUT="$1"
  REQUESTED_COMMIT="$2"
  [[ "$REQUESTED_COMMIT" == "$EXPECTED_SOURCE_COMMIT" ]] || {
    echo "unexpected requested source commit: $REQUESTED_COMMIT" >&2
    exit 1
  }
  [[ "$(git -C "$SOURCE_CHECKOUT" rev-parse HEAD)" == "$EXPECTED_SOURCE_COMMIT" ]] || {
    echo "source checkout is not at the final production commit" >&2
    exit 1
  }
  [[ "$(git -C "$SOURCE_CHECKOUT" rev-parse HEAD:contracts/src)" == "$EXPECTED_SRC_TREE" ]]
  [[ "$(git -C "$SOURCE_CHECKOUT" rev-parse HEAD:contracts/test)" == "$EXPECTED_TEST_TREE" ]]

  if git -C "$SOURCE_CHECKOUT" submodule status --recursive | grep -Eq '^[+-U]'; then
    echo "source checkout has missing or non-pinned submodules" >&2
    exit 1
  fi
  while IFS= read -r dependency_dir; do
    [[ -n "$(find "$dependency_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
      echo "empty dependency directory: $dependency_dir" >&2
      exit 1
    }
  done < <(find "$SOURCE_CHECKOUT/contracts/lib" -mindepth 1 -maxdepth 1 -type d -print)

  while IFS=$'\t' read -r kind source_rel audit_rel expected_object; do
    [[ "$kind" == "kind" ]] && continue
    [[ "$(git -C "$SOURCE_CHECKOUT" rev-parse "HEAD:$source_rel")" == "$expected_object" ]] || {
      echo "source object mismatch: $source_rel" >&2
      exit 1
    }
    if [[ "$kind" == "blob" ]]; then
      cmp -s "$SOURCE_CHECKOUT/$source_rel" "$ROOT_DIR/$audit_rel" || {
        echo "source/audit file mismatch: $source_rel -> $audit_rel" >&2
        exit 1
      }
    fi
  done < "$MAPPING"
  diff -qr "$SOURCE_CHECKOUT/contracts/src" source-snapshot/contracts/src
  diff -qr "$SOURCE_CHECKOUT/contracts/test" source-snapshot/contracts/test
fi

if [[ "$RUN_BUILD" == true ]]; then
  check_dependency() {
    local path="$1"
    local expected="$2"
    [[ -d "$path/.git" || -f "$path/.git" ]] || {
      echo "missing dependency checkout: $path" >&2
      exit 1
    }
    [[ "$(git -C "$path" rev-parse HEAD)" == "$expected" ]] || {
      echo "dependency commit mismatch: $path" >&2
      exit 1
    }
    if git -C "$path" submodule status --recursive | grep -Eq '^[+-U]'; then
      echo "dependency has missing or non-pinned recursive submodules: $path" >&2
      exit 1
    fi
  }

  check_dependency source-snapshot/contracts/lib/forge-std \
    726a6ee5fc8427a0013d6f624e486c9130c0e336
  check_dependency source-snapshot/contracts/lib/openzeppelin-contracts \
    bd325d56b4c62c9c5c1aff048c37c6bb18ac0290
  check_dependency source-snapshot/contracts/lib/openzeppelin-contracts-upgradeable \
    2d081f24cac1a867f6f73d512f2022e1fa987854
  check_dependency source-snapshot/contracts/lib/Solady \
    362b2efd20f38aea7252b391e5e016633ff79641
  check_dependency source-snapshot/contracts/lib/V2-gov \
    b880481d701d2b07236f2e04842c79b4fe77e5fd

  (cd source-snapshot/contracts && forge build --skip test)
fi

echo "production companion verification: PASS"
