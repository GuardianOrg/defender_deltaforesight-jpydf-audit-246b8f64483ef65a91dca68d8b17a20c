// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {ICollateralVault} from "src/Interfaces/ICollateralVault.sol";
import {IStrategy} from "src/Interfaces/IStrategy.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {LatestTroveData} from "src/Types/LatestTroveData.sol";

interface IMainnetPilotDToken is IERC20 {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function acceptOwnership() external;
    function setCap(uint256 _newCap) external;
    function cap() external view returns (uint256);
    function underlying() external view returns (IERC20);
}

interface IMainnetPilotInterestRouter {
    function jpydfToken() external view returns (IERC20);
    function recipient() external view returns (address);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function route() external returns (uint256 amount);
}

interface IMainnetPilotOwnableStrategy {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
}

/**
 * @title MainnetPilotController
 * @notice One-shot containment and cleanup controller for the August 2026
 *         TEST_ONLY_NOT_FOR_PRODUCTION mainnet pilot.
 * @dev This contract deliberately exposes no arbitrary-call or ownership-transfer
 *      surface. It owns every pilot dToken, opens only the dUSDC cap for one
 *      explicitly bounded frontend test window, and permanently freezes after
 *      proving that the pilot state has been removed. The complete pilot overlay
 *      must be deleted before production deployment (jpydf-v2 #1548).
 * @custom:security-contact security@deltaforesight.xyz
 */
contract MainnetPilotController is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct PilotConfiguration {
        address pilotOwner;
        IERC20 usdc;
        IERC20 jpydfToken;
        IMainnetPilotDToken dUsdc;
        ICollateralVault usdcVault;
        IBorrowerOperations borrowerOperations;
        ITroveManager troveManager;
        address stabilityPool;
        IMainnetPilotInterestRouter interestRouter;
        IMainnetPilotDToken[] dTokens;
        IStrategy[] strategies;
    }

    uint256 public constant DTOKEN_COUNT = 8;
    uint256 public constant STRATEGY_COUNT = 2;
    uint256 public constant PILOT_MIN_DEBT = 1_000e18;
    uint256 private constant MAX_JPYDF_ROUNDING_DUST = 1e6;

    address public immutable pilotOwner;
    IERC20 public immutable usdc;
    IERC20 public immutable jpydfToken;
    IMainnetPilotDToken public immutable dUsdc;
    ICollateralVault public immutable usdcVault;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    address public immutable stabilityPool;
    IMainnetPilotInterestRouter public immutable interestRouter;

    IMainnetPilotDToken[] private _dTokens;
    IStrategy[] private _strategies;

    uint256 public testWindowCap;
    bool public dTokenOwnershipsAccepted;
    bool public testWindowOpened;
    bool public testWindowFrozen;
    bool public troveClosed;
    bool public finalized;

    error MainnetPilotController__Unauthorized();
    error MainnetPilotController__WrongChain();
    error MainnetPilotController__ZeroAddress();
    error MainnetPilotController__NotContract(address account);
    error MainnetPilotController__BadArrayLength();
    error MainnetPilotController__BadWiring();
    error MainnetPilotController__InvalidState();
    error MainnetPilotController__InvalidCap();
    error MainnetPilotController__NonZeroState(address account, uint256 amount);
    error MainnetPilotController__UnexpectedAmount(uint256 expected, uint256 actual);
    error MainnetPilotController__ActiveStrategyConfiguration(
        address strategy, bool enabled, uint256 weightBps, uint256 cap
    );

    event DTokenOwnershipsAccepted();
    event TestWindowOpened(uint256 dTokenCap);
    event TestWindowFrozen(uint256 dTokenSupply);
    event TroveSettledAndClosed(uint256 indexed troveId, uint256 excessDebtRepaid, uint256 finalDebtRepaid);
    event UnsolicitedUsdcSwept(uint256 amount);
    event Finalized();

    modifier onlyPilotOwner() {
        if (msg.sender != pilotOwner) revert MainnetPilotController__Unauthorized();
        _;
    }

    modifier beforeFinalization() {
        if (finalized) revert MainnetPilotController__InvalidState();
        _;
    }

    constructor(PilotConfiguration memory config) {
        if (block.chainid != 1) revert MainnetPilotController__WrongChain();
        if (
            config.pilotOwner == address(0) || address(config.usdc) == address(0)
                || address(config.jpydfToken) == address(0) || address(config.dUsdc) == address(0)
                || address(config.usdcVault) == address(0) || address(config.borrowerOperations) == address(0)
                || address(config.troveManager) == address(0) || config.stabilityPool == address(0)
                || address(config.interestRouter) == address(0)
        ) revert MainnetPilotController__ZeroAddress();
        if (config.dTokens.length != DTOKEN_COUNT || config.strategies.length != STRATEGY_COUNT) {
            revert MainnetPilotController__BadArrayLength();
        }

        _requireContract(address(config.usdc));
        _requireContract(address(config.jpydfToken));
        _requireContract(address(config.dUsdc));
        _requireContract(address(config.usdcVault));
        _requireContract(address(config.borrowerOperations));
        _requireContract(address(config.troveManager));
        _requireContract(config.stabilityPool);
        _requireContract(address(config.interestRouter));

        if (
            address(config.dTokens[1]) != address(config.dUsdc)
                || address(config.dUsdc.underlying()) != address(config.usdc)
                || address(config.usdcVault.underlying()) != address(config.usdc)
                || address(config.usdcVault.dToken()) != address(config.dUsdc)
                || address(config.interestRouter.jpydfToken()) != address(config.jpydfToken)
                || config.interestRouter.recipient() != config.pilotOwner
                || config.interestRouter.owner() != config.pilotOwner
                || config.interestRouter.pendingOwner() != address(0)
                || address(config.troveManager.borrowerOperations()) != address(config.borrowerOperations)
                || address(config.troveManager.stabilityPool()) != config.stabilityPool
        ) revert MainnetPilotController__BadWiring();

        for (uint256 i; i < DTOKEN_COUNT; ++i) {
            _requireContract(address(config.dTokens[i]));
            for (uint256 j; j < i; ++j) {
                if (address(config.dTokens[i]) == address(config.dTokens[j])) {
                    revert MainnetPilotController__BadWiring();
                }
            }
            _dTokens.push(config.dTokens[i]);
        }
        if (config.usdcVault.getStrategiesCount() != STRATEGY_COUNT) {
            revert MainnetPilotController__BadWiring();
        }
        for (uint256 i; i < STRATEGY_COUNT; ++i) {
            _requireContract(address(config.strategies[i]));
            IMainnetPilotOwnableStrategy ownableStrategy = IMainnetPilotOwnableStrategy(address(config.strategies[i]));
            if (
                config.strategies[i].underlying() != address(config.usdc)
                    || address(config.usdcVault.strategies(i)) != address(config.strategies[i])
                    || (i != 0 && address(config.strategies[i]) == address(config.strategies[0]))
                    || ownableStrategy.owner() != config.pilotOwner || ownableStrategy.pendingOwner() != address(0)
            ) {
                revert MainnetPilotController__BadWiring();
            }
            _strategies.push(config.strategies[i]);
        }

        pilotOwner = config.pilotOwner;
        usdc = config.usdc;
        jpydfToken = config.jpydfToken;
        dUsdc = config.dUsdc;
        usdcVault = config.usdcVault;
        borrowerOperations = config.borrowerOperations;
        troveManager = config.troveManager;
        stabilityPool = config.stabilityPool;
        interestRouter = config.interestRouter;
    }

    function dTokenAt(uint256 _index) external view returns (IMainnetPilotDToken) {
        return _dTokens[_index];
    }

    function strategyAt(uint256 _index) external view returns (IStrategy) {
        return _strategies[_index];
    }

    function acceptDTokenOwnerships() external nonReentrant onlyPilotOwner beforeFinalization {
        if (dTokenOwnershipsAccepted) revert MainnetPilotController__InvalidState();

        for (uint256 i; i < DTOKEN_COUNT; ++i) {
            IMainnetPilotDToken token = _dTokens[i];
            if (token.owner() != address(this)) {
                if (token.pendingOwner() != address(this)) revert MainnetPilotController__BadWiring();
                token.acceptOwnership();
            }
            token.setCap(0);
            _requireZero(address(token), token.totalSupply());
        }

        dTokenOwnershipsAccepted = true;
        emit DTokenOwnershipsAccepted();
    }

    /**
     * @notice Opens the only frontend test window at the reviewed production
     *         dUSDC cap derived by the cap-conversion evidence package.
     */
    function openTestWindow(uint256 _dTokenCap) external nonReentrant onlyPilotOwner beforeFinalization {
        if (_dTokenCap == 0) revert MainnetPilotController__InvalidCap();
        if (!dTokenOwnershipsAccepted || testWindowOpened) revert MainnetPilotController__InvalidState();
        _requireAllDTokensFrozenAndEmpty();
        _sweepUnsolicitedUsdc();

        testWindowCap = _dTokenCap;
        testWindowOpened = true;
        dUsdc.setCap(_dTokenCap);
        uint256 actualCap = dUsdc.cap();
        if (actualCap != _dTokenCap) revert MainnetPilotController__UnexpectedAmount(_dTokenCap, actualCap);

        emit TestWindowOpened(_dTokenCap);
    }

    /**
     * @notice Permanently stops new dUSDC minting before participant cleanup.
     * @dev Existing dUSDC can still be burned through normal frontend close and
     *      redemption flows. The window cannot be reopened.
     */
    function freezeTestWindow() external nonReentrant onlyPilotOwner beforeFinalization {
        if (!testWindowOpened || testWindowFrozen) revert MainnetPilotController__InvalidState();

        testWindowFrozen = true;
        dUsdc.setCap(0);
        _sweepUnsolicitedUsdc();

        emit TestWindowFrozen(dUsdc.totalSupply());
    }

    /**
     * @notice Routes all minted pilot fees to the pilot owner, repays the debt
     *         above the pilot floor, routes the interest minted by that repay,
     *         then closes the only Trove in the same transaction.
     */
    function settleAndClose(uint256 _troveId) external nonReentrant onlyPilotOwner beforeFinalization {
        if (!testWindowFrozen || troveClosed || troveManager.getTroveIdsCount() != 1) {
            revert MainnetPilotController__InvalidState();
        }
        if (troveManager.getTroveStatus(_troveId) != ITroveManager.Status.active) {
            revert MainnetPilotController__InvalidState();
        }
        _requireRouterWiring();
        (address removeManager, address receiver) = borrowerOperations.removeManagerReceiverOf(_troveId);
        if (removeManager != address(this) || receiver != pilotOwner) revert MainnetPilotController__BadWiring();
        _requireZero(stabilityPool, jpydfToken.balanceOf(stabilityPool));

        _routeAllInterest();
        uint256 totalExcessDebt;
        for (uint256 attempt; attempt < 2; ++attempt) {
            LatestTroveData memory currentTrove = troveManager.getLatestTroveData(_troveId);
            if (currentTrove.entireDebt < PILOT_MIN_DEBT) revert MainnetPilotController__InvalidState();

            uint256 excessDebt = currentTrove.entireDebt - PILOT_MIN_DEBT;
            if (excessDebt == 0) break;

            totalExcessDebt += excessDebt;
            _pullJpydfShortfallFromOwner(excessDebt);
            borrowerOperations.repayJpydf(_troveId, excessDebt);

            // The first repayment can leave a few aggregate-interest rounding
            // wei in the real core. Route that mint and permit one measured retry.
            _routeAllInterest();
        }

        _routeAllInterest();
        _requireZero(stabilityPool, jpydfToken.balanceOf(stabilityPool));

        LatestTroveData memory trove = troveManager.getLatestTroveData(_troveId);
        if (trove.entireDebt != PILOT_MIN_DEBT) {
            revert MainnetPilotController__UnexpectedAmount(PILOT_MIN_DEBT, trove.entireDebt);
        }
        uint256 finalSupply = jpydfToken.totalSupply();
        if (finalSupply < trove.entireDebt || finalSupply - trove.entireDebt > MAX_JPYDF_ROUNDING_DUST) {
            revert MainnetPilotController__UnexpectedAmount(trove.entireDebt, finalSupply);
        }
        // Consolidate the complete remaining supply. A floor-clamped repayment
        // can already have left a few unburned wei in this controller, so pull
        // only the measured shortfall. Tokens held elsewhere still make this
        // transfer fail and atomically preserve the open Trove for recovery.
        _pullJpydfShortfallFromOwner(finalSupply);
        borrowerOperations.closeTrove(_troveId);

        if (
            troveManager.getTroveIdsCount() != 0
                || troveManager.getTroveStatus(_troveId) != ITroveManager.Status.closedByOwner
        ) revert MainnetPilotController__InvalidState();
        _requireZero(address(jpydfToken), jpydfToken.totalSupply());
        _requireZero(address(interestRouter), jpydfToken.balanceOf(address(interestRouter)));
        _requireZero(stabilityPool, jpydfToken.balanceOf(stabilityPool));
        _requireZero(address(jpydfToken), jpydfToken.balanceOf(address(this)));

        troveClosed = true;
        emit TroveSettledAndClosed(_troveId, totalExcessDebt, trove.entireDebt);
    }

    /**
     * @notice Permanently disables all controller actions after every pilot
     *         liability, principal, cap, and allocation configuration is cleared.
     * @dev Raw Vault and Strategy balances are deliberately not zero-gates because
     *      ERC-20 assets and position tokens can be donated permissionlessly. With
     *      dToken supply, pending withdrawals, Strategy principal, weight, and cap
     *      at zero, such donations are unencumbered surplus rather than pilot state.
     */
    function finalize() external nonReentrant onlyPilotOwner beforeFinalization {
        if (!testWindowOpened || !testWindowFrozen) revert MainnetPilotController__InvalidState();
        _requireRouterWiring();
        _requireAllDTokensFrozenAndEmpty();

        _requireZero(address(jpydfToken), jpydfToken.totalSupply());
        _requireZero(address(interestRouter), jpydfToken.balanceOf(address(interestRouter)));
        _requireZero(stabilityPool, jpydfToken.balanceOf(stabilityPool));
        _requireZero(address(troveManager), troveManager.getTroveIdsCount());
        _requireZero(address(usdcVault), usdcVault.pendingWithdrawals());

        _requireStrategiesFrozenAndPrincipalZero();

        _sweepUnsolicitedUsdc();
        _requireZero(address(usdc), usdc.balanceOf(address(this)));
        _requireZero(address(jpydfToken), jpydfToken.balanceOf(address(this)));
        _requireZero(address(dUsdc), dUsdc.balanceOf(address(this)));

        finalized = true;
        emit Finalized();
    }

    function _requireAllDTokensFrozenAndEmpty() internal view {
        for (uint256 i; i < DTOKEN_COUNT; ++i) {
            IMainnetPilotDToken token = _dTokens[i];
            if (token.owner() != address(this) || token.pendingOwner() != address(0)) {
                revert MainnetPilotController__BadWiring();
            }
            _requireZero(address(token), token.cap());
            _requireZero(address(token), token.totalSupply());
        }
    }

    function _sweepUnsolicitedUsdc() private {
        uint256 amount = usdc.balanceOf(address(this));
        if (amount == 0) return;

        usdc.safeTransfer(pilotOwner, amount);
        emit UnsolicitedUsdcSwept(amount);
    }

    function _requireContract(address _account) private view {
        if (_account.code.length == 0) revert MainnetPilotController__NotContract(_account);
    }

    function _requireRouterWiring() private view {
        if (
            address(interestRouter.jpydfToken()) != address(jpydfToken) || interestRouter.recipient() != pilotOwner
                || interestRouter.owner() != pilotOwner || interestRouter.pendingOwner() != address(0)
        ) {
            revert MainnetPilotController__BadWiring();
        }
    }

    function _requireStrategiesFrozenAndPrincipalZero() private view {
        for (uint256 i; i < STRATEGY_COUNT; ++i) {
            IStrategy strategy = _strategies[i];
            (bool enabled, uint256 weightBps, uint256 cap) = usdcVault.strategyConfigs(strategy);
            if (enabled || weightBps != 0 || cap != 0) {
                revert MainnetPilotController__ActiveStrategyConfiguration(address(strategy), enabled, weightBps, cap);
            }
            _requireZero(address(strategy), strategy.principal());
        }
    }

    function _routeAllInterest() private {
        uint256 balanceBefore = jpydfToken.balanceOf(address(interestRouter));
        uint256 routed = interestRouter.route();
        if (routed != balanceBefore) revert MainnetPilotController__UnexpectedAmount(balanceBefore, routed);
        _requireZero(address(interestRouter), jpydfToken.balanceOf(address(interestRouter)));
    }

    function _pullJpydfShortfallFromOwner(uint256 _requiredBalance) private {
        uint256 currentBalance = jpydfToken.balanceOf(address(this));
        if (currentBalance < _requiredBalance) {
            jpydfToken.safeTransferFrom(pilotOwner, address(this), _requiredBalance - currentBalance);
        }
    }

    function _requireZero(address _account, uint256 _amount) private pure {
        if (_amount != 0) revert MainnetPilotController__NonZeroState(_account, _amount);
    }
}
