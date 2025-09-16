// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {EigenVaultHook} from "../../src/hooks/EigenVaultHook.sol";
import {HookMiner} from "../hooks/HookMiner.sol";

/// @title HookDeployer
/// @notice Helper contract to deploy hooks with proper CREATE2 addresses
contract HookDeployer {
    /// @notice Deploy EigenVaultHook with proper address
    /// @param poolManager The pool manager
    /// @param orderVault The order vault address
    /// @param avsServiceManager The AVS service manager address
    /// @param deployer The deployer address
    /// @return hook The deployed hook
    /// @return salt The salt used for deployment
    function deployHook(
        IPoolManager poolManager,
        address orderVault,
        address avsServiceManager,
        address deployer
    ) external returns (EigenVaultHook hook, bytes32 salt) {
        // EigenVaultHook only uses beforeSwap permission
        uint160 flags = Hooks.BEFORE_SWAP_FLAG;
        
        // Get the creation code and constructor args
        bytes memory creationCode = type(EigenVaultHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager, orderVault, avsServiceManager);
        
        // Find a valid hook address
        address hookAddress;
        (hookAddress, salt) = HookMiner.find(deployer, flags, creationCode, constructorArgs);
        
        // Deploy the hook at the computed address
        bytes32 fullSalt = keccak256(abi.encodePacked(deployer, salt));
        
        // Use assembly to deploy with CREATE2
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        assembly {
            hook := create2(0, add(bytecode, 0x20), mload(bytecode), fullSalt)
        }
        
        // Verify the deployment
        require(address(hook) == hookAddress, "Hook deployment failed");
        require(address(hook).code.length > 0, "Hook deployment failed - no code");
        
        return (hook, salt);
    }
    
    /// @notice Predict the hook address
    /// @param poolManager The pool manager
    /// @param orderVault The order vault address
    /// @param avsServiceManager The AVS service manager address
    /// @param deployer The deployer address
    /// @return hookAddress The predicted hook address
    /// @return salt The salt that would be used
    function predictHookAddress(
        IPoolManager poolManager,
        address orderVault,
        address avsServiceManager,
        address deployer
    ) external pure returns (address hookAddress, bytes32 salt) {
        uint160 flags = Hooks.BEFORE_SWAP_FLAG;
        bytes memory creationCode = type(EigenVaultHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager, orderVault, avsServiceManager);
        
        return HookMiner.find(deployer, flags, creationCode, constructorArgs);
    }
}