// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "@eigenlayer/core/interfaces/IAVSDirectory.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";

import "../src/EigenVaultHook.sol";
import "../src/EigenVaultServiceManager.sol";
import "../src/OrderVault.sol";

/// @title DeployEigenVault
/// @notice Deployment script for EigenVault system on Holesky testnet
contract DeployEigenVault is Script {
    // Holesky testnet addresses
    address constant HOLESKY_AVS_DIRECTORY = 0x055733000064333CaDDbC92763c58BF0192fFeBf;
    address constant HOLESKY_DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address constant HOLESKY_STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    
    // Uniswap v4 addresses (will be available on mainnet/testnets)
    // For now, using placeholder - update with actual addresses when available
    address constant UNISWAP_V4_POOL_MANAGER = address(0x1234567890123456789012345678901234567890);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault system...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy OrderVault first
        console.log("Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault deployed at:", address(orderVault));

        // 2. Deploy ServiceManager with real EigenLayer integration
        console.log("Deploying EigenVaultServiceManager...");
        EigenVaultServiceManager serviceManager = new EigenVaultServiceManager(
            IAVSDirectory(HOLESKY_AVS_DIRECTORY),
            IStakeRegistry(address(0)), // Will be set up with proper StakeRegistry
            IEigenVaultHook(address(0)), // Will be updated after hook deployment
            IOrderVault(address(orderVault))
        );
        console.log("ServiceManager deployed at:", address(serviceManager));

        // 3. Deploy EigenVaultHook with real Uniswap v4 integration
        console.log("Deploying EigenVaultHook...");
        EigenVaultHook eigenVaultHook = new EigenVaultHook(
            IPoolManager(UNISWAP_V4_POOL_MANAGER),
            address(orderVault),
            address(serviceManager)
        );
        console.log("EigenVaultHook deployed at:", address(eigenVaultHook));

        // 4. Configure contracts
        console.log("Configuring contracts...");
        
        // Authorize hook in order vault
        orderVault.authorizeHook(address(eigenVaultHook));
        console.log("Hook authorized in OrderVault");

        // Update service manager reference in hook if needed
        // This would require additional setup function in production

        vm.stopBroadcast();

        // 5. Verify deployments
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("OrderVault:", address(orderVault));
        console.log("ServiceManager:", address(serviceManager));
        console.log("EigenVaultHook:", address(eigenVaultHook));
        
        // 6. Save deployment addresses to file
        string memory deploymentInfo = string.concat(
            "EIGENVAULT_ORDER_VAULT=", vm.toString(address(orderVault)), "\n",
            "EIGENVAULT_SERVICE_MANAGER=", vm.toString(address(serviceManager)), "\n",
            "EIGENVAULT_HOOK=", vm.toString(address(eigenVaultHook)), "\n"
        );
        
        vm.writeFile("deployments.env", deploymentInfo);
        console.log("\nDeployment addresses saved to deployments.env");
        
        // 7. Output next steps
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Register with EigenLayer AVS Directory");
        console.log("2. Set up operator infrastructure");
        console.log("3. Configure hook permissions in Uniswap v4");
        console.log("4. Test with small transactions on testnet");
    }

    function deployOnUnichain() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // Unichain Sepolia specific addresses
        address UNICHAIN_POOL_MANAGER = address(0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying on Unichain Sepolia...");

        // Deploy with Unichain-specific addresses
        OrderVault orderVault = new OrderVault();
        
        // For Unichain, we might not have full EigenLayer integration yet
        // Deploy a simplified version for testing
        EigenVaultServiceManager serviceManager = new EigenVaultServiceManager(
            IAVSDirectory(address(0)), // Placeholder for now
            IStakeRegistry(address(0)),
            IEigenVaultHook(address(0)),
            IOrderVault(address(orderVault))
        );

        EigenVaultHook eigenVaultHook = new EigenVaultHook(
            IPoolManager(UNICHAIN_POOL_MANAGER),
            address(orderVault),
            address(serviceManager)
        );

        // Configure contracts
        orderVault.authorizeHook(address(eigenVaultHook));

        vm.stopBroadcast();

        console.log("Unichain deployment complete:");
        console.log("OrderVault:", address(orderVault));
        console.log("ServiceManager:", address(serviceManager));
        console.log("EigenVaultHook:", address(eigenVaultHook));
    }
}