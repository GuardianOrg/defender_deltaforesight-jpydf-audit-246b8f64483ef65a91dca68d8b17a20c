// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {DToken} from "src/DToken.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {ICollateralVault} from "src/Interfaces/ICollateralVault.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {IStabilityPool} from "src/Interfaces/IStabilityPool.sol";
import {IStrategy} from "src/Interfaces/IStrategy.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {IWETH} from "src/Interfaces/IWETH.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";

interface ILocalMintableToken {
    function mint(address account, uint256 amount) external;
}

interface IReviewCollateralVault is ICollateralVault {
    function withdrawDelay() external view returns (uint256);
}

/// @dev Builds the persistent frontend review state. This profile intentionally differs
///      from SeedLocalDemo: only Day-1 public branches have supply, debt, and SP deposits.
///      Run it only against a fresh deployment; destructive scenario tests belong on the
///      full integration profile or inside an Anvil snapshot that is reverted afterward.
contract SeedFrontendDay1Review is Script {
    struct BranchRefs {
        IBorrowerOperations borrowerOperations;
        IStabilityPool stabilityPool;
        ITroveManager troveManager;
        DToken dToken;
        IReviewCollateralVault vault;
        IERC20Metadata underlying;
    }

    struct TroveSeed {
        uint256 branch;
        uint256 collDToken;
        uint256 debtJpy;
    }

    uint256 constant ACTIVE_YIELD_BRANCHES = 5;
    uint256 constant BPS_DENOMINATOR = 10_000;
    uint256 constant GAS_COMP = 0.0375 ether;
    uint256 constant MAX_SEED_DEBT_BPS = 10_010; // requested debt plus at most 0.1% upfront fee
    uint256 constant REVIEW_RATE = 2e16;
    uint256 constant SYNC_STRATEGY_WITHDRAW_DELAY = 0;

    // Demo-oracle token units corresponding to the Day-1 nominal exposure limits.
    // dwstETH demo price = stETH/USD demo x stEthPerToken (1.2) / JPY rate
    // = JPY 720,000.7200007 per wstETH, so the same token-unit cap now maps to
    // ~JPY 42M nominal; dUSDC: JPY 100M / JPY 150.00015000015.
    uint256 constant DWSTETH_CAP = 58.333275 ether;
    uint256 constant DUSDC_CAP = 666_666e18;

    uint256 constant DWSTETH_BOOTSTRAP_COLL = 12.05127 ether;
    uint256 constant DWSTETH_BOOTSTRAP_DEBT = 4_700_000e18;
    uint256 constant DUSDC_BOOTSTRAP_COLL = 618_488.2704e18;
    uint256 constant DUSDC_BOOTSTRAP_DEBT = 69_580_000e18;
    uint256 constant DWSTETH_SP_SEED = 15_950_000e18;
    uint256 constant DUSDC_SP_SEED = 8_330_000e18;
    uint256 constant EXPECTED_LP_JPYDF_BALANCE = 50_000_000e18;

    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant BOOTSTRAP_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    IJpydfToken jpydfToken;
    IWETH weth; // protocol-level WETH (gas compensation), NOT the branch-0 underlying
    BranchRefs[ACTIVE_YIELD_BRANCHES] branches;

    function run() external {
        ScriptSecurityPolicy.requireLocalChain(block.chainid);
        uint256 deployerKey = vm.envUint("DEPLOYER");
        require(deployerKey == DEPLOYER_KEY, "Day1 review: expected hosted/local Anvil deployer");

        _loadDeployment();
        _requireFreshDeployment();
        _configureDay1Branches(deployerKey);
        _fundBootstrapAccount(deployerKey);

        _openTrove(TroveSeed(0, DWSTETH_BOOTSTRAP_COLL, DWSTETH_BOOTSTRAP_DEBT));
        _openTrove(TroveSeed(1, DUSDC_BOOTSTRAP_COLL, DUSDC_BOOTSTRAP_DEBT));
        _seedStabilityPools();
        _allocateActiveVaults(deployerKey);
        _verifyReviewState();

        console2.log("Frontend Day-1 review seed complete.");
    }

    function _loadDeployment() internal {
        string memory manifest = vm.readFile("deployment-manifest.json");
        jpydfToken = IJpydfToken(vm.parseJsonAddress(manifest, ".jpydfToken"));
        weth = IWETH(vm.parseJsonAddress(manifest, ".weth"));

        for (uint256 i = 0; i < ACTIVE_YIELD_BRANCHES; ++i) {
            string memory bi = vm.toString(i);
            branches[i] = BranchRefs({
                borrowerOperations: IBorrowerOperations(
                    vm.parseJsonAddress(manifest, string.concat(".branches[", bi, "].borrowerOperations"))
                ),
                stabilityPool: IStabilityPool(
                    vm.parseJsonAddress(manifest, string.concat(".branches[", bi, "].stabilityPool"))
                ),
                troveManager: ITroveManager(
                    vm.parseJsonAddress(manifest, string.concat(".branches[", bi, "].troveManager"))
                ),
                dToken: DToken(vm.parseJsonAddress(manifest, string.concat(".branches[", bi, "].collToken"))),
                vault: IReviewCollateralVault(
                        vm.parseJsonAddress(manifest, string.concat(".dfYield[", bi, "].collateralVault"))
                    ),
                underlying: IERC20Metadata(
                    vm.parseJsonAddress(manifest, string.concat(".dfYield[", bi, "].underlying"))
                )
            });

            if (i < 2) _requireAaveOnlyReviewStrategy(manifest, bi, i);
        }
    }

    function _requireAaveOnlyReviewStrategy(string memory manifest, string memory branchIndex, uint256 i)
        internal
        view
    {
        require(branches[i].vault.getStrategiesCount() == 1, "Day1 review: expected one sync strategy");
        IStrategy configuredStrategy = branches[i].vault.strategies(0);
        address manifestStrategy =
            vm.parseJsonAddress(manifest, string.concat(".dfYield[", branchIndex, "].strategies[0].strategy"));
        string memory strategyKind =
            vm.parseJsonString(manifest, string.concat(".dfYield[", branchIndex, "].strategies[0].strategyKind"));
        require(address(configuredStrategy) == manifestStrategy, "Day1 review: strategy manifest mismatch");
        require(keccak256(bytes(strategyKind)) == keccak256("aave"), "Day1 review: expected Aave strategy");
    }

    function _requireFreshDeployment() internal view {
        require(jpydfToken.totalSupply() == 0, "Day1 review: JPYdf supply already exists");
        for (uint256 i = 0; i < ACTIVE_YIELD_BRANCHES; ++i) {
            require(branches[i].troveManager.getEntireBranchDebt() == 0, "Day1 review: branch debt already exists");
            require(branches[i].troveManager.getTroveIdsCount() == 0, "Day1 review: branch troves already exist");
            require(branches[i].stabilityPool.getTotalJpydfDeposits() == 0, "Day1 review: SP deposit already exists");
            require(branches[i].dToken.totalSupply() == 0, "Day1 review: dToken supply already exists");
        }
    }

    function _configureDay1Branches(uint256 deployerKey) internal {
        uint256[ACTIVE_YIELD_BRANCHES] memory caps = [DWSTETH_CAP, DUSDC_CAP, uint256(0), uint256(0), uint256(0)];
        uint256[ACTIVE_YIELD_BRANCHES] memory maxMoves = [DWSTETH_CAP, 666_666e6, uint256(0), uint256(0), uint256(0)];
        uint256[ACTIVE_YIELD_BRANCHES] memory bufferTargets = [uint256(1200), 333, 333, 938, 333];
        uint256[ACTIVE_YIELD_BRANCHES] memory withdrawDelays =
            [SYNC_STRATEGY_WITHDRAW_DELAY, SYNC_STRATEGY_WITHDRAW_DELAY, uint256(3 days), 10 days, 3 days];

        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < ACTIVE_YIELD_BRANCHES; ++i) {
            require(branches[i].dToken.owner() == vm.addr(deployerKey), "Day1 review: deployer is not dToken owner");
            branches[i].dToken.setCap(caps[i]);
            branches[i].vault.setBufferConfig(bufferTargets[i], 0);
            branches[i].vault.setWithdrawDelay(withdrawDelays[i]);
            branches[i].vault.setAllocatorConfig(maxMoves[i], 30 minutes);
        }
        vm.stopBroadcast();
    }

    function _fundBootstrapAccount(uint256 deployerKey) internal {
        address bootstrap = vm.addr(BOOTSTRAP_KEY);

        // Gas compensation comes from the protocol WETH; branch-0 collateral is the
        // local wstETH faucet minted by its owner (= deployer).
        vm.startBroadcast(BOOTSTRAP_KEY);
        weth.deposit{value: 1 ether}();
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        ILocalMintableToken(address(branches[0].underlying)).mint(bootstrap, 13e18);
        ILocalMintableToken(address(branches[1].underlying)).mint(bootstrap, 620_000e6);
        vm.stopBroadcast();
    }

    function _openTrove(TroveSeed memory seed) internal {
        BranchRefs memory branch = branches[seed.branch];
        uint256 decimals = branch.underlying.decimals();
        uint256 underlyingAmount = seed.collDToken / 10 ** (18 - decimals);
        address bootstrap = vm.addr(BOOTSTRAP_KEY);

        vm.startBroadcast(BOOTSTRAP_KEY);
        branch.underlying.approve(address(branch.vault), underlyingAmount);
        branch.vault.deposit(underlyingAmount);
        IERC20Metadata(address(weth)).approve(address(branch.borrowerOperations), GAS_COMP);
        branch.dToken.approve(address(branch.borrowerOperations), seed.collDToken);
        branch.borrowerOperations
            .openTrove(
                bootstrap,
                0,
                seed.collDToken,
                seed.debtJpy,
                0,
                0,
                REVIEW_RATE,
                type(uint256).max,
                address(0),
                address(0),
                address(0)
            );
        vm.stopBroadcast();
    }

    function _seedStabilityPools() internal {
        vm.startBroadcast(BOOTSTRAP_KEY);
        branches[0].stabilityPool.provideToSP(DWSTETH_SP_SEED, false);
        branches[1].stabilityPool.provideToSP(DUSDC_SP_SEED, false);
        vm.stopBroadcast();
    }

    function _allocateActiveVaults(uint256 deployerKey) internal {
        vm.startBroadcast(deployerKey);
        branches[0].vault.allocate();
        branches[1].vault.allocate();
        vm.stopBroadcast();
    }

    function _verifyReviewState() internal view {
        require(branches[0].dToken.cap() == DWSTETH_CAP, "Day1 review: dwstETH cap mismatch");
        require(branches[1].dToken.cap() == DUSDC_CAP, "Day1 review: dUSDC cap mismatch");
        require(branches[0].dToken.totalSupply() == DWSTETH_BOOTSTRAP_COLL, "Day1 review: dwstETH supply mismatch");
        require(branches[1].dToken.totalSupply() == DUSDC_BOOTSTRAP_COLL, "Day1 review: dUSDC supply mismatch");
        require(
            branches[0].troveManager.getEntireBranchColl() == DWSTETH_BOOTSTRAP_COLL,
            "Day1 review: dwstETH collateral mismatch"
        );
        require(
            branches[1].troveManager.getEntireBranchColl() == DUSDC_BOOTSTRAP_COLL,
            "Day1 review: dUSDC collateral mismatch"
        );
        require(
            branches[0].troveManager.getEntireBranchDebt() >= DWSTETH_BOOTSTRAP_DEBT,
            "Day1 review: dwstETH debt below plan"
        );
        require(
            branches[1].troveManager.getEntireBranchDebt() >= DUSDC_BOOTSTRAP_DEBT, "Day1 review: dUSDC debt below plan"
        );
        require(
            branches[0].troveManager.getEntireBranchDebt()
                <= DWSTETH_BOOTSTRAP_DEBT * MAX_SEED_DEBT_BPS / BPS_DENOMINATOR,
            "Day1 review: dwstETH debt above plan"
        );
        require(
            branches[1].troveManager.getEntireBranchDebt()
                <= DUSDC_BOOTSTRAP_DEBT * MAX_SEED_DEBT_BPS / BPS_DENOMINATOR,
            "Day1 review: dUSDC debt above plan"
        );
        require(branches[0].troveManager.getTroveIdsCount() == 1, "Day1 review: dwstETH trove count mismatch");
        require(branches[1].troveManager.getTroveIdsCount() == 1, "Day1 review: dUSDC trove count mismatch");
        require(branches[0].vault.bufferTargetBps() == 1200, "Day1 review: dwstETH buffer target mismatch");
        require(branches[1].vault.bufferTargetBps() == 333, "Day1 review: dUSDC buffer target mismatch");
        require(
            branches[0].vault.withdrawDelay() == SYNC_STRATEGY_WITHDRAW_DELAY,
            "Day1 review: dwstETH withdraw delay mismatch"
        );
        require(
            branches[1].vault.withdrawDelay() == SYNC_STRATEGY_WITHDRAW_DELAY,
            "Day1 review: dUSDC withdraw delay mismatch"
        );
        require(
            branches[0].stabilityPool.getTotalJpydfDeposits() == DWSTETH_SP_SEED, "Day1 review: dwstETH SP mismatch"
        );
        require(branches[1].stabilityPool.getTotalJpydfDeposits() == DUSDC_SP_SEED, "Day1 review: dUSDC SP mismatch");

        for (uint256 i = 2; i < ACTIVE_YIELD_BRANCHES; ++i) {
            require(branches[i].dToken.cap() == 0, "Day1 review: dormant cap is not zero");
            require(branches[i].dToken.totalSupply() == 0, "Day1 review: dormant supply is not zero");
            require(branches[i].troveManager.getEntireBranchDebt() == 0, "Day1 review: dormant debt is not zero");
            require(branches[i].stabilityPool.getTotalJpydfDeposits() == 0, "Day1 review: dormant SP is not zero");
        }

        require(
            jpydfToken.balanceOf(vm.addr(BOOTSTRAP_KEY)) == EXPECTED_LP_JPYDF_BALANCE,
            "Day1 review: bootstrap LP balance mismatch"
        );
    }
}
