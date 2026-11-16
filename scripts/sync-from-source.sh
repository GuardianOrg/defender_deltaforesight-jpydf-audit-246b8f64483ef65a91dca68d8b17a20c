#!/usr/bin/env bash
#
# Rebuild every tree in this repository from one source freeze plus the ordered
# remediation overlays committed here, and verify the result byte-for-byte.
#
#   ./scripts/sync-from-source.sh <source-repo> <commit>            # rewrite
#   ./scripts/sync-from-source.sh --verify <source-repo> <commit>   # check only
#
# --verify exits non-zero if any tracked file has drifted from the reconstructed
# review target. It is the fail-closed gate: run it before publishing a freeze
# or remediation, so a stale or partially-applied tree cannot reach an auditor.
#
# Two trees, two rules:
#
#   source-snapshot/contracts/  Rule-based. Whole directories plus a fixed list
#                               of build-config files, minus EXCLUDED_PATHS.
#   docs/, source/              Explicit, because the source repository has
#                               reorganised its documentation and file paths no
#                               longer correspond. Every pair is recorded in
#                               MAPPING; nothing is matched by guesswork.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAPPING="${REPO_ROOT}/scripts/source-mapping.tsv"

# The preliminary follow-up findings are remediated in this public review
# repository one finding per patch. The final test/docs-only Vault
# recertification is applied after those finding overlays. They are applied in
# order to the last source-side handoff identity before snapshot reconciliation.
# Pin each hash so changing a patch also requires an explicit provenance update.
OVERLAY_BASE="fe3d3d0e182b8189202dee3a3db8103bd0df1de7"
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

# Directories copied wholesale into source-snapshot/contracts/.
SNAPSHOT_DIRS=(src script test certora)

# Build configuration the auditor needs to compile what is in those directories.
SNAPSHOT_FILES=(
  foundry.toml remappings.txt slither.config.json
  package.json requirements.txt README.md LICENSE
  utils/check-contract-sizes.sh
  utils/assets/geist.txt
  utils/assets/jpydf_logo.txt
  utils/assets/weth_logo.txt
  utils/assets/test_output/.gitignore
)

# Curated out of the snapshot. SeedLocalDemo hardcodes a public Anvil private
# key; it is a local demo helper and not part of the review surface.
EXCLUDED_PATHS=(script/SeedLocalDemo.s.sol)

VERIFY=0
if [[ "${1:-}" == "--verify" ]]; then VERIFY=1; shift; fi
if [[ $# -ne 2 ]]; then
  echo "usage: $0 [--verify] <source-repo> <commit>" >&2
  exit 2
fi
SOURCE_REPO="$1"
COMMIT="$2"

git -C "$SOURCE_REPO" rev-parse --verify "${COMMIT}^{commit}" >/dev/null 2>&1 || {
  echo "error: ${COMMIT} is not a commit in ${SOURCE_REPO}" >&2
  exit 2
}
RESOLVED="$(git -C "$SOURCE_REPO" rev-parse "${COMMIT}^{commit}")"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
git clone --quiet --no-checkout --local "$SOURCE_REPO" "$STAGE"
git -C "$STAGE" checkout --quiet --detach "$RESOLVED"
git -C "$STAGE" submodule update --init --recursive

if git -C "$STAGE" submodule status --recursive | grep -Eq '^[-+U]'; then
  echo "error: source checkout has an uninitialized or mismatched submodule" >&2
  exit 2
fi
while read -r path; do
  [[ -n "$path" && -n "$(find "${STAGE}/${path}" -mindepth 1 -print -quit)" ]] || {
    echo "error: required dependency is empty: ${path}" >&2
    exit 2
  }
done < <(git -C "$STAGE" config --file .gitmodules --get-regexp path | awk '{print $2}')

overlay_count=0
if [[ "$RESOLVED" == "$OVERLAY_BASE" ]]; then
  echo "== ordered audit overlays =="
  for i in "${!OVERLAY_PATCHES[@]}"; do
    rel="${OVERLAY_PATCHES[$i]}"
    patch="${REPO_ROOT}/${rel}"
    [[ -f "$patch" ]] || {
      echo "error: missing remediation overlay ${rel}" >&2
      exit 2
    }
    actual_sha="$(shasum -a 256 "$patch" | cut -d' ' -f1)"
    [[ "$actual_sha" == "${OVERLAY_SHA256[$i]}" ]] || {
      echo "error: remediation overlay hash mismatch for ${rel}" >&2
      exit 2
    }
    git -C "$STAGE" apply --check "$patch"
    git -C "$STAGE" apply "$patch"
    echo "APPLIED            ${rel}"
    overlay_count=$((overlay_count + 1))
  done
fi

drift=0
missing=0
undecided=0

# Report a single file. In verify mode nothing is written.
sync_one() {
  local src="$1" dst="$2" shown="${2#$REPO_ROOT/}"
  if [[ ! -f "$src" ]]; then
    echo "MISSING-IN-SOURCE  $shown  <- ${src#$STAGE/}"
    missing=$((missing + 1))
    return
  fi
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return
  fi
  echo "DRIFT              $shown"
  drift=$((drift + 1))
  if [[ $VERIFY -eq 0 ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
}

is_excluded() {
  local rel="$1" ex
  for ex in "${EXCLUDED_PATHS[@]}"; do [[ "$rel" == "$ex" ]] && return 0; done
  return 1
}

echo "== source-snapshot/contracts =="
SNAP="${REPO_ROOT}/source-snapshot/contracts"

# Files present in the snapshot but no longer in the source commit are deletions
# and must be removed, or the auditor reviews code that no longer exists.
EXPECTED="${STAGE}/.expected"
: > "$EXPECTED"
for d in "${SNAPSHOT_DIRS[@]}"; do
  [[ -d "${STAGE}/contracts/${d}" ]] || continue
  while IFS= read -r -d '' f; do
    rel="${f#${STAGE}/contracts/}"
    is_excluded "$rel" && continue
    printf '%s\n' "$rel" >> "$EXPECTED"
    sync_one "$f" "${SNAP}/${rel}"
  done < <(find "${STAGE}/contracts/${d}" -type f -print0)
done
for f in "${SNAPSHOT_FILES[@]}"; do
  printf '%s\n' "$f" >> "$EXPECTED"
  sync_one "${STAGE}/contracts/${f}" "${SNAP}/${f}"
done

if [[ -d "$SNAP" ]]; then
  while IFS= read -r -d '' f; do
    rel="${f#${SNAP}/}"
    grep -qxF "$rel" "$EXPECTED" && continue
    echo "STALE              source-snapshot/contracts/${rel}  (gone from source)"
    drift=$((drift + 1))
    [[ $VERIFY -eq 0 ]] && rm -f "$f"
  done < <(find "$SNAP" -type f -print0)
fi

echo "== mapped files (docs/, source/) =="
while IFS=$'\t' read -r dst src; do
  [[ -z "${dst:-}" || "$dst" == \#* ]] && continue
  case "$src" in
    REMOVED-UPSTREAM*)
      # Deliberately retained: the file documents contracts that existed at the
      # audited identity. Kept as the as-audited record, never refreshed.
      ;;
    NEEDS-DECISION*)
      echo "UNDECIDED          $dst  (${src#NEEDS-DECISION })"
      undecided=$((undecided + 1))
      ;;
    *)
      sync_one "${STAGE}/${src}" "${REPO_ROOT}/${dst}"
      ;;
  esac
done < "$MAPPING"

# The trees can match a commit while the documents name a different one — that is
# how the freeze was once stated one commit behind what had actually been synced.
# Content checks cannot catch it, so check the prose too. Only lines that claim to
# name the freeze are examined, which keeps unrelated hashes (a Foundry build, an
# earlier audited identity) out of it.
#
# `-A2` because the check was line-scoped and prose wraps: two documents said
# "...refreshed to the follow-up freeze" and put the hash on the NEXT line, so a
# stale claim passed while an identically-stale one on a single line was caught.
# The trailing two lines are enough for any wrap that keeps the hash near its
# claim, and they do not reach far enough to pull in an unrelated hash.
# Identities the documents legitimately name alongside the freeze: the audited
# identity and the earlier handoff points. Not stale freeze claims.
PRIOR_IDENTITIES="03fa20a3|aa1e55e1|c1b34df3|0a85b374|0c7766e0|dab4dbe5|10cf5efc|4df6d902|60e6e0a8"
stated=0
for doc in README.md docs/audit/SOURCE_MANIFEST.md docs/audit/AUDITOR_READING_GUIDE.md \
           scripts/checkout-source.sh source-snapshot/README.md \
           docs/audit/history/SCOPE_DELTA_2026-08-07.md \
           docs/audit/history/SCOPE_DELTA_2026-08-09.md; do
  f="${REPO_ROOT}/${doc}"
  [[ -f "$f" ]] || continue
  while read -r found; do
    [[ -z "$found" || "$RESOLVED" == "$found"* ]] && continue
    echo "STATED-FREEZE      ${doc} names ${found} as the freeze, not ${RESOLVED:0:8}"
    stated=$((stated + 1))
  done < <(grep -iE -A2 "follow-up freeze|FREEZE_COMMIT|review target" "$f" 2>/dev/null \
           | grep -ohE "\b[0-9a-f]{8}([0-9a-f]{32})?\b" \
           | grep -vE "^(${PRIOR_IDENTITIES})" | sort -u)
done

echo
echo "commit    ${RESOLVED}"
echo "overlays  ${overlay_count}"
echo "drift     ${drift}"
echo "missing   ${missing}"
echo "undecided ${undecided}"
echo "stated    ${stated}"

if [[ $VERIFY -eq 1 ]]; then
  if (( drift || missing || undecided || stated )); then
    echo "FAIL: the handoff trees do not match the reconstructed review target." >&2
    exit 1
  fi
  echo "OK: every tracked file matches ${RESOLVED} plus ${overlay_count} overlay(s)."
else
  (( drift )) && echo "Rewrote ${drift} file(s). Review 'git diff' before committing."
  (( missing || undecided || stated )) && {
    echo "Resolve the entries above in scripts/source-mapping.tsv." >&2
    exit 1
  }
fi
