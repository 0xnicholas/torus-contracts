
pragma solidity ^0.8.23;

import "openzeppelin/contracts/interfaces/IERC1271.sol";
import "../libraries/Order.sol";
import "../libraries/Trade.sol";

abstract contract Signing {

    using Order for Order.Data;
    using Order for bytes;

    struct RecoveredOrder {
        Order.Data data;
        bytes uid;
        address owner;
        address receiver;
    }

    enum Scheme {
        Eip712,
        EthSign,
        Eip1271,
        PreSign
    }

    /// The EIP-712 domain type hash used for computing the domain separator.
     bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /// The EIP-712 domain name used for computing the domain separator.
    bytes32 private constant DOMAIN_NAME = keccak256("Torus Protocol");

    /// The EIP-712 domain version used for computing the domain separator.
    bytes32 private constant DOMAIN_VERSION = keccak256("v1");

    uint256 private constant PRE_SIGNED =
        uint256(keccak256("Signing.Scheme.PreSign"));

    bytes32 public immutable domainSeparator;

    uint256 private constant ECDSA_SIGNATURE_LENGTH = 65;

    /// Storage indicating whether or not an order has been signed by a
    /// particular address.
    mapping(bytes => uint256) public preSignature;

    event PreSignature(address indexed owner, bytes orderUid, bool signed);

    /// get the chain ID in solidity using assembly.
    constructor() {
        uint256 chainId;

        assembly {
            chainId := chainid()
        }

        domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                DOMAIN_NAME,
                DOMAIN_VERSION,
                chainId,
                address(this)
            )
        );
    }

    /// Sets a presignature for the specified order UID.
    function setPreSignature(bytes calldata orderUid, bool signed) external {
        (, address owner, ) = orderUid.extractOrderUidParams();
        require(owner == msg.sender, "Torus: cannot presign order");
        if (signed) {
            preSignature[orderUid] = PRE_SIGNED;
        } else {
            preSignature[orderUid] = 0;
        }
        emit PreSignature(owner, orderUid, signed);
    }

    /// Returns an empty recovered order with a pre-allocated buffer for
    /// packing the unique identifier.
    function allocateRecoveredOrder()
        internal
        pure
        returns (RecoveredOrder memory recoveredOrder)
    {
        recoveredOrder.uid = new bytes(Order.UID_LENGTH);
    }

    /// Extracts order data and recovers the signer from the specified trade.
    function recoverOrderFromTrade(
        RecoveredOrder memory recoveredOrder,
        ERC20[] calldata tokens,
        Trade.Data calldata trade
    ) internal view {
        Order.Data memory order = recoveredOrder.data;

        Scheme signingScheme = Trade.extractOrder(trade, tokens, order);
        (bytes32 orderDigest, address owner) = recoverOrderSigner(
            order,
            signingScheme,
            trade.signature
        );

        recoveredOrder.uid.packOrderUidParams(
            orderDigest,
            owner,
            order.validTo
        );
        recoveredOrder.owner = owner;
        recoveredOrder.receiver = order.actualReceiver(owner);
    }

    
    /// Recovers an order's signer from the specified order and signature.
    function recoverOrderSigner(
        Order.Data memory order,
        Scheme signingScheme,
        bytes calldata signature
    ) internal view returns (bytes32 orderDigest, address owner) {
        orderDigest = order.hash(domainSeparator);
        if (signingScheme == Scheme.Eip712) {
            owner = recoverEip712Signer(orderDigest, signature);
        } else if (signingScheme == Scheme.EthSign) {
            owner = recoverEthsignSigner(orderDigest, signature);
        } else if (signingScheme == Scheme.Eip1271) {
            owner = recoverEip1271Signer(orderDigest, signature);
        } else {
            owner = recoverPreSigner(orderDigest, signature, order.validTo);
        }
    }

    /// Perform an ECDSA recover for the specified message and calldata signature.
    function ecdsaRecover(
        bytes32 message,
        bytes calldata encodedSignature
    ) internal pure returns (address signer) {
        require(
            encodedSignature.length == ECDSA_SIGNATURE_LENGTH,
            "Torus: malformed ecdsa signature"
        );

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // r = uint256(encodedSignature[0:32])
            r := calldataload(encodedSignature.offset)
            // s = uint256(encodedSignature[32:64])
            s := calldataload(add(encodedSignature.offset, 32))
            // v = uint8(encodedSignature[64])
            v := shr(248, calldataload(add(encodedSignature.offset, 64)))
        }

        signer = ecrecover(message, v, r, s);
        require(signer != address(0), "Torus: invalid ecdsa signature");
    }

    /// Decodes signature bytes originating from an EIP-712-encoded signature.
    function recoverEip712Signer(
        bytes32 orderDigest,
        bytes calldata encodedSignature
    ) internal pure returns (address owner) {
        owner = ecdsaRecover(orderDigest, encodedSignature);
    }

    function recoverEthsignSigner(
        bytes32 orderDigest,
        bytes calldata encodedSignature
    ) internal pure returns (address owner) {
        // The signed message is encoded as:
        // `"\x19Ethereum Signed Message:\n" || length || data`, where
        // the length is a constant (32 bytes) and the data is defined as:
        // `orderDigest`.
        bytes32 ethsignDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", orderDigest)
        );

        owner = ecdsaRecover(ethsignDigest, encodedSignature);
    }


    function recoverEip1271Signer(
        bytes32 orderDigest,
        bytes calldata encodedSignature
    ) internal view returns (address owner) {
        // NOTE: Use assembly to read the verifier address from the encoded
        // signature bytes.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // owner = address(encodedSignature[0:20])
            owner := shr(96, calldataload(encodedSignature.offset))
        }

        // NOTE: Configure prettier to ignore the following line as it causes
        // a panic in the Solidity plugin.
        // prettier-ignore
        bytes calldata signature = encodedSignature[20:];

        require(
            IERC1271(owner).isValidSignature(orderDigest, signature) == "",
            "Torus: invalid erc1271 signature"
        );
    }

    function recoverPreSigner(
        bytes32 orderDigest,
        bytes calldata encodedSignature,
        uint32 validTo
    ) internal view returns (address owner) {
        require(encodedSignature.length == 20, "Torus: malformed presignature");
        // NOTE: Use assembly to read the owner address from the encoded
        // signature bytes.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // owner = address(encodedSignature[0:20])
            owner := shr(96, calldataload(encodedSignature.offset))
        }

        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderDigest, owner, validTo);

        require(
            preSignature[orderUid] == PRE_SIGNED,
            "Torus: order not presigned"
        );
    }


}