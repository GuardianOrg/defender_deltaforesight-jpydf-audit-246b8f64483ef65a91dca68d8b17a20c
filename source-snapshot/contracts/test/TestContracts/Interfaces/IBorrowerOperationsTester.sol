// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/Interfaces/IBorrowerOperations.sol";
import "src/Interfaces/IJpydfToken.sol";
import "src/Interfaces/ISortedTroves.sol";

interface IBorrowerOperationsTester is IBorrowerOperations {
    function getCollToken() external view returns (IERC20);
    function getSortedTroves() external view returns (ISortedTroves);
    function getJpydfToken() external view returns (IJpydfToken);

    function applyPendingDebt(uint256 _troveId) external;
    function getNewTCRFromTroveChange(
        uint256 _collChange,
        bool isCollIncrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        uint256 _price
    ) external view returns (uint256);
}
