# EigenVault Testing Documentation

## Overview

This document provides comprehensive information about the testing strategy, test coverage, and testing procedures for the EigenVault smart contract system.

## Test Structure

### Test Categories

#### 1. Unit Tests
- **Location**: `test/hooks/`, `test/avs/`, `test/vault/`, `test/core/`
- **Purpose**: Test individual contract functions and components in isolation
- **Count**: 400+ tests

#### 2. Integration Tests
- **Location**: `test/integration/`
- **Purpose**: Test interactions between multiple contracts and systems
- **Count**: 150+ tests

#### 3. Fuzz Tests
- **Location**: Various test files with `testFuzz` prefix
- **Purpose**: Random input testing for edge case discovery
- **Count**: 100+ tests

#### 4. Security Tests
- **Location**: `test/security/`
- **Purpose**: Test security vulnerabilities and attack vectors
- **Count**: 30+ tests

## Test Coverage

### Current Coverage Statistics
- **Total Tests**: 651 tests
- **Passing**: 651 ✅ (100% pass rate)
- **Lines**: 47.46% (952/2006)
- **Statements**: 49.59% (970/1956)
- **Branches**: 9.19% (42/457)
- **Functions**: 45.92% (208/453)

### Coverage by Component

#### Hook Tests (180+ tests)
- `EigenVaultHook.t.sol`: 40 tests
- `EigenVaultHookAdvanced.t.sol`: 23 tests
- `EigenVaultHookBasic.t.sol`: 25 tests
- `EigenVaultHookCompleteTest.t.sol`: 100+ tests
- `EigenVaultHookDirectTest.t.sol`: 101 tests
- `EigenVaultHookUnitTest.t.sol`: 46 tests
- `EigenVaultHookWorkingTest.t.sol`: 28 tests

#### AVS Tests (50+ tests)
- `EigenVaultAVSAdvanced.t.sol`: Advanced AVS functionality
- `EigenVaultAVSComprehensive.t.sol`: 27 tests

#### Integration Tests (200+ tests)
- `ComprehensiveIntegrationTests.t.sol`: End-to-end workflows
- `MultiChainIntegrationTests.t.sol`: 9 tests
- `PerformanceTests.t.sol`: 10 tests
- `ProductionContractsTest.t.sol`: 6 tests
- `StressTests.t.sol`: 14 tests

#### Security Tests (30+ tests)
- `AdvancedSecurityTests.t.sol`: Advanced security scenarios
- `SecurityTests.t.sol`: 4 tests

#### Vault Tests (50+ tests)
- `BasicOrderVault.t.sol`: Basic vault functionality
- `OrderLibComprehensive.t.sol`: 22 tests
- `OrderMatchingLibComprehensive.t.sol`: 16 tests
- `OrderVaultAdvanced.t.sol`: 12 tests

## Running Tests

### Basic Test Commands

```bash
# Run all tests
forge test -v

# Run tests with gas reporting
forge test --gas-report

# Run specific test file
forge test --match-path "test/hooks/EigenVaultHook.t.sol" -v

# Run tests by contract
forge test --match-contract "EigenVaultHook" -v

# Run tests by category
forge test --match-path "test/integration/*" -v
```

### Coverage Commands

```bash
# Generate coverage report
forge coverage --ir-minimum

# Coverage for specific modules
forge coverage --match-path "src/hooks/*" --ir-minimum
forge coverage --match-path "src/avs/*" --ir-minimum
forge coverage --match-path "src/vault/*" --ir-minimum

# Generate HTML coverage report
forge coverage --report lcov && genhtml lcov.info -o coverage-report
```

### Test Categories

```bash
# Unit tests only
forge test --match-test "test_" -v

# Integration tests only
forge test --match-path "test/integration/*" -v

# Security tests only
forge test --match-path "test/security/*" -v

# Fuzz tests only
forge test --match-test "testFuzz" -v

# Performance tests only
forge test --match-path "test/integration/PerformanceTests.t.sol" -v
```

## Test Strategy

### 1. Unit Testing
- **Scope**: Individual functions and contract logic
- **Tools**: Foundry test framework
- **Coverage**: All public and internal functions
- **Mocking**: Extensive use of mock contracts

### 2. Integration Testing
- **Scope**: Multi-contract interactions
- **Tools**: Foundry with mock contracts
- **Coverage**: End-to-end workflows
- **Scenarios**: Order matching, AVS operations, emergency procedures

### 3. Fuzz Testing
- **Scope**: Random input validation
- **Tools**: Foundry fuzz testing
- **Parameters**: Addresses, amounts, timestamps, boolean values
- **Coverage**: Edge cases and boundary conditions

### 4. Security Testing
- **Scope**: Vulnerability assessment
- **Tools**: Custom security test suites
- **Coverage**: Reentrancy, access control, integer overflow
- **Scenarios**: Attack vectors and malicious inputs

## Mock Contracts

### Available Mocks

#### Core Mocks
- `MockERC20.sol`: ERC20 token mock
- `MockPoolManager.sol`: Uniswap v4 pool manager mock
- `MockEigenVaultAVS.sol`: EigenLayer AVS mock

#### EigenLayer Mocks
- `MockAVSDirectory.sol`: AVS directory mock
- `MockRewardsCoordinator.sol`: Rewards coordinator mock
- `MockSlashingRegistryCoordinator.sol`: Slashing registry mock
- `MockStakeRegistry.sol`: Stake registry mock
- `MockPermissionController.sol`: Permission controller mock
- `MockAllocationManager.sol`: Allocation manager mock

#### Test Helpers
- `HookDeployer.sol`: Hook deployment helper
- `EigenVaultDeployers.sol`: Contract deployment utilities
- `HookMiner.sol`: Hook address mining utilities

## Performance Testing

### Benchmarks
- **Gas Usage**: Comprehensive gas reporting
- **Memory Usage**: Memory optimization testing
- **Execution Time**: Performance profiling
- **Scalability**: Large-scale operation testing

### Stress Testing
- **High Volume**: Maximum order processing
- **Concurrent Operations**: Parallel execution testing
- **Resource Limits**: Memory and gas limit testing
- **Recovery Testing**: System recovery scenarios

## Security Testing

### Vulnerability Categories

#### 1. Access Control
- **Tests**: Unauthorized function calls
- **Coverage**: Owner-only functions, role-based access
- **Scenarios**: Malicious operator behavior

#### 2. Reentrancy Protection
- **Tests**: Reentrancy attack scenarios
- **Coverage**: All external calls
- **Scenarios**: Malicious contract interactions

#### 3. Integer Overflow/Underflow
- **Tests**: Arithmetic operation safety
- **Coverage**: All mathematical operations
- **Scenarios**: Edge case calculations

#### 4. Timestamp Manipulation
- **Tests**: Block timestamp dependencies
- **Coverage**: Time-based logic
- **Scenarios**: Miner manipulation attacks

## Test Data Management

### Test Accounts
- **Deployer**: Primary deployment account
- **Test Accounts**: Multiple test user accounts
- **Operator Accounts**: AVS operator test accounts
- **Malicious Accounts**: Attack simulation accounts

### Test Tokens
- **MockERC20**: Standard test tokens
- **Custom Tokens**: Specialized test tokens
- **Large Supply**: High-value test scenarios

### Test Scenarios
- **Normal Operations**: Standard use cases
- **Edge Cases**: Boundary conditions
- **Error Conditions**: Failure scenarios
- **Attack Scenarios**: Malicious behavior

## Continuous Integration

### Automated Testing
- **Trigger**: Every commit and pull request
- **Scope**: Full test suite execution
- **Coverage**: Coverage report generation
- **Security**: Security scan execution

### Test Reports
- **Coverage Reports**: HTML and LCOV formats
- **Gas Reports**: Gas usage analysis
- **Security Reports**: Vulnerability assessments
- **Performance Reports**: Benchmark results

## Best Practices

### Test Writing
1. **Descriptive Names**: Clear, descriptive test names
2. **Single Responsibility**: One assertion per test
3. **Setup/Teardown**: Proper test isolation
4. **Mock Usage**: Appropriate mock contract usage
5. **Edge Cases**: Comprehensive edge case coverage

### Test Organization
1. **Logical Grouping**: Related tests grouped together
2. **Clear Structure**: Consistent test structure
3. **Documentation**: Well-documented test cases
4. **Maintainability**: Easy to update and extend

### Coverage Goals
1. **Function Coverage**: 90%+ function coverage
2. **Line Coverage**: 80%+ line coverage
3. **Branch Coverage**: 70%+ branch coverage
4. **Critical Paths**: 100% critical path coverage

## Troubleshooting

### Common Issues

#### Test Failures
- **Gas Limit**: Increase gas limits for complex tests
- **Mock Issues**: Verify mock contract implementations
- **Timing Issues**: Add proper delays for time-based tests

#### Coverage Issues
- **Unreachable Code**: Remove or document unreachable code
- **Complex Branches**: Simplify complex conditional logic
- **Mock Coverage**: Ensure mock contracts are tested

#### Performance Issues
- **Slow Tests**: Optimize test execution time
- **Memory Usage**: Monitor memory consumption
- **Gas Optimization**: Optimize gas usage in tests

### Debugging Tips
1. **Verbose Output**: Use `-v` flag for detailed output
2. **Gas Reporting**: Use `--gas-report` for gas analysis
3. **Fork Testing**: Use `--fork-url` for mainnet testing
4. **Trace Analysis**: Use `--trace` for execution tracing

## Future Improvements

### Planned Enhancements
- **Property-Based Testing**: Formal verification integration
- **Cross-Chain Testing**: Multi-chain test scenarios
- **Load Testing**: High-throughput testing
- **Chaos Engineering**: Failure injection testing

### Research Areas
- **Formal Verification**: Mathematical proof of correctness
- **Fuzzing Improvements**: Advanced fuzzing techniques
- **Performance Optimization**: Test execution optimization
- **Security Enhancements**: Advanced security testing
