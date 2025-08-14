// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "@forge-std/src/Script.sol";
import {EigenVaultServiceManager} from "../src/EigenVaultServiceManager.sol";

/// @title RegisterOperator
/// @notice Script to register operators with EigenVault AVS
contract RegisterOperator is Script {
    function run() external {
        address serviceManagerAddress = vm.envAddress("SERVICE_MANAGER_ADDRESS");
        address operatorAddress = vm.envAddress("OPERATOR_ADDRESS");
        
        console.log("Registering operator:", operatorAddress);
        console.log("Service Manager:", serviceManagerAddress);

        vm.startBroadcast();

        EigenVaultServiceManager serviceManager = EigenVaultServiceManager(serviceManagerAddress);
        
        // Register operator with the service manager
        serviceManager.registerOperator();
        
        console.log("Operator registered successfully!");

        vm.stopBroadcast();
    }

    function registerMultipleOperators(address[] memory operators) external {
        address serviceManagerAddress = vm.envAddress("SERVICE_MANAGER_ADDRESS");
        
        console.log("Registering", operators.length, "operators");
        console.log("Service Manager:", serviceManagerAddress);

        vm.startBroadcast();

        EigenVaultServiceManager serviceManager = EigenVaultServiceManager(serviceManagerAddress);
        
        for (uint256 i = 0; i < operators.length; i++) {
            console.log("Registering operator", i + 1, ":", operators[i]);
            
            // Switch to operator's private key (would need to be provided)
            // vm.startBroadcast(operatorPrivateKeys[i]);
            
            serviceManager.registerOperator();
            
            // vm.stopBroadcast();
        }
        
        console.log("All operators registered successfully!");

        vm.stopBroadcast();
    }
}