// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IPriceFeed.sol";
import "./TestContracts/FreshJpyProvenance.sol";

// =============================================================
//  案件2 (更新): mis-encoded (wrong-ABI) source は全 set-point で拒否される
//
//  背景: Solidity 0.8.24 では「外部呼び出し成功 + 戻り値 ABI デコード失敗」は proxy の
//  try/catch (`catch (bytes memory err)`) に捕捉されず、呼び出し元の外へ revert する
//  (本ファイル下部の mechanism テストで実測固定)。redemption の consumer
//  (CollateralRegistry.redeemCollateral / RedemptionHelper) は各ブランチ feed を
//  try/catch なしでループ呼出するため、1 ブランチに mis-encoded source が設定されると
//  redemption がシステム全体で停止しうる (DoS)。
//
//  対策 (C-1 / C-2): constructor と confirmSource の両方で fetchPrice() / fetchRedemptionPrice()
//  を直呼び smoke-test し、デコード失敗 (= 直呼びで貫通 revert) を fail-closed で弾く。
//  本ファイルは「両 set-point で symmetric / asymmetric な wrong-ABI source を拒否する」ことを固定。
//  (旧版は「mis-encoded source を constructor が通し fetch で brick する」危険挙動を固定していたが、
//   C-2 でその経路自体を塞いだため、本版は拒否されることを固定する。)
// =============================================================

/// @dev 両 fetch が (uint256) しか返さない symmetric wrong-ABI feed。lastGoodPrice は有効。
contract MisEncodedFeed {
    uint256 public lastGoodPrice = 1_000e18;

    // 正規は (uint256, bool) を返すべきところ、(uint256) = 32 byte だけ返す
    function fetchPrice() external pure returns (uint256) {
        return 1_234e18;
    }

    function fetchRedemptionPrice() external pure returns (uint256) {
        return 1_234e18;
    }

    function setLastGoodPrice(uint256 v) external {
        lastGoodPrice = v;
    }
}

/// @dev fetchPrice() は正規 (uint256,bool)、fetchRedemptionPrice() だけ wrong-ABI。
///      = C-1 の核心ケース (片側だけ壊れた source)。旧 confirm は fetchPrice() しか
///      smoke-test せず、これを通過させて切替後に redemption を brick していた。
contract AsymmetricMisEncodedFeed {
    uint256 public lastGoodPrice = 1_000e18;

    function fetchPrice() external pure returns (uint256, bool) {
        return (1_234e18, false);
    }

    // wrong-ABI: (uint256,bool) を期待されるが (uint256) しか返さない
    function fetchRedemptionPrice() external pure returns (uint256) {
        return 1_234e18;
    }
}

/// @dev 正規 source (両 fetch とも (uint256,bool))。confirm 元の initial source 用。
contract GoodFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice = 100_000e18;

    function fetchPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }
}

/// @dev BorrowerOperations スタブ (実セマンティクス: registered priceFeed のみ shutdown 可)
contract MockBO {
    bool public hasBeenShutDown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address p) external {
        registeredPriceFeed = p;
    }

    function shutdownFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        if (hasBeenShutDown) return;
        hasBeenShutDown = true;
    }
}

contract PriceFeedProxyMisEncodedSourceTest is Test {
    MockBO bo;
    GoodFeed good;

    function setUp() public {
        bo = new MockBO();
        good = new GoodFeed();
    }

    function _deployProxy(address src) internal returns (PriceFeedProxy p) {
        p = new PriceFeedProxy(src, address(this), address(bo));
        bo.setRegisteredPriceFeed(address(p));
    }

    // ---------------------------------------------------------
    //  C-2: constructor が wrong-ABI source を拒否 (symmetric / asymmetric)
    // ---------------------------------------------------------

    /// @notice symmetric wrong-ABI (両 fetch とも (uint256)) を constructor が拒否。
    ///         constructor の fetchPrice() smoke-test で decode 失敗が貫通 revert する。
    function test_C2_constructorRejectsSymmetricMisEncoded() public {
        MisEncodedFeed m = new MisEncodedFeed(); // code.length > 0 なので旧 code.length ガードは通過
        vm.expectRevert();
        new PriceFeedProxy(address(m), address(this), address(bo));
    }

    /// @notice asymmetric wrong-ABI (fetchRedemptionPrice だけ壊れ) も constructor が拒否。
    ///         constructor が fetchRedemptionPrice() も smoke-test するため。
    function test_C2_constructorRejectsAsymmetricMisEncoded() public {
        AsymmetricMisEncodedFeed a = new AsymmetricMisEncodedFeed();
        vm.expectRevert();
        new PriceFeedProxy(address(a), address(this), address(bo));
    }

    // ---------------------------------------------------------
    //  C-1: confirmSource が片側 (fetchRedemptionPrice) だけ壊れた source を拒否
    // ---------------------------------------------------------

    /// @notice fetchPrice() は正規だが fetchRedemptionPrice() が wrong-ABI な source への切替を
    ///         confirm が拒否する。旧実装は fetchPrice() のみ smoke-test し通過 →
    ///         切替後に proxy.fetchRedemptionPrice() が貫通 revert → redemption 全停止だった。
    function test_C1_confirmRejectsAsymmetricMisEncoded() public {
        PriceFeedProxy proxy = _deployProxy(address(good));

        AsymmetricMisEncodedFeed a = new AsymmetricMisEncodedFeed();
        proxy.proposeSource(address(a));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert();
        proxy.confirmSource();

        // 切替は revert で拒否され、source は元のまま
        assertEq(proxy.source(), address(good), "source must stay unchanged after rejected switch");
    }

    /// @notice symmetric wrong-ABI への切替も confirm が拒否 (fetchPrice() 側で貫通 revert)。
    function test_C1_confirmRejectsSymmetricMisEncoded() public {
        PriceFeedProxy proxy = _deployProxy(address(good));

        MisEncodedFeed m = new MisEncodedFeed();
        proxy.proposeSource(address(m));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert();
        proxy.confirmSource();

        assertEq(proxy.source(), address(good), "source must stay unchanged after rejected switch");
    }

    // ---------------------------------------------------------
    //  機構の固定: wrong-ABI source は (uint256,bool) に満たない returndata を返す
    // ---------------------------------------------------------

    /// @notice [確定挙動] wrong-ABI source は 32 byte (uint256) しか返さず、(uint256,bool) の
    ///         64 byte に満たない。proxy が期待デコードすると失敗し try/catch を貫通 revert する。
    ///         constructor / confirmSource の直呼び smoke-test は、まさにこの貫通 revert を利用して
    ///         wrong-ABI source を fail-closed で弾く。
    function test_mechanism_misEncodedReturnsTooFewBytes() public {
        MisEncodedFeed m = new MisEncodedFeed();
        (bool ok, bytes memory ret) = address(m).staticcall(abi.encodeWithSignature("fetchPrice()"));
        assertTrue(ok, "call itself succeeds (no revert)");
        assertEq(ret.length, 32, "returns only 32 bytes (uint256), short of (uint256,bool)=64");
    }
}
