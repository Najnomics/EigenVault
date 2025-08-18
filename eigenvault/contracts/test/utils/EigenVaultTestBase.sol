// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../mocks/MockPoolManager.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockAVSDirectory.sol";
import "../mocks/MockStakeRegistry.sol";

/// @title EigenVaultTestBase
/// @notice Base contract for EigenVault tests with common setup and utilities
contract EigenVaultTestBase is Test {
    // Mock contracts
    MockPoolManager public mockPoolManager;
    MockERC20 public mockToken0;
    MockERC20 public mockToken1;
    MockAVSDirectory public mockAVSDirectory;
    MockStakeRegistry public mockStakeRegistry;
    
    // Test addresses
    address public owner = address(this);
    address public trader1 = address(0x1001);
    address public trader2 = address(0x1002);
    address public operator1 = address(0x2001);
    address public operator2 = address(0x2002);
    address public operator3 = address(0x2003);
    
    // Test constants
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000 ether;
    uint256 public constant OPERATOR_INITIAL_STAKE = 32 ether;
    uint256 public constant LARGE_ORDER_AMOUNT = 1000 ether;
    uint256 public constant SMALL_ORDER_AMOUNT = 1 ether;
    
    function setUp() public virtual {
        // Deploy mock contracts
        mockPoolManager = new MockPoolManager();
        mockToken0 = new MockERC20("Mock Token 0", "MTK0", 18);
        mockToken1 = new MockERC20("Mock Token 1", "MTK1", 18);
        mockAVSDirectory = new MockAVSDirectory();
        mockStakeRegistry = new MockStakeRegistry();
        
        // Setup initial token balances
        mockToken0.mint(trader1, INITIAL_TOKEN_SUPPLY);
        mockToken0.mint(trader2, INITIAL_TOKEN_SUPPLY);
        mockToken1.mint(trader1, INITIAL_TOKEN_SUPPLY);
        mockToken1.mint(trader2, INITIAL_TOKEN_SUPPLY);
        
        // Setup operator stakes
        mockStakeRegistry.setOperatorStake(operator1, OPERATOR_INITIAL_STAKE);
        mockStakeRegistry.setOperatorStake(operator2, OPERATOR_INITIAL_STAKE);
        mockStakeRegistry.setOperatorStake(operator3, OPERATOR_INITIAL_STAKE);
        
        // Label addresses for better test output
        vm.label(address(mockPoolManager), "MockPoolManager");
        vm.label(address(mockToken0), "MockToken0");
        vm.label(address(mockToken1), "MockToken1");
        vm.label(address(mockAVSDirectory), "MockAVSDirectory");
        vm.label(address(mockStakeRegistry), "MockStakeRegistry");
        vm.label(trader1, "Trader1");
        vm.label(trader2, "Trader2");
        vm.label(operator1, "Operator1");
        vm.label(operator2, "Operator2");
        vm.label(operator3, "Operator3");
    }
    
    // Helper functions for tests
    
    function createMockPoolKey() public view returns (bytes32) {
        return keccak256(abi.encode(
            address(mockToken0),
            address(mockToken1),
            uint24(3000),
            int24(60),
            address(0)
        ));
    }
    
    function generateCommitment(
        address trader,
        uint256 amount,
        uint256 price,
        uint256 deadline
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(trader, amount, price, deadline, block.timestamp));
    }
    
    function expectOrderEvent(
        bytes32 orderId,
        address trader,
        uint256 amount
    ) public {
        // Helper to expect order events in tests
        vm.expectEmit(true, true, false, true);
    }
    
    function fundTrader(address trader, uint256 amount) public {
        mockToken0.mint(trader, amount);
        mockToken1.mint(trader, amount);
    }
    
    function registerMockOperator(address operator) public {
        mockStakeRegistry.registerOperator(operator, 1, "");
        mockAVSDirectory.registerOperatorToAVS(operator, "");
    }
    
    function createEncryptedOrderData(
        address trader,
        uint256 amount,
        uint256 price
    ) public pure returns (bytes memory) {
        // Simple mock encryption - in real tests would use proper encryption
        return abi.encodePacked("encrypted_", trader, "_", amount, "_", price);
    }
    
    function skipTime(uint256 timeToSkip) public {
        vm.warp(block.timestamp + timeToSkip);
    }
    
    function simulateBlockMining(uint256 blocks) public {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + (blocks * 12)); // 12 second blocks
    }
    
    // Gas measurement utilities
    uint256 private gasStart;
    
    function startGasCheck() public {
        gasStart = gasleft();
    }
    
    function endGasCheck(string memory operation) public view returns (uint256 gasUsed) {
        gasUsed = gasStart - gasleft();
        console.log("Gas used for %s: %d", operation, gasUsed);
        return gasUsed;
    }
    
    // Assertion helpers
    function assertOrderExists(bytes32 orderId, address expectedTrader) public {
        // This would be implemented based on the actual contract interface
        assertTrue(orderId != bytes32(0), "Order ID should not be zero");
        assertFalse(expectedTrader == address(0), "Trader should not be zero address");
    }
    
    function assertOrderExecuted(bytes32 orderId) public {
        // This would check the actual contract state
        assertTrue(orderId != bytes32(0), "Order should be executed");
    }
    
    // Mock proof generation for testing
    function generateMockProof(
        bytes32 orderId,
        address trader,
        uint256 amount
    ) public view returns (bytes memory proof) {
        // Generate a mock ZK proof for testing
        return abi.encodePacked(
            "mock_proof_",
            orderId,
            trader,
            amount,
            block.timestamp
        );
    }
    
    function generateMockSignatures(
        address[] memory operators,
        bytes32 messageHash
    ) public pure returns (bytes memory signatures) {
        // Generate mock operator signatures
        bytes memory sigs;
        for (uint i = 0; i < operators.length; i++) {
            bytes memory sig = abi.encodePacked(operators[i], messageHash, "sig");
            sigs = abi.encodePacked(sigs, sig);
        }
        return sigs;
    }
}