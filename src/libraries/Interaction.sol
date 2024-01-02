
pragma solidity ^0.8.23;

library Interaction {

    struct Data {
        address target;
        uint256 value;
        bytes callData;
    }

    function execute(Data calldata interaction) internal {
        address target = interaction.target;
        uint256 value = interaction.value;
        bytes calldata callData = interaction.callData;

        assembly {
            let freeMemoryPointer := mload(0x40)
            calldatacopy(freeMemoryPointer, callData.offset, callData.length)
            if iszero(
                call(
                    gas(),
                    target,
                    value,
                    freeMemoryPointer,
                    callData.length,
                    0,
                    0
                )
            ) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function selector(Data calldata interaction) internal pure returns (bytes4 result) {

        bytes calldata callData = interaction.callData;
        if (callData.length >= 4) {
            assembly {
                result := calldataload(callData.offset)
            }
        }
    }
}