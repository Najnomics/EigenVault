// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {MockPoolManager} from "../hooks/MockPoolManager.sol";
import {MockERC20} from "../core/MockERC20.sol";
import {EigenVaultHook} from "../../src/hooks/EigenVaultHook.sol";
import {OrderVault} from "../../src/vault/OrderVault.sol";
import {EigenVaultAVSServiceManager} from "../../src/avs/EigenVaultAVSServiceManager.sol";

// EigenLayer mock interfaces
import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";

/**
 * @title EigenVault Test Deployer
 * @notice Utility for deploying EigenVault components with proper hook address validation
 * @dev Based on Uniswap v4-template patterns with hook address mining
 */
contract EigenVaultDeployers is Test {
    IPoolManager public poolManager;
    OrderVault public orderVault;
    EigenVaultAVSServiceManager public avsServiceManager;
    
    Currency public currency0;
    Currency public currency1;

    function deployMockTokens() internal returns (Currency, Currency) {
        MockERC20 token0 = new MockERC20("Test Token A", "TSTA", 18);
        MockERC20 token1 = new MockERC20("Test Token B", "TSTB", 18);
        
        // Ensure token0 < token1 for proper ordering
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        
        vm.label(address(token0), "TSTA");
        vm.label(address(token1), "TSTB");
        
        return (Currency.wrap(address(token0)), Currency.wrap(address(token1)));
    }

    function deployMockPoolManager() internal returns (IPoolManager) {
        MockPoolManager manager = new MockPoolManager();
        vm.label(address(manager), "MockPoolManager");
        return IPoolManager(address(manager));
    }

    function deployOrderVault() internal returns (OrderVault) {
        OrderVault vault = new OrderVault();
        vm.label(address(vault), "OrderVault");
        return vault;
    }

    function deployMockAVS() internal returns (EigenVaultAVSServiceManager) {
        // For testing, we'll use proper type casting
        // Deploy with mock contract addresses
        address mockAddress = address(0x1234);
        EigenVaultAVSServiceManager avs = new EigenVaultAVSServiceManager(
            IAVSDirectory(mockAddress),
            IRewardsCoordinator(mockAddress),
            ISlashingRegistryCoordinator(mockAddress),
            IStakeRegistry(mockAddress),
            IPermissionController(mockAddress),
            IAllocationManager(mockAddress)
        );
        vm.label(address(avs), "MockAVS");
        return avs;
    }

    function deployHookToAddress(
        IPoolManager _poolManager,
        address _orderVault,
        address _avsServiceManager,
        uint160 flags
    ) internal returns (EigenVaultHook hook, address hookAddress) {
        // Use v4-template approach for hook deployment
        bytes memory constructorArgs = abi.encode(_poolManager, _orderVault, _avsServiceManager);
        
        // Create a deterministic address with the required flags using v4-template pattern
        // The flags need to be in the top 8 bits of the address
        hookAddress = address(
            uint160(
                flags | (0x4444 << 144) // Combine flags with namespace like v4-template
            )
        );
        
        // Deploy using deployCodeTo which handles CREATE2 internally
        deployCodeTo("EigenVaultHook.sol:EigenVaultHook", constructorArgs, hookAddress);
        hook = EigenVaultHook(hookAddress);
        
        vm.label(hookAddress, "EigenVaultHook");
        return (hook, hookAddress);
    }

    function findHookAddress(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);
        
        uint160 flagMask = 0xFF << 152; // Hook flags are in the top 8 bits
        
        for (uint256 i = 0; i < 10000; i++) {
            salt = bytes32(i);
            hookAddress = computeCreate2Address(deployer, salt, bytecodeHash);
            
            if ((uint160(hookAddress) & flagMask) == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("Could not find valid hook address");
    }

    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                bytecodeHash
            )
        );
        return address(uint160(uint256(hash)));
    }

    function deployEigenVaultSystem() internal returns (
        IPoolManager _poolManager,
        OrderVault _orderVault,
        EigenVaultAVSServiceManager _avsServiceManager,
        EigenVaultHook hook,
        Currency _currency0,
        Currency _currency1
    ) {
        // Deploy core components
        _poolManager = deployMockPoolManager();
        _orderVault = deployOrderVault();
        _avsServiceManager = deployMockAVS();
        
        // Deploy tokens
        (_currency0, _currency1) = deployMockTokens();
        
        // Deploy hook with proper flags (beforeSwap + afterSwap for production EigenVault)
        uint160 flags = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        (hook, ) = deployHookToAddress(_poolManager, address(_orderVault), address(_avsServiceManager), flags);
        
        return (_poolManager, _orderVault, _avsServiceManager, hook, _currency0, _currency1);
    }

    function createTestPoolKey(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks
    ) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: _currency0,
            currency1: _currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hooks
        });
    }
}