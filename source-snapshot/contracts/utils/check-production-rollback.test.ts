import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

import { toBytes } from "viem";

import { assertProductionRollbackEvidence, assertProductionRollbackSource } from "./check-production-rollback.js";
import { PRODUCTION_DEPLOYMENT_CLASSIFICATION, PRODUCTION_DEPLOYMENT_ID } from "./deployment-manifest-policy.js";
const productionConstants = `
uint256 constant MIN_DEBT = 100_000e18;
uint256 constant SP_YIELD_SPLIT = 75 * _1pct;
`;
const productionToken = `
string internal constant _NAME = "JPYdf Stablecoin";
string internal constant _SYMBOL = "JPYdf";
constructor() ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME) {}
`;

assert.doesNotThrow(() => assertProductionRollbackSource(productionConstants, productionToken));
assert.throws(
  () => assertProductionRollbackSource(productionConstants.replace("100_000e18", "1_000e18"), productionToken),
  /MIN_DEBT/,
);
assert.throws(
  () => assertProductionRollbackSource(productionConstants, productionToken.replace("JPYdf Stablecoin", "Wrong Name")),
  /canonical token name/,
);
assert.throws(
  () => assertProductionRollbackSource(productionConstants, productionToken.replace("\"JPYdf\";", "\"WRONG\";")),
  /canonical token symbol/,
);
assert.throws(
  () => assertProductionRollbackSource(productionConstants, `${productionToken}\nfunction x() { return "test-df"; }`),
  /test-df/,
);
for (const symbol of [
  "MAINNET_PILOT_CLEANUP_OVERLAY",
  "isMainnetPilotOverlay",
  "PILOT_MAX_JPYDF_ROUNDING_DUST",
  "effectiveSPYieldSplit",
]) {
  assert.throws(
    () => assertProductionRollbackSource(`${productionConstants}\n${symbol}`, productionToken),
    /pilot-only symbol/,
  );
  assert.throws(
    () => assertProductionRollbackSource(productionConstants, `${productionToken}\n${symbol}`),
    /pilot-only symbol/,
  );
}
assert.doesNotThrow(() =>
  assertProductionRollbackSource(
    readFileSync(new URL("../src/Dependencies/Constants.sol", import.meta.url), "utf8"),
    readFileSync(new URL("../src/JpydfToken.sol", import.meta.url), "utf8"),
  )
);
const baseDeployEnv = { ...process.env };
delete baseDeployEnv.MAINNET_PILOT;
delete baseDeployEnv.MAINNET_CANARY;
delete baseDeployEnv.DF_MAINNET_PILOT_EXPECTED_DEPLOYER;
delete baseDeployEnv.DF_MAINNET_CANARY_EXPECTED_DEPLOYER;
delete baseDeployEnv.RPC_URL;
for (
  const [args, env, expected] of [
    [["mainnet", "--mainnet-pilot"], {}, /fresh pilot deployments are retired/],
    [["mainnet"], { MAINNET_PILOT: "true" }, /fresh pilot deployments are retired/],
    [
      ["mainnet", "--pilot-expected-deployer", "0x1000000000000000000000000000000000000001"],
      {},
      /fresh pilot deployments are retired/,
    ],
    [
      ["mainnet"],
      { DF_MAINNET_PILOT_EXPECTED_DEPLOYER: "0x1000000000000000000000000000000000000001" },
      /fresh pilot deployments are retired/,
    ],
    [["mainnet", "--mainnet-canary"], {}, /fresh --mainnet-canary deployments are retired/],
    [["mainnet"], { MAINNET_CANARY: "true" }, /fresh --mainnet-canary deployments are retired/],
    [
      ["mainnet", "--canary-expected-deployer", "0x1000000000000000000000000000000000000001"],
      {},
      /fresh --mainnet-canary deployments are retired/,
    ],
    [
      ["mainnet"],
      { DF_MAINNET_CANARY_EXPECTED_DEPLOYER: "0x1000000000000000000000000000000000000001" },
      /fresh --mainnet-canary deployments are retired/,
    ],
  ] as const
) {
  const retiredDeploy = spawnSync("./deploy", args, {
    cwd: new URL("..", import.meta.url),
    encoding: "utf8",
    env: { ...baseDeployEnv, ...env },
  });
  assert.equal(retiredDeploy.status, 1);
  assert.match(retiredDeploy.stderr, expected);
}
const productionDeploy = spawnSync("./deploy", ["mainnet"], {
  cwd: new URL("..", import.meta.url),
  encoding: "utf8",
  env: baseDeployEnv,
});
assert.equal(productionDeploy.status, 1);
assert.match(productionDeploy.stderr, /--rpc-url <RPC_URL> is required/);
assert.doesNotMatch(productionDeploy.stderr, /retired/);

const runtimeAddress = "0x1000000000000000000000000000000000000001" as `0x${string}`;
const manifest = {
  deploymentClassification: PRODUCTION_DEPLOYMENT_CLASSIFICATION,
  deploymentProfile: "production-candidate",
  deploymentId: PRODUCTION_DEPLOYMENT_ID,
  chainId: 1,
  deploymentMode: "complete",
  create2Salt: `0x${"99".repeat(32)}`,
  deployer: "0x2000000000000000000000000000000000000002",
  bridgeAdmin: "0x3000000000000000000000000000000000000003",
  jpydfToken: runtimeAddress,
};
const manifestBytes = toBytes(JSON.stringify(manifest));
const runtimeHash = `0x${"11".repeat(32)}` as `0x${string}`;
const evidence = {
  repositoryCommit: "a".repeat(40),
  manifestSha256: createHash("sha256").update(manifestBytes).digest("hex"),
  pinnedBlockNumber: 1,
  pinnedBlockHash: `0x${"22".repeat(32)}` as `0x${string}`,
  contracts: [{
    address: runtimeAddress,
    artifactPath: "unused-in-document-test.json",
    artifactRuntimeCodeHash: runtimeHash,
    runtimeCodeHash: runtimeHash,
  }],
};
assert.doesNotThrow(() => assertProductionRollbackEvidence(evidence, manifest, manifestBytes, "a".repeat(40)));
assert.throws(
  () => assertProductionRollbackEvidence({ ...evidence, contracts: [] }, manifest, manifestBytes, "a".repeat(40)),
  /mandatory production runtime evidence missing/,
);
assert.throws(
  () =>
    assertProductionRollbackEvidence(
      {
        ...evidence,
        contracts: [{ ...evidence.contracts[0], runtimeCodeHash: "0x1234" as `0x${string}` }],
      },
      manifest,
      manifestBytes,
      "a".repeat(40),
    ),
  /on-chain runtime hash.*bytes32/,
);

console.log("production rollback gate tests passed");
