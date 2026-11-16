import { dirname, join } from "node:path";
import { getAddress } from "viem";
import { $, chalk, echo, fs, minimist, question } from "zx";

import { assertProductionNativeEthRouteEnvironment } from "./day1-native-eth-route.js";
import {
  assertDeploymentManifestScope,
  inferDeploymentManifestScope,
  MAINNET_CANARY_DEPLOYMENT_ID,
  MAINNET_CANARY_MANIFEST_PATH,
  MAINNET_CANARY_MIN_DEBT_ACK,
} from "./deployment-manifest-policy.js";

const HELP = `
deploy - deploy the JPYdf contracts.

Usage:
  ./deploy [NETWORK_PRESET] [OPTIONS]

Arguments:
  NETWORK_PRESET  A network preset, which is a shorthand for setting certain options
                  such as the chain ID and RPC URL. Options take precedence over
                  network presets. Available presets:
                  - local: Deploy to a local network
                  - hosted-anvil: Deploy to the AWS hosted staging Anvil network
                  - mainnet: Deploy to the Ethereum mainnet


Options:
  --chain-id <CHAIN_ID>                    Chain ID to deploy to.
  --debug                                  Show debug output.
  --bridge-admin <DF_BRIDGE_ADMIN>         Bridge admin contract address for
                                           dormant bridge readiness. Required
                                           outside local.
  --deployer <DEPLOYER>                    Public address to deploy from. Private
                                           keys are prohibited.
  --account <KEYSTORE_ACCOUNT>             Foundry keystore account name.
  --aws                                    Sign with AWS KMS.
  --ledger                                 Sign with a Ledger hardware wallet
                                           (default outside local presets).
  --ledger-path <LEDGER_PATH>              HD path to use with the Ledger (only used
                                           when Ledger is the selected signer).
  --dry-run                                Don't broadcast transaction, only
                                           simulate execution.
  --etherscan-api-key <ETHERSCAN_API_KEY>  Etherscan API key to verify the contracts
                                           (required when verifying with Etherscan).
  --gas-price <GAS_PRICE>                  Max fee per gas to use in transactions.
  --gas-estimate-multiplier <PERCENT>      Forge script gas estimate multiplier.
  --help, -h                               Show this help message.
  --mode <DEPLOYMENT_MODE>                 Deploy in one of the following modes:
                                           - complete (default),
                                           - jpydf-only,
                                           - use-existing-jpydf.
  --rpc-url <RPC_URL>                      RPC URL to use.
  --resume                                 Resume a previous failed broadcast.
  --salt <SALT>                            Use keccak256(bytes(SALT)) as CREATE2
                                           salt instead of block timestamp.
  --skip-confirmation                      Run non-interactively (skip confirmation).
  --slow                                   Only send a transaction after the previous
                                           one has been confirmed.
  --trezor                                 Sign with a Trezor hardware wallet.
  --unlocked                               Used when the deployer account is unlocked
                                           in the client (i.e. no private key or
                                           Ledger device needed).
  --verify                                 Verify contracts after deployment.
  --verifier <VERIFIER>                    Verification provider to use.
                                           Possible values: etherscan, sourcify.
  --verifier-url <VERIFIER_URL>            The verifier URL, if using a custom
                                           provider.

Note: options can also be set via corresponding environment variables,
e.g. --chain-id via CHAIN_ID. Signer variables are KEYSTORE_ACCOUNT, AWS_SIGNER,
LEDGER, TREZOR, and UNLOCKED. Parameters take precedence over variables.
`;

const ANVIL_FIRST_ACCOUNT = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const HOSTED_ANVIL_CHAIN_ID = 31_338;
const MULTICALL3_ADDRESS = "0xcA11bde05977b3631167028862bE2a173976CA11";
const MAINNET_CANARY_REAL_BROADCAST_ACK = "JPYDF_MAINNET_CANARY_REAL_MAINNET_BROADCAST_SEPARATELY_APPROVED";
const MAINNET_CANARY_FIXED_ENVIRONMENT = {
  DF_JPY_USD_FEED: "0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3",
  DF_JPY_USD_STALENESS: "108000",
  DF_UNDERLYING_0: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
  DF_COLL_USD_FEED_0: "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8",
  DF_COLL_USD_STALENESS_0: "86400",
  DF_REDEMPTION_ETH_USD_FEED_0: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
  DF_REDEMPTION_ETH_USD_STALENESS_0: "7200",
  DF_REDEMPTION_STETH_ETH_FEED_0: "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",
  DF_REDEMPTION_STETH_ETH_STALENESS_0: "90000",
  DF_ZAPPER_EXPECTED_STETH_0: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
  DF_ZAPPER_LIDO_REFERRAL_0: "0x0000000000000000000000000000000000000000",
  DF_STRATEGY_KIND_0: "none",
  DF_STRATEGY_WEIGHT_BPS_0: "0",
  DF_STRATEGY_CAP_0: "0",
  DF_UNDERLYING_1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  DF_COLL_USD_FEED_1: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
  DF_COLL_USD_STALENESS_1: "172800",
  DF_STRATEGY_COUNT_1: "2",
  DF_STRATEGY_KIND_1_0: "aave",
  DF_STRATEGY_WEIGHT_BPS_1_0: "5000",
  DF_STRATEGY_CAP_1_0: "100000000",
  DF_STRATEGY_AAVE_POOL_1_0: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
  DF_STRATEGY_AAVE_ATOKEN_1_0: "0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c",
  DF_STRATEGY_KIND_1_1: "erc4626",
  DF_STRATEGY_WEIGHT_BPS_1_1: "5000",
  DF_STRATEGY_CAP_1_1: "100000000",
  DF_STRATEGY_ERC4626_VAULT_1_1: "0xdd0f28e19C1780eb6396170735D45153D261490d",
} as const;
const MULTICALL3_RUNTIME_PATHS = [
  "utils/multicall3-runtime.hex",
  "contracts/utils/multicall3-runtime.hex",
];

const argv = minimist(process.argv.slice(2), {
  alias: {
    h: "help",
  },
  // We don't explicitly declare any options as boolean, so that we may tell the difference between an option missing
  // or it being explicitly set to false
  string: [
    "debug",
    "help",
    "resume",
    "verify",
    "dry-run",
    "slow",
    "unlocked",
    "aws",
    "ledger",
    "trezor",
    "chain-id",
    "account",
    "bridge-admin",
    "deployer",
    "etherscan-api-key",
    "ledger-path",
    "mode",
    "mainnet-pilot",
    "pilot-expected-deployer",
    "salt",
    "skip-confirmation",
    "rpc-url",
    "verifier",
    "verifier-url",
    "gas-price",
    "gas-estimate-multiplier",
    "mainnet-canary",
    "canary-expected-deployer",
  ],
});

export async function main() {
  const { networkPreset, options } = await parseArgs();

  if (options.help) {
    echo`${HELP}`;
    process.exit(0);
  }
  if ("open-demo-troves" in argv) {
    throw new Error("--open-demo-troves was removed; run SeedLocalDemo after deployment to seed local demo data");
  }

  // network preset: local
  if (networkPreset === "local") {
    options.chainId ??= 31337;
    options.deployer ??= ANVIL_FIRST_ACCOUNT;
    options.rpcUrl ??= "http://127.0.0.1:8545";
    options.unlocked = options.unlocked
      || (!options.account && !options.aws && !options.ledger && !options.ledgerPath && !options.trezor);
  }

  // network preset: hosted-anvil
  if (networkPreset === "hosted-anvil") {
    options.chainId ??= HOSTED_ANVIL_CHAIN_ID;
    options.deployer ??= ANVIL_FIRST_ACCOUNT;
    options.rpcUrl ??= process.env.JPYDF_HOSTED_ANVIL_RPC_URL;
    options.unlocked = options.unlocked
      || (!options.account && !options.aws && !options.ledger && !options.ledgerPath && !options.trezor);
  }

  // network preset: mainnet
  if (networkPreset === "mainnet") {
    options.chainId ??= 1;
  }

  options.mode ??= "complete";
  options.verifier ??= "etherscan";

  if (options.mainnetPilot || options.pilotExpectedDeployer !== undefined) {
    throw new Error("fresh pilot deployments are retired; use the existing-canary operations tooling");
  }
  if (options.mainnetCanary || options.canaryExpectedDeployer !== undefined) {
    throw new Error("fresh --mainnet-canary deployments are retired; use the existing-canary operations tooling");
  }

  // handle missing options
  if (!options.chainId) {
    throw new Error("--chain-id <CHAIN_ID> is required");
  }
  if (!options.rpcUrl) {
    throw new Error("--rpc-url <RPC_URL> is required");
  }
  if (!options.deployer) {
    throw new Error("--deployer <DEPLOYER> is required");
  }
  if (options.dryRun && options.resume) {
    throw new Error("--dry-run cannot be combined with --resume");
  }
  if (
    options.mainnetCanary
    && !options.dryRun
    && !isLoopbackRpcUrl(options.rpcUrl)
    && process.env.DF_MAINNET_CANARY_REAL_BROADCAST_ACK !== MAINNET_CANARY_REAL_BROADCAST_ACK
  ) {
    throw new Error(
      "real-mainnet canary execution is blocked; use a loopback fork or set the exact "
        + "DF_MAINNET_CANARY_REAL_BROADCAST_ACK after separate approval",
    );
  }
  if (!isLocalDevChainId(options.chainId) && !options.bridgeAdmin && !options.mainnetCanary) {
    throw new Error("--bridge-admin <DF_BRIDGE_ADMIN> is required outside local/dev Anvil");
  }
  if (options.verify && options.verifier === "etherscan" && !options.etherscanApiKey) {
    throw new Error(
      "Verifying with Etherscan requires --etherscan-api-key <ETHERSCAN_API_KEY>",
    );
  }
  assertProductionNativeEthRouteEnvironment({
    chainId: options.chainId,
    mainnetTestDeployment: options.mainnetCanary,
    deploymentMode: options.mode,
  });
  const forgeArgs: string[] = [
    "script",
    "DeployLiquity2Script",
    "--chain-id",
    String(options.chainId),
    "--rpc-url",
    options.rpcUrl,
  ];

  if (!options.dryRun) {
    forgeArgs.push("--broadcast");
  }

  if (options.resume) {
    forgeArgs.push("--resume");
  }

  if (options.slow) {
    forgeArgs.push("--slow");
  }

  if (options.gasPrice) {
    forgeArgs.push("--with-gas-price");
    forgeArgs.push(options.gasPrice);
  }

  if (options.gasEstimateMultiplier) {
    forgeArgs.push("--gas-estimate-multiplier");
    forgeArgs.push(String(options.gasEstimateMultiplier));
  }

  // Etherscan API key
  if (options.etherscanApiKey) {
    forgeArgs.push("--etherscan-api-key");
    forgeArgs.push(options.etherscanApiKey);
  }

  // verify
  if (options.verify) {
    forgeArgs.push("--verify");

    // verifier
    if (options.verifier) {
      forgeArgs.push("--verifier");
      forgeArgs.push(options.verifier);
    }

    // verifier URL
    if (options.verifierUrl) {
      forgeArgs.push("--verifier-url");
      forgeArgs.push(options.verifierUrl);
    }
  }

  let deployerAddress: string;
  try {
    deployerAddress = getAddress(options.deployer);
  } catch {
    throw new Error("--deployer must be a 20-byte public address; private keys are prohibited");
  }
  if (options.mainnetCanary && getAddress(options.canaryExpectedDeployer!) !== deployerAddress) {
    throw new Error("--canary-expected-deployer must exactly match --deployer");
  }

  const selectedSigners = [options.unlocked, options.account, options.aws, options.ledger, options.trezor].filter(
    Boolean,
  );
  if (selectedSigners.length > 1) {
    throw new Error("select exactly one signer: --account, --aws, --ledger, --trezor, or --unlocked");
  }
  if (options.ledgerPath && selectedSigners.length !== 0 && !options.ledger) {
    throw new Error("--ledger-path is only valid with the default Ledger signer");
  }
  if (options.unlocked && !isLocalDevChainId(options.chainId) && !isLoopbackRpcUrl(options.rpcUrl)) {
    throw new Error("--unlocked is restricted to local/dev chains or a loopback fork RPC");
  }

  let signer = "Ledger";
  if (options.dryRun) {
    // A dry-run only simulates the script against the selected RPC. Do not
    // initialize or prompt a hardware/keystore signer for a transaction that
    // cannot be broadcast. The explicit sender keeps CREATE2 addresses and
    // ownership checks identical to the eventual signed run.
    forgeArgs.push("--sender", deployerAddress);
    signer = "simulation only (no signer accessed)";
  } else if (options.unlocked) {
    forgeArgs.push("--unlocked");
    signer = "unlocked RPC account";
  } else if (options.account) {
    forgeArgs.push("--account", options.account);
    signer = `Foundry keystore (${options.account})`;
  } else if (options.aws) {
    forgeArgs.push("--aws");
    signer = "AWS KMS";
  } else if (options.trezor) {
    forgeArgs.push("--trezor");
    signer = "Trezor";
  } else {
    forgeArgs.push("--ledger");
    if (options.ledgerPath) {
      forgeArgs.push("--hd-paths", options.ledgerPath);
    }
  }

  echo`
Deploying JPYdf contracts with the following settings:

  CHAIN_ID:               ${options.chainId}
  DEPLOYMENT_MODE:        ${options.mode}
  DEPLOYER (address):     ${deployerAddress}
  SIGNER:                 ${signer}
  BRIDGE_ADMIN:           ${
    options.mainnetCanary
      ? "inert mainnet-canary bridge admin (CREATE2)"
      : options.bridgeAdmin ?? chalk.yellow("local LocalBridgeAdmin fallback will be deployed/reused")
  }
  DEPLOYMENT_PROFILE:     ${options.mainnetCanary ? "TEST_ONLY MAINNET CANARY" : "standard"}
  SALT:                   ${options.salt ?? chalk.yellow("block.timestamp will be used !!")}
  ETHERSCAN_API_KEY:      ${options.etherscanApiKey && "(secret)"}
  LEDGER_PATH:            ${options.ledgerPath}
  RPC_URL:                ${redactUrlForDisplay(options.rpcUrl)}
  GAS_ESTIMATE_MULTIPLIER:${options.gasEstimateMultiplier ?? "forge default"}
  VERIFY:                 ${options.verify ? "yes" : "no"}
  VERIFIER:               ${options.verifier}
  VERIFIER_URL:           ${redactUrlForDisplay(options.verifierUrl)}
`;

  // User confirmation
  if (!options.skipConfirmation) {
    for (;;) {
      const answer = (await question("Does that look good? (y/N) ")).toLowerCase();

      if (answer === "y") {
        echo("");
        break;
      }

      if (answer === "" || answer === "n") {
        echo("Deployment aborted.");
        process.exit(1);
      }
    }
  }

  process.env.DEPLOYER = deployerAddress;
  process.env.DEPLOYMENT_MODE = options.mode;
  let deploymentManifestPath = "deployment-manifest.json";
  let deploymentContextPath = "deployment-context-latest.json";
  let canaryArtifactDir: string | undefined;
  if (options.mainnetCanary) {
    deploymentManifestPath = MAINNET_CANARY_MANIFEST_PATH;
    canaryArtifactDir = dirname(MAINNET_CANARY_MANIFEST_PATH);
    deploymentContextPath = join(canaryArtifactDir, "deployment-context.json");
    const canaryBroadcastDir = join(canaryArtifactDir, "broadcast");
    fs.mkdirSync(canaryArtifactDir, { recursive: true, mode: 0o700 });
    fs.chmodSync(canaryArtifactDir, 0o700);
    fs.mkdirSync(canaryBroadcastDir, { recursive: true, mode: 0o700 });
    fs.chmodSync(canaryBroadcastDir, 0o700);
    process.env.FOUNDRY_BROADCAST = canaryBroadcastDir;
    configureMainnetCanaryEnvironment(deployerAddress);
    process.env.DF_MAINNET_CANARY_MIN_DEBT_ACK = MAINNET_CANARY_MIN_DEBT_ACK;
    process.env.DF_MAINNET_CANARY_ID = MAINNET_CANARY_DEPLOYMENT_ID;
    process.env.DF_MAINNET_CANARY_EXPECTED_DEPLOYER = getAddress(options.canaryExpectedDeployer!);
    process.env.DF_DEPLOYMENT_MANIFEST = deploymentManifestPath;
    if (isLoopbackRpcUrl(options.rpcUrl)) {
      delete process.env.DF_MAINNET_CANARY_REAL_BROADCAST_ACK;
    } else if (options.dryRun) {
      // DeployLiquity2 also enforces the remote execution boundary. This
      // process-local value only lets the non-broadcast simulation cross that
      // boundary; forgeArgs deliberately contains no --broadcast and no signer.
      process.env.DF_MAINNET_CANARY_REAL_BROADCAST_ACK = MAINNET_CANARY_REAL_BROADCAST_ACK;
    }
  }
  if (isLocalDevChainId(options.chainId)) {
    process.env.DF_ENABLE_LOCAL_NATIVE_ETH_ROUTE ??= "true";
  }
  if (options.bridgeAdmin) {
    process.env.DF_BRIDGE_ADMIN = options.bridgeAdmin;
  }

  if (options.salt) {
    process.env.SALT = options.salt;
  }

  if ("CI" in process.env) {
    echo("Workaround: deleting variable 'CI' from environment");
    delete process.env.CI;
  }

  if (options.debug) {
    $.verbose = true;
  }

  // deploy
  const foundryCacheRoot = process.env.FOUNDRY_CACHE_PATH ?? "cache";
  const foundryDryRunCacheDir = join(
    foundryCacheRoot,
    "DeployLiquity2.s.sol",
    String(options.chainId),
    "dry-run",
  );
  const forgeResult = await (async () => {
    try {
      return await $(options.debug ? { stdio: "inherit" } : {})`forge ${forgeArgs}`;
    } finally {
      if (options.dryRun) fs.removeSync(foundryDryRunCacheDir);
    }
  })();
  if (canaryArtifactDir) fs.chmodSync(deploymentManifestPath, 0o600);
  if (options.dryRun && !options.debug && forgeResult.stdout.trim()) {
    echo(forgeResult.stdout.trim());
  }
  if (options.dryRun) echo(`Removed Foundry sensitive dry-run cache: ${foundryDryRunCacheDir}`);

  await ensureAnvilMulticall3({
    chainId: options.chainId,
    dryRun: options.dryRun,
    rpcUrl: options.rpcUrl,
  });

  const deploymentManifestJson = fs.readFileSync(deploymentManifestPath, "utf-8");
  const deploymentManifest = JSON.parse(deploymentManifestJson) as {
    deploymentClassification?: string;
    deploymentProfile?: string;
    deploymentId?: string;
    chainId?: number;
    deploymentMode?: string;
    create2Salt?: string;
    deployer?: string;
    jpydfToken: string;
    bridgeAdmin?: string;
    bridgeMinterCount?: number;
    proposedBridgeMinter?: string;
    launchEvidence?: {
      bridgeAdapter?: string;
      activeBridgeAdapter?: boolean;
      day1JpydfLiquidityVenue?: string;
      day1JpydfLiquidityPair?: string;
      uniswapV4RouteStatus?: string;
      uniswapV4RouteAdapter?: string;
      nonDay1JpydfLiquidityRoute?: boolean;
    };
    branches: Record<string, string>[];
    dfYield: Array<{
      collateralYieldZapper: string;
    }>;
    collateralRegistry: string;
    hintHelpers: string;
    liquidationCandidateGetter: string;
    multiTroveGetter: string;
  };

  assertDeploymentManifestScope(
    deploymentManifest,
    options.mainnetCanary ? "mainnet-canary" : inferDeploymentManifestScope(deploymentManifest),
  );

  if (options.mode === "jpydf-only") {
    echo("JpydfToken address:", deploymentManifest.jpydfToken);
    echo("Bridge admin:", deploymentManifest.bridgeAdmin);
    echo("Bridge minter count:", deploymentManifest.bridgeMinterCount ?? 0);
    echo("Proposed bridge minter:", deploymentManifest.proposedBridgeMinter);
    echo("Launch v4 route status:", deploymentManifest.launchEvidence?.uniswapV4RouteStatus ?? "n/a");
    return;
  }

  if (!Array.isArray(deploymentManifest.dfYield)) {
    throw new Error("deployment-manifest.json missing dfYield[]");
  }
  if (deploymentManifest.dfYield.length !== deploymentManifest.branches.length) {
    throw new Error("deployment-manifest.json dfYield.length does not match branches.length");
  }

  const protocolContracts = {
    JpydfToken: deploymentManifest.jpydfToken,
    BridgeAdmin: deploymentManifest.bridgeAdmin ?? "n/a",
    CollateralRegistry: deploymentManifest.collateralRegistry,
    HintHelpers: deploymentManifest.hintHelpers,
    LiquidationCandidateGetter: deploymentManifest.liquidationCandidateGetter,
    MultiTroveGetter: deploymentManifest.multiTroveGetter,
    WETHTester: deploymentManifest.branches[0].collToken,
  };

  const collateralContracts = deploymentManifest.branches.map((branch, index) => ({
    activePool: branch.activePool,
    addressesRegistry: branch.addressesRegistry,
    borrowerOperations: branch.borrowerOperations,
    collSurplusPool: branch.collSurplusPool,
    collToken: branch.collToken,
    collateralYieldZapper: deploymentManifest.dfYield[index].collateralYieldZapper,
    defaultPool: branch.defaultPool,
    gasPool: branch.gasPool,
    interestRouter: branch.interestRouter,
    metadataNFT: branch.metadataNFT,
    priceFeed: branch.priceFeed,
    sortedTroves: branch.sortedTroves,
    stabilityPool: branch.stabilityPool,
    troveManager: branch.troveManager,
    troveNFT: branch.troveNFT,
  }));

  if (deploymentManifest.launchEvidence) {
    echo("Launch bridge adapter:", deploymentManifest.launchEvidence.bridgeAdapter ?? "n/a");
    echo("Launch v4 route status:", deploymentManifest.launchEvidence.uniswapV4RouteStatus ?? "n/a");
    echo("Launch v4 route adapter:", deploymentManifest.launchEvidence.uniswapV4RouteAdapter ?? "n/a");
  }

  // write env file
  await fs.writeJson(deploymentContextPath, {
    options: redactDeployOptionsForArtifact(options),
    collateralContracts,
    protocolContracts,
  });
  if (canaryArtifactDir) fs.chmodSync(deploymentContextPath, 0o600);

  // format deployed contracts
  const longestContractName = Math.max(
    ...Object.keys(protocolContracts).map((name) => name.length),
    ...collateralContracts.flatMap((contracts) => Object.keys(contracts).map((name) => name.length)),
  );

  const formatContracts = (contracts: Array<[string, string | undefined]>) => (
    contracts.map(([name, address]) => {
      name = name[0].toUpperCase() + name.slice(1);
      return `  ${name.padEnd(longestContractName)}  ${address ?? "n/a"}`;
    }).join("\n")
  );

  echo("Protocol contracts:");
  echo("");
  echo(formatContracts(Object.entries(protocolContracts)));
  echo("");
  echo(
    collateralContracts.map((collateral, index) => (
      `Collateral ${index + 1} contracts:\n\n${formatContracts(Object.entries(collateral))}`
    )).join("\n\n"),
  );
  echo("");
  echo("Deployment complete.");
  echo("");
}

function configureMainnetCanaryEnvironment(deployerAddress: string) {
  delete process.env.DF_BRIDGE_ADMIN;
  delete process.env.DF_STRATEGY_COUNT_0;

  process.env.DF_ENABLE_MAINNET_DTOKEN_WIRING = "true";
  process.env.DF_TREASURY = deployerAddress;
  process.env.DF_INTEREST_ROUTER_RECIPIENT = deployerAddress;
  process.env.DF_INTEREST_ROUTER_OWNER = deployerAddress;
  Object.assign(process.env, MAINNET_CANARY_FIXED_ENVIRONMENT);
}

function safeParseInt(value: string) {
  const parsed = parseInt(value, 10);
  return isNaN(parsed) ? undefined : parsed;
}

function isLocalDevChainId(chainId: number): boolean {
  return chainId === 31337 || chainId === HOSTED_ANVIL_CHAIN_ID;
}

function isLoopbackRpcUrl(value: string): boolean {
  try {
    return ["localhost", "127.0.0.1", "::1", "[::1]"].includes(new URL(value).hostname);
  } catch {
    return false;
  }
}

function redactDeployOptionsForArtifact(options: Record<string, unknown>) {
  const { deployer, etherscanApiKey, rpcUrl, verifierUrl, ...safeOptions } = options;
  void deployer;

  return {
    ...safeOptions,
    etherscanApiKey: etherscanApiKey ? "[redacted]" : undefined,
    rpcUrl: redactUrlForDisplay(rpcUrl),
    verifierUrl: redactUrlForDisplay(verifierUrl),
  };
}

function redactUrlForDisplay(value: unknown) {
  if (typeof value !== "string" || value.length === 0) {
    return value;
  }

  try {
    const url = new URL(value);
    if (isLoopbackRpcUrl(value)) {
      return value;
    }
    return `${url.protocol}//${url.host}/[redacted]`;
  } catch {
    return "[redacted]";
  }
}

async function ensureAnvilMulticall3({
  chainId,
  dryRun,
  rpcUrl,
}: {
  chainId: number;
  dryRun: boolean;
  rpcUrl: string;
}) {
  if (dryRun || !isLocalDevChainId(chainId)) {
    return;
  }

  const runtimePath = MULTICALL3_RUNTIME_PATHS.find((path) => fs.existsSync(path));
  if (!runtimePath) {
    throw new Error("utils/multicall3-runtime.hex is missing");
  }

  const runtime = fs.readFileSync(runtimePath, "utf-8").trim();
  if (!runtime.startsWith("0x") || runtime.length < 100) {
    throw new Error(`${runtimePath} is malformed`);
  }

  const rpc = async (method: string, params: unknown[]) => {
    const response = await fetch(rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    const payload = await response.json() as { error?: { message?: string }; result?: unknown };
    if (!response.ok || payload.error) {
      throw new Error(payload.error?.message ?? `JSON-RPC ${method} failed with HTTP ${response.status}`);
    }
    return payload.result;
  };

  const currentCode = String(await rpc("eth_getCode", [MULTICALL3_ADDRESS, "latest"]) ?? "");
  if (currentCode.length > 100) {
    echo(`Multicall3 already present at ${MULTICALL3_ADDRESS}.`);
    return;
  }

  echo(`Injecting Multicall3 at ${MULTICALL3_ADDRESS} for Anvil frontend reads...`);
  await rpc("anvil_setCode", [MULTICALL3_ADDRESS, runtime]);

  const injectedCode = String(await rpc("eth_getCode", [MULTICALL3_ADDRESS, "latest"]) ?? "");
  if (injectedCode.length <= 100) {
    throw new Error("Multicall3 injection failed");
  }
}

function parseBoolValue(value: string): boolean {
  return value !== "false"
    && value !== "no"
    && value !== "0";
}

// Passing an empty string for a bool parameter through the environment should count as not passing the parameter at all
function parseBoolEnv(value: string | undefined): boolean | undefined {
  if (value === undefined || value === "") return undefined;
  return parseBoolValue(value);
}

// Passing a bool option without an explicit value (e.g. `--debug`) should count as true
// In this case, value will be an empty string
function parseBoolOption(value: string | undefined): boolean | undefined {
  if (value == undefined) return undefined;
  return value === "" || parseBoolValue(value);
}

function parseBool(optionValue: string | undefined, envValue?: string | undefined): boolean {
  return parseBoolOption(optionValue)
    ?? parseBoolEnv(envValue)
    ?? false;
}

async function parseArgs() {
  const options = {
    account: argv.account,
    aws: argv.aws,
    chainId: safeParseInt(argv["chain-id"]),
    bridgeAdmin: argv["bridge-admin"],
    debug: argv["debug"],
    deployer: argv["deployer"],
    etherscanApiKey: argv["etherscan-api-key"],
    help: argv["help"],
    ledgerPath: argv["ledger-path"],
    ledger: argv.ledger,
    mainnetPilot: argv["mainnet-pilot"],
    pilotExpectedDeployer: argv["pilot-expected-deployer"],
    mainnetCanary: argv["mainnet-canary"],
    canaryExpectedDeployer: argv["canary-expected-deployer"],
    mode: argv["mode"],
    salt: argv["salt"],
    rpcUrl: argv["rpc-url"],
    resume: argv["resume"],
    dryRun: argv["dry-run"],
    skipConfirmation: argv["skip-confirmation"],
    slow: argv["slow"],
    trezor: argv.trezor,
    unlocked: argv["unlocked"],
    verify: argv["verify"],
    verifier: argv["verifier"],
    verifierUrl: argv["verifier-url"],
    gasPrice: argv["gas-price"],
    gasEstimateMultiplier: safeParseInt(argv["gas-estimate-multiplier"]),
  };

  const [networkPreset] = argv._;

  options.chainId ??= safeParseInt(process.env.CHAIN_ID ?? "");
  options.account ??= process.env.KEYSTORE_ACCOUNT;
  options.aws = parseBool(options.aws, process.env.AWS_SIGNER);
  options.bridgeAdmin ??= process.env.DF_BRIDGE_ADMIN;
  options.debug = parseBool(options.debug, process.env.DEBUG);
  options.deployer ??= process.env.DEPLOYER;
  options.dryRun = parseBool(options.dryRun, process.env.DRY_RUN);
  options.etherscanApiKey ??= process.env.ETHERSCAN_API_KEY;
  options.help = parseBool(options.help);
  options.ledgerPath ??= process.env.LEDGER_PATH;
  options.ledger = parseBool(options.ledger, process.env.LEDGER);
  options.mainnetPilot = parseBool(options.mainnetPilot, process.env.MAINNET_PILOT);
  options.pilotExpectedDeployer ??= process.env.DF_MAINNET_PILOT_EXPECTED_DEPLOYER;
  options.mainnetCanary = parseBool(options.mainnetCanary, process.env.MAINNET_CANARY);
  options.canaryExpectedDeployer ??= process.env.DF_MAINNET_CANARY_EXPECTED_DEPLOYER;
  options.mode ??= process.env.DEPLOYMENT_MODE;
  options.rpcUrl ??= process.env.RPC_URL;
  options.resume = parseBool(options.resume, process.env.RESUME);
  options.salt ??= process.env.SALT;
  options.skipConfirmation = parseBool(options.skipConfirmation, process.env.SKIP_CONFIRMATION);
  options.slow = parseBool(options.slow, process.env.SLOW);
  options.trezor = parseBool(options.trezor, process.env.TREZOR);
  options.unlocked = parseBool(options.unlocked, process.env.UNLOCKED);
  options.verify = parseBool(options.verify, process.env.VERIFY);
  options.verifier ??= process.env.VERIFIER;
  options.verifierUrl ??= process.env.VERIFIER_URL;
  options.gasEstimateMultiplier ??= safeParseInt(process.env.GAS_ESTIMATE_MULTIPLIER ?? "");

  return { options, networkPreset };
}
