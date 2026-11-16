#!/usr/bin/env python3
"""Verify the exported files and reconstruct the exact deployed source tree."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

package = Path(__file__).resolve().parent
repo = package.parents[2]
identity = json.loads((package / "identity.json").read_text())
for name, expected in json.loads((package / "file-sha256.json").read_text()).items():
    assert hashlib.sha256((package / name).read_bytes()).hexdigest() == expected, name
assert not any(p.name in {".git", ".env"} for p in package.rglob("*"))
with tempfile.TemporaryDirectory(prefix="jpydf-review-source-") as directory:
    temporary = Path(directory)
    shutil.copytree(repo / "source-snapshot/contracts/src", temporary / "contracts/src")
    def git(*args):
        return subprocess.check_output(["git", "-C", directory, *args], text=True).strip()
    git("init", "-q")
    git("add", "contracts/src")
    baseline = git("write-tree")
    assert git("rev-parse", baseline + ":contracts/src") == identity["guardianBaselineContractsSrcTree"]
    git("apply", str(package / "guardian-to-deployed.patch"))
    def files(root):
        return {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert files(temporary / "contracts/src") == files(package / "source/contracts/src")
    git("add", "contracts/src")
    result = git("write-tree")
    assert git("rev-parse", result + ":contracts/src") == identity["deploymentContractsSrcTree"]
print("PASS: file hashes, baseline tree, patch reconstruction and deployed source tree")
