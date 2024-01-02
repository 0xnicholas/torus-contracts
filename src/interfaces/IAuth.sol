
pragma solidity ^0.8.23;

interface IAuth {

    function isSolver(address candidateSolver) external view returns (bool);
}