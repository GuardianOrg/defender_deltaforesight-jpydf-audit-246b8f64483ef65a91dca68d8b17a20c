// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {IInitiative} from "src/Interfaces/IInitiative.sol";
import {JpydfToken} from "src/JpydfToken.sol";
import {PILAllocator} from "src/PILAllocator.sol";

contract MockBridgeAdmin {}

contract MockCoreContract {}

contract MockActivePoolMinter {
    function mint(JpydfToken token, address account, uint256 amount) external {
        token.mint(account, amount);
    }
}

contract MockInitiative is IInitiative {
    uint256 public registeredAt;
    uint256 public unregisteredAt;
    uint256 public lastClaimEpoch;
    uint256 public totalClaimed;
    uint256 public claimCalls;
    bool public revertClaimHook;

    function setRevertClaimHook(bool value) external {
        revertClaimHook = value;
    }

    function onRegisterInitiative(uint256 atEpoch) external override {
        registeredAt = atEpoch;
    }

    function onUnregisterInitiative(uint256 atEpoch) external override {
        unregisteredAt = atEpoch;
    }

    function onAfterAllocateLQTY(
        uint256,
        address,
        IInitiative.UserState calldata,
        IInitiative.Allocation calldata,
        IInitiative.InitiativeState calldata
    ) external override {}

    function onClaimForInitiative(uint256 claimEpoch, uint256 amount) external override {
        if (revertClaimHook) revert("claim hook failed");

        lastClaimEpoch = claimEpoch;
        totalClaimed += amount;
        claimCalls++;
    }
}

contract ReentrantClaimInitiative is IInitiative {
    PILAllocator public immutable allocator;
    bool public attemptedReenter;
    bool public reenterSucceeded;
    bool public reenterReverted;

    constructor(PILAllocator _allocator) {
        allocator = _allocator;
    }

    function onRegisterInitiative(uint256) external override {}

    function onUnregisterInitiative(uint256) external override {}

    function onAfterAllocateLQTY(
        uint256,
        address,
        IInitiative.UserState calldata,
        IInitiative.Allocation calldata,
        IInitiative.InitiativeState calldata
    ) external override {}

    function onClaimForInitiative(uint256, uint256) external override {
        if (attemptedReenter) return;

        attemptedReenter = true;
        try allocator.distribute() {
            reenterSucceeded = true;
        } catch {
            reenterReverted = true;
        }
    }
}

contract RevertBombInitiative is IInitiative {
    function onRegisterInitiative(uint256) external override {}

    function onUnregisterInitiative(uint256) external override {}

    function onAfterAllocateLQTY(
        uint256,
        address,
        IInitiative.UserState calldata,
        IInitiative.Allocation calldata,
        IInitiative.InitiativeState calldata
    ) external override {}

    function onClaimForInitiative(uint256, uint256) external pure override {
        assembly {
            revert(0, 0x100000)
        }
    }
}

contract PILAllocatorTest is Test {
    uint256 internal constant EPOCH_DURATION = 7 days;
    uint256 internal constant MIN_DISTRIBUTE = 1e18;

    event Distributed(address indexed initiative, uint256 amount, uint256 indexed epoch, bool hookSucceeded);
    event InitiativeRegistered(address indexed initiative, uint256 atEpoch, bool hookSucceeded);
    event InitiativeUnregistered(address indexed initiative, uint256 atEpoch, bool hookSucceeded);
    event WeightsUpdated(address[] initiatives, uint256[] weights);
    event Paused();
    event Unpaused();
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);

    JpydfToken internal token;
    PILAllocator internal allocator;
    MockActivePoolMinter internal activePoolMinter;
    MockInitiative internal initiativeA;
    MockInitiative internal initiativeB;

    address internal owner = makeAddr("owner");
    address internal guardian = makeAddr("guardian");

    function setUp() public {
        token = new JpydfToken(address(this), address(new MockBridgeAdmin()));

        activePoolMinter = new MockActivePoolMinter();
        token.setBranchAddresses(
            address(new MockCoreContract()),
            address(new MockCoreContract()),
            address(new MockCoreContract()),
            address(activePoolMinter)
        );

        allocator = new PILAllocator(token, block.timestamp, EPOCH_DURATION, MIN_DISTRIBUTE, owner, guardian);
        initiativeA = new MockInitiative();
        initiativeB = new MockInitiative();
    }

    function test_RegisterInitiativeValidatesJpydfRecipientAndCallsHook() public {
        // PILA-EVT-001
        vm.expectEmit(true, false, false, true, address(allocator));
        emit InitiativeRegistered(address(initiativeA), allocator.epoch(), true);
        vm.prank(owner);
        allocator.registerInitiative(address(initiativeA));

        assertTrue(allocator.registeredInitiatives(address(initiativeA)), "registered");
        assertEq(allocator.initiativeCount(), 1, "count");
        assertEq(allocator.initiativeAt(0), address(initiativeA), "stored");
        assertEq(initiativeA.registeredAt(), allocator.epoch(), "hook epoch");
    }

    function test_RevertWhen_RegisteringInvalidJpydfRecipient() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PILAllocator.PILAllocator__InvalidJpydfRecipient.selector, address(activePoolMinter))
        );
        allocator.registerInitiative(address(activePoolMinter));
    }

    function test_RevertWhen_ConstructorTokenIsNotContract() public {
        vm.expectRevert(abi.encodeWithSelector(PILAllocator.PILAllocator__DependencyNotContract.selector, address(1)));
        new PILAllocator(JpydfToken(address(1)), block.timestamp, EPOCH_DURATION, MIN_DISTRIBUTE, owner, guardian);
    }

    function test_RevertWhen_ConstructorMinDistributeIsZero() public {
        vm.expectRevert(PILAllocator.PILAllocator__ZeroMinDistribute.selector);
        new PILAllocator(token, block.timestamp, EPOCH_DURATION, 0, owner, guardian);
    }

    function test_RevertWhen_RegisteringMoreThanMaxInitiatives() public {
        uint256 maxInitiatives = allocator.MAX_INITIATIVES();

        vm.startPrank(owner);
        for (uint256 i; i < maxInitiatives; ++i) {
            allocator.registerInitiative(address(uint160(0x1000 + i)));
        }

        vm.expectRevert(abi.encodeWithSelector(PILAllocator.PILAllocator__TooManyInitiatives.selector, maxInitiatives));
        allocator.registerInitiative(address(uint160(0x2000)));
        vm.stopPrank();

        assertEq(allocator.initiativeCount(), maxInitiatives, "count capped");
    }

    function test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight() public {
        _registerTwoInitiatives();

        address[] memory initiatives = new address[](2);
        initiatives[0] = address(initiativeA);
        initiatives[1] = address(initiativeA);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PILAllocator.PILAllocator__DuplicateInitiative.selector, address(initiativeA))
        );
        allocator.setWeights(initiatives, weights);

        initiatives[1] = address(initiativeB);
        weights[1] = 0.6e18;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PILAllocator.PILAllocator__InvalidTotalWeight.selector, 1.1e18));
        allocator.setWeights(initiatives, weights);

        weights[1] = 0.25e18;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PILAllocator.PILAllocator__InvalidTotalWeight.selector, 0.75e18));
        allocator.setWeights(initiatives, weights);
    }

    function test_SetWeightsCanDeactivateBySettingAllWeightsZero() public {
        _registerTwoInitiatives();
        _setTwoWeights(0.4e18, 0.6e18);

        // PILA-EVT-003: the deactivating update carries both initiatives at weight 0.
        address[] memory expectedInitiatives = new address[](2);
        expectedInitiatives[0] = address(initiativeA);
        expectedInitiatives[1] = address(initiativeB);
        uint256[] memory expectedWeights = new uint256[](2);
        vm.expectEmit(false, false, false, true, address(allocator));
        emit WeightsUpdated(expectedInitiatives, expectedWeights);
        _setTwoWeights(0, 0);

        assertEq(allocator.totalWeight(), 0, "inactive");
        assertEq(allocator.weightOf(address(initiativeA)), 0, "initiative A");
        assertEq(allocator.weightOf(address(initiativeB)), 0, "initiative B");
    }

    function test_DistributePushesByFullWeightAndRepeatedCallNoops() public {
        _registerTwoInitiatives();
        _setTwoWeights(0.4e18, 0.6e18);
        activePoolMinter.mint(token, address(allocator), 1_000e18);

        uint256 distributed = allocator.distribute();

        assertEq(distributed, 1_000e18, "distributed");
        assertEq(token.balanceOf(address(initiativeA)), 400e18, "initiative A");
        assertEq(token.balanceOf(address(initiativeB)), 600e18, "initiative B");
        assertEq(token.balanceOf(address(allocator)), 0, "no carry over");
        assertEq(initiativeA.totalClaimed(), 400e18, "hook A");
        assertEq(initiativeB.totalClaimed(), 600e18, "hook B");
        assertEq(allocator.pendingDistributable(), 0, "no pending");
        assertEq(allocator.distribute(), 0, "second call noops");
    }

    function test_DistributeReturnsZeroWhenBelowThresholdOrNoWeights() public {
        vm.prank(owner);
        allocator.registerInitiative(address(initiativeA));
        activePoolMinter.mint(token, address(allocator), MIN_DISTRIBUTE - 1);

        assertEq(allocator.distribute(), 0, "below threshold");
        assertEq(token.balanceOf(address(allocator)), MIN_DISTRIBUTE - 1, "kept");

        activePoolMinter.mint(token, address(allocator), 1);
        assertEq(allocator.distribute(), 0, "no weights");
        assertEq(token.balanceOf(address(allocator)), MIN_DISTRIBUTE, "still kept");
    }

    function test_DistributeIsolatesFailingHookAfterTransfer() public {
        _registerTwoInitiatives();
        _setTwoWeights(0.5e18, 0.5e18);
        initiativeA.setRevertClaimHook(true);
        activePoolMinter.mint(token, address(allocator), 10e18);

        vm.expectEmit(true, true, false, true, address(allocator));
        emit Distributed(address(initiativeA), 5e18, allocator.epoch(), false);
        vm.expectEmit(true, true, false, true, address(allocator));
        emit Distributed(address(initiativeB), 5e18, allocator.epoch(), true);
        uint256 distributed = allocator.distribute();

        assertEq(distributed, 10e18, "distributed");
        assertEq(token.balanceOf(address(initiativeA)), 5e18, "failing hook still funded");
        assertEq(token.balanceOf(address(initiativeB)), 5e18, "next initiative funded");
        assertEq(initiativeA.claimCalls(), 0, "failing hook rolled back");
        assertEq(initiativeB.claimCalls(), 1, "second hook called");
    }

    function test_DistributeIsolatesRevertBombHookAfterTransfer() public {
        RevertBombInitiative revertBomb = new RevertBombInitiative();

        vm.startPrank(owner);
        allocator.registerInitiative(address(revertBomb));
        allocator.registerInitiative(address(initiativeB));
        vm.stopPrank();

        address[] memory initiatives = new address[](2);
        initiatives[0] = address(revertBomb);
        initiatives[1] = address(initiativeB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
        vm.prank(owner);
        allocator.setWeights(initiatives, weights);

        activePoolMinter.mint(token, address(allocator), 10e18);

        uint256 distributed = allocator.distribute();

        assertEq(distributed, 10e18, "distributed");
        assertEq(token.balanceOf(address(revertBomb)), 5e18, "revert bomb still funded");
        assertEq(token.balanceOf(address(initiativeB)), 5e18, "second initiative funded");
        assertEq(initiativeB.claimCalls(), 1, "second hook called");
    }

    function test_DistributeBlocksReentrantHookAndContinues() public {
        ReentrantClaimInitiative reentrant = new ReentrantClaimInitiative(allocator);

        vm.startPrank(owner);
        allocator.registerInitiative(address(reentrant));
        allocator.registerInitiative(address(initiativeB));
        vm.stopPrank();

        address[] memory initiatives = new address[](2);
        initiatives[0] = address(reentrant);
        initiatives[1] = address(initiativeB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
        vm.prank(owner);
        allocator.setWeights(initiatives, weights);

        activePoolMinter.mint(token, address(allocator), 10e18);

        uint256 distributed = allocator.distribute();

        assertEq(distributed, 10e18, "distributed");
        assertTrue(reentrant.attemptedReenter(), "reenter attempted");
        assertTrue(reentrant.reenterReverted(), "reenter blocked");
        assertFalse(reentrant.reenterSucceeded(), "reenter did not succeed");
        assertEq(token.balanceOf(address(reentrant)), 5e18, "reentrant still funded");
        assertEq(token.balanceOf(address(initiativeB)), 5e18, "second initiative funded");
        assertEq(initiativeB.claimCalls(), 1, "second hook called");
    }

    function test_PauseUnpauseAndOwnership() public {
        // PILA-EVT-006
        vm.expectEmit(false, false, false, true, address(allocator));
        emit Paused();
        vm.prank(guardian);
        allocator.pause();

        vm.expectRevert(PILAllocator.PILAllocator__Paused.selector);
        allocator.distribute();

        vm.expectEmit(false, false, false, true, address(allocator));
        emit Unpaused();
        vm.prank(owner);
        allocator.unpause();

        address nextOwner = makeAddr("nextOwner");
        vm.prank(owner);
        allocator.transferOwnership(nextOwner);
        assertEq(allocator.pendingOwner(), nextOwner, "pending owner");

        vm.prank(nextOwner);
        allocator.acceptOwnership();
        assertEq(allocator.owner(), nextOwner, "accepted owner");

        vm.prank(nextOwner);
        vm.expectRevert(PILAllocator.PILAllocator__RenounceOwnershipDisabled.selector);
        allocator.renounceOwnership();
    }

    function test_GuardianCanBeUpdatedByOwner() public {
        address nextGuardian = makeAddr("nextGuardian");

        // PILA-EVT-007
        vm.expectEmit(true, true, false, true, address(allocator));
        emit GuardianUpdated(guardian, nextGuardian);
        vm.prank(owner);
        allocator.setGuardian(nextGuardian);

        vm.prank(guardian);
        vm.expectRevert(PILAllocator.PILAllocator__Unauthorized.selector);
        allocator.pause();

        vm.prank(nextGuardian);
        allocator.pause();
        assertTrue(allocator.paused(), "paused by new guardian");
    }

    function test_TransferOwnershipZeroCancelsPendingOwner() public {
        address nextOwner = makeAddr("nextOwner");

        vm.prank(owner);
        allocator.transferOwnership(nextOwner);
        assertEq(allocator.pendingOwner(), nextOwner, "pending owner");

        vm.prank(owner);
        allocator.transferOwnership(address(0));
        assertEq(allocator.pendingOwner(), address(0), "pending owner cleared");

        vm.prank(nextOwner);
        vm.expectRevert(PILAllocator.PILAllocator__Unauthorized.selector);
        allocator.acceptOwnership();
    }

    function test_UnregisterRemovesWeightAndInitiative() public {
        _registerTwoInitiatives();
        _setTwoWeights(0.4e18, 0.6e18);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                PILAllocator.PILAllocator__InitiativeHasWeight.selector, address(initiativeA), 0.4e18
            )
        );
        allocator.unregisterInitiative(address(initiativeA));

        _setTwoWeights(0, 1e18);

        // PILA-EVT-002
        vm.expectEmit(true, false, false, true, address(allocator));
        emit InitiativeUnregistered(address(initiativeA), allocator.epoch(), true);
        vm.prank(owner);
        allocator.unregisterInitiative(address(initiativeA));

        assertFalse(allocator.registeredInitiatives(address(initiativeA)), "unregistered");
        assertEq(allocator.totalWeight(), 1e18, "weight preserved");
        assertEq(allocator.initiativeCount(), 1, "count");
        assertEq(initiativeA.unregisteredAt(), allocator.epoch(), "hook epoch");
    }

    function _registerTwoInitiatives() internal {
        vm.startPrank(owner);
        allocator.registerInitiative(address(initiativeA));
        allocator.registerInitiative(address(initiativeB));
        vm.stopPrank();
    }

    function _setTwoWeights(uint256 weightA, uint256 weightB) internal {
        address[] memory initiatives = new address[](2);
        initiatives[0] = address(initiativeA);
        initiatives[1] = address(initiativeB);

        uint256[] memory weights = new uint256[](2);
        weights[0] = weightA;
        weights[1] = weightB;

        vm.prank(owner);
        allocator.setWeights(initiatives, weights);
    }
}
