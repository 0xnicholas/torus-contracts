
pragma solidity ^0.8.23;

import "solmate/tokens/ERC20.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVault.sol";
import "./Order.sol";

library Transfer {

    using SafeERC20 for ERC20;

    struct Data {
        address account;
        ERC20 token;
        uint256 amount;
        bytes32 balance;
    }

    // Ether marker address used to indicate an Ether transfer.
    address internal constant BUY_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// Execute the specified transfer from the specified account to a
    /// recipient. The recipient will either receive internal Vault balances or
    /// ERC20 token balances depending on whether the account is using internal
    /// balances or not.
    function fastTransferFromAccount(IVault vault, Data calldata transfer, address recipient) internal {
        require(
            address(transfer.token) != BUY_ETH_ADDRESS,
            "Torus: cannot transfer native ETH"
        );

        if (transfer.balance == Order.BALANCE_ERC20) {
            transfer.token.safeTransferFrom(transfer.account, recipient, transfer.amount);
        } else {
            IVault.UserBalanceOp[] memory balanceOps = new IVault.UserBalanceOp[](1);

            IVault.UserBalanceOp memory balanceOp = balanceOps[0];

            balanceOp.kind = transfer.balance == Order.BALANCE_EXTERNAL
                ? IVault.UserBalanceOpKind.TRANSFER_EXTERNAL
                : IVault.UserBalanceOpKind.TRANSFER_INTERNAL;
            balanceOp.asset = transfer.token;
            balanceOp.amount = transfer.amount;
            balanceOp.sender = transfer.account;
            balanceOp.recipient = payable(recipient);

            vault.manageUserBalance(balanceOps);
        }

    }

    /// Execute the specified transfers from the specified accounts to a
    /// single recipient. The recipient will receive all transfers as ERC20
    /// token balances, regardless of whether or not the accounts are using
    /// internal Vault balances.
    function transferFromAccounts(IVault vault, Data[] calldata transfers, address recipient) internal {
        IVault.UserBalanceOp[] memory balanceOps = new IVault.UserBalanceOp[](transfers.length);

        uint256 balanceOpCount = 0;

        for (uint256 i = 0; i < transfers.length; i++) {
            Data calldata transfer = transfers[i];
            require(
                address(transfer.token) != BUY_ETH_ADDRESS,
                "Torus: cannot transfer native ETH"
            );

            if (transfer.balance == Order.BALANCE_ERC20) {
                transfer.token.safeTransferFrom(transfer.account, recipient, transfer.amount);
            } else {
                IVault.UserBalanceOp memory balanceOp = balanceOps[balanceOpCount++];
                balanceOp.kind = transfer.balance == Order.BALANCE_EXTERNAL
                    ? IVault.UserBalanceOpKind.TRANSFER_EXTERNAL
                    : IVault.UserBalanceOpKind.TRANSFER_INTERNAL;
                balanceOp.asset = transfer.token;
                balanceOp.amount = transfer.amount;
                balanceOp.sender = transfer.account;
                balanceOp.recipient = payable(recipient);
            }
        }

        if (balanceOpCount > 0) {
            truncateBalanceOpsArray(balanceOps, balanceOpCount);
            vault.manageUserBalance(balanceOps);
        }
    }

    /// Execute the specified transfers to their respective accounts.
    function transferToAccounts(IVault vault, Data[] memory transfers) internal {
        IVault.UserBalanceOp[] memory balanceOps = new IVault.UserBalanceOp[](
            transfers.length
        );
        uint256 balanceOpCount = 0;

        for (uint256 i = 0; i < transfers.length; i++) {
                Data memory transfer = transfers[i];

                if (address(transfer.token) == BUY_ETH_ADDRESS) {
                    require(
                        transfer.balance != GPv2Order.BALANCE_INTERNAL,
                        "Torus: unsupported internal ETH"
                    );
                    payable(transfer.account).transfer(transfer.amount);
                } else if (transfer.balance == GPv2Order.BALANCE_ERC20) {
                    transfer.token.safeTransfer(transfer.account, transfer.amount);
                } else {
                    IVault.UserBalanceOp memory balanceOp = balanceOps[
                        balanceOpCount++
                    ];
                    balanceOp.kind = IVault.UserBalanceOpKind.DEPOSIT_INTERNAL;
                    balanceOp.asset = transfer.token;
                    balanceOp.amount = transfer.amount;
                    balanceOp.sender = address(this);
                    balanceOp.recipient = payable(transfer.account);
                }
            }

        if (balanceOpCount > 0) {
            truncateBalanceOpsArray(balanceOps, balanceOpCount);
            vault.manageUserBalance(balanceOps);
        }
    }

    function truncateBalanceOpsArray(
        IVault.UserBalanceOp[] memory balanceOps,
        uint256 newLength
    ) private pure {

        assembly {
            mstore(balanceOps, newLength)
        }
    }
}
