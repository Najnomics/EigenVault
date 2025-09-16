// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// Import our contracts
import "../src/vault/OrderVault.sol";
import "../test/hooks/MockPoolManager.sol";
import "../test/core/MockERC20.sol";

/// @title Deploy Order Vault Only
/// @notice Deploy just the OrderVault and supporting contracts for testing
contract DeployOrderVaultOnly is Script {
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== EigenVault Order Vault Deployment ===");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

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

        // 4. Mint test tokens
        console.log("\n4. Minting test tokens...");
        uint256 initialSupply = 1000000 ether;
        
        // Mint to deployer
        token0.mint(deployer, initialSupply);
        token1.mint(deployer, initialSupply);
        
        // Mint to test accounts
        address testAccount1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address testAccount2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        
        token0.mint(testAccount1, initialSupply);
        token1.mint(testAccount1, initialSupply);
        token0.mint(testAccount2, initialSupply);
        token1.mint(testAccount2, initialSupply);
        
        console.log("Tokens minted to all accounts");

        vm.stopBroadcast();

        // 5. Display deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Anvil (Chain ID: 31337)");
        console.log("MockPoolManager:", address(poolManager));
        console.log("OrderVault:", address(orderVault));
        console.log("Test Token A (TSTA):", address(token0));
        console.log("Test Token B (TSTB):", address(token1));
        
        console.log("\n=== Core Components Ready! ===");
        console.log("- OrderVault deployed and ready for order storage");
        console.log("- Mock tokens available for testing");
        console.log("- Pool manager ready for mock operations");
        
        // Save deployment addresses to environment file
        string memory envContent = string.concat(
            "# EigenVault Anvil Deployment\n",
            "ANVIL_POOL_MANAGER=", vm.toString(address(poolManager)), "\n",
            "ANVIL_ORDER_VAULT=", vm.toString(address(orderVault)), "\n",
            "ANVIL_TOKEN0=", vm.toString(address(token0)), "\n",
            "ANVIL_TOKEN1=", vm.toString(address(token1)), "\n"
        );
        
        vm.writeFile("anvil-deployments.env", envContent);
        console.log("\nDeployment addresses saved to anvil-deployments.env");
    }
}