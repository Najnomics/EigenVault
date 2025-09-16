// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {EigenVaultTaskAVSRegistrar} from "@project/l1-contracts/EigenVaultTaskAVSRegistrar.sol";

// Mock contracts for testing
contract MockAllocationManager {
    function getOperatorMagnitude(address, address) external pure returns (uint64) {
        return 1000; // Mock magnitude
    }
}

contract MockKeyRegistrar {
    function getOperatorKzgBLSPubkey(address) external pure returns (bytes memory) {
        return abi.encode("mock_pubkey");
    }
}

contract MockPermissionController {
    function hasPermission(address, address, bytes4) external pure returns (bool) {
        return true;
    }
}

contract EigenVaultTaskAVSRegistrarTest is Test {
    EigenVaultTaskAVSRegistrar public registrar;
    MockAllocationManager public mockAllocationManager;
    MockKeyRegistrar public mockKeyRegistrar;
    MockPermissionController public mockPermissionController;
    
    address public owner = address(0x1);
    address public avs = address(0x2);
    address public operator1 = address(0x3);
    address public operator2 = address(0x4);
    address public taskHook = address(0x5);

    function setUp() public {
        // Deploy mock contracts
        mockAllocationManager = new MockAllocationManager();
        mockKeyRegistrar = new MockKeyRegistrar();
        mockPermissionController = new MockPermissionController();

        // Deploy the registrar
        registrar = new EigenVaultTaskAVSRegistrar(
            mockAllocationManager,
            mockKeyRegistrar,
            mockPermissionController
        );

        // Initialize the registrar
        vm.prank(owner);
        EigenVaultTaskAVSRegistrar.AvsConfig memory config = EigenVaultTaskAVSRegistrar.AvsConfig({
            taskFrozen: false,
            slashingEnabled: true
        });
        registrar.initialize(avs, owner, config);
    }

    function testInitialization() public view {
        assertEq(registrar.owner(), owner);
        // Additional initialization checks can be added here
    }

    function testSetEigenVaultTaskHook() public {
        vm.prank(owner);
        registrar.setEigenVaultTaskHook(taskHook);
        
        assertEq(registrar.eigenVaultTaskHook(), taskHook);
    }

    function testSetEigenVaultTaskHookFailsWithInvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid task hook address");
        registrar.setEigenVaultTaskHook(address(0));
    }

    function testSetEigenVaultTaskHookFailsWithUnauthorized() public {
        vm.prank(operator1);
        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        registrar.setEigenVaultTaskHook(taskHook);
    }

    function testUpdateOperatorPerformance() public {
        // First set the task hook
        vm.prank(owner);
        registrar.setEigenVaultTaskHook(taskHook);

        // Mock operator registration (this would normally happen through parent contract)
        // For testing purposes, we'll assume operator1 is registered

        // Update performance from task hook
        vm.prank(taskHook);
        registrar.updateOperatorPerformance(operator1, 95);

        assertEq(registrar.getOperatorPerformanceScore(operator1), 95);
        assertEq(registrar.operatorLastTaskCompletion(operator1), block.timestamp);
    }

    function testUpdateOperatorPerformanceFailsWithUnauthorized() public {
        vm.prank(operator2);
        vm.expectRevert("Unauthorized");
        registrar.updateOperatorPerformance(operator1, 95);
    }

    function testGetOperatorPerformanceScore() public {
        // Initially should be 0
        assertEq(registrar.getOperatorPerformanceScore(operator1), 0);

        // Set up and update performance
        vm.prank(owner);
        registrar.setEigenVaultTaskHook(taskHook);
        
        vm.prank(taskHook);
        registrar.updateOperatorPerformance(operator1, 85);

        assertEq(registrar.getOperatorPerformanceScore(operator1), 85);
    }

    function testIsOperatorEligible() public {
        // Set up task hook
        vm.prank(owner);
        registrar.setEigenVaultTaskHook(taskHook);

        // Mock operator registration - in a real test, this would involve parent contract setup
        // For now, we'll assume operator eligibility is based on our custom logic

        // Test with good performance score
        vm.prank(taskHook);
        registrar.updateOperatorPerformance(operator1, 90);
        
        // Note: This test would need proper operator registration setup
        // bool eligible = registrar.isOperatorEligible(operator1);
        // assertTrue(eligible);
    }

    function testMinimumStakeConstant() public view {
        assertEq(registrar.MINIMUM_STAKE(), 32 ether);
    }

    function testOperatorPerformanceUpdatedEvent() public {
        vm.prank(owner);
        registrar.setEigenVaultTaskHook(taskHook);

        vm.expectEmit(true, false, false, true);
        emit EigenVaultTaskAVSRegistrar.OperatorPerformanceUpdated(operator1, 88);

        vm.prank(taskHook);
        registrar.updateOperatorPerformance(operator1, 88);
    }

    function testEigenVaultTaskHookUpdatedEvent() public {
        address oldHook = registrar.eigenVaultTaskHook();

        vm.expectEmit(true, true, false, false);
        emit EigenVaultTaskAVSRegistrar.EigenVaultTaskHookUpdated(oldHook, taskHook);

        vm.prank(owner);
        registrar.setEigenVaultTaskHook(taskHook);
    }
}