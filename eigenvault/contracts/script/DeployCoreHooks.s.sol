// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Import core hook contracts
import "../src/hooks/EigenVaultHook.sol";
import "../src/vault/OrderVault.sol";
import "../src/avs/EigenVaultAVSServiceManager.sol";

// Mock contracts for testing (minimal mocks for dependencies)
import "../test/core/MockERC20.sol";
import "../test/mocks/EigenLayerMocks.sol";

/// @title DeployCoreHooks
/// @notice Deployment script for EigenVault core hook contracts on Anvil
contract DeployCoreHooks is Script {
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault core hook contracts on Anvil...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy minimal mock contracts for dependencies
        console.log("Deploying minimal mock dependencies...");
        SimpleMockAVSDirectory mockAVSDirectory = new SimpleMockAVSDirectory();
        SimpleMockRewardsCoordinator mockRewardsCoordinator = new SimpleMockRewardsCoordinator();
        SimpleMockSlashingRegistryCoordinator mockSlashingRegistry = new SimpleMockSlashingRegistryCoordinator();
        SimpleMockStakeRegistry mockStakeRegistry = new SimpleMockStakeRegistry();
        SimpleMockPermissionController mockPermissionController = new SimpleMockPermissionController();
        SimpleMockAllocationManager mockAllocationManager = new SimpleMockAllocationManager();
        
        console.log("SimpleMockAVSDirectory:", address(mockAVSDirectory));
        console.log("SimpleMockRewardsCoordinator:", address(mockRewardsCoordinator));
        console.log("SimpleMockSlashingRegistryCoordinator:", address(mockSlashingRegistry));
        console.log("SimpleMockStakeRegistry:", address(mockStakeRegistry));
        console.log("SimpleMockPermissionController:", address(mockPermissionController));
        console.log("SimpleMockAllocationManager:", address(mockAllocationManager));

        // 2. Deploy EigenVaultAVSServiceManager (needed by hook)
        console.log("Deploying EigenVaultAVSServiceManager...");
        EigenVaultAVSServiceManager avsServiceManager = new EigenVaultAVSServiceManager(
            mockAVSDirectory,
            mockRewardsCoordinator,
            mockSlashingRegistry,
            mockStakeRegistry,
            mockPermissionController,
            mockAllocationManager
        );
        console.log("EigenVaultAVSServiceManager:", address(avsServiceManager));

        // 3. Deploy OrderVault
        console.log("Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault:", address(orderVault));

        // 4. Deploy EigenVaultHook (main hook contract)
        console.log("Deploying EigenVaultHook...");
        EigenVaultHook eigenVaultHook = new EigenVaultHook(
            address(avsServiceManager),
            address(orderVault)
        );
        console.log("EigenVaultHook:", address(eigenVaultHook));

        // 5. Configure contracts
        console.log("Configuring contracts...");
        
        // Authorize the hook in the order vault
        orderVault.authorizeHook(address(eigenVaultHook), true);
        console.log("EigenVaultHook authorized in OrderVault");

        // Transfer ownership of the hook to deployer for testing
        eigenVaultHook.transferOwnership(deployer);
        console.log("Hook ownership transferred to deployer");

        // 6. Deploy test tokens for testing
        console.log("Deploying test tokens...");
        MockERC20 token0 = new MockERC20("Test Token A", "TSTA", 18);
        MockERC20 token1 = new MockERC20("Test Token B", "TSTB", 18);
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));

        // Mint tokens to test accounts
        uint256 initialSupply = 1000000 ether;
        address testAccount1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address testAccount2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        
        token0.mint(deployer, initialSupply);
        token1.mint(deployer, initialSupply);
        token0.mint(testAccount1, initialSupply);
        token1.mint(testAccount1, initialSupply);
        token0.mint(testAccount2, initialSupply);
        token1.mint(testAccount2, initialSupply);
        
        console.log("Test tokens minted to accounts");

        vm.stopBroadcast();

        // 7. Deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("EigenVaultHook:", address(eigenVaultHook));
        console.log("OrderVault:", address(orderVault));
        console.log("EigenVaultAVSServiceManager:", address(avsServiceManager));
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));
        
        // 8. Save addresses for environment file
        console.log("\n=== SAVE THESE ADDRESSES ===");
        console.log("EIGENVAULT_HOOK=", address(eigenVaultHook));
        console.log("ORDER_VAULT=", address(orderVault));
        console.log("EIGENVAULT_AVS=", address(avsServiceManager));
        console.log("TOKEN0=", address(token0));
        console.log("TOKEN1=", address(token1));
        console.log("DEPLOYER=", deployer);
        console.log("RPC_URL=http://localhost:8545");
        
        // 9. Test basic functionality
        console.log("\n=== TESTING BASIC FUNCTIONALITY ===");
        testBasicFunctionality(eigenVaultHook, orderVault, avsServiceManager, token0, token1, deployer);
    }

    function testBasicFunctionality(
        EigenVaultHook hook,
        OrderVault orderVault,
        EigenVaultAVSServiceManager avs,
        MockERC20 token0,
        MockERC20 token1,
        address deployer
    ) internal {
        console.log("Testing basic functionality...");
        
        // Test 1: Check contract states
        console.log("Hook owner:", hook.owner());
        console.log("OrderVault total orders:", orderVault.totalOrders());
        console.log("Hook is authorized in OrderVault:", orderVault.isAuthorizedHook(address(hook)));
        console.log("AVS total operators:", avs.totalOperators());
        
        // Test 2: Check token balances
        console.log("Deployer Token0 balance:", token0.balanceOf(deployer));
        console.log("Deployer Token1 balance:", token1.balanceOf(deployer));
        
        // Test 3: Try to register an operator (this should require ETH)
        console.log("Attempting operator registration with 32 ETH...");
        try avs.registerOperator{value: 32 ether}("https://test-operator.com") {
            console.log("[SUCCESS] Operator registration successful");
            console.log("Total operators now:", avs.totalOperators());
            console.log("Is operator registered:", avs.isRegisteredOperator(deployer));
        } catch {
            console.log("[INFO] Operator registration failed - may need additional setup");
        }
        
        console.log("\n[SUCCESS] Basic functionality test completed");
        console.log("=== NEXT STEPS FOR TESTING ===");
        console.log("1. Use cast to interact with contracts");
        console.log("2. Test hook integration with Uniswap v4");
        console.log("3. Test order matching and execution");
        console.log("4. Test ZK proof verification");
    }
}
