// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// Import our actual contracts
import "../src/avs/EigenVaultAVSServiceManager.sol";
import "../src/hooks/EigenVaultHook.sol";
import "../src/vault/OrderVault.sol";

// Mock contracts for testing
import "../test/hooks/MockPoolManager.sol";
import "../test/core/MockERC20.sol";

// EigenLayer interface imports
import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";

/// @title Deploy EigenVault Simplified
/// @notice Simplified deployment script for Anvil using working test patterns
contract DeploySimplifiedOnAnvil is Script {
    // Production flags for EigenVault
    uint160 public constant REQUIRED_FLAGS = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG; // 192
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== EigenVault Simplified Deployment to Anvil ===");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Required flags:", REQUIRED_FLAGS);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock ERC20 tokens
        console.log("\n1. Deploying Mock Tokens...");
        MockERC20 token0 = new MockERC20("Test Token A", "TSTA", 18);
        MockERC20 token1 = new MockERC20("Test Token B", "TSTB", 18);
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));

        // 2. Deploy Mock Pool Manager
        console.log("\n2. Deploying Mock Pool Manager...");
        MockPoolManager poolManager = new MockPoolManager();
        console.log("MockPoolManager:", address(poolManager));

        // 3. Deploy OrderVault
        console.log("\n3. Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault:", address(orderVault));

        // 4. Deploy EigenVaultAVSServiceManager with mock interfaces
        console.log("\n4. Deploying EigenVaultAVSServiceManager...");
        address mockAddress = address(0x1234); // Mock address for EigenLayer contracts
        EigenVaultAVSServiceManager avs = new EigenVaultAVSServiceManager(
            IAVSDirectory(mockAddress),
            IRewardsCoordinator(mockAddress),
            ISlashingRegistryCoordinator(mockAddress),
            IStakeRegistry(mockAddress),
            IPermissionController(mockAddress),
            IAllocationManager(mockAddress)
        );
        console.log("EigenVaultAVSServiceManager:", address(avs));

        // 5. Deploy Hook directly (simplified approach for Anvil)
        console.log("\n5. Deploying EigenVaultHook with production flags...");
        
        EigenVaultHook hook = new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avs)
        );
        
        console.log("EigenVaultHook deployed at:", address(hook));
        
        // Verify hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        console.log("Hook permissions - beforeSwap:", permissions.beforeSwap);
        console.log("Hook permissions - afterSwap:", permissions.afterSwap);

        // 6. Configure contracts
        console.log("\n6. Configuring contracts...");
        
        // Authorize hook in order vault
        orderVault.authorizeHook(address(hook), true);
        console.log("Hook authorized in OrderVault");

        // 7. Mint test tokens
        console.log("\n7. Minting test tokens...");
        uint256 initialSupply = 1000000 ether;
        
        // Mint to deployer
        token0.mint(deployer, initialSupply);
        token1.mint(deployer, initialSupply);
        
        // Mint to test accounts
        address testAccount1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
        address testAccount2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2
        
        token0.mint(testAccount1, initialSupply);
        token1.mint(testAccount1, initialSupply);
        token0.mint(testAccount2, initialSupply);
        token1.mint(testAccount2, initialSupply);
        
        console.log("Tokens minted to deployer and test accounts");

        vm.stopBroadcast();

        // 8. Display deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Anvil (Chain ID: 31337)");
        console.log("MockPoolManager:", address(poolManager));
        console.log("OrderVault:", address(orderVault));
        console.log("EigenVaultAVSServiceManager:", address(avs));
        console.log("EigenVaultHook:", address(hook));
        console.log("Test Token A (TSTA):", address(token0));
        console.log("Test Token B (TSTB):", address(token1));
        console.log("Hook Flags (Production):", REQUIRED_FLAGS);
        
        console.log("\n=== Ready for Testing! ===");
        console.log("- Hook deployed with production flags (beforeSwap + afterSwap)");
        console.log("- Test tokens minted to deployer and test accounts");
        console.log("- All contracts configured and ready");
    }
}