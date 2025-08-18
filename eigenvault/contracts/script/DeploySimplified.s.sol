// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "@forge-std/src/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {SimplifiedEigenVaultHook} from "../src/SimplifiedEigenVaultHook.sol";
import {SimplifiedServiceManager} from "../src/SimplifiedServiceManager.sol";
import {OrderVault} from "../src/OrderVault.sol";

/// @title DeploySimplified
/// @notice Script to deploy simplified EigenVault contracts for demonstration
contract DeploySimplified is Script {
    // Deployment addresses
    struct DeployedContracts {
        address poolManager;
        address orderVault;
        address serviceManager;
        address eigenVaultHook;
    }

    function run() public returns (DeployedContracts memory) {
        console.log("Deploying Simplified EigenVault...");
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();

        // Deploy Pool Manager
        console.log("Deploying Pool Manager...");
        PoolManager poolManager = new PoolManager(500000);
        console.log("Pool Manager deployed at:", address(poolManager));

        // Deploy Order Vault
        console.log("Deploying Order Vault...");
        OrderVault orderVault = new OrderVault();
        console.log("Order Vault deployed at:", address(orderVault));

        // Deploy Service Manager (simplified version)
        console.log("Deploying Simplified Service Manager...");
        SimplifiedServiceManager serviceManager = new SimplifiedServiceManager(
            SimplifiedEigenVaultHook(address(0)) // Will be updated after hook deployment
        );
        console.log("Service Manager deployed at:", address(serviceManager));

        // Deploy EigenVault Hook
        console.log("Deploying Simplified EigenVault Hook...");
        SimplifiedEigenVaultHook eigenVaultHook = new SimplifiedEigenVaultHook(
            poolManager,
            address(serviceManager),
            orderVault
        );
        console.log("EigenVault Hook deployed at:", address(eigenVaultHook));

        // Configure contracts
        console.log("Configuring contracts...");
        
        // Authorize hook in order vault
        orderVault.authorizeHook(address(eigenVaultHook));
        console.log("Hook authorized in Order Vault");

        DeployedContracts memory deployed = DeployedContracts({
            poolManager: address(poolManager),
            orderVault: address(orderVault),
            serviceManager: address(serviceManager),
            eigenVaultHook: address(eigenVaultHook)
        });

        console.log("Deployment completed successfully!");
        
        // Log all deployed addresses
        _logDeployedAddresses(deployed);

        vm.stopBroadcast();

        return deployed;
    }

    function _logDeployedAddresses(DeployedContracts memory deployed) internal view {
        console.log("\n=== Simplified EigenVault Deployment Summary ===");
        console.log("Pool Manager:", deployed.poolManager);
        console.log("Order Vault:", deployed.orderVault);
        console.log("Service Manager:", deployed.serviceManager);
        console.log("EigenVault Hook:", deployed.eigenVaultHook);
        console.log("=============================================\n");
    }

    // Function to deploy to specific network
    function deployToNetwork(string memory networkName) external {
        if (keccak256(abi.encodePacked(networkName)) == keccak256(abi.encodePacked("local"))) {
            vm.createSelectFork("http://localhost:8545");
        } else if (keccak256(abi.encodePacked(networkName)) == keccak256(abi.encodePacked("unichain"))) {
            vm.createSelectFork("https://sepolia.unichain.org");
        } else {
            revert("Unsupported network");
        }
        
        run();
    }

    // Function to verify deployment
    function verifyDeployment(DeployedContracts memory deployed) external view {
        console.log("Verifying deployment...");
        
        // Verify Pool Manager
        require(deployed.poolManager != address(0), "Pool Manager not deployed");
        console.log("✓ Pool Manager verified");
        
        // Verify Order Vault
        require(deployed.orderVault != address(0), "Order Vault not deployed");
        OrderVault vault = OrderVault(deployed.orderVault);
        require(vault.isAuthorizedHook(deployed.eigenVaultHook), "Hook not authorized");
        console.log("✓ Order Vault verified");
        
        // Verify Service Manager
        require(deployed.serviceManager != address(0), "Service Manager not deployed");
        console.log("✓ Service Manager verified");
        
        // Verify Hook
        require(deployed.eigenVaultHook != address(0), "Hook not deployed");
        SimplifiedEigenVaultHook hook = SimplifiedEigenVaultHook(deployed.eigenVaultHook);
        require(address(hook.poolManager()) == deployed.poolManager, "Hook pool manager mismatch");
        require(address(hook.orderVault()) == deployed.orderVault, "Hook order vault mismatch");
        console.log("✓ Hook verified");
        
        console.log("All contracts verified successfully!");
    }
}