// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "src/Interfaces/IPriceFeed.sol";

interface IPriceFeedTestnet is IPriceFeed {
    function setPrice(uint256 _price) external returns (bool);
    function setUrgentRedemptionPrice(uint256 _price) external;
    function setOracleFailure(bool _oracleFailure) external;
    function setRedemptionOracleFailure(bool _oracleFailure) external;
    function getPrice() external view returns (uint256);
}
