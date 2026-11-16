#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <jpydf-v2-checkout> <source-commit>" >&2
  exit 2
fi

SOURCE_REPO="$1"
SOURCE_COMMIT="$2"
AUDIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_HEAD="$(git -C "$SOURCE_REPO" rev-parse --verify HEAD)"
RESOLVED="$(git -C "$SOURCE_REPO" rev-parse --verify "${SOURCE_COMMIT}^{commit}")"
if [[ "$SOURCE_HEAD" != "$RESOLVED" ]]; then
  echo "FAIL: source checkout is at $SOURCE_HEAD, expected $RESOLVED" >&2
  exit 1
fi

if git -C "$SOURCE_REPO" submodule status --recursive | grep -Eq '^[-+U]'; then
  echo "FAIL: source checkout has an uninitialized or mismatched submodule" >&2
  exit 1
fi
while read -r path; do
  [[ -n "$path" && -n "$(find "${SOURCE_REPO}/${path}" -mindepth 1 -print -quit)" ]] || {
    echo "FAIL: required dependency is empty: ${path}" >&2
    exit 1
  }
done < <(git -C "$SOURCE_REPO" config --file .gitmodules --get-regexp path | awk '{print $2}')

SOURCE_TREE="$(git -C "$SOURCE_REPO" rev-parse "${RESOLVED}:contracts/src")"
SNAPSHOT_TREE="$(git -C "$AUDIT_ROOT" rev-parse "HEAD:source-snapshot/contracts/src")"
if [[ "$SOURCE_TREE" != "$SNAPSHOT_TREE" ]]; then
  echo "FAIL: contracts/src tree mismatch" >&2
  echo "source   $SOURCE_TREE" >&2
  echo "snapshot $SNAPSHOT_TREE" >&2
  exit 1
fi

echo "OK: source-snapshot/contracts/src = $RESOLVED:contracts/src ($SOURCE_TREE)"
