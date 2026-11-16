import assert from "node:assert/strict";

import { getAddress, keccak256, toBytes } from "viem";

import {
  assertDeploymentManifestScope,
  assertTargetsInDeploymentManifest,
  inferDeploymentManifestScope,
  MAINNET_CANARY_DEPLOYMENT_ID,
  MAINNET_CANARY_DEPLOYMENT_PROFILE,
  MAINNET_CANARY_SALT_INPUT,
  MAINNET_PILOT_DEPLOYMENT_ID,
  MAINNET_PILOT_DEPLOYMENT_PROFILE,
  MAINNET_PILOT_SALT_INPUT,
  PRODUCTION_DEPLOYMENT_CLASSIFICATION,
  PRODUCTION_DEPLOYMENT_ID,
  TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
} from "./deployment-manifest-policy.js";

const deployer = getAddress("0x1000000000000000000000000000000000000001");
const bridgeAdmin = getAddress("0x2000000000000000000000000000000000000002");
const mainnetPilotController = getAddress("0x3000000000000000000000000000000000000003");
const unknownTarget = getAddress("0x4000000000000000000000000000000000000004");

const productionManifest = {
  deploymentClassification: PRODUCTION_DEPLOYMENT_CLASSIFICATION,
  deploymentProfile: "production-candidate",
  deploymentId: PRODUCTION_DEPLOYMENT_ID,
  chainId: 1,
  deploymentMode: "complete",
  create2Salt: `0x${"11".repeat(32)}`,
  deployer,
  bridgeAdmin,
};

const pilotManifest = {
  deploymentClassification: TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
  deploymentProfile: MAINNET_PILOT_DEPLOYMENT_PROFILE,
  deploymentId: MAINNET_PILOT_DEPLOYMENT_ID,
  chainId: 1,
  deploymentMode: "complete",
  create2Salt: keccak256(toBytes(MAINNET_PILOT_SALT_INPUT)),
  deployer,
  bridgeAdmin,
  mainnetPilotController,
};

const canaryManifest = {
  deploymentClassification: TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
  deploymentProfile: MAINNET_CANARY_DEPLOYMENT_PROFILE,
  deploymentId: MAINNET_CANARY_DEPLOYMENT_ID,
  chainId: 1,
  deploymentMode: "complete",
  create2Salt: keccak256(toBytes(MAINNET_CANARY_SALT_INPUT)),
  deployer,
  bridgeAdmin,
};

const localManifest = {
  deploymentClassification: TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
  deploymentProfile: "non-mainnet-test-only",
  deploymentId: "local-31337",
  chainId: 31_337,
  deploymentMode: "complete",
  create2Salt: `0x${"22".repeat(32)}`,
  deployer,
  bridgeAdmin,
};
const sepoliaManifest = {
  deploymentClassification: TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
  deploymentProfile: "non-mainnet-test-only",
  deploymentId: "jpydf-sepolia-staging-2026-08-24",
  chainId: 11_155_111,
  deploymentMode: "complete",
  create2Salt: `0x${"33".repeat(32)}`,
  deployer,
  bridgeAdmin,
};

assert.doesNotThrow(() => assertDeploymentManifestScope(productionManifest, "production"));
assert.doesNotThrow(() => assertDeploymentManifestScope(pilotManifest, "mainnet-pilot"));
assert.doesNotThrow(() => assertDeploymentManifestScope(canaryManifest, "mainnet-canary"));
assert.doesNotThrow(() => assertDeploymentManifestScope(sepoliaManifest, "sepolia"));
assert.doesNotThrow(() => assertDeploymentManifestScope(localManifest, "local"));

assert.throws(
  () => assertDeploymentManifestScope(pilotManifest, "production"),
  /deploymentClassification/,
);
assert.throws(
  () => assertDeploymentManifestScope(productionManifest, "mainnet-pilot"),
  /deploymentClassification/,
);
assert.throws(
  () => assertDeploymentManifestScope(canaryManifest, "production"),
  /deploymentClassification/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...canaryManifest, mainnetPilotController }, "mainnet-canary"),
  /must not contain mainnetPilotController/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...canaryManifest, create2Salt: `0x${"00".repeat(32)}` }, "mainnet-canary"),
  /create2Salt/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...pilotManifest, bridgeAdmin: deployer }, "mainnet-pilot"),
  /bridgeAdmin must differ from deployer/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...pilotManifest, create2Salt: `0x${"00".repeat(32)}` }, "mainnet-pilot"),
  /create2Salt/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...pilotManifest, mainnetPilotController: undefined }, "mainnet-pilot"),
  /mainnetPilotController/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...productionManifest, mainnetPilotController }, "production"),
  /must not contain mainnetPilotController/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...productionManifest, deploymentId: "production-candidate-1" }, "production"),
  /deploymentId/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...sepoliaManifest, bridgeAdmin: deployer }, "sepolia"),
  /bridgeAdmin must differ from deployer/,
);
assert.throws(
  () => assertDeploymentManifestScope({ ...sepoliaManifest, chainId: 31_337 }, "sepolia"),
  /chainId/,
);

assert.equal(inferDeploymentManifestScope(productionManifest), "production");
assert.equal(inferDeploymentManifestScope(pilotManifest), "production");
assert.equal(inferDeploymentManifestScope(pilotManifest, "mainnet-pilot"), "mainnet-pilot");
assert.equal(inferDeploymentManifestScope(canaryManifest, "mainnet-canary"), "mainnet-canary");
assert.equal(inferDeploymentManifestScope(sepoliaManifest), "sepolia");
assert.equal(inferDeploymentManifestScope(localManifest), "local");

assert.doesNotThrow(() =>
  assertTargetsInDeploymentManifest(
    { ...productionManifest, branches: [{ dToken: mainnetPilotController }] },
    "production",
    [mainnetPilotController],
  )
);
assert.throws(
  () =>
    assertTargetsInDeploymentManifest(
      { ...productionManifest, branches: [{ dToken: mainnetPilotController }] },
      "production",
      [unknownTarget],
    ),
  /target is not present/,
);
assert.throws(
  () =>
    assertTargetsInDeploymentManifest(
      { ...productionManifest, metadata: { approver: unknownTarget } },
      "production",
      [unknownTarget],
    ),
  /target is not present/,
);
assert.throws(
  () =>
    assertTargetsInDeploymentManifest(
      { ...canaryManifest, branches: [{ dToken: mainnetPilotController }] },
      "production",
      [mainnetPilotController],
    ),
  /deploymentClassification/,
);

console.log("deployment manifest scope policy tests passed");
