// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Aave V3 Sepolia addresses consumed by the dUSDC rehearsal.
///      Source: https://github.com/aave-dao/aave-address-book/blob/main/src/AaveV3Sepolia.sol
library SepoliaExternalAddresses {
    address internal constant AAVE_V3_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal constant AAVE_USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address internal constant AAVE_USDC_ATOKEN = 0x16dA4541aD1807f4443d92D26044C1147406EB80;
    address internal constant AAVE_FAUCET = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D;
}
