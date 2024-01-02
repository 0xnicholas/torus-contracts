
pragma solidity ^0.8.23;

import "";

contract AllowListAuth {

    address public manager;

    mapping[address => bool] private solvers;

    event ManagerChanged(address manager, address oldManager);

    event SolverJoined(address solver);

    event SolverQuited(address sovler);

    //
    function initializeManager(address manager_) external initializer {
        manager = manager_;
        emit ManagerChanged(manager_, address(0));
    }

    modifier onlyManager() {
        require(manager == msg.sender, "Torus: caller not manager.");
        _;
    }

    modifier onlyManagerOwner() {
        require(
            manager == msg.sender || EIP1967.getAdmin() == msg.sender,
            "Torus: not authorized."
        );
    }

    function setManager(address manager_) external onlyManagerOwner {
        address oldManager = manager;
        manager = manager_;
        emit ManagerChanged(manager_, oldManager);
    }

    function solverJoin(address solver) external onlyManager {
        solvers[solver] = true;
        emit SolverJoined(solver);
    }

    function solverQuit(address solver) external onlyManager {
        solvers[solver] = false;
        emit SolverQuited(solver);
    }

    function isSolver(address candidateSolver) 
        external view override returns (bool) {
        
        return solvers[candidateSolver];
    }

}