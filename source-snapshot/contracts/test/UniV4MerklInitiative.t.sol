// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IDistributionCreator} from "src/Interfaces/IDistributionCreator.sol";
import {IInitiative} from "src/Interfaces/IInitiative.sol";
import {UniV4MerklInitiative} from "src/Initiatives/UniV4MerklInitiative.sol";
import {ERC20Faucet} from "test/TestContracts/ERC20Faucet.sol";

contract MockDistributionCreator is IDistributionCreator {
    bool public acceptedConditions;
    bytes32 public nextCampaignId = keccak256("campaign");
    address public lastCreator;
    address public lastRewardToken;
    uint256 public lastAmount;
    uint32 public lastCampaignType;
    uint32 public lastStartTimestamp;
    uint32 public lastDuration;
    bytes public lastCampaignData;

    function acceptConditions() external override {
        acceptedConditions = true;
    }

    function campaignId(CampaignParameters memory) external view override returns (bytes32) {
        return nextCampaignId;
    }

    function createCampaign(CampaignParameters memory newCampaign) external override returns (bytes32) {
        IERC20(newCampaign.rewardToken).transferFrom(msg.sender, address(this), newCampaign.amount);

        lastCreator = newCampaign.creator;
        lastRewardToken = newCampaign.rewardToken;
        lastAmount = newCampaign.amount;
        lastCampaignType = newCampaign.campaignType;
        lastStartTimestamp = newCampaign.startTimestamp;
        lastDuration = newCampaign.duration;
        lastCampaignData = newCampaign.campaignData;

        return nextCampaignId;
    }
}

contract ReentrantDistributionCreator is IDistributionCreator {
    bool public acceptedConditions;
    bool public attemptedReenter;
    bool public reenterSucceeded;
    bool public reenterReverted;
    bytes32 public nextCampaignId = keccak256("reentrant-campaign");

    function acceptConditions() external override {
        acceptedConditions = true;
    }

    function campaignId(CampaignParameters memory) external view override returns (bytes32) {
        return nextCampaignId;
    }

    function createCampaign(CampaignParameters memory newCampaign) external override returns (bytes32) {
        if (!attemptedReenter) {
            attemptedReenter = true;
            try UniV4MerklInitiative(msg.sender).createCampaign() {
                reenterSucceeded = true;
            } catch {
                reenterReverted = true;
            }
        }

        IERC20(newCampaign.rewardToken).transferFrom(msg.sender, address(this), newCampaign.amount);
        return nextCampaignId;
    }
}

contract UniV4MerklInitiativeTest is Test {
    event NewMerklCampaign(uint256 indexed epoch, uint256 amount, bytes32 campaignId);
    event MerklCampaignAlreadyCreated(
        uint256 indexed epoch, uint256 indexed startTimestamp, uint256 amount, bytes32 campaignId
    );

    uint256 internal constant EPOCH_DURATION = 7 days;
    uint256 internal constant CAMPAIGN_CREATION_WINDOW = 1 days;
    uint256 internal constant THRESHOLD = 100e18;
    bytes32 internal constant POOL_ID = bytes32(uint256(0x1234));

    ERC20Faucet internal token;
    MockDistributionCreator internal merkl;
    UniV4MerklInitiative internal initiative;
    address internal allocator = makeAddr("allocator");
    address internal campaignCreator = makeAddr("campaignCreator");

    function setUp() public {
        token = new ERC20Faucet("JPYdf", "JPYdf", 0, type(uint256).max);
        merkl = new MockDistributionCreator();
        initiative = _newInitiative(merkl);
    }

    function test_ConstructorAcceptsMerklConditions() public view {
        assertTrue(merkl.acceptedConditions(), "conditions accepted");
    }

    function test_RevertWhen_ConstructorArgsInvalid() public {
        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__ZeroAddress.selector);
        new UniV4MerklInitiative(
            address(0),
            token,
            merkl,
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__ZeroAddress.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            address(0),
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__PoolIdZero.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            bytes32(0),
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__InvalidWeights.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_001,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__EpochStartInFuture.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp + 1,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__ZeroCampaignThreshold.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            campaignCreator,
            0,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__InvalidCampaignCreationWindow.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            campaignCreator,
            THRESHOLD,
            0,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(UniV4MerklInitiative.UniV4MerklInitiative__InvalidCampaignCreationWindow.selector);
        new UniV4MerklInitiative(
            allocator,
            token,
            merkl,
            campaignCreator,
            THRESHOLD,
            EPOCH_DURATION,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                UniV4MerklInitiative.UniV4MerklInitiative__DependencyNotContract.selector, address(1)
            )
        );
        new UniV4MerklInitiative(
            allocator,
            IERC20(address(1)),
            merkl,
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                UniV4MerklInitiative.UniV4MerklInitiative__DependencyNotContract.selector, address(2)
            )
        );
        new UniV4MerklInitiative(
            allocator,
            token,
            IDistributionCreator(address(2)),
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );
    }

    function test_CreateCampaignNoopsBelowThreshold() public {
        token.mint(address(initiative), THRESHOLD - 1);

        bytes32 campaignId = initiative.createCampaign();

        assertEq(campaignId, bytes32(0), "no campaign");
        assertEq(token.balanceOf(address(initiative)), THRESHOLD - 1, "balance carried");
        assertEq(token.balanceOf(address(merkl)), 0, "merkl not funded");
    }

    function test_CreateCampaignPullsAmountAndClearsAllowance() public {
        token.mint(address(initiative), 250e18);
        vm.warp(block.timestamp + 2 days);

        // PILA-EVT-005
        vm.expectEmit(true, false, false, true, address(initiative));
        emit NewMerklCampaign(initiative.epoch(), 250e18, merkl.nextCampaignId());
        vm.prank(campaignCreator);
        bytes32 campaignId = initiative.createCampaign();

        assertEq(campaignId, merkl.nextCampaignId(), "campaign id");
        assertEq(token.balanceOf(address(initiative)), 0, "initiative drained");
        assertEq(token.balanceOf(address(merkl)), 250e18, "merkl funded");
        assertEq(token.allowance(address(initiative), address(merkl)), 0, "allowance cleared");
        assertEq(merkl.lastCreator(), address(initiative), "creator");
        assertEq(merkl.lastRewardToken(), address(token), "reward token");
        assertEq(merkl.lastAmount(), 250e18, "amount");
        assertEq(merkl.lastCampaignType(), initiative.CAMPAIGN_TYPE(), "campaign type");
        assertEq(merkl.lastStartTimestamp(), uint32(initiative.epochStart() + EPOCH_DURATION), "next epoch start");
        assertEq(merkl.lastDuration(), uint32(EPOCH_DURATION), "duration");
        assertEq(merkl.lastCampaignData(), initiative.getCampaignData(), "campaign data");
    }

    function test_CreateCampaignRejectsPublicCallerBeforeFallbackWindow() public {
        token.mint(address(initiative), 250e18);
        uint256 earliestPublicCreation = initiative.publicCampaignCreationStart();

        vm.expectRevert(
            abi.encodeWithSelector(
                UniV4MerklInitiative.UniV4MerklInitiative__CampaignCreationTooEarly.selector, earliestPublicCreation
            )
        );
        initiative.createCampaign();
    }

    function test_CreateCampaignAllowsPublicCallerInsideFallbackWindow() public {
        token.mint(address(initiative), 250e18);
        vm.warp(initiative.publicCampaignCreationStart());

        bytes32 campaignId = initiative.createCampaign();

        assertEq(campaignId, merkl.nextCampaignId(), "campaign id");
        assertEq(token.balanceOf(address(merkl)), 250e18, "merkl funded");
    }

    function test_CanCreateCampaignReflectsBalanceWindowAndExistingCampaign() public {
        assertFalse(initiative.canCreateCampaign(campaignCreator), "below threshold");

        token.mint(address(initiative), 250e18);
        assertTrue(initiative.canCreateCampaign(campaignCreator), "creator allowed");
        assertFalse(initiative.canCreateCampaign(address(this)), "public too early");

        vm.warp(initiative.publicCampaignCreationStart());
        assertTrue(initiative.canCreateCampaign(address(this)), "public fallback allowed");

        initiative.createCampaign();
        assertFalse(initiative.canCreateCampaign(campaignCreator), "campaign already created");
    }

    function test_CreateCampaignNoopsAfterCampaignForStartExists() public {
        token.mint(address(initiative), 250e18);

        uint256 campaignStart = initiative.epochStart() + EPOCH_DURATION;
        vm.prank(campaignCreator);
        bytes32 firstCampaignId = initiative.createCampaign();
        assertEq(initiative.campaignIdByStartTimestamp(campaignStart), firstCampaignId, "campaign tracked");

        token.mint(address(initiative), 500e18);
        // PILA-EVT-005: the duplicate-suppression branch reports the existing campaign.
        vm.expectEmit(true, true, false, true, address(initiative));
        emit MerklCampaignAlreadyCreated(initiative.epoch(), campaignStart, 500e18, firstCampaignId);
        bytes32 secondCampaignId = initiative.createCampaign();

        assertEq(secondCampaignId, bytes32(0), "same start noops");
        assertEq(token.balanceOf(address(initiative)), 500e18, "later funds carried");
        assertEq(token.balanceOf(address(merkl)), 250e18, "no second pull");
        assertEq(token.allowance(address(initiative), address(merkl)), 0, "allowance remains zero");

        vm.warp(block.timestamp + EPOCH_DURATION);
        vm.prank(campaignCreator);
        bytes32 nextCampaignId = initiative.createCampaign();

        assertEq(nextCampaignId, merkl.nextCampaignId(), "next start campaign id");
        assertEq(token.balanceOf(address(initiative)), 0, "carried funds campaigned");
        assertEq(token.balanceOf(address(merkl)), 750e18, "merkl funded twice");
    }

    function test_CreateCampaignBlocksReentrantMerklCallback() public {
        ReentrantDistributionCreator reentrantMerkl = new ReentrantDistributionCreator();
        UniV4MerklInitiative reentrantInitiative = _newInitiative(reentrantMerkl);
        token.mint(address(reentrantInitiative), 250e18);

        vm.prank(campaignCreator);
        bytes32 campaignId = reentrantInitiative.createCampaign();

        assertEq(campaignId, reentrantMerkl.nextCampaignId(), "campaign id");
        assertTrue(reentrantMerkl.attemptedReenter(), "reentered");
        assertTrue(reentrantMerkl.reenterReverted(), "reenter blocked");
        assertFalse(reentrantMerkl.reenterSucceeded(), "reenter did not succeed");
        assertEq(token.balanceOf(address(reentrantInitiative)), 0, "initiative drained once");
        assertEq(token.balanceOf(address(reentrantMerkl)), 250e18, "merkl funded once");
        assertEq(token.allowance(address(reentrantInitiative), address(reentrantMerkl)), 0, "allowance cleared");
    }

    function test_GetCampaignDataUsesEmptyWhitelistBlacklistAndHooks() public view {
        bytes memory expected = bytes.concat(
            abi.encode(416, false, uint32(5_000), uint32(2_500), uint32(2_500), 480, 512, 544),
            abi.encode(0, 0, 0, 0, 576, 32, POOL_ID, 0, 0, 0, 0)
        );

        assertEq(initiative.getCampaignData(), expected, "campaign data");
    }

    function test_HooksAreNoopAndPhaseBReusable() public {
        IInitiative.UserState memory userState;
        IInitiative.Allocation memory allocation;
        IInitiative.InitiativeState memory initiativeState;

        initiative.onRegisterInitiative(1);
        initiative.onUnregisterInitiative(2);
        initiative.onClaimForInitiative(3, 4);
        initiative.onAfterAllocateLQTY(5, address(this), userState, allocation, initiativeState);
    }

    function _newInitiative(IDistributionCreator distributionCreator)
        internal
        returns (UniV4MerklInitiative newInitiative)
    {
        newInitiative = new UniV4MerklInitiative(
            allocator,
            token,
            distributionCreator,
            campaignCreator,
            THRESHOLD,
            CAMPAIGN_CREATION_WINDOW,
            POOL_ID,
            5_000,
            2_500,
            2_500,
            block.timestamp,
            EPOCH_DURATION
        );
    }
}
