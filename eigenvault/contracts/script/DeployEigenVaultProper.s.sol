// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// EigenLayer interface imports
import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";

// Import our actual contracts
import "../src/avs/EigenVaultAVSServiceManager.sol";
import "../src/hooks/EigenVaultHook.sol";
import "../src/vault/OrderVault.sol";

// Mock contracts for testing
import "../test/hooks/MockPoolManager.sol";
import "../test/core/MockERC20.sol";

/// @title DeployEigenVaultProper
/// @notice Deployment script using eigenlvr-inspired hook deployment approach
contract DeployEigenVaultProper is Script {
    // Required flags for EigenVaultHook - using only BEFORE_SWAP for simplicity
    uint160 public constant REQUIRED_FLAGS = Hooks.BEFORE_SWAP_FLAG; // 128
    
    function run() external {
        // Use the first Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EigenVault system with proper hook mining...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Required flags:", REQUIRED_FLAGS);

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

        // 4. Deploy EigenVaultAVSServiceManager
        console.log("Deploying EigenVaultAVSServiceManager...");
        EigenVaultAVSServiceManager avs = new EigenVaultAVSServiceManager(
            IAVSDirectory(address(0)),
            IRewardsCoordinator(address(0)),
            ISlashingRegistryCoordinator(address(0)),
            IStakeRegistry(address(0)),
            IPermissionController(address(0)),
            IAllocationManager(address(0))
        );
        console.log("EigenVaultAVSServiceManager deployed at:", address(avs));

        // 5. Mine and deploy the hook with proper CREATE2 approach
        console.log("Mining hook address with required flags...");
        
        // Get contract creation code and constructor args
        bytes memory creationCode = type(EigenVaultHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avs)
        );
        
        // Mine the correct address using the eigenlvr approach
        (address hookAddress, bytes32 salt) = findHookAddress(
            deployer,
            REQUIRED_FLAGS,
            creationCode,
            constructorArgs
        );
        
        console.log("Found valid hook address:", hookAddress);
        console.log("Salt used:", vm.toString(salt));
        
        // Verify the address has correct flags
        require(uint160(hookAddress) & REQUIRED_FLAGS == REQUIRED_FLAGS, "Invalid hook address mined");
        
        // Deploy using CREATE2 with the mined salt (eigenlvr approach)
        EigenVaultHook hook = new EigenVaultHook{salt: salt}(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avs)
        );
        
        console.log("EigenVaultHook deployed at:", address(hook));
        require(address(hook) == hookAddress, "Hook deployment address mismatch");

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
        console.log("EigenVaultAVSServiceManager:", address(avs));
        console.log("EigenVaultHook:", address(hook));
        console.log("Hook Salt:", vm.toString(salt));
        
        // 8. Save deployment addresses
        string memory deploymentInfo = string.concat(
            "TOKEN0=", vm.toString(address(token0)), "\n",
            "TOKEN1=", vm.toString(address(token1)), "\n",
            "POOL_MANAGER=", vm.toString(address(poolManager)), "\n",
            "ORDER_VAULT=", vm.toString(address(orderVault)), "\n",
            "EIGENVAULT_AVS=", vm.toString(address(avs)), "\n",
            "EIGENVAULT_HOOK=", vm.toString(address(hook)), "\n",
            "HOOK_SALT=", vm.toString(salt), "\n",
            "DEPLOYER=", vm.toString(deployer), "\n",
            "RPC_URL=http://localhost:8545", "\n"
        );
        
        vm.writeFile("anvil-deployments.env", deploymentInfo);
        console.log("\nDeployment addresses saved to anvil-deployments.env");
        
        // 9. Test basic functionality
        console.log("\n=== TESTING BASIC FUNCTIONALITY ===");
        testBasicFunctionality(avs, orderVault, hook, token0, token1);
    }
    
    /**
     * @notice Find a valid hook address with required permissions (eigenlvr approach)
     */
    function findHookAddress(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        // Increase iteration limit for flag mining (eigenlvr approach)
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeCreate2Address(deployer, salt, bytecode);
            
            // Check if address has required flags (eigenlvr approach)
            if (uint160(hookAddress) & flags == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: Could not find valid address");
    }
    
    /**
     * @notice Compute CREATE2 address (eigenlvr approach)
     */
    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes memory bytecode
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    function testBasicFunctionality(
        EigenVaultAVSServiceManager avs,
        OrderVault orderVault,
        EigenVaultHook hook,
        MockERC20 token0,
        MockERC20 token1
    ) internal view {
        console.log("Testing basic functionality...");
        
        // Test 1: Check initial state
        console.log("AVS total operators:", avs.totalOperators());
        console.log("OrderVault total orders:", orderVault.totalOrders());
        console.log("Hook is authorized:", orderVault.isAuthorizedHook(address(hook)));
        
        // Test 2: Test token balances
        console.log("Deployer Token0 balance:", token0.balanceOf(msg.sender));
        console.log("Deployer Token1 balance:", token1.balanceOf(msg.sender));
        
        console.log("[SUCCESS] Basic functionality test completed");
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Use cast to interact with contracts");
        console.log("2. Test hook interactions through pool manager");
        console.log("3. Test order creation and matching");
    }
}