import type { Address } from "viem";
import { getAddress, isAddress, zeroAddress } from "viem";

import ownerManifest from "../../config/day1-branch-manifest.json";

type NativeEthRoute = {
  expectedStEth: Address;
  lidoReferral: Address;
};

type ProductionEnvironment = {
  chainId: number;
  mainnetTestDeployment: boolean;
  deploymentMode: string;
  env?: NodeJS.ProcessEnv;
};

function normalizeManifestAddress(label: string, value: unknown): Address {
  if (typeof value !== "string" || !isAddress(value)) {
    throw new Error(`${label} must be a 20-byte address in config/day1-branch-manifest.json`);
  }
  const normalized = getAddress(value);
  if (normalized !== value) {
    throw new Error(`${label} must use its EIP-55 checksum in config/day1-branch-manifest.json`);
  }
  if (normalized === zeroAddress) {
    throw new Error(`${label} must not be the zero address in config/day1-branch-manifest.json`);
  }
  return normalized;
}

function loadDay1NativeEthRoute(): NativeEthRoute {
  const branches = ownerManifest.branches;
  const branchZero = branches.find((branch) => branch.index === 0);
  if (!branchZero?.nativeEthRoute) {
    throw new Error("branch 0 nativeEthRoute is missing from config/day1-branch-manifest.json");
  }
  for (const branch of branches) {
    if (branch.index !== 0 && branch.nativeEthRoute !== null) {
      throw new Error(`branch ${branch.index} nativeEthRoute must be null in config/day1-branch-manifest.json`);
    }
  }
  return {
    expectedStEth: normalizeManifestAddress(
      "branches[0].nativeEthRoute.expectedStEth",
      branchZero.nativeEthRoute.expectedStEth,
    ),
    lidoReferral: normalizeManifestAddress(
      "branches[0].nativeEthRoute.lidoReferral",
      branchZero.nativeEthRoute.lidoReferral,
    ),
  };
}

export const DAY1_NATIVE_ETH_ROUTE = loadDay1NativeEthRoute();

export function assertProductionNativeEthRouteEnvironment({
  chainId,
  mainnetTestDeployment,
  deploymentMode,
  env = process.env,
}: ProductionEnvironment): void {
  if (chainId !== 1 || mainnetTestDeployment || deploymentMode === "jpydf-only") return;

  const required = [
    ["DF_ZAPPER_EXPECTED_STETH_0", DAY1_NATIVE_ETH_ROUTE.expectedStEth],
    ["DF_ZAPPER_LIDO_REFERRAL_0", DAY1_NATIVE_ETH_ROUTE.lidoReferral],
  ] as const;

  for (const [name, expected] of required) {
    const actual = env[name];
    if (!actual || !isAddress(actual) || getAddress(actual) !== expected) {
      throw new Error(
        `${name} must match the Day-1 owner manifest value ${expected} for a production mainnet deployment`,
      );
    }
  }
}
