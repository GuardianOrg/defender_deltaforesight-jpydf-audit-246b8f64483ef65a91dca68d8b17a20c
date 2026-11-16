import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const BASE_SOURCE_COMMIT = "d4122704d08b521d832438c31c0ddccf202fea81";
const FINAL_SOURCE_COMMIT = "1b453c10e3378390109cf42037a97b7f6de57b9e";
const BASE_SRC_TREE = "417fe3b995f3dec84fd611fcc2f5c3ebd62d5c7a";
const FINAL_SRC_TREE = "84476d9086e89580c58918b203f4142ecd839765";
const EXPECTED_HUNKS = 171;
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const TSV = join(ROOT, "FINAL_PRODUCTION_HUNK_PROVENANCE.tsv");

const HEADER = [
  "path",
  "hunk_id",
  "base_range",
  "final_range",
  "hunk_sha256",
  "base_blob",
  "final_blob",
  "origin_prs",
  "origin_commits",
  "attribution_basis",
  "theme",
  "rationale",
];

const metadata = new Map([
  ["AddressesRegistry.sol", ["reserved-risk-finalization", "Add dedicated one-shot atomic risk finalization and contract-side invariant validation for reserved branches."]],
  ["BorrowerOperations.sol", ["oracle-recovery-and-risk-finalization", "Separate recoverable oracle pause from terminal shutdown, allow defined risk-reducing operations, synchronize finalized risk values, and validate all live paths on resume."]],
  ["CollateralVault.sol", ["vault-full-backing", "Require live conservative full backing on user outflow/inflow paths and after nonzero Strategy allocation while retaining repair ingress."]],
  ["DFStabilityPool.sol", ["reserved-risk-finalization", "Expose/synchronize the reserved-branch risk parameters consumed by DF Stability Pool behavior."]],
  ["Dependencies/Constants.sol", ["production-parameters-and-cleanup", "Set the production MIN_DEBT floor to 100,000e18; #1847 removes every intermediate pilot overlay, so that cleanup is endpoint absence rather than a surviving d412-to-final hunk."]],
  ["Interfaces/IAddressesRegistry.sol", ["reserved-risk-finalization", "Expose finalizer, finalized state, parameters, and finalization entrypoint consistently with implementation."]],
  ["Interfaces/IBorrowerOperations.sol", ["oracle-recovery-and-risk-finalization", "Expose recoverable-pause and synchronized-risk operations used by proxy/registry integration."]],
  ["Interfaces/IJpyUsdRateProvider.sol", ["jpy-provenance", "Expose source-bound JPY round provenance needed by the 30-hour normal-redemption gate."]],
  ["Interfaces/IPriceFeed.sol", ["urgent-price-path", "Add the dedicated live urgent-redemption price path."]],
  ["Interfaces/IPriceFeedProxy.sol", ["proxy-lifecycle-and-recovery", "Expose source lifecycle, recoverable pause, and urgent path behavior used by governance/core."]],
  ["Interfaces/IStabilityPool.sol", ["reserved-risk-finalization", "Expose synchronized reserved risk state used by Stability Pool implementations."]],
  ["Interfaces/ITroveManager.sol", ["reserved-risk-finalization", "Expose one-shot risk synchronization consumed by AddressesRegistry finalization."]],
  ["PriceFeeds/CompositePriceFeed.sol", ["urgent-price-path", "Provide a live urgent path and prevent terminal cached price use for urgent settlement."]],
  ["PriceFeeds/DFPriceFeedBase.sol", ["oracle-recovery-and-urgent", "Keep probing after recoverable failure, expose live urgent pricing, and preserve failure-state separation."]],
  ["PriceFeeds/DFWstETHPriceFeed.sol", ["wsteth-redemption-and-urgent", "Use max(direct,derived) for normal/urgent redemption, keep both reference legs fail-closed, and isolate normal vs redemption cache updates."]],
  ["PriceFeeds/JpyFreezeLib.sol", ["oracle-recovery", "Route shared-JPY expiry into recoverable pause instead of conflating it with irreversible shutdown."]],
  ["PriceFeeds/JpyUsdRateProvider.sol", ["jpy-runtime-validation-and-provenance", "Validate runtime decimals, harden freeze episodes, and expose the accepted round timestamp/provider provenance."]],
  ["PriceFeeds/MainnetPriceFeedBase.sol", ["oracle-response-acquisition", "Return timestamp-aware validated Chainlink responses while retaining the shared gas-griefing and staleness checks."]],
  ["PriceFeeds/PriceFeedPlaceholder.sol", ["reserved-branch-source", "Return a valid sentinel on all three price paths; reserved-branch inoperability comes from the cap, Vault, dToken, and finalization guards."]],
  ["PriceFeeds/PriceFeedProxy.sol", ["proxy-lifecycle-recovery-and-30h", "Latch recoverable failures, separate three caches/paths, validate resume, enforce source-bound 30-hour redemption provenance, and accurately describe the shallow source marker."]],
  ["RedemptionHelper.sol", ["redemption-failure-accounting", "Retain failed-branch denominator share and refund unused input instead of reallocating to healthy branches."]],
  ["StabilityPool.sol", ["reserved-risk-finalization", "Synchronize finalized reserved risk values in the inherited Stability Pool surface."]],
  ["TroveManager.sol", ["shutdown-urgent-and-risk-finalization", "Separate failure from terminal shutdown, consume the dedicated urgent price, and synchronize one-shot risk parameters."]],
  ["Zappers/CollateralYieldZapper.sol", ["zapper-referral-and-native-eth", "Add manager-controlled Lido referral attribution and native-ETH wrapping without changing user accounting/min-out/refund semantics."]],
  ["Zappers/archive/SkyUsdcSUsdsYieldZapper.sol", ["zapper-constructor-context", "Keep the archived derived constructor chain compatible with the referral-manager base change."]],
]);

const hunkMetadata = new Map([
  ["H-66144cfadce8c49f68c8", ["legacy-build-compatibility", "Mirror the reserved-risk gate in the non-production legacy StabilityPool used only by parity tests."]],
  ["H-4ddd64b7487f7ad501a2", ["legacy-build-compatibility", "Mirror the reserved-risk gate in the non-production legacy StabilityPool used only by parity tests."]],
  ["H-1edff495755bd1dca53e", ["legacy-build-compatibility", "Mirror the reserved-risk gate in the non-production legacy StabilityPool used only by parity tests."]],
  ["H-8080a4dda91cc5466470", ["archive-feed-compatibility", "Provide the default urgent path used only by archived sUSDS; the active wstETH feed overrides it."]],
  ["H-5936a9e8dc8c4c3d82c9", ["oracle-recovery", "Rename the active oracle-failure helper to make recoverable source retry behavior explicit."]],
  ["H-d6ecf8ae374748bdca95", ["oracle-recovery", "Remove the terminal priceSource latch from the active oracle-failure helper so live source probing can recover."]],
  ["H-af9389d85c876e68b4c6", ["archive-feed-compatibility", "Retain the terminal-switch wrapper only for archived DFWBTC and sUSDS test compatibility; current production callers do not use it."]],
  ["H-3f2ed8ff86c05ed44e60", ["cosmetic-comment", "Consolidate a comment without changing code, ABI, storage, or runtime behavior."]],
  ["H-cdbd3091976837699ca1", ["archive-zapper-compatibility", "Forward the parent constructor argument only so the archived Sky Zapper test surface continues to compile."]],
]);

function reviewMetadata(path, hunkId) {
  return hunkMetadata.get(hunkId) ?? metadata.get(path);
}

// PR commits without a PR number in their subject are attributed only when they
// are on the PR's second-parent history and absent from its first parent.
const prBranches = [
  ["1575", "d209b5438054ce10701a9813a55528b943a90b2a", "4651d9c5aa5173fa469cccadae2ce2645ef6d11b"],
  ["1595", "2d537328aa97260c83c3bfcc9d8e70225e48a30f", "bb13eb9b40a04daf78d3c12f200508ef92a30d63"],
  ["1780", "bdfe6b254ad27dd82b540cda380a929c2957e86c", "6cee4bd033b41c9bad972ba90f0d1b3697bafc5b"],
  ["1799", "d6aef86940e8a226ff01f48ebb14a963536f4fe6", "e52e78069a63558d0756c9c5b1c19306a9aafb7a"],
  ["1805", "b85f6f995663c55169c0bc0d9fd460dc7ddb665e", "fdd18070f243d925560cecfaed9ef16f819fb30d"],
  ["1841", "8ee30c8b977891efa4bc19b58276882dee1b8822", "e6b7cadc35398d2c7e732368657fa25361fb0ea8"],
  ["1847", "061dd124aeb5baef76e7bb5352e8d497ecf7197a", "96a2a746c0cf513911e1e132ced246ea38480e31"],
];

const deletionOverrides = new Map([
  ["PriceFeeds/MainnetPriceFeedBase.sol:81,2:81,0", "d49ee76f1731ed1b0d8e191a3acd61ae0fde2530"],
]);

function git(cwd, args) {
  return execFileSync("git", args, { cwd, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }).trimEnd();
}

function isAncestor(cwd, ancestor, descendant) {
  return spawnSync("git", ["merge-base", "--is-ancestor", ancestor, descendant], { cwd }).status === 0;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function normalizePath(path) {
  return path.startsWith("contracts/src/") ? path.slice("contracts/src/".length) : path;
}

function parseDiff(diff) {
  const hunks = [];
  let path;
  let current;

  const finish = () => {
    if (!current) return;
    // Exclude Git's optional @@ function hint: the stable identity is the
    // normalized path/ranges plus the exact zero-context +/- body.
    const canonical = `${current.path}\0${current.oldStart},${current.oldCount}`
      + `\0${current.newStart},${current.newCount}\0${current.body.join("\n")}\n`;
    current.hunkSha256 = sha256(canonical);
    current.hunkId = `H-${current.hunkSha256.slice(0, 20)}`;
    hunks.push(current);
    current = undefined;
  };

  for (const line of diff.split("\n")) {
    const fileMatch = line.match(/^diff --git a\/(.+) b\/(.+)$/);
    if (fileMatch) {
      finish();
      path = normalizePath(fileMatch[2]);
      continue;
    }
    const hunkMatch = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
    if (hunkMatch) {
      finish();
      if (!path) throw new Error(`hunk without path: ${line}`);
      current = {
        path,
        header: line,
        body: [],
        oldStart: Number(hunkMatch[1]),
        oldCount: hunkMatch[2] === undefined ? 1 : Number(hunkMatch[2]),
        newStart: Number(hunkMatch[3]),
        newCount: hunkMatch[4] === undefined ? 1 : Number(hunkMatch[4]),
      };
      continue;
    }
    if (current) current.body.push(line);
  }
  finish();
  if (hunks.length !== EXPECTED_HUNKS) {
    throw new Error(`expected ${EXPECTED_HUNKS} hunks, found ${hunks.length}`);
  }
  return hunks;
}

function getTreeHunks(cwd) {
  const diff = git(cwd, [
    "diff", "--no-ext-diff", "--no-renames", "--unified=0", "--no-color",
    BASE_SRC_TREE, FINAL_SRC_TREE, "--",
  ]);
  return parseDiff(diff);
}

function range(start, count) {
  return `${start},${count}`;
}

function structuralFields(cwd, hunk) {
  return {
    path: hunk.path,
    hunk_id: hunk.hunkId,
    base_range: range(hunk.oldStart, hunk.oldCount),
    final_range: range(hunk.newStart, hunk.newCount),
    hunk_sha256: hunk.hunkSha256,
    base_blob: git(cwd, ["rev-parse", `${BASE_SRC_TREE}:${hunk.path}`]),
    final_blob: git(cwd, ["rev-parse", `${FINAL_SRC_TREE}:${hunk.path}`]),
  };
}

function splitNonempty(value) {
  return value.split("\n").map((entry) => entry.trim()).filter(Boolean);
}

function commitPr(source, commit, cache) {
  if (cache.has(commit)) return cache.get(commit);
  const subject = git(source, ["show", "-s", "--format=%s", commit]);
  const direct = [...subject.matchAll(/#(\d+)/g)].map((match) => match[1]);
  if (direct.length > 0) {
    cache.set(commit, direct[direct.length - 1]);
    return cache.get(commit);
  }
  for (const [pr, firstParent, secondParent] of prBranches) {
    if (isAncestor(source, commit, secondParent) && !isAncestor(source, commit, firstParent)) {
      cache.set(commit, pr);
      return pr;
    }
  }
  throw new Error(`cannot attribute commit ${commit} (${subject}) to a PR`);
}

function hunkOrigins(source, hunk, postBase, postBaseRank, prCache) {
  const overrideKey = `${hunk.path}:${range(hunk.oldStart, hunk.oldCount)}:${range(hunk.newStart, hunk.newCount)}`;
  let commits;
  let basis;
  if (hunk.newCount === 0) {
    const commit = deletionOverrides.get(overrideKey);
    if (!commit) throw new Error(`missing deletion override for ${overrideKey}`);
    commits = [commit];
    basis = `deleting-commit-parent-patch:${commit};base-range=${range(hunk.oldStart, hunk.oldCount)}`;
  } else {
    const end = hunk.newStart + hunk.newCount - 1;
    const blame = git(source, [
      "blame", "--line-porcelain", `-L${hunk.newStart},${end}`,
      FINAL_SOURCE_COMMIT, "--", `contracts/src/${hunk.path}`,
    ]);
    const lineAuthors = [...blame.matchAll(/^([0-9a-f]{40}) \d+ \d+(?: \d+)?$/gm)].map((match) => match[1]);
    commits = [...new Set(lineAuthors.filter((commit) => postBase.has(commit)))];
    commits.sort((left, right) => postBaseRank.get(left) - postBaseRank.get(right));
    if (commits.length === 0) {
      throw new Error(`no post-base final-line author for ${hunk.path}:${range(hunk.newStart, hunk.newCount)}`);
    }
    basis = `git-blame:final-${hunk.newStart}-${end};filter=${BASE_SOURCE_COMMIT.slice(0, 8)}..${FINAL_SOURCE_COMMIT.slice(0, 8)}`;
  }
  const prs = [...new Set(commits.map((commit) => commitPr(source, commit, prCache)))];
  return { commits, prs, basis };
}

function checkedRow(values) {
  const fields = HEADER.map((header) => String(values[header]));
  for (let index = 0; index < fields.length; index += 1) {
    if (/[\t\r\n]/.test(fields[index])) throw new Error(`invalid TSV field ${HEADER[index]}`);
  }
  return fields.join("\t");
}

function generate(sourceArg) {
  const source = resolve(sourceArg);
  if (git(source, ["rev-parse", `${BASE_SOURCE_COMMIT}:contracts/src`]) !== BASE_SRC_TREE) {
    throw new Error("base source tree mismatch");
  }
  if (git(source, ["rev-parse", `${FINAL_SOURCE_COMMIT}:contracts/src`]) !== FINAL_SRC_TREE) {
    throw new Error("final source tree mismatch");
  }
  const sourceDiff = git(source, [
    "diff", "--no-ext-diff", "--no-renames", "--unified=0", "--no-color",
    BASE_SOURCE_COMMIT, FINAL_SOURCE_COMMIT, "--", "contracts/src",
  ]);
  const hunks = parseDiff(sourceDiff);
  const postBaseHistory = splitNonempty(git(source, [
    "rev-list", "--reverse", "--topo-order", `${BASE_SOURCE_COMMIT}..${FINAL_SOURCE_COMMIT}`,
  ]));
  const postBase = new Set(postBaseHistory);
  const postBaseRank = new Map(postBaseHistory.map((commit, index) => [commit, index]));
  const prCache = new Map();
  const rows = [HEADER.join("\t")];
  for (const hunk of hunks) {
    const fileMetadata = reviewMetadata(hunk.path, hunk.hunkId);
    if (!fileMetadata) throw new Error(`missing metadata for ${hunk.path}`);
    const origins = hunkOrigins(source, hunk, postBase, postBaseRank, prCache);
    rows.push(checkedRow({
      ...structuralFields(source, hunk),
      origin_prs: origins.prs.join(","),
      origin_commits: origins.commits.join(","),
      attribution_basis: origins.basis,
      theme: fileMetadata[0],
      rationale: fileMetadata[1],
    }));
  }
  process.stdout.write(`${rows.join("\n")}\n`);
}

function verify() {
  const hunks = getTreeHunks(ROOT);
  const lines = readFileSync(TSV, "utf8").trimEnd().split("\n");
  const actualHeader = lines.shift().split("\t");
  if (actualHeader.join("\t") !== HEADER.join("\t")) {
    throw new Error(`unexpected TSV header: ${actualHeader.join("\t")}`);
  }
  if (lines.length !== hunks.length) {
    throw new Error(`expected ${hunks.length} TSV rows, found ${lines.length}`);
  }
  const ids = new Set();
  const reviewPaths = new Set();
  for (let index = 0; index < hunks.length; index += 1) {
    const values = lines[index].split("\t");
    if (values.length !== HEADER.length) throw new Error(`row ${index + 2} has ${values.length} fields`);
    const row = Object.fromEntries(HEADER.map((header, field) => [header, values[field]]));
    const expected = structuralFields(ROOT, hunks[index]);
    for (const [field, value] of Object.entries(expected)) {
      if (row[field] !== value) {
        throw new Error(`row ${index + 2} ${field}: expected ${value}, got ${row[field]}`);
      }
    }
    if (ids.has(row.hunk_id)) throw new Error(`duplicate hunk ID ${row.hunk_id}`);
    ids.add(row.hunk_id);
    reviewPaths.add(row.path);
    if (!/^\d+(,\d+)*$/.test(row.origin_prs)) throw new Error(`invalid origin_prs at row ${index + 2}`);
    if (!/^[0-9a-f]{40}(,[0-9a-f]{40})*$/.test(row.origin_commits)) {
      throw new Error(`invalid origin_commits at row ${index + 2}`);
    }
    if (!row.attribution_basis) throw new Error(`missing attribution_basis at row ${index + 2}`);
    const fileMetadata = reviewMetadata(row.path, row.hunk_id);
    if (!fileMetadata || row.theme !== fileMetadata[0] || row.rationale !== fileMetadata[1]) {
      throw new Error(`metadata mismatch at row ${index + 2}`);
    }
  }
  if (hunks.length !== EXPECTED_HUNKS || reviewPaths.size !== 25) {
    throw new Error(`review boundary mismatch: ${hunks.length} hunks across ${reviewPaths.size} paths`);
  }
  console.log(
    `final production hunk provenance verification: PASS `
      + `(${hunks.length} source hunks across ${reviewPaths.size} review paths)`,
  );
}

if (process.argv[2] === "--generate") {
  if (process.argv.length !== 4) {
    throw new Error("usage: node scripts/verify-final-hunk-provenance.mjs --generate SOURCE_CHECKOUT");
  }
  generate(process.argv[3]);
} else if (process.argv.length === 2) {
  verify();
} else {
  throw new Error("usage: node scripts/verify-final-hunk-provenance.mjs [--generate SOURCE_CHECKOUT]");
}
