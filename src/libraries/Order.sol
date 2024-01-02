
pragma solidity ^0.8.23;

import "solmate/tokens/ERC20.sol";

library Order {


    struct Data {
        ERC20 sellToken;
        ERC20 buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 kind;
        bool partiallyFillable;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
    }

    /// keccak256(
    ///     "Order(" +
    ///         "address sellToken," +
    ///         "address buyToken," +
    ///         "address receiver," +
    ///         "uint256 sellAmount," +
    ///         "uint256 buyAmount," +
    ///         "uint32 validTo," +
    ///         "bytes32 appData," +
    ///         "uint256 feeAmount," +
    ///         "string kind," +
    ///         "bool partiallyFillable," +
    ///         "string sellTokenBalance," +
    ///         "string buyTokenBalance" +
    ///     ")"
    /// )
    bytes32 internal constant TYPE_HASH = hex"";

    // keccak256("sell")
    bytes32 internal constant KIND_SELL = hex"f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775";

    // keccak256("buy")
    bytes32 internal constant KIND_BUY = hex"6ed88e868af0a1983e3886d5f3e95a2fafbd6c3450bc229e27342283dc429ccc";

    // keccak256("erc20")
    bytes32 internal constant BALANCE_ERC20 = hex"5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9";

    // keccak256("external")
    bytes32 internal constant BALANCE_EXTERNAL = hex"abee3b73373acd583a130924aad6dc38cfdc44ba0555ba94ce2ff63980ea0632";

    // keccak256("internal")
    bytes32 internal constant BALANCE_INTERNAL = hex"4ac99ace14ee0a5ef932dc609df0943ab7ac16b7583634612f8dc35a4289a6ce";

    address internal constant RECEIVER_SAME_AS_OWNER = address(0);

    uint256 internal constant UID_LENGTH = 56;


    function actualReceiver(Data memory order, address owner) internal pure returns (address receiver) {
        if (receiver == RECEIVER_SAME_AS_OWNER) {
            receiver = owner;
        } else {
            receiver = order.receiver;
        }
    }

    // Return the EIP-712 signing hash for the specified order.
    function hash(Data memory order, bytes32 domainSeparator) internal pure returns (bytes32 orderDigest) {

    }

    /// Packs order UID parameters into the specified memory location. The
    /// result is equivalent to `abi.encodePacked(...)` with the difference that
    /// it allows re-using the memory for packing the order UID.
    function packOrderUidParams(bytes memory orderUid, bytes32 orderDigest, address owner, uint32 validTo) internal pure {

    }

    /// Extracts specific order information from the standardized unique
    /// order id of the protocol.
    function extractOrderUidParams(bytes calldata oderUid) internal pure 
        returns(bytes32 orderDigest, address owner, uint32 validTo) {

    }
}