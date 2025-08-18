// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/EigenVaultServiceManager.sol";
import "../src/EigenVaultHook.sol";
import "../src/OrderVault.sol";
import "../src/interfaces/IEigenVaultHook.sol";
import "../src/interfaces/IOrderVault.sol";
import "./utils/EigenVaultTestBase.sol";

contract EigenVaultServiceManagerTest is Test, EigenVaultTestBase {
    EigenVaultServiceManager public serviceManager;
    EigenVaultHook public hook;
    OrderVault public orderVault;

    function setUp() public override {
        // Deploy order vault
        orderVault = new OrderVault();

        // Deploy service manager with simplified constructor
        serviceManager = new EigenVaultServiceManager(
            IEigenVaultHook(address(0)), // Will update after hook deployment
            IOrderVault(address(orderVault))
        );

        // Deploy hook with service manager
        hook = new EigenVaultHook(
            IPoolManager(address(mockPoolManager)),
            address(orderVault),
            address(serviceManager)
        );

        // Give test accounts some ETH for staking
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);
    }

    function testOperatorRegistration() public {
        // Register operator1 with minimum stake
        vm.prank(operator1);
        serviceManager.registerOperator{value: 1 ether}();

        // Check operator info
        (bool isRegistered, uint256 stake, bool isSlashed) = serviceManager.getOperatorInfo(operator1);
        assertTrue(isRegistered);
        assertEq(stake, 1 ether);
        assertFalse(isSlashed);

        // Check active operators
        address[] memory operators = serviceManager.getActiveOperators();
        assertEq(operators.length, 1);
        assertEq(operators[0], operator1);
    }

    function testTaskCreation() public {
        // Register an operator first
        vm.prank(operator1);
        serviceManager.registerOperator{value: 1 ether}();

        // Create a task
        bytes32 ordersHash = keccak256("test_orders");
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 taskId = serviceManager.createTask(ordersHash, deadline);
        assertTrue(taskId != bytes32(0));

        // Check task details
        (
            bytes32 returnedOrdersHash,
            uint256 returnedDeadline,
            bool completed,
            address assignedOperator,
            bytes32 resultHash
        ) = serviceManager.getTask(taskId);

        assertEq(returnedOrdersHash, ordersHash);
        assertEq(returnedDeadline, deadline);
        assertFalse(completed);
        assertEq(assignedOperator, operator1);
        assertEq(resultHash, bytes32(0));
    }

    function testTaskSubmission() public {
        // Register an operator
        vm.prank(operator1);
        serviceManager.registerOperator{value: 1 ether}();

        // Create a task
        bytes32 ordersHash = keccak256("test_orders");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 taskId = serviceManager.createTask(ordersHash, deadline);

        // Submit task response
        bytes memory response = "test_response";
        bytes32 resultHash = keccak256("test_result");
        
        vm.prank(operator1);
        serviceManager.submitTaskResponse(taskId, response, resultHash);

        // Check task completion
        (,,bool completed,, bytes32 returnedResultHash) = serviceManager.getTask(taskId);
        assertTrue(completed);
        assertEq(returnedResultHash, resultHash);

        // Check operator stats
        (,, bool isSlashed) = serviceManager.getOperatorInfo(operator1);
        assertFalse(isSlashed);
    }

    function testOperatorSlashing() public {
        // Register an operator
        vm.prank(operator1);
        serviceManager.registerOperator{value: 10 ether}();

        // Slash the operator
        serviceManager.slashOperator(operator1, 5 ether);

        // Check operator info
        (bool isRegistered, uint256 stake, bool isSlashed) = serviceManager.getOperatorInfo(operator1);
        assertTrue(isRegistered);
        assertEq(stake, 5 ether);
        assertTrue(isSlashed);
    }

    function test_RevertWhen_InsufficientStake() public {
        // Try to register with insufficient stake
        vm.prank(operator1);
        vm.expectRevert("Insufficient stake");
        serviceManager.registerOperator{value: 0.5 ether}(); // Less than minimum stake
    }

    function test_RevertWhen_UnregisteredOperatorTaskSubmission() public {
        // Create a task first
        vm.prank(operator1);
        serviceManager.registerOperator{value: 1 ether}();
        
        bytes32 taskId = serviceManager.createTask(keccak256("test"), block.timestamp + 1 hours);

        // Try to submit from unregistered operator
        vm.prank(operator2);
        vm.expectRevert("Operator not registered");
        serviceManager.submitTaskResponse(taskId, "response", keccak256("result"));
    }
}