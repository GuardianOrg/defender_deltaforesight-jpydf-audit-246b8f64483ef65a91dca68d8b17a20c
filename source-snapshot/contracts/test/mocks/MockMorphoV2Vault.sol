// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @title MockMorphoV2Vault - Morpho Vaults V2 lookalike for tests
 * @notice ERC-4626 with Morpho Vaults V2 semantics: all max* views return 0
 *         unconditionally while deposit/withdraw/redeem remain fully
 *         synchronous, toggleable receive/send share gates, settable available
 *         liquidity that makes liquidity-short withdrawals revert with a raw
 *         untyped error, a deposit-cap revert toggle, and a permissionless
 *         `forceDeallocate` charging a configurable penalty in `onBehalf`
 *         shares with the vault as receiver.
 * @dev    Donations enter through the (max*-unclamped) `deposit` plus a share
 *         transfer; losses are injected by burning underlying held by this
 *         vault directly.
 */
contract MockMorphoV2Vault is ERC4626 {
    bool public depositCapExceeded;
    bool public receiveGateClosed;
    bool public sendGateClosed;
    uint256 public availableLiquidity = type(uint256).max;
    uint256 public forceDeallocatePenaltyBps;
    bool public valuationUnavailable;

    constructor(IERC20 asset_) ERC20("Mock Morpho Vault V2", "mMVv2") ERC4626(asset_) {}

    // ---------------------------------------------------------
    // Test knobs
    // ---------------------------------------------------------

    function setDepositCapExceeded(bool _exceeded) external {
        depositCapExceeded = _exceeded;
    }

    function setReceiveGateClosed(bool _closed) external {
        receiveGateClosed = _closed;
    }

    function setSendGateClosed(bool _closed) external {
        sendGateClosed = _closed;
    }

    function setAvailableLiquidity(uint256 _liquidity) external {
        availableLiquidity = _liquidity;
    }

    function setForceDeallocatePenaltyBps(uint256 _bps) external {
        forceDeallocatePenaltyBps = _bps;
    }

    function setValuationUnavailable(bool _unavailable) external {
        valuationUnavailable = _unavailable;
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        if (valuationUnavailable) revert("valuation unavailable");
        return super.convertToAssets(shares);
    }

    // ---------------------------------------------------------
    // Morpho Vaults V2: max* views are hard-zero
    // ---------------------------------------------------------

    function maxDeposit(address) public view virtual override returns (uint256) {
        return 0;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        return 0;
    }

    function maxWithdraw(address) public view virtual override returns (uint256) {
        return 0;
    }

    function maxRedeem(address) public view virtual override returns (uint256) {
        return 0;
    }

    // ---------------------------------------------------------
    // Synchronous flows (no max* clamping, unlike stock OZ 4626)
    // ---------------------------------------------------------

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        if (depositCapExceeded) revert("liquidity adapter cap exceeded");
        if (receiveGateClosed) revert("cannot receive shares");
        shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        _checkSendPath(assets);
        shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        assets = previewRedeem(shares);
        _checkSendPath(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    function _checkSendPath(uint256 assets) internal view {
        if (sendGateClosed) revert("cannot send shares");
        if (assets > availableLiquidity) {
            // Liquidity-short deallocations bubble up as raw untyped
            // lower-level reverts with no vault-level typed error.
            assembly {
                revert(0, 0)
            }
        }
    }

    // ---------------------------------------------------------
    // forceDeallocate (permissionless on the real vault)
    // ---------------------------------------------------------

    function forceDeallocate(address adapter, bytes calldata data, uint256 assets, address onBehalf)
        external
        virtual
        returns (uint256 penaltyShares)
    {
        adapter;
        data;
        // Deallocation moves assets from the adapter into idle liquidity.
        if (availableLiquidity != type(uint256).max) {
            availableLiquidity += assets;
        }
        uint256 penaltyAssets = (assets * forceDeallocatePenaltyBps) / 10_000;
        penaltyShares = previewWithdraw(penaltyAssets);
        if (penaltyShares != 0) {
            // Penalty is paid from onBehalf's shares with the vault as receiver.
            _transfer(onBehalf, address(this), penaltyShares);
        }
    }
}
