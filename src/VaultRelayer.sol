
pragma solidity ^0.8.23;

import "solmate/tokens/ERC20.sol";
import "./interfaces/IVault.sol";
import "./libraries/Transfer.sol";

contract VaultRelayer {

    using Transfer for IVault;

    /// The creator of the contract which has special permissions. This
    /// value is set at creation time and cannot change.
    address private immutable creator;

    /// The vault this relayer is for.
    IVault private immutable vault;

    constructor(IVault vault_) {
        creator = msg.sender;
        vault = vault_;
    }

    modifier onlyCreator() {
        require(msg.sender == creator, "Torus: not creator");
        _;
    }

    /// Transfers all sell amounts for the executed trades from their
    /// owners to the caller.
    function transferFromAccounts(Transfer.Data[] calldata transfers) external onlyCreator {
        vault.transferFromAccounts(transfers, msg.sender);
    }

    /// Performs a Balancer batched swap on behalf of a user and sends a
    /// fee to the caller.
    function batchSwapWithFee(
        IVault.SwapKind kind,
        IVault.BatchSwapStep[] calldata swaps,
        ERC20[] memory tokens,
        IVault.FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline,
        Transfer.Data calldata feeTransfer
    ) external onlyCreator returns (int256[] memory tokenDeltas) {
        tokenDeltas = vault.batchSwap(
            kind,
            swaps,
            tokens,
            funds,
            limits,
            deadline
        );
        vault.fastTransferFromAccount(feeTransfer, msg.sender);
    }


}

