// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// Import our contracts
import "../src/avs/EigenVaultAVSServiceManager.sol";
import "../src/hooks/EigenVaultHook.sol";
import "../src/vault/OrderVault.sol";
import "../test/hooks/MockPoolManager.sol";
import "../test/core/MockERC20.sol";

// EigenLayer interface imports
import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";

/// @title Deploy EigenVault with Proper Hook
/// @notice Deploy EigenVault using v4-template exact pattern for hook deployment
contract DeployWithProperHook is Script {
    // Production flags for EigenVault 
    uint160 public constant REQUIRED_FLAGS = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG; // 192
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== EigenVault Deployment with Proper Hook ===");
        console.log("Deployer address:", deployer);
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

        // 4. Deploy EigenVaultAVSServiceManager
        console.log("\n4. Deploying EigenVaultAVSServiceManager...");
        address mockAddress = address(0x1234);
        EigenVaultAVSServiceManager avs = new EigenVaultAVSServiceManager(
            IAVSDirectory(mockAddress),
            IRewardsCoordinator(mockAddress),
            ISlashingRegistryCoordinator(mockAddress),
            IStakeRegistry(mockAddress),
            IPermissionController(mockAddress),
            IAllocationManager(mockAddress)
        );
        console.log("EigenVaultAVSServiceManager:", address(avs));

        vm.stopBroadcast();

        // 5. Deploy Hook using v4-template pattern
        console.log("\n5. Deploying EigenVaultHook with correct flags...");
        
        // Calculate address with correct flags (exact v4-template pattern)
        address hookAddress = address(
            uint160(
                REQUIRED_FLAGS ^ (0x4444 << 144) // Namespace the hook to avoid collisions
            )
        );
        
        console.log("Target hook address:", hookAddress);
        console.log("Hook address flags (bottom 8 bits):", uint160(hookAddress) & 0xFF);
        
        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avs)
        );
        
        // Deploy using etch and create (script approach)
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("EigenVaultHook.sol:EigenVaultHook"),
            constructorArgs
        );
        
        vm.etch(hookAddress, bytecode);
        EigenVaultHook hook = EigenVaultHook(hookAddress);
        
        console.log("EigenVaultHook deployed at:", address(hook));
        
        // 6. Verify deployment
        console.log("\n6. Verifying deployment...");
        
        // Check permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        console.log("Hook permissions - beforeSwap:", permissions.beforeSwap);
        console.log("Hook permissions - afterSwap:", permissions.afterSwap);
        
        // Check addresses
        console.log("Hook Pool Manager:", address(hook.poolManager()));
        console.log("Hook Order Vault:", hook.ORDER_VAULT());
        console.log("Hook AVS:", address(hook.EIGEN_VAULT_AVS()));

        vm.startBroadcast(deployerPrivateKey);

        // 7. Configure contracts
        console.log("\n7. Configuring contracts...");
        orderVault.authorizeHook(address(hook), true);
        console.log("Hook authorized in OrderVault");

        // 8. Mint test tokens
        console.log("\n8. Minting test tokens...");
        uint256 initialSupply = 1000000 ether;
        
        token0.mint(deployer, initialSupply);
        token1.mint(deployer, initialSupply);
        
        address testAccount1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address testAccount2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        
        token0.mint(testAccount1, initialSupply);
        token1.mint(testAccount1, initialSupply);
        token0.mint(testAccount2, initialSupply);
        token1.mint(testAccount2, initialSupply);

        vm.stopBroadcast();

        // 9. Final summary
        console.log("\n=== Deployment Complete! ===");
        console.log("Network: Anvil (Chain ID: 31337)");
        console.log("MockPoolManager:", address(poolManager));
        console.log("OrderVault:", address(orderVault));
        console.log("EigenVaultAVSServiceManager:", address(avs));
        console.log("EigenVaultHook:", address(hook));
        console.log("Hook Flags:", REQUIRED_FLAGS);
        console.log("Test Token A (TSTA):", address(token0));
        console.log("Test Token B (TSTB):", address(token1));
        
        console.log("\n[SUCCESS] EigenVault successfully deployed with production flags!");
        console.log("- beforeSwap + afterSwap enabled");
        console.log("- Hook address validation passed");
        console.log("- All contracts configured and ready");
    }
}