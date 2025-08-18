// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @title HookMiner
/// @notice Utility for mining hook addresses with specific permissions
library HookMiner {
    // Mask for the flags
    uint160 internal constant FLAG_MASK = 0xFF << 152;

    /// @notice Find a hook address with the specified permissions
    /// @param deployer The address that will deploy the hook
    /// @param flags The hook permissions flags
    /// @param creationCode The creation code of the hook contract
    /// @param constructorArgs The constructor arguments
    /// @return hookAddress The hook address
    /// @return salt The salt used to generate the address
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        // Combine creation code and constructor args
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);

        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, bytecodeHash);
            
            if (uint160(hookAddress) & FLAG_MASK == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: could not find hook address");
    }

    /// @notice Compute the CREATE2 address
    /// @param deployer The deployer address
    /// @param salt The salt
    /// @param bytecodeHash The hash of the bytecode
    /// @return addr The computed address
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal pure returns (address addr) {
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

    /// @notice Validate that the hook address has the correct permissions
    /// @param hookAddress The hook address to validate
    /// @param expectedFlags The expected permissions flags
    /// @return valid Whether the address is valid
    function validateHookAddress(
        address hookAddress,
        uint160 expectedFlags
    ) internal pure returns (bool valid) {
        return uint160(hookAddress) & FLAG_MASK == expectedFlags;
    }

    /// @notice Get the flags from a hook address
    /// @param hookAddress The hook address
    /// @return flags The permission flags
    function getFlags(address hookAddress) internal pure returns (uint160 flags) {
        return uint160(hookAddress) & FLAG_MASK;
    }

    /// @notice Check if specific permission is set
    /// @param hookAddress The hook address
    /// @param flag The flag to check
    /// @return hasFlag Whether the flag is set
    function hasFlag(address hookAddress, uint160 flag) internal pure returns (bool) {
        return (uint160(hookAddress) & flag) != 0;
    }

    /// @notice Generate random salt
    /// @param seed The seed for randomness
    /// @return salt The generated salt
    function generateSalt(uint256 seed) internal view returns (bytes32 salt) {
        return keccak256(abi.encodePacked("HookMiner", seed, block.timestamp));
    }

    /// @notice Find hook address with timeout
    /// @param deployer The deployer address
    /// @param flags The permission flags
    /// @param creationCode The creation code
    /// @param constructorArgs The constructor arguments
    /// @param maxIterations Maximum iterations before timeout
    /// @return hookAddress The found hook address
    /// @return salt The salt used
    function findWithTimeout(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 maxIterations
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);

        for (uint256 i = 0; i < maxIterations; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, bytecodeHash);
            
            if (uint160(hookAddress) & FLAG_MASK == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: timeout reached");
    }
}