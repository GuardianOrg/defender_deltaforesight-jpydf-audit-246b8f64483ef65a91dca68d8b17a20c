import { getAddress, isAddress, keccak256, toBytes } from "viem";

export const PRODUCTION_DEPLOYMENT_CLASSIFICATION = "PRODUCTION_CANDIDATE";
export const PRODUCTION_DEPLOYMENT_PROFILE = "production-candidate";
export const PRODUCTION_DEPLOYMENT_ID = "jpydf-production-candidate";
export const TEST_ONLY_DEPLOYMENT_CLASSIFICATION = "TEST_ONLY_NOT_FOR_PRODUCTION";
export const MAINNET_PILOT_DEPLOYMENT_PROFILE = "mainnet-pilot-min-debt-1000";
export const MAINNET_PILOT_DEPLOYMENT_ID = "jpydf-mainnet-test-only-min-debt-1000-2026-08";
export const MAINNET_PILOT_SALT_INPUT = "JPYDF_MAINNET_TEST_ONLY_MIN_DEBT_1000_2026_08";
export const MAINNET_PILOT_MIN_DEBT_ACK = "JPYDF_MAINNET_TEST_ONLY_MIN_DEBT_1000_NOT_FOR_PRODUCTION";
export const MAINNET_PILOT_MANIFEST_PATH =
  "pilot-artifacts/jpydf-mainnet-test-only-min-debt-1000-2026-08/deployment-manifest.json";
export const MAINNET_CANARY_DEPLOYMENT_PROFILE = "mainnet-persistent-canary-v2-min-debt-1000";
export const MAINNET_CANARY_DEPLOYMENT_ID = "jpydf-mainnet-persistent-canary-v2-2026-08";
export const MAINNET_CANARY_SALT_INPUT = "JPYDF_MAINNET_PERSISTENT_CANARY_V2_2026_08";
export const MAINNET_CANARY_MIN_DEBT_ACK = "JPYDF_MAINNET_CANARY_MIN_DEBT_1000_TEST_ONLY";
export const MAINNET_CANARY_MANIFEST_PATH =
  "canary-artifacts/jpydf-mainnet-persistent-canary-v2-2026-08/deployment-manifest.json";

export type DeploymentManifestScope = "production" | "mainnet-pilot" | "mainnet-canary" | "sepolia" | "local";

export type DeploymentManifestMetadata = {
  deploymentClassification?: unknown;
  deploymentProfile?: unknown;
  deploymentId?: unknown;
  chainId?: unknown;
  deploymentMode?: unknown;
  create2Salt?: unknown;
  deployer?: unknown;
  bridgeAdmin?: unknown;
  mainnetPilotController?: unknown;
};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const MAINNET_PILOT_CREATE2_SALT = keccak256(toBytes(MAINNET_PILOT_SALT_INPUT));
const MAINNET_CANARY_CREATE2_SALT = keccak256(toBytes(MAINNET_CANARY_SALT_INPUT));

export function parseDeploymentManifestScope(value: string | undefined): DeploymentManifestScope | undefined {
  const normalized = value?.trim().toLowerCase();
  if (!normalized) return undefined;
  if (
    normalized === "production"
    || normalized === "mainnet-pilot"
    || normalized === "mainnet-canary"
    || normalized === "sepolia"
    || normalized === "local"
  ) {
    return normalized;
  }
  throw new Error(`Unsupported deployment manifest scope: ${value}`);
}

export function inferDeploymentManifestScope(
  manifest: DeploymentManifestMetadata,
  explicitScope?: string,
): DeploymentManifestScope {
  const parsed = parseDeploymentManifestScope(explicitScope);
  if (parsed) return parsed;
  const chainId = readChainId(manifest.chainId);
  if (chainId === 1) return "production";
  if (chainId === 11_155_111) return "sepolia";
  return "local";
}

export function assertDeploymentManifestScope(
  manifest: DeploymentManifestMetadata,
  scope: DeploymentManifestScope,
): void {
  if (scope === "production") {
    assertEqual(
      "deploymentClassification",
      manifest.deploymentClassification,
      PRODUCTION_DEPLOYMENT_CLASSIFICATION,
    );
    assertEqual("deploymentProfile", manifest.deploymentProfile, PRODUCTION_DEPLOYMENT_PROFILE);
    assertEqual("deploymentId", manifest.deploymentId, PRODUCTION_DEPLOYMENT_ID);
    assertEqual("chainId", readChainId(manifest.chainId), 1);
    assertEqual("deploymentMode", manifest.deploymentMode, "complete");
    normalizeHex(manifest.create2Salt);
    const deployer = readAddress("deployer", manifest.deployer);
    const bridgeAdmin = readAddress("bridgeAdmin", manifest.bridgeAdmin);
    if (bridgeAdmin === ZERO_ADDRESS || bridgeAdmin === deployer) {
      throw new Error("production bridgeAdmin must be nonzero and differ from deployer");
    }
    if (manifest.mainnetPilotController !== undefined) {
      throw new Error("production manifest must not contain mainnetPilotController");
    }
    return;
  }

  if (scope === "mainnet-pilot") {
    assertEqual(
      "deploymentClassification",
      manifest.deploymentClassification,
      TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
    );
    assertEqual("deploymentProfile", manifest.deploymentProfile, MAINNET_PILOT_DEPLOYMENT_PROFILE);
    assertEqual("deploymentId", manifest.deploymentId, MAINNET_PILOT_DEPLOYMENT_ID);
    assertEqual("chainId", readChainId(manifest.chainId), 1);
    assertEqual("deploymentMode", manifest.deploymentMode, "complete");
    assertEqual("create2Salt", normalizeHex(manifest.create2Salt), MAINNET_PILOT_CREATE2_SALT.toLowerCase());
    const deployer = readAddress("deployer", manifest.deployer);
    const bridgeAdmin = readAddress("bridgeAdmin", manifest.bridgeAdmin);
    const controller = readAddress("mainnetPilotController", manifest.mainnetPilotController);
    if (bridgeAdmin === ZERO_ADDRESS) throw new Error("bridgeAdmin must be nonzero for mainnet pilot");
    if (bridgeAdmin === deployer) throw new Error("bridgeAdmin must differ from deployer for mainnet pilot");
    if (controller === ZERO_ADDRESS) throw new Error("mainnetPilotController must be nonzero for mainnet pilot");
    return;
  }

  if (scope === "mainnet-canary") {
    assertEqual(
      "deploymentClassification",
      manifest.deploymentClassification,
      TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
    );
    assertEqual("deploymentProfile", manifest.deploymentProfile, MAINNET_CANARY_DEPLOYMENT_PROFILE);
    assertEqual("deploymentId", manifest.deploymentId, MAINNET_CANARY_DEPLOYMENT_ID);
    assertEqual("chainId", readChainId(manifest.chainId), 1);
    assertEqual("deploymentMode", manifest.deploymentMode, "complete");
    assertEqual("create2Salt", normalizeHex(manifest.create2Salt), MAINNET_CANARY_CREATE2_SALT.toLowerCase());
    const deployer = readAddress("deployer", manifest.deployer);
    const bridgeAdmin = readAddress("bridgeAdmin", manifest.bridgeAdmin);
    if (bridgeAdmin === ZERO_ADDRESS) throw new Error("bridgeAdmin must be nonzero for mainnet canary");
    if (bridgeAdmin === deployer) throw new Error("bridgeAdmin must differ from deployer for mainnet canary");
    if (manifest.mainnetPilotController !== undefined) {
      throw new Error("mainnet canary manifest must not contain mainnetPilotController");
    }
    return;
  }

  if (scope === "sepolia") {
    assertEqual(
      "deploymentClassification",
      manifest.deploymentClassification,
      TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
    );
    assertEqual("deploymentProfile", manifest.deploymentProfile, "non-mainnet-test-only");
    assertEqual("chainId", readChainId(manifest.chainId), 11_155_111);
    assertEqual("deploymentMode", manifest.deploymentMode, "complete");
    normalizeHex(manifest.create2Salt);
    const deployer = readAddress("deployer", manifest.deployer);
    const bridgeAdmin = readAddress("bridgeAdmin", manifest.bridgeAdmin);
    if (bridgeAdmin === ZERO_ADDRESS) throw new Error("bridgeAdmin must be nonzero for Sepolia");
    if (bridgeAdmin === deployer) throw new Error("bridgeAdmin must differ from deployer for Sepolia");
    if (manifest.mainnetPilotController !== undefined) {
      throw new Error("Sepolia manifest must not contain mainnetPilotController");
    }
    return;
  }

  assertEqual(
    "deploymentClassification",
    manifest.deploymentClassification,
    TEST_ONLY_DEPLOYMENT_CLASSIFICATION,
  );
  assertEqual("deploymentProfile", manifest.deploymentProfile, "non-mainnet-test-only");
  const chainId = readChainId(manifest.chainId);
  if (chainId === 1) throw new Error("local deployment manifest scope rejects chainId 1");
}

export function assertTargetsInDeploymentManifest(
  manifest: DeploymentManifestMetadata & Record<string, unknown>,
  scope: DeploymentManifestScope,
  targets: readonly string[],
): void {
  assertDeploymentManifestScope(manifest, scope);
  const manifestAddresses = new Set<string>();
  collectCallableAddresses(manifest, manifestAddresses);
  for (const target of targets) {
    const normalized = readAddress("target", target);
    if (!manifestAddresses.has(normalized)) {
      throw new Error(`target is not present in the ${scope} deployment manifest: ${target}`);
    }
  }
}

function readChainId(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`chainId must be a positive safe integer`);
  return parsed;
}

function readAddress(label: string, value: unknown): string {
  if (typeof value !== "string" || !isAddress(value)) throw new Error(`${label} must be a 20-byte address`);
  return getAddress(value).toLowerCase();
}

function normalizeHex(value: unknown): string {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error("create2Salt must be a 32-byte hex value");
  }
  return value.toLowerCase();
}

function assertEqual(label: string, actual: unknown, expected: unknown): void {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`);
}

function collectCallableAddresses(manifest: Record<string, unknown>, addresses: Set<string>): void {
  const add = (value: unknown) => {
    if (typeof value === "string" && isAddress(value)) addresses.add(getAddress(value).toLowerCase());
  };
  for (
    const key of [
      "collateralRegistry",
      "jpydfToken",
      "hintHelpers",
      "multiTroveGetter",
      "exchangeHelpers",
      "collateralVaultLens",
      "redemptionHelper",
      "liquidationCandidateGetter",
      "debtInFrontHelper",
    ]
  ) add(manifest[key]);
  if (Array.isArray(manifest.branches)) {
    for (const branch of manifest.branches) {
      if (typeof branch === "object" && branch) for (const value of Object.values(branch)) add(value);
    }
  }
  if (Array.isArray(manifest.dfYield)) {
    for (const rawEntry of manifest.dfYield) {
      if (typeof rawEntry !== "object" || !rawEntry) continue;
      const entry = rawEntry as Record<string, unknown>;
      for (const key of ["dToken", "collateralVault", "collateralYieldZapper", "jpyUsdRateProvider"]) add(entry[key]);
      if (Array.isArray(entry.strategies)) {
        for (const rawStrategy of entry.strategies) {
          if (typeof rawStrategy === "object" && rawStrategy) add((rawStrategy as Record<string, unknown>).strategy);
        }
      }
    }
  }
}
