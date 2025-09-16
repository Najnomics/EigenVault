// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Import core contracts
import "../src/vault/OrderVault.sol";
import "../src/hooks/EigenVaultHook.sol";

// Mock contracts for testing
import "../test/core/MockERC20.sol";
import "../test/hooks/MockPoolManager.sol";

/// @title DeploySimpleHooks
/// @notice Simplified deployment script for EigenVault core contracts without complex dependencies
contract DeploySimpleHooks is Script {
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault core contracts on Anvil...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy MockPoolManager
        console.log("Deploying MockPoolManager...");
        MockPoolManager mockPoolManager = new MockPoolManager();
        console.log("MockPoolManager deployed at:", address(mockPoolManager));

        // 2. Deploy OrderVault
        console.log("Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault deployed at:", address(orderVault));

        // 3. Deploy EigenVaultHook with proper dependencies
        console.log("Deploying EigenVaultHook...");
        EigenVaultHook eigenVaultHook = new EigenVaultHook(
            mockPoolManager,
            address(orderVault),
            address(0) // AVS service manager (will be set later)
        );
        console.log("EigenVaultHook deployed at:", address(eigenVaultHook));

        // 4. Configure contracts
        console.log("Configuring contracts...");
        
        // Authorize the hook in the order vault
        orderVault.authorizeHook(address(eigenVaultHook), true);
        console.log("EigenVaultHook authorized in OrderVault");

        // Transfer ownership of the hook to deployer for testing
        eigenVaultHook.transferOwnership(deployer);
        console.log("Hook ownership transferred to deployer");

        // 5. Deploy test tokens for testing
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

        // 6. Deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("EigenVaultHook:", address(eigenVaultHook));
        console.log("OrderVault:", address(orderVault));
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));
        
        // 7. Save addresses for environment file
        console.log("\n=== SAVE THESE ADDRESSES ===");
        console.log("EIGENVAULT_HOOK=", address(eigenVaultHook));
        console.log("ORDER_VAULT=", address(orderVault));
        console.log("TOKEN0=", address(token0));
        console.log("TOKEN1=", address(token1));
        console.log("DEPLOYER=", deployer);
        console.log("RPC_URL=http://localhost:8545");
        
        // 8. Test basic functionality
        console.log("\n=== TESTING BASIC FUNCTIONALITY ===");
        testBasicFunctionality(eigenVaultHook, orderVault, token0, token1, deployer);
    }

    function testBasicFunctionality(
        EigenVaultHook hook,
        OrderVault orderVault,
        MockERC20 token0,
        MockERC20 token1,
        address deployer
    ) internal {
        console.log("Testing basic functionality...");
        
        // Test 1: Check contract states
        console.log("Hook owner:", hook.owner());
        console.log("OrderVault total orders:", orderVault.totalOrders());
        console.log("Hook is authorized in OrderVault:", orderVault.isAuthorizedHook(address(hook)));
        
        // Test 2: Check token balances
        console.log("Deployer Token0 balance:", token0.balanceOf(deployer));
        console.log("Deployer Token1 balance:", token1.balanceOf(deployer));
        
        // Test 3: Test OrderVault functionality
        console.log("Testing OrderVault order storage...");
        bytes32 testOrderId = keccak256("test_order_1");
        bytes memory testOrderData = abi.encode("sample_order_data", block.timestamp);
        uint256 testDeadline = block.timestamp + 2 hours;
        
        try orderVault.storeOrder(testOrderId, deployer, testOrderData, testDeadline) {
            console.log("[SUCCESS] Order stored successfully");
            console.log("Total orders now:", orderVault.totalOrders());
            
            // Try to retrieve the order
            bytes memory retrievedData = orderVault.retrieveOrder(testOrderId);
            console.log("Retrieved order data length:", retrievedData.length);
            console.log("[SUCCESS] Order retrieval successful");
        } catch {
            console.log("[ERROR] Order storage failed");
        }
        
        console.log("\n[SUCCESS] Basic functionality test completed");
        console.log("=== NEXT STEPS FOR TESTING ===");
        console.log("1. Use cast to interact with contracts");
        console.log("2. Test hook integration with Uniswap v4");
        console.log("3. Test order matching and execution");
        console.log("4. Test ZK proof verification");
    }
}
