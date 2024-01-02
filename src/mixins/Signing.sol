
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

    
}