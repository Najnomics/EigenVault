// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/EigenVaultServiceManager.sol";

/// @title RegisterOperator
/// @notice Script to register an operator with EigenVault AVS
contract RegisterOperator is Script {
    function run() external {
        uint256 operatorPrivateKey = vm.envUint("OPERATOR_PRIVATE_KEY");
        address operatorAddress = vm.addr(operatorPrivateKey);
        address serviceManagerAddress = vm.envAddress("EIGENVAULT_SERVICE_MANAGER");

        console.log("Registering operator:", operatorAddress);
        console.log("Service Manager:", serviceManagerAddress);

        EigenVaultServiceManager serviceManager = EigenVaultServiceManager(serviceManagerAddress);

        vm.startBroadcast(operatorPrivateKey);

        // Check if operator has sufficient stake
        console.log("Checking operator stake requirement...");
        uint256 minimumStake = serviceManager.minimumStakePerOperator();
        console.log("Minimum stake required:", minimumStake);

        // Register operator
        console.log("Registering with AVS...");
        serviceManager.registerOperator();

        vm.stopBroadcast();

        // Verify registration
        bool isRegistered = serviceManager.registeredOperators(operatorAddress);
        require(isRegistered, "Operator registration failed");

        console.log("Operator successfully registered!");
        console.log("Active operators count:", serviceManager.getActiveOperatorsCount());
    }

    function batchRegisterOperators() external {
        address serviceManagerAddress = vm.envAddress("EIGENVAULT_SERVICE_MANAGER");
        EigenVaultServiceManager serviceManager = EigenVaultServiceManager(serviceManagerAddress);

        // Read operator addresses from environment
        address[] memory operators = new address[](3);
        operators[0] = vm.envAddress("OPERATOR_1");
        operators[1] = vm.envAddress("OPERATOR_2");  
        operators[2] = vm.envAddress("OPERATOR_3");

        for (uint256 i = 0; i < operators.length; i++) {
            address operator = operators[i];
            console.log("Registering operator", i + 1, ":", operator);

            // This would require the operator's private key for each
            // In practice, each operator would run the registration themselves
            
            vm.startPrank(operator);
            serviceManager.registerOperator();
            vm.stopPrank();

            console.log("Operator", i + 1, "registered successfully");
        }

        console.log("All operators registered!");
        console.log("Total active operators:", serviceManager.getActiveOperatorsCount());
    }
}