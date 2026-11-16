import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

import { type Address, createPublicClient, getAddress, type Hex, http, isAddress, keccak256 } from "viem";
import { mainnet } from "viem/chains";

import { assertDeploymentManifestScope, assertTargetsInDeploymentManifest } from "./deployment-manifest-policy.js";

type RollbackEvidence = {
  repositoryCommit: string;
  manifestSha256: string;
  pinnedBlockNumber: number;
  pinnedBlockHash: Hex;
  contracts: Array<{
    address: Address;
    artifactPath: string;
    artifactRuntimeCodeHash: Hex;
    runtimeCodeHash: Hex;
  }>;
};

export function assertProductionRollbackSource(constantsSource: string, tokenSource: string): void {
  requireMatch(constantsSource, /uint256 constant MIN_DEBT = 100_000e18;/, "MIN_DEBT production value");
  requireMatch(constantsSource, /uint256 constant SP_YIELD_SPLIT = 75 \* _1pct;/, "SP_YIELD_SPLIT production value");
  requireMatch(tokenSource, /string internal constant _NAME = "JPYdf Stablecoin";/, "canonical token name");
  requireMatch(tokenSource, /string internal constant _SYMBOL = "JPYdf";/, "canonical token symbol");
  requireMatch(tokenSource, /ERC20\(_NAME, _SYMBOL\)/, "canonical ERC-20 constructor identity");
  requireMatch(tokenSource, /ERC20Permit\(_NAME\)/, "canonical EIP-712 constructor identity");
  const pilotSymbols =
    /MAINNET_PILOT_CLEANUP_OVERLAY|isMainnetPilotOverlay|PILOT_MAX_JPYDF_ROUNDING_DUST|effectiveSPYieldSplit/;
  if (pilotSymbols.test(constantsSource) || pilotSymbols.test(tokenSource)) {
    throw new Error("pilot-only symbol remains in production source");
  }
  if (/test-df/.test(constantsSource) || /test-df/.test(tokenSource)) {
    throw new Error("test-df identity remains in production source");
  }
}

export function mandatoryProductionRuntimeAddresses(manifest: Record<string, unknown>): Set<string> {
  assertDeploymentManifestScope(manifest, "production");
  const addresses = new Set<string>();
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
      if (typeof branch !== "object" || !branch) continue;
      for (const value of Object.values(branch)) add(value);
    }
  }
  if (Array.isArray(manifest.dfYield)) {
    for (const rawEntry of manifest.dfYield) {
      if (typeof rawEntry !== "object" || !rawEntry) continue;
      const entry = rawEntry as Record<string, unknown>;
      for (const key of ["dToken", "collateralVault", "collateralYieldZapper", "jpyUsdRateProvider"]) add(entry[key]);
      if (Array.isArray(entry.strategies)) {
        for (const strategy of entry.strategies) {
          if (typeof strategy === "object" && strategy) add((strategy as Record<string, unknown>).strategy);
        }
      }
    }
  }
  if (addresses.size === 0) throw new Error("production manifest contains no mandatory runtime addresses");
  return addresses;
}

export function assertProductionRollbackEvidence(
  evidence: RollbackEvidence,
  manifest: Record<string, unknown>,
  manifestBytes: Uint8Array,
  repositoryCommit: string,
): void {
  assertDeploymentManifestScope(manifest, "production");
  if (evidence.repositoryCommit !== repositoryCommit.trim().toLowerCase()) {
    throw new Error("production evidence repository commit mismatch");
  }
  if (evidence.manifestSha256.toLowerCase() !== createHash("sha256").update(manifestBytes).digest("hex")) {
    throw new Error("production evidence manifest hash mismatch");
  }
  if (!Number.isSafeInteger(evidence.pinnedBlockNumber) || evidence.pinnedBlockNumber <= 0) {
    throw new Error("pinnedBlockNumber must be positive");
  }
  requireBytes32("pinnedBlockHash", evidence.pinnedBlockHash);

  const mandatory = mandatoryProductionRuntimeAddresses(manifest);
  const seen = new Set<string>();
  for (const contract of evidence.contracts) {
    const address = getAddress(contract.address).toLowerCase();
    if (seen.has(address)) throw new Error(`duplicate production runtime evidence: ${contract.address}`);
    seen.add(address);
    requireBytes32(`artifact runtime hash ${address}`, contract.artifactRuntimeCodeHash);
    requireBytes32(`on-chain runtime hash ${address}`, contract.runtimeCodeHash);
  }
  assertTargetsInDeploymentManifest(manifest, "production", [...seen]);
  for (const address of mandatory) {
    if (!seen.has(address)) throw new Error(`mandatory production runtime evidence missing: ${address}`);
  }
}

async function main() {
  const manifestPath = argument("--manifest");
  const constantsPath = argument("--constants");
  const tokenPath = argument("--token");
  const evidencePath = argument("--evidence");
  const rpcUrl = argument("--rpc-url");
  const manifestBytes = readFileSync(manifestPath);
  const manifest = JSON.parse(manifestBytes.toString("utf8")) as Record<string, unknown>;
  const evidence = JSON.parse(readFileSync(evidencePath, "utf8")) as RollbackEvidence;
  assertDeploymentManifestScope(manifest, "production");
  assertProductionRollbackSource(readFileSync(constantsPath, "utf8"), readFileSync(tokenPath, "utf8"));
  const commit = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" });
  assertProductionRollbackEvidence(evidence, manifest, manifestBytes, commit);

  const client = createPublicClient({ chain: mainnet, transport: http(rpcUrl) });
  if (await client.getChainId() !== 1) throw new Error("RPC chainId must be 1");
  const blockNumber = BigInt(evidence.pinnedBlockNumber);
  const block = await client.getBlock({ blockNumber });
  if (block.hash.toLowerCase() !== evidence.pinnedBlockHash.toLowerCase()) throw new Error("pinnedBlockHash mismatch");
  for (const contract of evidence.contracts) {
    const artifact = JSON.parse(readFileSync(contract.artifactPath, "utf8")) as {
      deployedBytecode?: {
        object?: string;
        immutableReferences?: Record<string, Array<{ start: number; length: number }>>;
      };
    };
    const artifactCode = artifact.deployedBytecode?.object;
    if (!artifactCode || !/^0x[0-9a-fA-F]+$/.test(artifactCode)) {
      throw new Error(`artifact has no linked deployed bytecode: ${contract.artifactPath}`);
    }
    if (keccak256(artifactCode as Hex) !== contract.artifactRuntimeCodeHash.toLowerCase()) {
      throw new Error(`artifact runtime hash evidence mismatch: ${contract.address}`);
    }
    const runtime = await client.getCode({ address: getAddress(contract.address), blockNumber });
    if (!runtime || keccak256(runtime) !== contract.runtimeCodeHash.toLowerCase()) {
      throw new Error(`on-chain runtime hash mismatch: ${contract.address}`);
    }
    const references = Object.values(artifact.deployedBytecode?.immutableReferences ?? {}).flat();
    if (maskImmutableReferences(artifactCode as Hex, references) !== maskImmutableReferences(runtime, references)) {
      throw new Error(`artifact/runtime bytecode mismatch outside immutable references: ${contract.address}`);
    }
  }
  console.log("production rollback source/artifact/runtime gate: PASS");
}

function argument(name: string): string {
  const index = process.argv.indexOf(name);
  if (index === -1 || !process.argv[index + 1]) throw new Error(`${name} is required`);
  return process.argv[index + 1];
}

function requireMatch(source: string, pattern: RegExp, label: string): void {
  if (!pattern.test(source)) throw new Error(`${label} is missing`);
}

function requireBytes32(label: string, value: string): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new Error(`${label} must be bytes32`);
}

function maskImmutableReferences(code: Hex, references: Array<{ start: number; length: number }>): string {
  const bytes = code.slice(2).toLowerCase().split("");
  for (const reference of references) {
    if (
      !Number.isSafeInteger(reference.start)
      || !Number.isSafeInteger(reference.length)
      || reference.start < 0
      || reference.length <= 0
      || (reference.start + reference.length) * 2 > bytes.length
    ) {
      throw new Error("artifact contains invalid immutable references");
    }
    bytes.fill("0", reference.start * 2, (reference.start + reference.length) * 2);
  }
  return bytes.join("");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
