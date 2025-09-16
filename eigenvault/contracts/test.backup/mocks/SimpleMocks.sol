// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";

/// @title Simple Mock Contracts - Abstract versions to avoid interface implementation issues
/// @notice Abstract mock implementations for testing

abstract contract SimpleMockAVSDirectory is IAVSDirectory {}
abstract contract SimpleMockRewardsCoordinator is IRewardsCoordinator {}
abstract contract SimpleMockSlashingRegistryCoordinator is ISlashingRegistryCoordinator {}
abstract contract SimpleMockStakeRegistry is IStakeRegistry {}
abstract contract SimpleMockPermissionController is IPermissionController {}
abstract contract SimpleMockAllocationManager is IAllocationManager {}