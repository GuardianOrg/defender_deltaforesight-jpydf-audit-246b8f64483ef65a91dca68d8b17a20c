// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/CollateralVault.sol";
import "src/CollateralVaultLens.sol";
import "../src/DToken.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/IStrategy.sol";
import "../src/Strategies/MorphoV2Strategy.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockMorphoV2Vault.sol";

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/// @notice Mirrors ExternalAuditGas01BackingRatio.t.sol for the Morpho Vaults
///         V2 adapter: 32 MorphoV2Strategy instances (each with its own venue)
///         on a real CollateralVault must keep `backingRatio()` inside the same
///         gas ceilings established for the Sky converter Strategy.
contract MorphoV2BackingRatioTest is Test {
    /// @dev Reporting views moved to CollateralVaultLens. It is stateless, so one instance
    ///      serves every Vault and the Vault is passed per call.
    CollateralVaultLens private _sharedLens;

    function _lens() internal returns (CollateralVaultLens) {
        if (address(_sharedLens) == address(0)) _sharedLens = new CollateralVaultLens();
        return _sharedLens;
    }

    uint256 internal constant STRATEGY_COUNT = 32;
    uint256 internal constant CURRENT_DF_BRANCH_COUNT = 8;
    uint256 internal constant COLLATERAL_REGISTRY_MAX_BRANCHES = 10;
    uint256 internal constant DEPOSIT_AMOUNT = 1_000_000e6;
    uint256 internal constant PER_BRANCH_GAS_CEILING = 2_000_000;
    uint256 internal constant MAX_BRANCH_TWO_PASS_VALUATION_CEILING = 20_000_000;
    uint256 internal constant MAX_STRATEGY_ALLOCATE_GAS_CEILING = 15_000_000;

    address internal treasury;
    MockERC20 internal usdc;
    CollateralVault internal emptyVault;
    CollateralVault internal singleStrategyVault;
    CollateralVault internal fiveStrategyVault;
    CollateralVault internal maxStrategyVault;

    function setUp() public {
        treasury = makeAddr("treasury");
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        emptyVault = _deployVault();
        singleStrategyVault = _deployVault();
        fiveStrategyVault = _deployVault();
        maxStrategyVault = _deployVault();

        _registerMorphoV2Strategies(singleStrategyVault, 1);
        _registerMorphoV2Strategies(fiveStrategyVault, 5);
        _registerMorphoV2Strategies(maxStrategyVault, STRATEGY_COUNT);

        _depositAndAllocate(emptyVault);
        _depositAndAllocate(singleStrategyVault);
        _depositAndAllocate(fiveStrategyVault);
        _depositAndAllocate(maxStrategyVault);

        assertEq(maxStrategyVault.getStrategiesCount(), STRATEGY_COUNT, "max Strategy count reached");
        for (uint256 i; i < STRATEGY_COUNT; ++i) {
            (IStrategy strategy,) = _lens().getStrategyAt(ICollateralVault(address(maxStrategyVault)), i);
            assertGt(MorphoV2Strategy(address(strategy)).ownShares(), 0, "Strategy has a live position");
        }
    }

    function test_Max32MorphoV2StrategiesBackingRatioStaysWithinBoundedGas() public {
        // Measure the max-size path first so every Strategy proxy and every
        // distinct Morpho vault venue begins cold in this transaction.
        (uint256 maxRatio, uint256 maxGas) = _measureBackingRatio(maxStrategyVault);
        (, uint256 maxWarmGas) = _measureBackingRatio(maxStrategyVault);
        (uint256 fiveRatio, uint256 fiveGas) = _measureBackingRatio(fiveStrategyVault);
        (uint256 singleRatio, uint256 singleGas) = _measureBackingRatio(singleStrategyVault);
        (uint256 emptyRatio, uint256 emptyGas) = _measureBackingRatio(emptyVault);

        uint256 loopGas = maxGas - emptyGas;
        uint256 marginalGasPerStrategy = loopGas / STRATEGY_COUNT;
        uint256 eightBranchColdPassUpperBound = maxGas * CURRENT_DF_BRANCH_COUNT;
        uint256 eightBranchTwoPassUpperBound = (maxGas + maxWarmGas) * CURRENT_DF_BRANCH_COUNT;
        uint256 maxBranchTwoPassUpperBound = (maxGas + maxWarmGas) * COLLATERAL_REGISTRY_MAX_BRANCHES;

        emit log_named_uint("MorphoV2 empty backingRatio gas", emptyGas);
        emit log_named_uint("MorphoV2 one Strategy backingRatio gas", singleGas);
        emit log_named_uint("MorphoV2 five distinct Strategies backingRatio gas", fiveGas);
        emit log_named_uint("MorphoV2 32 distinct Strategies backingRatio gas", maxGas);
        emit log_named_uint("MorphoV2 warm repeat of 32-Strategy backingRatio gas", maxWarmGas);
        emit log_named_uint("MorphoV2 32-Strategy loop gas above empty baseline", loopGas);
        emit log_named_uint("MorphoV2 marginal gas per Strategy", marginalGasPerStrategy);
        emit log_named_uint("MorphoV2 conservative 8-branch cold-pass upper bound", eightBranchColdPassUpperBound);
        emit log_named_uint("MorphoV2 conservative 8-branch two-pass upper bound", eightBranchTwoPassUpperBound);
        emit log_named_uint("MorphoV2 conservative 10-branch two-pass upper bound", maxBranchTwoPassUpperBound);

        assertEq(emptyRatio, 1e18, "empty Vault fully backed");
        assertEq(singleRatio, 1e18, "single-Strategy Vault fully backed");
        assertEq(fiveRatio, 1e18, "five-Strategy Vault fully backed");
        assertEq(maxRatio, 1e18, "max-Strategy Vault fully backed");
        assertLt(maxGas, PER_BRANCH_GAS_CEILING, "32 supported Strategies exceed per-branch gas ceiling");
        assertLt(
            maxBranchTwoPassUpperBound,
            MAX_BRANCH_TWO_PASS_VALUATION_CEILING,
            "max-branch two-pass valuation exceeds gas ceiling"
        );
    }

    function test_Max32MorphoV2StrategiesAllocateStaysWithinBoundedGas() public {
        _depositForAllocation(emptyVault);
        _depositForAllocation(singleStrategyVault);
        _depositForAllocation(fiveStrategyVault);
        _depositForAllocation(maxStrategyVault);

        uint256 maxGas = _measureAllocate(maxStrategyVault);
        uint256 fiveGas = _measureAllocate(fiveStrategyVault);
        uint256 singleGas = _measureAllocate(singleStrategyVault);
        uint256 emptyGas = _measureAllocate(emptyVault);

        emit log_named_uint("MorphoV2 empty allocate gas", emptyGas);
        emit log_named_uint("MorphoV2 one Strategy allocate gas", singleGas);
        emit log_named_uint("MorphoV2 five distinct Strategies allocate gas", fiveGas);
        emit log_named_uint("MorphoV2 32 distinct Strategies allocate gas", maxGas);

        assertEq(maxStrategyVault.backingRatio(), 1e18, "max-Strategy Vault remains fully backed");
        assertLt(maxGas, MAX_STRATEGY_ALLOCATE_GAS_CEILING, "32 Morpho V2 Strategies exceed allocate gas ceiling");
    }

    function test_PricingViewDistinguishesUnavailableValuationFromMeasuredZero() public {
        CollateralVault vault = _deployVault();
        _registerMorphoV2Strategies(vault, 1);
        _depositAndAllocate(vault);

        (IStrategy rawStrategy,) = _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        MorphoV2Strategy strategy = MorphoV2Strategy(address(rawStrategy));
        MockMorphoV2Vault morphoVault = MockMorphoV2Vault(address(strategy.morphoVault()));

        vault.setStrategyValuationMaxAge(1);
        vm.warp(block.timestamp + 2);
        morphoVault.setValuationUnavailable(true);

        assertEq(vault.backingRatio(), 0, "operational view remains conservatively numeric");
        (uint256 unavailableRatio, bool unavailable) = vault.backingRatioForPricing();
        assertEq(unavailableRatio, 0, "unavailable pricing view carries no numeric ratio");
        assertFalse(unavailable, "pricing view exposes the valuation outage");

        morphoVault.setValuationUnavailable(false);
        usdc.burn(address(morphoVault), DEPOSIT_AMOUNT);

        assertEq(vault.backingRatio(), 0, "measured total loss is still numeric zero");
        (uint256 measuredRatio, bool measuredAvailable) = vault.backingRatioForPricing();
        assertEq(measuredRatio, 0, "measured total loss remains zero");
        assertTrue(measuredAvailable, "measured zero must not be misclassified as an outage");
    }

    function _measureBackingRatio(CollateralVault vault) internal view returns (uint256 ratio, uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        ratio = vault.backingRatio();
        gasUsed = gasBefore - gasleft();
    }

    function _measureAllocate(CollateralVault vault) internal returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        vault.allocate();
        gasUsed = gasBefore - gasleft();
    }

    function _deployVault() internal returns (CollateralVault vault) {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        DToken dToken = DToken(
            address(
                new ERC1967Proxy(
                    address(dTokenImplementation),
                    abi.encodeWithSelector(DToken.initialize.selector, predictedVault, address(this))
                )
            )
        );
        dToken.setAllowedUnderlying(address(usdc), true);
        vault = CollateralVault(
            address(
                new ERC1967Proxy(
                    address(vaultImplementation),
                    abi.encodeWithSelector(
                        CollateralVault.initialize.selector,
                        IERC20(address(usdc)),
                        IDToken(address(dToken)),
                        treasury,
                        address(this)
                    )
                )
            )
        );
        dToken.setTokenInfo("dUSDC", "dUSDC", IERC20MetadataUpgradeable(address(usdc)));
        activateDTokenForTest(dToken);
    }

    function _registerMorphoV2Strategies(CollateralVault vault, uint256 strategyCount) internal {
        uint256 assignedWeight;
        for (uint256 i; i < strategyCount; ++i) {
            MockMorphoV2Vault morphoVault = new MockMorphoV2Vault(IERC20(address(usdc)));
            MorphoV2Strategy implementation = new MorphoV2Strategy();
            MorphoV2Strategy strategy = MorphoV2Strategy(
                address(
                    new ERC1967Proxy(
                        address(implementation),
                        abi.encodeWithSelector(
                            MorphoV2Strategy.initialize.selector,
                            address(vault),
                            IERC20(address(usdc)),
                            address(this),
                            address(this),
                            IMorphoVaultV2(address(morphoVault)),
                            200
                        )
                    )
                )
            );

            uint256 weight =
                strategyCount == 1 ? 10_000 : i + 1 == strategyCount ? 10_000 - assignedWeight : 10_000 / strategyCount;
            assignedWeight += weight;
            vault.addToWhitelist(address(strategy));
            vault.addStrategy(IStrategy(address(strategy)), weight, type(uint256).max);
        }
        assertEq(assignedWeight, 10_000, "weights sum to 100%");
    }

    function _depositAndAllocate(CollateralVault vault) internal {
        _depositForAllocation(vault);
        vault.setBufferConfig(0, 0);
        vault.allocate();
    }

    function _depositForAllocation(CollateralVault vault) internal {
        usdc.mint(address(this), DEPOSIT_AMOUNT);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
    }
}
