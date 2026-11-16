// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/CollateralVault.sol";
import "src/CollateralVaultLens.sol";
import "../src/DToken.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/ISkyUsdcSUsdsConverter.sol";
import "../src/Interfaces/IStrategy.sol";
import "../src/Strategies/SkyUsdcSUsdsStrategy.sol";
import "./mocks/MockERC20.sol";

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract ExternalAuditGas01SUsdsVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Gas 01 sUSDS", "gSUSDS") ERC4626(asset_) {}
}

contract ExternalAuditGas01SkyConverter is ISkyUsdcSUsdsConverter {
    using SafeERC20 for IERC20;

    MockERC20 public immutable usdc;
    MockERC20 public immutable usds;

    constructor(MockERC20 _usdc, MockERC20 _usds) {
        usdc = _usdc;
        usds = _usds;
    }

    function usdcToken() external view returns (IERC20) {
        return IERC20(address(usdc));
    }

    function usdsToken() external view returns (IERC20) {
        return IERC20(address(usds));
    }

    function psmWrapper() external pure returns (ISkyLitePsmWrapper) {
        return ISkyLitePsmWrapper(address(0));
    }

    function isUsdsToUsdcRouteHalted() external pure returns (bool) {
        return false;
    }

    function convertUsdcToUsds(uint256 usdcAmount, uint256 minUsdsOut, address receiver)
        external
        returns (uint256 usdsOut)
    {
        IERC20(address(usdc)).safeTransferFrom(msg.sender, address(this), usdcAmount);
        usdc.burn(address(this), usdcAmount);
        usdsOut = usdcAmount * 1e12;
        require(usdsOut >= minUsdsOut, "USDS_MIN");
        usds.mint(receiver, usdsOut);
    }

    function convertUsdsToUsdc(uint256 maxUsdsIn, uint256 minUsdcOut, address receiver)
        external
        returns (uint256 usdcOut)
    {
        IERC20(address(usds)).safeTransferFrom(msg.sender, address(this), maxUsdsIn);
        usds.burn(address(this), maxUsdsIn);
        usdcOut = maxUsdsIn / 1e12;
        require(usdcOut >= minUsdcOut, "USDC_MIN");
        usdc.mint(receiver, usdcOut);
    }

    function previewUsdsToUsdc(uint256 maxUsdsIn) external pure returns (uint256 usdcOut) {
        return maxUsdsIn / 1e12;
    }
}

contract ExternalAuditGas01BackingRatioTest is Test {
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

        _registerSkyStrategies(singleStrategyVault, 1);
        _registerSkyStrategies(fiveStrategyVault, 5);
        _registerSkyStrategies(maxStrategyVault, STRATEGY_COUNT);

        _depositAndAllocate(emptyVault);
        _depositAndAllocate(singleStrategyVault);
        _depositAndAllocate(fiveStrategyVault);
        _depositAndAllocate(maxStrategyVault);

        assertEq(maxStrategyVault.getStrategiesCount(), STRATEGY_COUNT, "max Strategy count reached");
        for (uint256 i; i < STRATEGY_COUNT; ++i) {
            (IStrategy strategy,) = _lens().getStrategyAt(ICollateralVault(address(maxStrategyVault)), i);
            assertGt(SkyUsdcSUsdsStrategy(address(strategy)).ownSUsdsShares(), 0, "Strategy has a live position");
        }
    }

    function test_Max32SupportedSkyStrategiesBackingRatioStaysWithinBoundedGas() public {
        // Measure the max-size path first so every Strategy proxy and every
        // distinct sUSDS/converter venue begins cold in this transaction.
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

        emit log_named_uint("Gas01 empty backingRatio gas", emptyGas);
        emit log_named_uint("Gas01 one Sky Strategy backingRatio gas", singleGas);
        emit log_named_uint("Gas01 five distinct Sky Strategies backingRatio gas", fiveGas);
        emit log_named_uint("Gas01 32 distinct Sky Strategies backingRatio gas", maxGas);
        emit log_named_uint("Gas01 warm repeat of 32-Strategy backingRatio gas", maxWarmGas);
        emit log_named_uint("Gas01 32-Strategy loop gas above empty baseline", loopGas);
        emit log_named_uint("Gas01 marginal gas per Strategy", marginalGasPerStrategy);
        emit log_named_uint("Gas01 conservative 8-branch cold-pass upper bound", eightBranchColdPassUpperBound);
        emit log_named_uint("Gas01 conservative 8-branch two-pass upper bound", eightBranchTwoPassUpperBound);
        emit log_named_uint("Gas01 conservative 10-branch two-pass upper bound", maxBranchTwoPassUpperBound);

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

    function test_Max32SupportedSkyStrategiesAllocateStaysWithinBoundedGas() public {
        _depositForAllocation(emptyVault);
        _depositForAllocation(singleStrategyVault);
        _depositForAllocation(fiveStrategyVault);
        _depositForAllocation(maxStrategyVault);

        uint256 maxGas = _measureAllocate(maxStrategyVault);
        uint256 fiveGas = _measureAllocate(fiveStrategyVault);
        uint256 singleGas = _measureAllocate(singleStrategyVault);
        uint256 emptyGas = _measureAllocate(emptyVault);

        emit log_named_uint("Gas01 empty allocate gas", emptyGas);
        emit log_named_uint("Gas01 one Sky Strategy allocate gas", singleGas);
        emit log_named_uint("Gas01 five distinct Sky Strategies allocate gas", fiveGas);
        emit log_named_uint("Gas01 32 distinct Sky Strategies allocate gas", maxGas);

        assertEq(maxStrategyVault.backingRatio(), 1e18, "max-Strategy Vault remains fully backed");
        assertLt(maxGas, MAX_STRATEGY_ALLOCATE_GAS_CEILING, "32 supported Strategies exceed allocate gas ceiling");
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

    function _registerSkyStrategies(CollateralVault vault, uint256 strategyCount) internal {
        uint256 assignedWeight;
        for (uint256 i; i < strategyCount; ++i) {
            MockERC20 usds = new MockERC20("Mock USDS", "mUSDS", 18);
            ExternalAuditGas01SUsdsVault susdsVault = new ExternalAuditGas01SUsdsVault(IERC20(address(usds)));
            ExternalAuditGas01SkyConverter converter = new ExternalAuditGas01SkyConverter(usdc, usds);
            SkyUsdcSUsdsStrategy implementation = new SkyUsdcSUsdsStrategy();
            SkyUsdcSUsdsStrategy strategy = SkyUsdcSUsdsStrategy(
                address(
                    new ERC1967Proxy(
                        address(implementation),
                        abi.encodeWithSelector(
                            SkyUsdcSUsdsStrategy.initialize.selector,
                            address(vault),
                            IERC20(address(usdc)),
                            address(this),
                            address(this),
                            IERC20(address(usds)),
                            IERC4626(address(susdsVault)),
                            ISkyUsdcSUsdsConverter(address(converter)),
                            0
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
