// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "@forge-std/src/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {EigenVaultHook} from "../src/EigenVaultHook.sol";
import {EigenVaultServiceManager} from "../src/EigenVaultServiceManager.sol";
import {OrderVault} from "../src/OrderVault.sol";

// EigenLayer imports
import {RegistryCoordinator} from "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {StakeRegistry} from "@eigenlayer-middleware/src/StakeRegistry.sol";
import {BLSApkRegistry} from "@eigenlayer-middleware/src/BLSApkRegistry.sol";
import {IndexRegistry} from "@eigenlayer-middleware/src/IndexRegistry.sol";
import {IAVSDirectory} from "@eigenlayer/contracts/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";

/// @title DeployEigenVault
/// @notice Script to deploy EigenVault contracts
contract DeployEigenVault is Script {
    // Network configurations
    struct NetworkConfig {
        address avsDirectory;
        address rewardsCoordinator;
        address delegationManager;
        address strategyManager;
        address poolManager;
        string name;
    }

    // Deployment addresses
    struct DeployedContracts {
        address poolManager;
        address registryCoordinator;
        address stakeRegistry;
        address blsApkRegistry;
        address indexRegistry;
        address orderVault;
        address serviceManager;
        address eigenVaultHook;
    }

    // Network configurations
    mapping(uint256 => NetworkConfig) public networkConfigs;

    function setUp() public {
        // Holesky Testnet configuration
        networkConfigs[17000] = NetworkConfig({
            avsDirectory: 0x055733000064333CaDDbC92763c58BF0192fFeBf,
            rewardsCoordinator: 0xAcc1fb458a1317E886dB376fc8141540537E68fE,
            delegationManager: 0xA44151489861Fe9e3055d95adC98FbD462B948e7,
            strategyManager: 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6,
            poolManager: address(0), // To be deployed or use existing
            name: "Holesky"
        });

        // Unichain Sepolia configuration (placeholder addresses)
        networkConfigs[1301] = NetworkConfig({
            avsDirectory: address(0), // Deploy mock or use bridged contracts
            rewardsCoordinator: address(0),
            delegationManager: address(0),
            strategyManager: address(0),
            poolManager: address(0), // To be deployed
            name: "Unichain Sepolia"
        });
    }

    function run() public returns (DeployedContracts memory) {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];
        
        console.log("Deploying EigenVault on", config.name);
        console.log("Chain ID:", chainId);

        vm.startBroadcast();

        // Deploy or get existing Pool Manager
        address poolManager = config.poolManager;
        if (poolManager == address(0)) {
            console.log("Deploying Pool Manager...");
            poolManager = address(new PoolManager(500000));
            console.log("Pool Manager deployed at:", poolManager);
        }

        // Deploy EigenLayer middleware contracts if needed
        DeployedContracts memory deployed = _deployMiddlewareContracts(config);
        deployed.poolManager = poolManager;

        // Deploy Order Vault
        console.log("Deploying Order Vault...");
        OrderVault orderVault = new OrderVault();
        deployed.orderVault = address(orderVault);
        console.log("Order Vault deployed at:", address(orderVault));

        // Deploy Service Manager
        console.log("Deploying Service Manager...");
        EigenVaultServiceManager serviceManager = new EigenVaultServiceManager(
            IAVSDirectory(config.avsDirectory != address(0) ? config.avsDirectory : deployed.orderVault), // Mock if needed
            IRewardsCoordinator(config.rewardsCoordinator != address(0) ? config.rewardsCoordinator : deployed.orderVault), // Mock if needed
            RegistryCoordinator(deployed.registryCoordinator),
            StakeRegistry(deployed.stakeRegistry),
            EigenVaultHook(address(0)) // Will be set after hook deployment
        );
        deployed.serviceManager = address(serviceManager);
        console.log("Service Manager deployed at:", address(serviceManager));

        // Deploy EigenVault Hook
        console.log("Deploying EigenVault Hook...");
        EigenVaultHook eigenVaultHook = new EigenVaultHook(
            IPoolManager(poolManager),
            address(serviceManager),
            orderVault
        );
        deployed.eigenVaultHook = address(eigenVaultHook);
        console.log("EigenVault Hook deployed at:", address(eigenVaultHook));

        // Configure contracts
        console.log("Configuring contracts...");
        
        // Authorize hook in order vault
        orderVault.authorizeHook(address(eigenVaultHook));
        
        // The service manager would need to be updated with the hook address
        // This would require an admin function in the service manager
        
        console.log("Deployment completed successfully!");
        
        // Log all deployed addresses
        _logDeployedAddresses(deployed);

        vm.stopBroadcast();

        return deployed;
    }

    function _deployMiddlewareContracts(NetworkConfig memory config) 
        internal 
        returns (DeployedContracts memory deployed) 
    {
        // For networks without EigenLayer, deploy mock contracts
        if (config.avsDirectory == address(0)) {
            console.log("Deploying mock EigenLayer contracts...");
            
            // Deploy minimal mock contracts for testing
            deployed.registryCoordinator = address(new MockRegistryCoordinator());
            deployed.stakeRegistry = address(new MockStakeRegistry());
            deployed.blsApkRegistry = address(new MockBLSApkRegistry());
            deployed.indexRegistry = address(new MockIndexRegistry());
            
            return deployed;
        }

        console.log("Deploying EigenLayer middleware contracts...");
        
        // Deploy BLS APK Registry
        BLSApkRegistry blsApkRegistry = new BLSApkRegistry(
            RegistryCoordinator(address(0)) // Will be set after registry coordinator deployment
        );
        deployed.blsApkRegistry = address(blsApkRegistry);

        // Deploy Index Registry
        IndexRegistry indexRegistry = new IndexRegistry(
            RegistryCoordinator(address(0)) // Will be set after registry coordinator deployment
        );
        deployed.indexRegistry = address(indexRegistry);

        // Deploy Stake Registry
        StakeRegistry stakeRegistry = new StakeRegistry(
            RegistryCoordinator(address(0)), // Will be set after registry coordinator deployment
            IDelegationManager(config.delegationManager)
        );
        deployed.stakeRegistry = address(stakeRegistry);

        // Deploy Registry Coordinator
        RegistryCoordinator registryCoordinator = new RegistryCoordinator(
            IServiceManager(address(0)), // Will be set after service manager deployment
            stakeRegistry,
            blsApkRegistry,
            indexRegistry
        );
        deployed.registryCoordinator = address(registryCoordinator);

        // Update references in other contracts
        // Note: This would require admin functions in the middleware contracts
        // For now, we'll deploy with placeholder addresses and update manually

        return deployed;
    }

    function _logDeployedAddresses(DeployedContracts memory deployed) internal view {
        console.log("\n=== EigenVault Deployment Summary ===");
        console.log("Pool Manager:", deployed.poolManager);
        console.log("Registry Coordinator:", deployed.registryCoordinator);
        console.log("Stake Registry:", deployed.stakeRegistry);
        console.log("BLS APK Registry:", deployed.blsApkRegistry);
        console.log("Index Registry:", deployed.indexRegistry);
        console.log("Order Vault:", deployed.orderVault);
        console.log("Service Manager:", deployed.serviceManager);
        console.log("EigenVault Hook:", deployed.eigenVaultHook);
        console.log("=====================================\n");
    }

    // Function to deploy to specific network
    function deployToNetwork(string memory networkName) external {
        if (keccak256(abi.encodePacked(networkName)) == keccak256(abi.encodePacked("holesky"))) {
            vm.createSelectFork("https://ethereum-holesky-rpc.publicnode.com");
        } else if (keccak256(abi.encodePacked(networkName)) == keccak256(abi.encodePacked("unichain"))) {
            vm.createSelectFork("https://sepolia.unichain.org");
        } else {
            revert("Unsupported network");
        }
        
        run();
    }
}

// Mock contracts for testing on networks without EigenLayer
contract MockRegistryCoordinator {
    enum OperatorStatus { NEVER_REGISTERED, REGISTERED, DEREGISTERED }
    
    mapping(address => OperatorStatus) public operatorStatus;
    
    function getOperatorStatus(address operator) external view returns (OperatorStatus) {
        return operatorStatus[operator];
    }
    
    function registerOperator(address operator) external {
        operatorStatus[operator] = OperatorStatus.REGISTERED;
    }
}

contract MockStakeRegistry {
    // Mock implementation
}

contract MockBLSApkRegistry {
    // Mock implementation
}

contract MockIndexRegistry {
    // Mock implementation
}