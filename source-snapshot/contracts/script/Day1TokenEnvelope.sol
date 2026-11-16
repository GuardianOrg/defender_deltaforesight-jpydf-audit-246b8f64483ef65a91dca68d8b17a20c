// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @dev Shared mainnet gate for Day-1 dToken caps and Vault allocation limits.
///      The Owner Decision records nominal JPY limits, while the on-chain setters consume
///      dToken units (18 decimals) and Underlying units (Underlying decimals), respectively.
abstract contract Day1TokenEnvelope is Script {
    uint256 internal constant MAINNET_CHAIN_ID = 1;
    bytes32 private constant APPROVED_EVIDENCE_CLASSIFICATION = keccak256("APPROVED_FOR_MAINNET_BROADCAST");
    bytes32 private constant TEST_ONLY_EVIDENCE_CLASSIFICATION =
        keccak256("TEST_ONLY_NOT_APPROVED_FOR_MAINNET_BROADCAST");
    bytes32 private constant LOCAL_FORK_TEST_ONLY_OVERRIDE = keccak256("LOCAL_MAINNET_FORK_ONLY");
    address private constant LOCAL_FORK_SENTINEL = 0x0000000000000000000000000000000000001455;
    bytes32 private constant LOCAL_FORK_SENTINEL_CODEHASH = keccak256(hex"60006000fd");
    uint256 internal constant DAY1_NOMINAL_CAP_JPY_WAD_BRANCH_0 = 35_000_000e18;
    uint256 internal constant DAY1_NOMINAL_CAP_JPY_WAD_BRANCH_1 = 100_000_000e18;
    uint256 internal constant DAY1_NOMINAL_ALLOCATE_JPY_WAD_BRANCH_0 = 0;
    uint256 internal constant DAY1_NOMINAL_ALLOCATE_JPY_WAD_BRANCH_1 = 100_000_000e18;

    function _requireMainnetDay1Envelope(
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals,
        uint256 cap,
        uint256 allocateMaxMove
    ) internal view {
        if (block.chainid != MAINNET_CHAIN_ID) return;

        string memory evidencePath = vm.envString("DF_DTOKEN_CAP_CONVERSION");
        _requireMainnetDay1EnvelopeFromEvidence(
            vm.readFile(evidencePath), branchIndex, dToken, underlying, underlyingDecimals, cap, allocateMaxMove
        );
    }

    function _requireMainnetDay1EnvelopeFromEvidence(
        string memory evidence,
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals,
        uint256 cap,
        uint256 allocateMaxMove
    ) internal view {
        require(cap != type(uint256).max, "DF Day-1: cap unlimited");
        require(allocateMaxMove != type(uint256).max, "DF Day-1: allocate unlimited");
        _requireEvidenceHeader(evidence);

        string memory branchPath = string.concat(".branches[", vm.toString(branchIndex), "]");
        _requireEvidenceBranchMetadata(evidence, branchPath, branchIndex, dToken, underlying, underlyingDecimals);
        (uint256 computedCap, uint256 computedAllocateMaxMove) =
            _computedDay1Values(evidence, branchPath, branchIndex, underlyingDecimals);
        require(cap == computedCap, "DF Day-1: cap != converted value");
        require(allocateMaxMove == computedAllocateMaxMove, "DF Day-1: allocate != converted value");
    }

    function _requireEvidenceHeader(string memory evidence) private view {
        require(vm.parseJsonUint(evidence, ".schemaVersion") == 1, "DF Day-1: evidence schema");
        require(vm.parseJsonUint(evidence, ".chainId") == MAINNET_CHAIN_ID, "DF Day-1: evidence chain");
        _requireEvidenceClassification(evidence);
        require(vm.parseJsonUint(evidence, ".forkBlock") != 0, "DF Day-1: evidence block");
        require(bytes(vm.parseJsonString(evidence, ".capturedAt")).length != 0, "DF Day-1: evidence time");
        uint256 capturedAtUnix = vm.parseJsonUint(evidence, ".capturedAtUnix");
        uint256 validUntil = vm.parseJsonUint(evidence, ".validUntil");
        require(capturedAtUnix <= block.timestamp, "DF Day-1: evidence from future");
        require(validUntil >= capturedAtUnix, "DF Day-1: invalid validity window");
        require(validUntil - capturedAtUnix <= 1 days, "DF Day-1: validity exceeds 24h");
        require(block.timestamp <= validUntil, "DF Day-1: evidence expired");
    }

    function _requireEvidenceClassification(string memory evidence) private view {
        bytes32 classification = keccak256(bytes(vm.parseJsonString(evidence, ".classification")));
        if (classification == APPROVED_EVIDENCE_CLASSIFICATION) return;

        require(classification == TEST_ONLY_EVIDENCE_CLASSIFICATION, "DF Day-1: evidence classification");
        require(
            keccak256(bytes(vm.envOr("DF_ALLOW_TEST_ONLY_CAP_CONVERSION", string(""))))
                == LOCAL_FORK_TEST_ONLY_OVERRIDE,
            "DF Day-1: test-only evidence"
        );
        require(LOCAL_FORK_SENTINEL.codehash == LOCAL_FORK_SENTINEL_CODEHASH, "DF Day-1: local fork sentinel");
    }

    function _requireEvidenceBranchMetadata(
        string memory evidence,
        string memory branchPath,
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals
    ) private pure {
        require(
            vm.parseJsonUint(evidence, string.concat(branchPath, ".branchIndex")) == branchIndex,
            "DF Day-1: evidence branch"
        );
        require(
            vm.parseJsonAddress(evidence, string.concat(branchPath, ".dToken")) == dToken, "DF Day-1: evidence dToken"
        );
        require(
            vm.parseJsonAddress(evidence, string.concat(branchPath, ".underlying")) == underlying,
            "DF Day-1: evidence underlying"
        );
        require(
            vm.parseJsonUint(evidence, string.concat(branchPath, ".underlyingDecimals")) == underlyingDecimals,
            "DF Day-1: evidence decimals"
        );
        require(
            keccak256(bytes(vm.parseJsonString(evidence, string.concat(branchPath, ".rounding"))))
                == keccak256("floor"),
            "DF Day-1: evidence rounding"
        );
        require(
            vm.parseJsonBool(evidence, string.concat(branchPath, ".backingRatioExcluded")),
            "DF Day-1: backing ratio included"
        );
        require(
            bytes(vm.parseJsonString(evidence, string.concat(branchPath, ".priceSource"))).length != 0,
            "DF Day-1: evidence price source"
        );
        require(
            bytes(vm.parseJsonString(evidence, string.concat(branchPath, ".riskOwnerSignoff"))).length != 0,
            "DF Day-1: risk sign-off"
        );
        require(
            bytes(vm.parseJsonString(evidence, string.concat(branchPath, ".deployReviewerSignoff"))).length != 0,
            "DF Day-1: deploy sign-off"
        );
    }

    function _computedDay1Values(
        string memory evidence,
        string memory branchPath,
        uint256 branchIndex,
        uint8 underlyingDecimals
    ) private pure returns (uint256 computedCap, uint256 computedAllocateMaxMove) {
        (uint256 nominalCapJpyWad, uint256 nominalAllocateJpyWad) = _day1NominalEnvelope(branchIndex);
        require(
            _parseUintString(evidence, string.concat(branchPath, ".nominalCapJpyWad")) == nominalCapJpyWad,
            "DF Day-1: nominal cap"
        );
        require(
            _parseUintString(evidence, string.concat(branchPath, ".nominalAllocateMaxMoveJpyWad"))
                == nominalAllocateJpyWad,
            "DF Day-1: nominal allocate"
        );

        uint256 priceJpyPerUnderlyingWad =
            _parseUintString(evidence, string.concat(branchPath, ".priceJpyPerUnderlyingWad"));
        require(priceJpyPerUnderlyingWad != 0, "DF Day-1: zero price");

        computedCap = Math.mulDiv(nominalCapJpyWad, 1e18, priceJpyPerUnderlyingWad);
        computedAllocateMaxMove = Math.mulDiv(nominalAllocateJpyWad, 10 ** underlyingDecimals, priceJpyPerUnderlyingWad);
        require(
            _parseUintString(evidence, string.concat(branchPath, ".computedDTokenCap")) == computedCap,
            "DF Day-1: evidence cap calculation"
        );
        require(
            _parseUintString(evidence, string.concat(branchPath, ".computedAllocateMaxMove"))
                == computedAllocateMaxMove,
            "DF Day-1: evidence allocate calculation"
        );
    }

    function _day1NominalEnvelope(uint256 branchIndex)
        internal
        pure
        returns (uint256 nominalCapJpyWad, uint256 nominalAllocateJpyWad)
    {
        if (branchIndex == 0) {
            return (DAY1_NOMINAL_CAP_JPY_WAD_BRANCH_0, DAY1_NOMINAL_ALLOCATE_JPY_WAD_BRANCH_0);
        }
        if (branchIndex == 1) {
            return (DAY1_NOMINAL_CAP_JPY_WAD_BRANCH_1, DAY1_NOMINAL_ALLOCATE_JPY_WAD_BRANCH_1);
        }
        revert("DF Day-1: no nominal envelope");
    }

    function _parseUintString(string memory json, string memory key) private pure returns (uint256) {
        return vm.parseUint(vm.parseJsonString(json, key));
    }
}
