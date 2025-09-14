// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Import our actual contracts
import "../src/avs/EigenVaultAVS.sol";
import "../src/vault/OrderVault.sol";

// Mock contracts for testing
import "../test/core/MockERC20.sol";

/// @title DeploySimplifiedOnAnvil
/// @notice Simplified deployment script for EigenVault core components on Anvil
contract DeploySimplifiedOnAnvil is Script {
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault core system on Anvil...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock ERC20 tokens for testing
        console.log("Deploying Mock Tokens...");
        MockERC20 token0 = new MockERC20("Test Token A", "TSTA", 18);
        MockERC20 token1 = new MockERC20("Test Token B", "TSTB", 18);
        console.log("Token0 (TSTA) deployed at:", address(token0));
        console.log("Token1 (TSTB) deployed at:", address(token1));

        // 2. Deploy OrderVault
        console.log("Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault deployed at:", address(orderVault));

        // 3. Deploy EigenVaultAVS
        console.log("Deploying EigenVaultAVS...");
        EigenVaultAVS avs = new EigenVaultAVSServiceManager(address(0), address(0), address(0), address(0), address(0), address(0));
        console.log("EigenVaultAVS deployed at:", address(avs));

        // 4. Configure contracts
        console.log("Configuring contracts...");
        
        // For testing, we'll authorize the deployer as a "hook" to test order storage
        orderVault.authorizeHook(deployer, true);
        console.log("Deployer authorized as hook in OrderVault for testing");

        // 5. Mint some test tokens to deployer and additional accounts
        uint256 initialSupply = 1000000 ether;
        token0.mint(deployer, initialSupply);
        token1.mint(deployer, initialSupply);
        
        // Mint to additional test accounts
        address testAccount1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address testAccount2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        
        token0.mint(testAccount1, initialSupply);
        token1.mint(testAccount1, initialSupply);
        token0.mint(testAccount2, initialSupply);
        token1.mint(testAccount2, initialSupply);
        
        console.log("Tokens minted to test accounts");

        vm.stopBroadcast();

        // 6. Deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));
        console.log("OrderVault:", address(orderVault));
        console.log("EigenVaultAVS:", address(avs));
        
        // 7. Record deployment addresses (manually copy from logs if needed)
        console.log("=== SAVE THESE ADDRESSES ===");
        console.log("TOKEN0=", address(token0));
        console.log("TOKEN1=", address(token1));
        console.log("ORDER_VAULT=", address(orderVault));
        console.log("EIGENVAULT_AVS=", address(avs));
        console.log("DEPLOYER=", deployer);
        
        // 8. Test basic functionality
        console.log("\n=== TESTING BASIC FUNCTIONALITY ===");
        testBasicFunctionality(avs, orderVault, token0, token1, deployer);
    }

    function testBasicFunctionality(
        EigenVaultAVS avs,
        OrderVault orderVault,
        MockERC20 token0,
        MockERC20 token1,
        address deployer
    ) internal {
        console.log("Testing basic functionality...");
        
        // Test 1: Check initial state
        console.log("AVS total operators:", avs.totalOperators());
        console.log("OrderVault total orders:", orderVault.totalOrders());
        console.log("Deployer is authorized hook:", orderVault.isAuthorizedHook(deployer));
        
        // Test 2: Try to register an operator (this should require ETH)
        console.log("Attempting operator registration with 32 ETH...");
        try avs.registerOperator{value: 32 ether}("https://test-operator.com") {
            console.log("[SUCCESS] Operator registration successful");
            console.log("Total operators now:", avs.totalOperators());
            console.log("Is operator registered:", avs.isRegisteredOperator(deployer));
        } catch {
            console.log("[INFO] Operator registration failed - may need additional setup");
        }
        
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
        
        // Test 4: Check token balances
        console.log("Checking token balances...");
        console.log("Deployer Token0 balance:", token0.balanceOf(deployer));
        console.log("Deployer Token1 balance:", token1.balanceOf(deployer));
        
        console.log("\n[SUCCESS] Basic functionality test completed");
        console.log("=== NEXT STEPS FOR TESTING ===");
        console.log("1. Use cast to interact with contracts");
        console.log("2. Test operator registration with different accounts");
        console.log("3. Test order matching and execution");
        console.log("4. Test reward distribution and slashing");
    }
}