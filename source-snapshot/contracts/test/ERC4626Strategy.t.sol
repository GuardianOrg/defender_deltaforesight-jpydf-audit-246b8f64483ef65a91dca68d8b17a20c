// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "src/CollateralVaultLens.sol";
import "../src/Strategies/ERC4626Strategy.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/IStrategy.sol";
import "./mocks/MockERC20.sol";

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract MockERC4626Vault is ERC4626 {
    uint256 public maxWithdrawLimit = type(uint256).max;

    constructor(IERC20 asset_) ERC20("Mock ERC4626 Vault", "m4626") ERC4626(asset_) {}

    function setMaxWithdrawLimit(uint256 _limit) external {
        maxWithdrawLimit = _limit;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 maxAssets = super.maxWithdraw(owner);
        return maxAssets < maxWithdrawLimit ? maxAssets : maxWithdrawLimit;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 shares = super.maxRedeem(owner);
        if (maxWithdrawLimit == type(uint256).max) return shares;

        uint256 maxAssets = super.maxWithdraw(owner);
        if (maxWithdrawLimit >= maxAssets) return shares;

        uint256 limitedShares = previewWithdraw(maxWithdrawLimit);
        return limitedShares < shares ? limitedShares : shares;
    }
}

contract ZeroShareERC4626Vault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_) {}

    function deposit(uint256 assets, address receiver) public pure override returns (uint256) {
        assets;
        receiver;
        return 0;
    }
}

contract LyingDepositERC4626Vault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_) {}

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        return super.deposit(assets, receiver) + 1;
    }
}

contract LyingWithdrawERC4626Vault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_) {}

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        return super.withdraw(assets, receiver, owner) + 1;
    }
}

contract ZeroBurnWithdrawERC4626Vault is MockERC4626Vault {
    using SafeERC20 for IERC20;

    constructor(IERC20 asset_) MockERC4626Vault(asset_) {}

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        owner;
        IERC20(asset()).safeTransfer(receiver, assets);
        return 0;
    }
}

contract ZeroAssetWithdrawERC4626Vault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_) {}

    function withdraw(uint256 assets, address, address owner) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _burn(owner, shares);
    }
}

contract ZeroAssetRedeemERC4626Vault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_) {}

    function redeem(uint256 shares, address, address owner) public override returns (uint256 assets) {
        assets = previewRedeem(shares);
        _burn(owner, shares);
    }
}

contract MockMerklDistributor {
    using SafeERC20 for IERC20;

    address public lastCaller;
    address public lastUser;
    address public lastToken;
    uint256 public lastAmount;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        require(
            users.length == tokens.length && users.length == amounts.length && users.length == proofs.length,
            "BAD_LENGTH"
        );

        lastCaller = msg.sender;
        for (uint256 i = 0; i < users.length; i++) {
            lastUser = users[i];
            lastToken = tokens[i];
            lastAmount = amounts[i];
            IERC20(tokens[i]).safeTransfer(users[i], amounts[i]);
        }
    }
}

/// @title ERC4626StrategyTest - generic ERC-4626 strategy coverage.
/// @notice Covers the adapter shape intended for Morpho Vault / EulerEarn /
///         other ERC-4626 venues whose `asset()` matches the Vault underlying.
contract ERC4626StrategyTest is Test {
    /// @dev Reporting views moved to CollateralVaultLens. It is stateless, so one instance
    ///      serves every Vault and the Vault is passed per call.
    CollateralVaultLens private _sharedLens;

    function _lens() internal returns (CollateralVaultLens) {
        if (address(_sharedLens) == address(0)) _sharedLens = new CollateralVaultLens();
        return _sharedLens;
    }

    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public admin;
    address public treasury;
    address public alice;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
    }

    function _deployERC4626Setup()
        internal
        returns (
            CollateralVault collateralVault,
            ERC4626Strategy strategy,
            MockERC4626Vault erc4626Vault,
            MockERC20 underlyingToken
        )
    {
        underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        erc4626Vault = new MockERC4626Vault(IERC20(address(underlyingToken)));
        (collateralVault, strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);
    }

    function _deployERC4626SetupWithVault(MockERC20 underlyingToken, MockERC4626Vault erc4626Vault)
        internal
        returns (CollateralVault collateralVault, ERC4626Strategy strategy)
    {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dTokenInitializer = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        DToken dToken = DToken(address(new ERC1967Proxy(address(dTokenImplementation), dTokenInitializer)));
        dToken.setAllowedUnderlying(address(underlyingToken), true);
        bytes memory vaultInitializer = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlyingToken)),
            IDToken(address(dToken)),
            treasury,
            admin
        );
        collateralVault = CollateralVault(address(new ERC1967Proxy(address(vaultImplementation), vaultInitializer)));
        dToken.setTokenInfo("dmUSDC", "dmUSDC", IERC20MetadataUpgradeable(address(underlyingToken)));
        activateDTokenForTest(dToken);

        ERC4626Strategy strategyImplementation = new ERC4626Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            ERC4626Strategy.initialize.selector,
            address(collateralVault),
            IERC20(address(underlyingToken)),
            admin,
            admin,
            IERC4626(address(erc4626Vault))
        );
        strategy = ERC4626Strategy(address(new ERC1967Proxy(address(strategyImplementation), strategyInitializer)));

        collateralVault.addToWhitelist(address(strategy));
        collateralVault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
    }

    function _depositAndAllocate(CollateralVault collateralVault, MockERC20 underlyingToken, uint256 amount) internal {
        underlyingToken.mint(alice, amount);
        vm.startPrank(alice);
        underlyingToken.approve(address(collateralVault), amount);
        collateralVault.deposit(amount);
        vm.stopPrank();
        collateralVault.setBufferConfig(0, 0);
        collateralVault.allocate();
    }

    function test_Initialize_RevertsOnERC4626AssetMismatch() public {
        MockERC20 underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        MockERC20 otherUnderlying = new MockERC20("Other", "OTHER", 18);
        MockERC4626Vault wrongVault = new MockERC4626Vault(IERC20(address(otherUnderlying)));

        ERC4626Strategy strategyImplementation = new ERC4626Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            ERC4626Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IERC4626(address(wrongVault))
        );

        vm.expectRevert(ERC4626Strategy.InvalidERC4626Asset.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnNonContractERC4626Vault() public {
        MockERC20 underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        address vaultEoa = makeAddr("erc4626VaultEoa");

        ERC4626Strategy strategyImplementation = new ERC4626Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            ERC4626Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IERC4626(vaultEoa)
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, vaultEoa));
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnZeroUpgrader() public {
        MockERC20 underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        MockERC4626Vault erc4626Vault = new MockERC4626Vault(IERC20(address(underlying)));

        ERC4626Strategy strategyImplementation = new ERC4626Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            ERC4626Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            address(0),
            IERC4626(address(erc4626Vault))
        );

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_SweepRewardToken_RejectsERC4626ShareToken() public {
        (, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault,) = _deployERC4626Setup();

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        strategy.sweepRewardToken(IERC20(address(erc4626Vault)), type(uint256).max);
    }

    function test_SweepRewardToken_RewardStillSweepsToTreasury() public {
        (, ERC4626Strategy strategy,,) = _deployERC4626Setup();
        MockERC20 reward = new MockERC20("Reward", "RWD", 18);
        uint256 amount = 25e18;
        reward.mint(address(strategy), amount);

        vm.prank(admin);
        uint256 swept = strategy.sweepRewardToken(IERC20(address(reward)), type(uint256).max);

        assertEq(swept, amount, "reported treasury receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received reward");
        assertEq(reward.balanceOf(address(strategy)), 0, "strategy reward drained");
    }

    function test_ClaimMerklRewards_SweepsERC4626RewardToTreasuryWithoutAccountingImpact() public {
        (CollateralVault vault, ERC4626Strategy strategy,, MockERC20 underlyingToken) = _deployERC4626Setup();
        _depositAndAllocate(vault, underlyingToken, 100e18);

        MockMerklDistributor distributor = new MockMerklDistributor();
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);
        uint256 amount = 25e18;
        reward.mint(address(distributor), amount);

        uint256 principalBefore = strategy.principal();
        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();
        uint256 bufferBefore = vault.bufferBalance();

        address[] memory tokens = new address[](1);
        tokens[0] = address(reward);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.prank(admin);
        uint256[] memory swept =
            strategy.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(strategy), "strategy called Merkl");
        assertEq(distributor.lastUser(), address(strategy), "claim user is strategy");
        assertEq(distributor.lastToken(), address(reward), "claimed reward token");
        assertEq(distributor.lastAmount(), amount, "claimed cumulative amount");
        assertEq(swept[0], amount, "reported treasury receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received reward");
        assertEq(reward.balanceOf(address(strategy)), 0, "strategy reward drained");
        assertEq(strategy.principal(), principalBefore, "principal unchanged");
        assertEq(strategy.estimatedTotalUnderlying(), estimatedBefore, "strategy AUM unchanged");
        assertEq(vault.bufferBalance(), bufferBefore, "vault buffer unchanged");
    }

    function test_ClaimMerklRewards_PushesUnderlyingRewardToVaultWithoutReducingPrincipal() public {
        (CollateralVault vault, ERC4626Strategy strategy,, MockERC20 underlyingToken) = _deployERC4626Setup();
        _depositAndAllocate(vault, underlyingToken, 100e18);

        MockMerklDistributor distributor = new MockMerklDistributor();
        uint256 amount = 25e18;
        underlyingToken.mint(address(distributor), amount);

        uint256 principalBefore = strategy.principal();
        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();
        uint256 bufferBefore = vault.bufferBalance();
        uint256 totalUnderlyingBefore = vault.totalUnderlying();

        address[] memory tokens = new address[](1);
        tokens[0] = address(underlyingToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.prank(admin);
        uint256[] memory sent =
            strategy.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(strategy), "strategy called Merkl");
        assertEq(distributor.lastUser(), address(strategy), "claim user is strategy");
        assertEq(distributor.lastToken(), address(underlyingToken), "claimed underlying token");
        assertEq(distributor.lastAmount(), amount, "claimed cumulative amount");
        assertEq(sent[0], amount, "reported vault receipt");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "underlying not left idle");
        assertEq(underlyingToken.balanceOf(address(vault)), bufferBefore + amount, "vault received underlying reward");
        assertEq(strategy.principal(), principalBefore, "principal unchanged");
        assertEq(strategy.estimatedTotalUnderlying(), estimatedBefore, "ERC4626 AUM unchanged");
        assertEq(vault.totalUnderlying(), totalUnderlyingBefore + amount, "vault assets include claimed reward");
    }

    function test_ClaimMerklRewards_RejectsERC4626ShareTokenBeforeDistributorCall() public {
        (, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault,) = _deployERC4626Setup();
        MockMerklDistributor distributor = new MockMerklDistributor();

        address[] memory tokens = new address[](1);
        tokens[0] = address(erc4626Vault);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        strategy.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(0), "distributor not called");
        assertEq(erc4626Vault.balanceOf(address(strategy)), 0, "strategy did not receive share token");
    }

    function test_ClaimMerklRewards_RevertsWhenTokenBatchTooLarge() public {
        (, ERC4626Strategy strategy,,) = _deployERC4626Setup();
        MockMerklDistributor distributor = new MockMerklDistributor();

        uint256 length = strategy.MAX_MERKL_TOKENS_PER_CLAIM() + 1;
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        bytes32[][] memory proofs = new bytes32[][](length);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseStrategy.TooManyMerklTokens.selector, length, strategy.MAX_MERKL_TOKENS_PER_CLAIM()
            )
        );
        vm.prank(admin);
        strategy.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(0), "distributor not called");
    }

    function test_ShareDonationDoesNotInflateRealizedYield() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        uint256 yieldBefore = strategy.realizedYield();
        uint256 principalBefore = strategy.principal();
        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();

        address donor = makeAddr("donor");
        underlyingToken.mint(donor, 10e18);
        vm.startPrank(donor);
        underlyingToken.approve(address(erc4626Vault), 10e18);
        uint256 donatedShares = erc4626Vault.deposit(10e18, donor);
        erc4626Vault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        assertEq(strategy.realizedYield(), yieldBefore, "share donation did not inflate realizedYield");
        assertEq(strategy.estimatedTotalUnderlying(), estimatedBefore, "estimatedTotalUnderlying unchanged");
        assertEq(strategy.principal(), principalBefore, "principal unchanged");
    }

    function test_Allocate_RecoversAndSkipsWhenERC4626MintsZeroShares() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroShareERC4626Vault erc4626Vault = new ZeroShareERC4626Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, ERC4626Strategy strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);

        underlyingToken.mint(alice, 100e18);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 100e18, "rejected allocation returns to buffer");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "strategy retains no idle underlying");
        assertEq(strategy.principal(), 0, "principal stays zero");
    }

    function test_Allocate_RecoversAndSkipsWhenERC4626ReturnDoesNotMatchShareDelta() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        LyingDepositERC4626Vault erc4626Vault = new LyingDepositERC4626Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, ERC4626Strategy strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);

        underlyingToken.mint(alice, 100e18);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 100e18, "mismatched deposit returns to buffer");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "strategy retains no idle underlying");
        assertEq(strategy.principal(), 0, "principal stays zero");
    }

    function test_Allocate_RevertsAndRollsBackWhenERC4626ShareRoundingBreaksFullBacking() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();
        address seeder = makeAddr("seeder");

        underlyingToken.mint(seeder, 3);
        vm.startPrank(seeder);
        underlyingToken.approve(address(erc4626Vault), 2);
        erc4626Vault.deposit(2, seeder);
        underlyingToken.transfer(address(erc4626Vault), 1);
        vm.stopPrank();

        underlyingToken.mint(alice, 2);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 2);
        vault.deposit(2);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        (uint256 cacheBefore, uint256 cacheUpdatedAtBefore, bool cacheInitializedBefore) =
            vault.strategyValuationCaches(IStrategy(address(strategy)));
        uint256 allocatorTimeBefore = vault.lastAllocatorTime();

        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(5e17), uint256(1e18))
        );
        vault.allocate();

        (uint256 cacheAfter, uint256 cacheUpdatedAtAfter, bool cacheInitializedAfter) =
            vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertEq(vault.bufferBalance(), 2, "failed allocation restores buffer");
        assertEq(strategy.principal(), 0, "failed allocation restores principal");
        assertEq(erc4626Vault.balanceOf(address(strategy)), 0, "failed allocation restores shares");
        assertEq(cacheAfter, cacheBefore, "failed allocation restores cached value");
        assertEq(cacheUpdatedAtAfter, cacheUpdatedAtBefore, "failed allocation restores cache timestamp");
        assertEq(cacheInitializedAfter, cacheInitializedBefore, "failed allocation restores cache state");
        assertEq(vault.lastAllocatorTime(), allocatorTimeBefore, "failed allocation preserves allocator timestamp");
    }

    function test_Allocate_ERC4626ShareRoundingUsesProtectedCushion() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();
        address seeder = makeAddr("seeder");

        underlyingToken.mint(seeder, 3);
        vm.startPrank(seeder);
        underlyingToken.approve(address(erc4626Vault), 2);
        erc4626Vault.deposit(2, seeder);
        underlyingToken.transfer(address(erc4626Vault), 1);
        vm.stopPrank();

        underlyingToken.mint(alice, 2);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 2);
        vault.deposit(2);
        vm.stopPrank();

        underlyingToken.mint(address(this), 1);
        underlyingToken.approve(address(vault), 1);
        vault.backstopDeposit(1);
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 0, "only user buffer is allocated");
        assertEq(vault.backstopBalance(), 1, "rounding cushion remains protected");
        assertEq(strategy.principal(), 2, "principal records exact received assets");
        assertEq(erc4626Vault.convertToAssets(erc4626Vault.balanceOf(address(strategy))), 1, "shares round down");
        assertEq(vault.backingRatio(), 1e18, "protected cushion preserves exact backing");
    }

    function test_SendToVault_RevertsWhenERC4626WithdrawReturnDoesNotMatchShareDelta() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        LyingWithdrawERC4626Vault erc4626Vault = new LyingWithdrawERC4626Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, ERC4626Strategy strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);

        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.expectRevert(ERC4626Strategy.ERC4626ShareBalanceMismatch.selector);
        strategy.sendToVault(10e18);
    }

    function test_SendToVault_RevertsWhenERC4626WithdrawBurnsZeroShares() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroBurnWithdrawERC4626Vault erc4626Vault = new ZeroBurnWithdrawERC4626Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, ERC4626Strategy strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 principalBefore = strategy.principal();

        vm.expectRevert(ERC4626Strategy.ERC4626ZeroShares.selector);
        strategy.sendToVault(10e18);

        assertEq(strategy.principal(), principalBefore, "principal unchanged after failed zero-share burn");
        assertEq(vault.bufferBalance(), 0, "vault received no assets after revert");
    }

    function test_SendToVault_RevertsWhenERC4626WithdrawAssetDeltaMismatch() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroAssetWithdrawERC4626Vault erc4626Vault = new ZeroAssetWithdrawERC4626Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, ERC4626Strategy strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 principalBefore = strategy.principal();

        vm.expectRevert(abi.encodeWithSelector(ERC4626Strategy.ERC4626AssetAmountMismatch.selector, 10e18, 0));
        strategy.sendToVault(10e18);

        assertEq(strategy.principal(), principalBefore, "principal unchanged after failed zero-asset withdraw");
        assertEq(vault.bufferBalance(), 0, "vault received no assets after revert");
    }

    function test_AssetLossReflectedInEstimateAndVaultTotal() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();
        uint256 totalBefore = vault.totalUnderlying();

        underlyingToken.burn(address(erc4626Vault), 50e18);

        assertLt(strategy.estimatedTotalUnderlying(), estimatedBefore, "estimated dropped after loss");
        assertLt(vault.totalUnderlying(), totalBefore, "vault total reflects loss immediately");
    }

    function test_SendToVault_RespectsERC4626WithdrawLimit() public {
        (, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) = _deployERC4626Setup();
        CollateralVault vault = CollateralVault(strategy.vault());

        _depositAndAllocate(vault, underlyingToken, 100e18);
        erc4626Vault.setMaxWithdrawLimit(40e18);

        uint256 sent = strategy.sendToVault(100e18);

        assertEq(sent, 40e18, "sent only currently withdrawable assets");
        assertEq(vault.bufferBalance(), 40e18, "vault received partial withdrawal");
        assertEq(strategy.principal(), 60e18, "principal reduced by sent amount");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 60e18, 2, "remaining shares track residual principal");
    }

    function test_SendProfitToVault_HarvestsSharePriceYieldWithoutReducingPrincipal() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        underlyingToken.mint(address(erc4626Vault), 10e18);
        uint256 principalBefore = strategy.principal();

        uint256 sent = strategy.sendProfitToVault();

        assertApproxEqAbs(sent, 10e18, 2, "yield pushed to vault");
        assertEq(strategy.principal(), principalBefore, "principal unchanged by harvest");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), principalBefore, 2, "remaining shares back principal");
    }

    function test_EmergencyWithdrawFromERC4626_DrainsAndPushesToVault() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.prank(admin);
        uint256 sent = strategy.emergencyWithdrawFromERC4626();

        assertEq(sent, 100e18, "reported vault receipt");
        assertEq(erc4626Vault.balanceOf(address(strategy)), 0, "share token drained");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "underlying not left idle in strategy");
        assertEq(strategy.estimatedTotalUnderlying(), 0, "estimated reset to zero");
        assertEq(strategy.principal(), 0, "returned principal accounted");
        assertEq(vault.bufferBalance(), 100e18, "underlying returned to vault buffer");
        (uint256 cachedValue,, bool cacheInitialized) = vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertFalse(cacheInitialized, "exhausted historical estimate is invalidated");
        assertEq(cachedValue, 0, "valuation cache reduced after emergency push");
    }

    function test_ExternalAuditInfo07_ReplacesVenueWithFreshStrategyWithoutImplementationUpgrade() public {
        (CollateralVault vault, ERC4626Strategy oldStrategy, MockERC4626Vault oldVenue, MockERC20 underlyingToken) =
            _deployERC4626Setup();
        _depositAndAllocate(vault, underlyingToken, 100e18);

        bytes32 oldImplementationBefore = vm.load(address(oldStrategy), ERC1967_IMPLEMENTATION_SLOT);
        assertNotEq(oldImplementationBefore, bytes32(0), "implementation slot must be populated before comparison");
        MockERC4626Vault newVenue = new MockERC4626Vault(IERC20(address(underlyingToken)));
        ERC4626Strategy newImplementation = new ERC4626Strategy();
        ERC4626Strategy newStrategy = ERC4626Strategy(
            address(
                new ERC1967Proxy(
                    address(newImplementation),
                    abi.encodeWithSelector(
                        ERC4626Strategy.initialize.selector,
                        address(vault),
                        IERC20(address(underlyingToken)),
                        admin,
                        admin,
                        IERC4626(address(newVenue))
                    )
                )
            )
        );

        // Freeze the old destination and register the independently validated
        // replacement before draining. Both adapters can coexist while an
        // asynchronous or partially liquid old venue finishes recovery.
        vault.updateStrategy(IStrategy(address(oldStrategy)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(newStrategy));
        vault.addStrategy(IStrategy(address(newStrategy)), 10_000, type(uint256).max);

        vm.prank(admin);
        uint256 recovered = oldStrategy.emergencyWithdrawFromERC4626();
        vault.removeStrategy(IStrategy(address(oldStrategy)));
        vault.allocate();

        assertEq(recovered, 100e18, "old venue principal returned through Vault");
        assertEq(oldStrategy.principal(), 0, "old principal drained");
        assertEq(oldVenue.balanceOf(address(oldStrategy)), 0, "old position drained");
        assertEq(vm.load(address(oldStrategy), ERC1967_IMPLEMENTATION_SLOT), oldImplementationBefore, "no old upgrade");
        assertEq(address(newStrategy.erc4626Vault()), address(newVenue), "fresh proxy binds replacement venue");
        assertEq(newStrategy.principal(), 100e18, "principal allocated to replacement");
        assertEq(newVenue.balanceOf(address(newStrategy)), 100e18, "replacement position funded");
        assertEq(vault.getStrategiesCount(), 1, "old Strategy removed after complete drain");
        (IStrategy registered,) = _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertEq(address(registered), address(newStrategy), "replacement is the sole registered Strategy");
        assertEq(vault.totalUnderlying(), 100e18, "migration preserves accounted assets");
        assertEq(vault.backingRatio(), 1e18, "migration preserves full backing");
    }

    function test_EmergencyWithdrawFromERC4626_PartialRecoveryAccountsReturnedPrincipal() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        erc4626Vault.setMaxWithdrawLimit(40e18);

        vm.prank(admin);
        uint256 sent = strategy.emergencyWithdrawFromERC4626();

        assertEq(sent, 40e18, "reported vault receipt");
        assertEq(vault.bufferBalance(), 40e18, "vault received liquid portion");
        assertEq(strategy.principal(), 60e18, "principal reduced by recovered amount");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 60e18, 2, "remaining shares stay valued");
        assertApproxEqAbs(vault.totalUnderlying(), 100e18, 2, "partial liquidity is not loss");

        vault.emergencyDisableStrategy(IStrategy(address(strategy)));
        vault.writeoffStrategyPrincipal(IStrategy(address(strategy)), 60e18, 0);

        assertEq(strategy.principal(), 0, "residual principal written off");
        assertEq(vault.totalUnderlying(), 40e18, "only recovered buffer remains counted");
        assertEq(_lens().backingShortfall(ICollateralVault(address(vault))), 60e18, "writeoff exposes confirmed residual loss");
    }

    function test_EmergencyWithdrawFromERC4626_DonationAfterLossPreservesRemainingOwnShares() public {
        (CollateralVault vault, ERC4626Strategy strategy, MockERC4626Vault erc4626Vault, MockERC20 underlyingToken) =
            _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        underlyingToken.burn(address(erc4626Vault), 50e18);

        uint256 estimatedAfterLoss = strategy.estimatedTotalUnderlying();
        address donor = makeAddr("repairDonor");
        underlyingToken.mint(donor, 20e18);
        vm.startPrank(donor);
        underlyingToken.approve(address(erc4626Vault), 20e18);
        uint256 donatedShares = erc4626Vault.deposit(20e18, donor);
        erc4626Vault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        assertEq(strategy.estimatedTotalUnderlying(), estimatedAfterLoss, "donation excluded before emergency");
        erc4626Vault.setMaxWithdrawLimit(40e18);

        vm.prank(admin);
        uint256 sent = strategy.emergencyWithdrawFromERC4626();

        uint256 remainingRawShares = erc4626Vault.balanceOf(address(strategy));
        uint256 remainingOwnedAssets = erc4626Vault.convertToAssets(remainingRawShares);
        assertEq(sent, 40e18, "partial recovery sent to vault");
        assertEq(
            strategy.estimatedTotalUnderlying(), remainingOwnedAssets, "remaining raw shares retain owned valuation"
        );
        assertEq(strategy.principal(), 60e18, "principal reduced only by vault receipt");
        assertApproxEqAbs(
            vault.totalUnderlying(), estimatedAfterLoss + 20e18, 2, "recovered donation enters conservative backing"
        );
    }

    function test_EmergencyWithdrawFromERC4626_DoesNotTransientlyDiscountBacking() public {
        (CollateralVault vault, ERC4626Strategy strategy,, MockERC20 underlyingToken) = _deployERC4626Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        assertEq(vault.totalUnderlying(), 100e18, "fully accounted before emergency");
        assertEq(vault.backingRatio(), 1e18, "fully backed before emergency");

        vm.prank(admin);
        strategy.emergencyWithdrawFromERC4626();

        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "funds are not left idle in strategy");
        assertEq(strategy.estimatedTotalUnderlying(), 0, "idle strategy funds are not counted as ERC4626 AUM");
        assertEq(vault.totalUnderlying(), 100e18, "vault still accounts recovered funds");
        assertEq(vault.backingRatio(), 1e18, "oracle-visible backing never discounts recoverable funds");
    }

    function test_EmergencyWithdrawFromERC4626_RevertsWhenRedeemAssetDeltaMismatch() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroAssetRedeemERC4626Vault erc4626Vault = new ZeroAssetRedeemERC4626Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, ERC4626Strategy strategy) = _deployERC4626SetupWithVault(underlyingToken, erc4626Vault);

        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Strategy.ERC4626AssetAmountMismatch.selector, 100e18, 0));
        vm.prank(admin);
        strategy.emergencyWithdrawFromERC4626();

        assertEq(strategy.estimatedTotalUnderlying(), 100e18, "revert preserves strategy value");
        assertEq(strategy.principal(), 100e18, "principal unchanged");
        assertEq(vault.bufferBalance(), 0, "vault did not receive mismatched redeem");
    }
}
