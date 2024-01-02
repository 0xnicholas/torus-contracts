
pragma solidity ^0.8.23;

import "solmate/tokens/ERC20.sol";

interface IVault {


    enum UserBalanceOpKind {
        DEPOSIT_INTERNAL,
        WITHDRAW_INTERNAL,
        TRANSFER_INTERNAL,
        TRANSFER_EXTERNAL
    }

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct UserBalanceOp {
        UserBalanceOpKind kind;
        ERC20 asset;
        uint256 amount;
        address sender;
        address payable recipient;
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        ERC20 assetIn;
        ERC20 assetOut;
        uint256 amount;
        bytes userData;
    }

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 aseetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }


    function manageUserBalance(UserBalanceOp[] memory ops) external payable;

    function swap(
        SingleSwap memory singleSwap, 
        FundManagement memory funds, 
        uint256 limit, 
        uint256 deadline
    ) external payable return (uint256);

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        ERC20[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);

}