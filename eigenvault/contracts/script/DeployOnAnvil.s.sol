// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Import our actual contracts
import "../src/avs/EigenVaultAVS.sol";
import "../src/hooks/EigenVaultHook.sol";
import "../src/vault/OrderVault.sol";

// Mock contracts for testing
import "../test/hooks/MockPoolManager.sol";
import "../test/core/MockERC20.sol";

/// @title DeployOnAnvil
/// @notice Deployment script for EigenVault system on local Anvil
contract DeployOnAnvil is Script {
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault system on Anvil...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock ERC20 tokens for testing
        console.log("Deploying Mock Tokens...");
        MockERC20 token0 = new MockERC20("Test Token A", "TSTA", 18);
        MockERC20 token1 = new MockERC20("Test Token B", "TSTB", 18);
        console.log("Token0 (TSTA) deployed at:", address(token0));
        console.log("Token1 (TSTB) deployed at:", address(token1));

        // 2. Deploy Mock Pool Manager for testing
        console.log("Deploying Mock Pool Manager...");
        MockPoolManager poolManager = new MockPoolManager();
        console.log("MockPoolManager deployed at:", address(poolManager));

        // 3. Deploy OrderVault
        console.log("Deploying OrderVault...");
        OrderVault orderVault = new OrderVault();
        console.log("OrderVault deployed at:", address(orderVault));

        // 4. Deploy EigenVaultAVS
        console.log("Deploying EigenVaultAVS...");
        EigenVaultAVS avs = new EigenVaultAVSServiceManager(address(0), address(0), address(0), address(0), address(0), address(0));
        console.log("EigenVaultAVS deployed at:", address(avs));

        // 5. Deploy EigenVaultHook
        console.log("Deploying EigenVaultHook...");
        EigenVaultHook hook = new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avs)
        );
        console.log("EigenVaultHook deployed at:", address(hook));

        // 6. Configure contracts
        console.log("Configuring contracts...");
        
        // Authorize hook in order vault
        orderVault.authorizeHook(address(hook), true);
        console.log("Hook authorized in OrderVault");

        // Mint some test tokens to deployer and additional accounts
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

        // 7. Deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Token0 (TSTA):", address(token0));
        console.log("Token1 (TSTB):", address(token1));
        console.log("MockPoolManager:", address(poolManager));
        console.log("OrderVault:", address(orderVault));
        console.log("EigenVaultAVS:", address(avs));
        console.log("EigenVaultHook:", address(hook));
        
        // 8. Save deployment addresses
        string memory deploymentInfo = string.concat(
            "TOKEN0=", vm.toString(address(token0)), "\n",
            "TOKEN1=", vm.toString(address(token1)), "\n",
            "POOL_MANAGER=", vm.toString(address(poolManager)), "\n",
            "ORDER_VAULT=", vm.toString(address(orderVault)), "\n",
            "EIGENVAULT_AVS=", vm.toString(address(avs)), "\n",
            "EIGENVAULT_HOOK=", vm.toString(address(hook)), "\n"
        );
        
        vm.writeFile("anvil-deployments.env", deploymentInfo);
        console.log("\nDeployment addresses saved to anvil-deployments.env");
        
        // 9. Test basic functionality
        console.log("\n=== TESTING BASIC FUNCTIONALITY ===");
        testBasicFunctionality(avs, orderVault, hook, token0, token1);
    }

    function testBasicFunctionality(
        EigenVaultAVS avs,
        OrderVault orderVault,
        EigenVaultHook hook,
        MockERC20 token0,
        MockERC20 token1
    ) internal {
        console.log("Testing basic functionality...");
        
        // Test 1: Check initial state
        console.log("AVS total operators:", avs.totalOperators());
        console.log("OrderVault total orders:", orderVault.totalOrders());
        console.log("Hook is authorized:", orderVault.isAuthorizedHook(address(hook)));
        
        // Test 2: Try to register an operator (this should require ETH)
        try avs.registerOperator{value: 32 ether}("https://test-operator.com") {
            console.log("[SUCCESS] Operator registration successful");
            console.log("Total operators now:", avs.totalOperators());
        } catch {
            console.log("[ERROR] Operator registration failed (expected - may need more complex setup)");
        }
        
        // Test 3: Check token balances
        console.log("Deployer Token0 balance:", token0.balanceOf(msg.sender));
        console.log("Deployer Token1 balance:", token1.balanceOf(msg.sender));
        
        console.log("[SUCCESS] Basic functionality test completed");
    }
}