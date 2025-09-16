// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Import core contracts
import "../src/vault/OrderVault.sol";

// Mock contracts for testing
import "../test/core/MockERC20.sol";

/// @title DeployOrderVaultOnly
/// @notice Simplified deployment script for EigenVault OrderVault contract
contract DeployOrderVaultOnly is Script {
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault OrderVault on Anvil...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy OrderVault
        console.log("Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault deployed at:", address(orderVault));

        // 2. Deploy test tokens for testing
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

        // 3. Test OrderVault functionality
        console.log("Testing OrderVault functionality...");
        
        // Authorize deployer as a hook for testing
        orderVault.authorizeHook(deployer, true);
        console.log("Deployer authorized as hook in OrderVault");

        // Test order storage
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

        vm.stopBroadcast();

        // 4. Deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("OrderVault:", address(orderVault));
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));
        
        // 5. Save addresses for environment file
        console.log("\n=== SAVE THESE ADDRESSES ===");
        console.log("ORDER_VAULT=", address(orderVault));
        console.log("TOKEN0=", address(token0));
        console.log("TOKEN1=", address(token1));
        console.log("DEPLOYER=", deployer);
        console.log("RPC_URL=http://localhost:8545");
        
        // 6. Test results
        console.log("\n=== TEST RESULTS ===");
        console.log("OrderVault total orders:", orderVault.totalOrders());
        console.log("Deployer is authorized hook:", orderVault.isAuthorizedHook(deployer));
        console.log("Deployer Token0 balance:", token0.balanceOf(deployer));
        console.log("Deployer Token1 balance:", token1.balanceOf(deployer));
        
        console.log("\n[SUCCESS] OrderVault deployment completed!");
        console.log("=== NEXT STEPS ===");
        console.log("1. Use cast to interact with OrderVault");
        console.log("2. Test order matching and execution");
        console.log("3. Deploy hook contracts when dependencies are ready");
    }
}
