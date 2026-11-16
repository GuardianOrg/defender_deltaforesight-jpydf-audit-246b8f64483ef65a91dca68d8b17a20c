// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DToken} from "src/DToken.sol";

/// @dev Isolates yield-layer tests from Core deployment. Lifecycle integration
/// tests use the real AddressesRegistry instead.
contract MockDTokenRegistry {
    address public immutable collToken;
    bool public riskParamsFinalized;

    constructor(address token, bool finalized) {
        collToken = token;
        riskParamsFinalized = finalized;
    }

    function setFinalized(bool finalized) external {
        riskParamsFinalized = finalized;
    }
}

function activateDTokenForTest(DToken token) {
    token.setRiskParamsRegistry(address(new MockDTokenRegistry(address(token), true)));
    token.setCap(type(uint256).max);
}
