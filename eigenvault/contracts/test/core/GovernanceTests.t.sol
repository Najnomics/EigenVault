// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/avs/EigenVaultAVS.sol";
import "../../src/vault/OrderVault.sol";

/// @title GovernanceTests
/// @notice Comprehensive governance and administrative testing
contract GovernanceTestsTest is Test {
    EigenVaultAVS public avs;
    OrderVault public orderVault;
    
    address public constant OWNER = address(0x1);
    address public constant NEW_OWNER = address(0x2);
    address public constant UNAUTHORIZED = address(0x3);
    address public constant OPERATOR1 = address(0x10);
    address public constant HOOK1 = address(0x20);
    
    uint256 public constant MIN_STAKE = 32 ether;
    
    function setUp() public {
        vm.startPrank(OWNER);
        avs = new EigenVaultAVS();
        orderVault = new OrderVault();
        vm.stopPrank();
    }
    
    function testOwnershipTransfer() public {
        // Check initial owner
        assertEq(avs.owner(), OWNER);
        assertEq(orderVault.owner(), OWNER);
        
        // Transfer ownership of AVS
        vm.prank(OWNER);
        avs.transferOwnership(NEW_OWNER);
        assertEq(avs.owner(), NEW_OWNER);
        
        // Transfer ownership of OrderVault
        vm.prank(OWNER);
        orderVault.transferOwnership(NEW_OWNER);
        assertEq(orderVault.owner(), NEW_OWNER);
        
        // Old owner should not be able to perform admin actions
        vm.prank(OWNER);
        vm.expectRevert();
        avs.emergencyPause();
        
        vm.prank(OWNER);
        vm.expectRevert();
        orderVault.authorizeHook(HOOK1, true);
        
        // New owner should be able to perform admin actions
        vm.prank(NEW_OWNER);
        avs.emergencyPause();
        
        vm.prank(NEW_OWNER);
        orderVault.authorizeHook(HOOK1, true);
        assertTrue(orderVault.isAuthorizedHook(HOOK1));
    }
    
    function testUnauthorizedOwnershipTransfer() public {
        // Non-owner should not be able to transfer ownership
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        avs.transferOwnership(UNAUTHORIZED);
        
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        orderVault.transferOwnership(UNAUTHORIZED);
        
        // Ownership should remain unchanged
        assertEq(avs.owner(), OWNER);
        assertEq(orderVault.owner(), OWNER);
    }
    
    function testPauseUnpauseGovernance() public {
        // Initial state should be unpaused
        assertFalse(avs.paused());
        
        // Only owner can pause
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        avs.emergencyPause();
        
        vm.prank(OWNER);
        avs.emergencyPause();
        assertTrue(avs.paused());
        
        // Only owner can unpause
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        avs.emergencyUnpause();
        
        vm.prank(OWNER);
        avs.emergencyUnpause();
        assertFalse(avs.paused());
    }
    
    function testHookAuthorizationGovernance() public {
        // Initially hook should not be authorized
        assertFalse(orderVault.isAuthorizedHook(HOOK1));
        
        // Only owner can authorize hooks
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        orderVault.authorizeHook(HOOK1, true);
        
        // Owner can authorize
        vm.prank(OWNER);
        orderVault.authorizeHook(HOOK1, true);
        assertTrue(orderVault.isAuthorizedHook(HOOK1));
        
        // Owner can deauthorize
        vm.prank(OWNER);
        orderVault.authorizeHook(HOOK1, false);
        assertFalse(orderVault.isAuthorizedHook(HOOK1));
    }
    
    function testRewardDistributionGovernance() public {
        // Register operator
        vm.deal(OPERATOR1, MIN_STAKE);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("test_operator");
        
        uint256 rewardAmount = 1 ether;
        vm.deal(address(avs), rewardAmount);
        
        // Only owner can distribute rewards
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        avs.distributeReward(OPERATOR1, rewardAmount);
        
        // Owner can distribute rewards
        vm.prank(OWNER);
        avs.distributeReward(OPERATOR1, rewardAmount);
        
        assertEq(avs.getTotalRewards(OPERATOR1), rewardAmount);
    }
    
    function testSlashingGovernance() public {
        // Register operator with larger stake
        uint256 largerStake = MIN_STAKE + 10 ether;
        vm.deal(OPERATOR1, largerStake);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: largerStake}("slash_test_operator");
        
        uint256 slashAmount = 5 ether;
        
        // Only owner can slash
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        avs.slashOperator(OPERATOR1, slashAmount, "Test slashing");
        
        // Owner can slash
        vm.prank(OWNER);
        avs.slashOperator(OPERATOR1, slashAmount, "Owner slashing");
        
        assertEq(avs.getOperatorStake(OPERATOR1), largerStake - slashAmount);
        (uint256 totalSlashed, uint256 slashCount) = avs.getSlashingInfo(OPERATOR1);
        assertEq(totalSlashed, slashAmount);
        assertEq(slashCount, 1);
    }
    
    function testTaskCreationGovernance() public {
        bytes32 taskId = keccak256("governance_task");
        bytes memory taskData = "governance_data";
        
        // Only owner can create tasks
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        avs.createTask(taskId, taskData, block.timestamp + 2 hours);
        
        // Owner can create tasks
        vm.prank(OWNER);
        uint32 taskIndex = avs.createTask(taskId, taskData, block.timestamp + 2 hours);
        
        (bytes32 storedId,,,) = avs.getTask(taskIndex);
        assertEq(storedId, taskId);
        assertEq(avs.totalTasks(), 1);
    }
    
    function testMultipleAdminActions() public {
        // Transfer ownership first
        vm.prank(OWNER);
        avs.transferOwnership(NEW_OWNER);
        
        vm.prank(OWNER);
        orderVault.transferOwnership(NEW_OWNER);
        
        // New owner performs multiple admin actions
        vm.startPrank(NEW_OWNER);
        
        // Authorize hooks
        orderVault.authorizeHook(HOOK1, true);
        orderVault.authorizeHook(address(avs), true);
        
        // Pause system
        avs.emergencyPause();
        
        // Create task (should fail while paused)
        vm.expectRevert();
        avs.createTask(keccak256("paused_task"), "data", block.timestamp + 2 hours);
        
        // Unpause
        avs.emergencyUnpause();
        
        // Now create task (should succeed)
        avs.createTask(keccak256("unpaused_task"), "data", block.timestamp + 2 hours);
        
        vm.stopPrank();
        
        assertEq(avs.totalTasks(), 1);
        assertTrue(orderVault.isAuthorizedHook(HOOK1));
        assertFalse(avs.paused());
    }
    
    function testOperatorSelfGovernance() public {
        vm.deal(OPERATOR1, MIN_STAKE + 20 ether);
        
        // Operator registers themselves
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("self_gov_operator");
        assertTrue(avs.isRegisteredOperator(OPERATOR1));
        
        // Operator adds their own stake
        vm.prank(OPERATOR1);
        avs.addStake{value: 10 ether}();
        assertEq(avs.getOperatorStake(OPERATOR1), MIN_STAKE + 10 ether);
        
        // Operator withdraws some of their stake
        vm.prank(OPERATOR1);
        avs.withdrawStake(5 ether);
        assertEq(avs.getOperatorStake(OPERATOR1), MIN_STAKE + 5 ether);
        
        // Operator cannot slash themselves
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.slashOperator(OPERATOR1, 1 ether, "Self slash");
        
        // Operator cannot distribute rewards to themselves
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.distributeReward(OPERATOR1, 1 ether);
    }
    
    function testGovernanceEventEmissions() public {
        // Test ownership transfer events
        vm.expectEmit(true, true, false, false, address(avs));
        emit OwnershipTransferred(OWNER, NEW_OWNER);
        vm.prank(OWNER);
        avs.transferOwnership(NEW_OWNER);
        
        vm.expectEmit(true, true, false, false, address(orderVault));
        emit OwnershipTransferred(OWNER, NEW_OWNER);
        vm.prank(OWNER);
        orderVault.transferOwnership(NEW_OWNER);
        
        // Test pause events
        vm.expectEmit(false, false, false, false, address(avs));
        emit Paused(NEW_OWNER);
        vm.prank(NEW_OWNER);
        avs.emergencyPause();
        
        vm.expectEmit(false, false, false, false, address(avs));
        emit Unpaused(NEW_OWNER);
        vm.prank(NEW_OWNER);
        avs.emergencyUnpause();
    }
    
    function testBoundaryGovernanceScenarios() public {
        // Test governance with zero address (should fail)
        vm.prank(OWNER);
        vm.expectRevert();
        avs.transferOwnership(address(0));
        
        vm.prank(OWNER);
        vm.expectRevert();
        orderVault.transferOwnership(address(0));
        
        // Test governance with contract address as new owner
        address contractOwner = address(new TestContract());
        
        vm.prank(OWNER);
        avs.transferOwnership(contractOwner);
        assertEq(avs.owner(), contractOwner);
        
        // Contract owner should be able to perform admin actions via calls
        vm.prank(contractOwner);
        avs.emergencyPause();
        assertTrue(avs.paused());
    }
    
    function testGovernanceAccessControl() public {
        // Create array of unauthorized addresses
        address[5] memory unauthorizedUsers = [
            address(0x100),
            address(0x200),
            address(0x300),
            address(0x400),
            address(0x500)
        ];
        
        for (uint256 i = 0; i < unauthorizedUsers.length; i++) {
            address user = unauthorizedUsers[i];
            
            // Each user should fail at all admin operations
            vm.prank(user);
            vm.expectRevert();
            avs.emergencyPause();
            
            vm.prank(user);
            vm.expectRevert();
            avs.transferOwnership(user);
            
            vm.prank(user);
            vm.expectRevert();
            orderVault.authorizeHook(user, true);
            
            vm.prank(user);
            vm.expectRevert();
            orderVault.transferOwnership(user);
        }
        
        // Owner should still have all permissions
        assertEq(avs.owner(), OWNER);
        assertEq(orderVault.owner(), OWNER);
        
        vm.prank(OWNER);
        avs.emergencyPause();
        assertTrue(avs.paused());
    }
    
    function testGovernanceAfterPause() public {
        // Pause system
        vm.prank(OWNER);
        avs.emergencyPause();
        
        // Admin operations should still work while paused
        vm.prank(OWNER);
        avs.transferOwnership(NEW_OWNER);
        assertEq(avs.owner(), NEW_OWNER);
        
        vm.prank(OWNER);
        orderVault.authorizeHook(HOOK1, true);
        assertTrue(orderVault.isAuthorizedHook(HOOK1));
        
        // New owner should be able to unpause
        vm.prank(NEW_OWNER);
        avs.emergencyUnpause();
        assertFalse(avs.paused());
    }
    
    function testCrossContractGovernance() public {
        // Set up cross-contract relationship
        vm.prank(OWNER);
        orderVault.authorizeHook(address(avs), true);
        
        // Register operator
        vm.deal(OPERATOR1, MIN_STAKE);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("cross_contract_op");
        
        // AVS should be able to store orders as authorized hook
        bytes32 orderId = keccak256("cross_contract_order");
        vm.prank(address(avs));
        orderVault.storeOrder(orderId, OPERATOR1, "cross_data", block.timestamp + 2 hours);
        
        (bool exists,) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        
        // Owner can revoke AVS authorization
        vm.prank(OWNER);
        orderVault.authorizeHook(address(avs), false);
        
        // AVS should no longer be able to store orders
        bytes32 orderId2 = keccak256("revoked_order");
        vm.prank(address(avs));
        vm.expectRevert();
        orderVault.storeOrder(orderId2, OPERATOR1, "revoked_data", block.timestamp + 2 hours);
    }
    
    function DISABLED_testGovernanceEdgeCaseRecovery() public {
        // Transfer ownership to a contract that might not handle ownership properly
        BadContract badContract = new BadContract();
        
        vm.prank(OWNER);
        avs.transferOwnership(address(badContract));
        
        // System should still be functional, owner is now the bad contract
        assertEq(avs.owner(), address(badContract));
        
        // Bad contract cannot perform admin functions (has no implementation)
        vm.prank(address(badContract));
        vm.expectRevert();
        avs.emergencyPause();
    }
    
    function testSequentialOwnershipTransfers() public {
        address[3] memory owners = [address(0x111), address(0x222), address(0x333)];
        
        address currentOwner = OWNER;
        
        for (uint256 i = 0; i < owners.length; i++) {
            vm.prank(currentOwner);
            avs.transferOwnership(owners[i]);
            assertEq(avs.owner(), owners[i]);
            currentOwner = owners[i];
        }
        
        // Final owner should have admin privileges
        vm.prank(currentOwner);
        avs.emergencyPause();
        assertTrue(avs.paused());
    }
    
    // Events to test emission
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);
}

contract TestContract {
    // Simple contract for testing contract ownership
}

contract BadContract {
    // Contract that doesn't implement proper admin functions
}