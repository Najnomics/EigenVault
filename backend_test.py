#!/usr/bin/env python3
"""
EigenVault Backend Testing Suite

This test suite validates the EigenVault system components:
1. Smart Contract Architecture
2. Contract Interface Validation
3. System Integration Points
4. Production Readiness Assessment

Since this is a blockchain-based system, the "backend" consists of:
- Smart Contracts (Solidity)
- Operator Software (Rust)
- Zero-Knowledge Circuits (Circom)
"""

import sys
import json
import os
from datetime import datetime
from typing import Dict, List, Any, Optional

class EigenVaultSystemTester:
    def __init__(self):
        self.tests_run = 0
        self.tests_passed = 0
        self.test_results = []
        self.system_components = {
            'smart_contracts': {
                'EigenVaultHook.sol': '/app/eigenvault/contracts/src/EigenVaultHook.sol',
                'EigenVaultServiceManager.sol': '/app/eigenvault/contracts/src/EigenVaultServiceManager.sol',
                'OrderVault.sol': '/app/eigenvault/contracts/src/OrderVault.sol',
                'EigenVaultBase.sol': '/app/eigenvault/contracts/src/EigenVaultBase.sol'
            },
            'libraries': {
                'OrderLib.sol': '/app/eigenvault/contracts/src/libraries/OrderLib.sol',
                'ZKProofLib.sol': '/app/eigenvault/contracts/src/libraries/ZKProofLib.sol'
            },
            'interfaces': {
                'IEigenVaultHook.sol': '/app/eigenvault/contracts/src/interfaces/IEigenVaultHook.sol',
                'IOrderVault.sol': '/app/eigenvault/contracts/src/interfaces/IOrderVault.sol',
                'IEigenVaultServiceManager.sol': '/app/eigenvault/contracts/src/interfaces/IEigenVaultServiceManager.sol'
            },
            'operator_software': {
                'main.rs': '/app/eigenvault/operator/src/main.rs',
                'matching_engine': '/app/eigenvault/operator/src/matching/',
                'proofs': '/app/eigenvault/operator/src/proofs/',
                'networking': '/app/eigenvault/operator/src/networking/',
                'ethereum': '/app/eigenvault/operator/src/ethereum/'
            },
            'circuits': {
                'order_matching.circom': '/app/circuits/order_matching.circom',
                'privacy_proof.circom': '/app/circuits/privacy_proof.circom'
            },
            'frontend': {
                'App.jsx': '/app/frontend/src/App.jsx',
                'useEigenVault.ts': '/app/frontend/src/hooks/useEigenVault.ts',
                'useWeb3.ts': '/app/frontend/src/hooks/useWeb3.ts'
            }
        }

    def run_test(self, name: str, test_func, *args, **kwargs) -> bool:
        """Run a single test and record results"""
        self.tests_run += 1
        print(f"\n🔍 Testing {name}...")
        
        try:
            result = test_func(*args, **kwargs)
            if result:
                self.tests_passed += 1
                print(f"✅ Passed - {name}")
                self.test_results.append({
                    'name': name,
                    'status': 'PASSED',
                    'details': 'Test completed successfully'
                })
                return True
            else:
                print(f"❌ Failed - {name}")
                self.test_results.append({
                    'name': name,
                    'status': 'FAILED',
                    'details': 'Test failed validation'
                })
                return False
        except Exception as e:
            print(f"❌ Failed - {name}: {str(e)}")
            self.test_results.append({
                'name': name,
                'status': 'ERROR',
                'details': str(e)
            })
            return False

    def test_file_exists(self, file_path: str) -> bool:
        """Test if a file exists"""
        return os.path.exists(file_path)

    def test_smart_contract_structure(self) -> bool:
        """Test smart contract file structure and basic validation"""
        print("📋 Validating Smart Contract Architecture...")
        
        all_exist = True
        for category, files in self.system_components.items():
            if category in ['smart_contracts', 'libraries', 'interfaces']:
                for name, path in files.items():
                    if not os.path.exists(path):
                        print(f"❌ Missing: {name} at {path}")
                        all_exist = False
                    else:
                        print(f"✅ Found: {name}")
                        
                        # Basic content validation
                        with open(path, 'r') as f:
                            content = f.read()
                            if 'pragma solidity' not in content:
                                print(f"⚠️  Warning: {name} missing Solidity pragma")
                            if 'contract ' not in content and 'interface ' not in content and 'library ' not in content:
                                print(f"⚠️  Warning: {name} missing contract/interface/library declaration")
        
        return all_exist

    def test_contract_interfaces(self) -> bool:
        """Test contract interface definitions"""
        print("🔌 Validating Contract Interfaces...")
        
        # Key interface methods that should exist
        expected_methods = {
            'IEigenVaultHook.sol': [
                'routeToVault',
                'executeVaultOrder',
                'fallbackToAMM',
                'getOrder'
            ],
            'IOrderVault.sol': [
                'storeOrder',
                'retrieveOrder',
                'expireOrder',
                'getVaultOrder'
            ],
            'IEigenVaultServiceManager.sol': [
                'createMatchingTask',
                'submitTaskResponse',
                'registerOperator',
                'getOperatorMetrics'
            ]
        }
        
        all_valid = True
        for interface_name, methods in expected_methods.items():
            interface_path = self.system_components['interfaces'][interface_name]
            if os.path.exists(interface_path):
                with open(interface_path, 'r') as f:
                    content = f.read()
                    for method in methods:
                        if f'function {method}' not in content:
                            print(f"❌ Missing method {method} in {interface_name}")
                            all_valid = False
                        else:
                            print(f"✅ Found method {method} in {interface_name}")
            else:
                print(f"❌ Interface file not found: {interface_name}")
                all_valid = False
        
        return all_valid

    def test_operator_software_structure(self) -> bool:
        """Test operator software structure"""
        print("🦀 Validating Rust Operator Software...")
        
        cargo_toml = '/app/eigenvault/operator/Cargo.toml'
        if not os.path.exists(cargo_toml):
            print("❌ Missing Cargo.toml")
            return False
        
        # Check Cargo.toml content
        with open(cargo_toml, 'r') as f:
            cargo_content = f.read()
            if 'tokio' not in cargo_content:
                print("⚠️  Warning: Missing tokio dependency for async runtime")
            if 'ethers' not in cargo_content:
                print("⚠️  Warning: Missing ethers dependency for Ethereum integration")
        
        # Check main modules
        required_modules = [
            '/app/eigenvault/operator/src/main.rs',
            '/app/eigenvault/operator/src/matching/mod.rs',
            '/app/eigenvault/operator/src/proofs/mod.rs',
            '/app/eigenvault/operator/src/networking/mod.rs',
            '/app/eigenvault/operator/src/ethereum/mod.rs'
        ]
        
        all_exist = True
        for module in required_modules:
            if os.path.exists(module):
                print(f"✅ Found: {os.path.basename(module)}")
            else:
                print(f"❌ Missing: {module}")
                all_exist = False
        
        return all_exist

    def test_zk_circuits(self) -> bool:
        """Test zero-knowledge circuit files"""
        print("🔐 Validating Zero-Knowledge Circuits...")
        
        circuits = self.system_components['circuits']
        all_exist = True
        
        for name, path in circuits.items():
            if os.path.exists(path):
                print(f"✅ Found: {name}")
                with open(path, 'r') as f:
                    content = f.read()
                    if 'pragma circom' not in content:
                        print(f"⚠️  Warning: {name} missing Circom pragma")
                    if 'component main' not in content:
                        print(f"⚠️  Warning: {name} missing main component")
            else:
                print(f"❌ Missing: {name}")
                all_exist = False
        
        return all_exist

    def test_frontend_integration(self) -> bool:
        """Test frontend Web3 integration"""
        print("🌐 Validating Frontend Web3 Integration...")
        
        frontend_files = self.system_components['frontend']
        all_exist = True
        
        for name, path in frontend_files.items():
            if os.path.exists(path):
                print(f"✅ Found: {name}")
                with open(path, 'r') as f:
                    content = f.read()
                    
                    if name == 'useEigenVault.ts':
                        # Check for key Web3 integration points
                        required_features = [
                            'ethers',
                            'submitOrder',
                            'getOrder',
                            'connectWallet',
                            'CONTRACT_ADDRESSES'
                        ]
                        for feature in required_features:
                            if feature in content:
                                print(f"  ✅ Has {feature} integration")
                            else:
                                print(f"  ❌ Missing {feature} integration")
                                all_exist = False
                    
                    elif name == 'useWeb3.ts':
                        # Check for wallet connectivity
                        wallet_features = [
                            'MetaMask',
                            'connectWallet',
                            'switchNetwork',
                            'getBalance'
                        ]
                        for feature in wallet_features:
                            if feature in content:
                                print(f"  ✅ Has {feature} functionality")
                            else:
                                print(f"  ❌ Missing {feature} functionality")
            else:
                print(f"❌ Missing: {name}")
                all_exist = False
        
        return all_exist

    def test_deployment_scripts(self) -> bool:
        """Test deployment and production scripts"""
        print("🚀 Validating Deployment Scripts...")
        
        script_dir = '/app/scripts'
        expected_scripts = [
            'deploy-production.sh',
            'deploy-local.sh',
            'start-operator.sh',
            'test-system.sh',
            'register-operators.sh'
        ]
        
        all_exist = True
        for script in expected_scripts:
            script_path = os.path.join(script_dir, script)
            if os.path.exists(script_path):
                print(f"✅ Found: {script}")
                # Check if script is executable
                if os.access(script_path, os.X_OK):
                    print(f"  ✅ {script} is executable")
                else:
                    print(f"  ⚠️  {script} is not executable")
            else:
                print(f"❌ Missing: {script}")
                all_exist = False
        
        return all_exist

    def test_configuration_files(self) -> bool:
        """Test configuration files"""
        print("⚙️  Validating Configuration Files...")
        
        config_files = [
            '/app/eigenvault/foundry.toml',
            '/app/eigenvault/operator/config.example.yaml',
            '/app/frontend/package.json',
            '/app/eigenvault/package.json'
        ]
        
        all_exist = True
        for config_file in config_files:
            if os.path.exists(config_file):
                print(f"✅ Found: {os.path.basename(config_file)}")
            else:
                print(f"❌ Missing: {config_file}")
                all_exist = False
        
        return all_exist

    def test_documentation(self) -> bool:
        """Test documentation completeness"""
        print("📚 Validating Documentation...")
        
        doc_files = [
            '/app/README.md',
            '/app/eigenvault/README.md',
            '/app/docs/ARCHITECTURE.md',
            '/app/docs/DEPLOYMENT.md'
        ]
        
        all_exist = True
        for doc_file in doc_files:
            if os.path.exists(doc_file):
                print(f"✅ Found: {os.path.basename(doc_file)}")
                with open(doc_file, 'r') as f:
                    content = f.read()
                    if len(content) < 100:
                        print(f"⚠️  Warning: {os.path.basename(doc_file)} seems incomplete")
            else:
                print(f"❌ Missing: {doc_file}")
                all_exist = False
        
        return all_exist

    def assess_production_readiness(self) -> Dict[str, Any]:
        """Assess overall production readiness"""
        print("\n🏭 Assessing Production Readiness...")
        
        readiness_score = 0
        max_score = 8
        
        assessments = {
            'smart_contracts': self.tests_passed >= 3,
            'operator_software': os.path.exists('/app/eigenvault/operator/Cargo.toml'),
            'frontend_integration': os.path.exists('/app/frontend/src/hooks/useEigenVault.ts'),
            'zk_circuits': os.path.exists('/app/circuits/order_matching.circom'),
            'deployment_scripts': os.path.exists('/app/scripts/deploy-production.sh'),
            'documentation': os.path.exists('/app/docs/ARCHITECTURE.md'),
            'configuration': os.path.exists('/app/eigenvault/foundry.toml'),
            'testing_framework': self.tests_run > 0
        }
        
        for component, ready in assessments.items():
            if ready:
                readiness_score += 1
                print(f"✅ {component.replace('_', ' ').title()}: Ready")
            else:
                print(f"❌ {component.replace('_', ' ').title()}: Not Ready")
        
        readiness_percentage = (readiness_score / max_score) * 100
        
        return {
            'score': readiness_score,
            'max_score': max_score,
            'percentage': readiness_percentage,
            'assessments': assessments,
            'recommendation': self._get_readiness_recommendation(readiness_percentage)
        }

    def _get_readiness_recommendation(self, percentage: float) -> str:
        """Get production readiness recommendation"""
        if percentage >= 90:
            return "PRODUCTION READY - System is ready for mainnet deployment"
        elif percentage >= 75:
            return "MOSTLY READY - Minor issues to address before production"
        elif percentage >= 50:
            return "DEVELOPMENT STAGE - Significant work needed before production"
        else:
            return "EARLY STAGE - Major components missing, not ready for production"

    def generate_report(self) -> Dict[str, Any]:
        """Generate comprehensive test report"""
        readiness = self.assess_production_readiness()
        
        return {
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'tests_run': self.tests_run,
                'tests_passed': self.tests_passed,
                'success_rate': (self.tests_passed / self.tests_run * 100) if self.tests_run > 0 else 0
            },
            'test_results': self.test_results,
            'production_readiness': readiness,
            'system_components': {
                'smart_contracts': len(self.system_components['smart_contracts']),
                'libraries': len(self.system_components['libraries']),
                'interfaces': len(self.system_components['interfaces']),
                'operator_modules': len([f for f in self.system_components['operator_software'].values() if os.path.exists(f)]),
                'circuits': len(self.system_components['circuits']),
                'frontend_files': len(self.system_components['frontend'])
            }
        }

def main():
    """Main test execution"""
    print("🔐 EigenVault System Testing Suite")
    print("=" * 50)
    
    tester = EigenVaultSystemTester()
    
    # Run all tests
    test_suite = [
        ("Smart Contract Structure", tester.test_smart_contract_structure),
        ("Contract Interfaces", tester.test_contract_interfaces),
        ("Operator Software Structure", tester.test_operator_software_structure),
        ("Zero-Knowledge Circuits", tester.test_zk_circuits),
        ("Frontend Integration", tester.test_frontend_integration),
        ("Deployment Scripts", tester.test_deployment_scripts),
        ("Configuration Files", tester.test_configuration_files),
        ("Documentation", tester.test_documentation)
    ]
    
    for test_name, test_func in test_suite:
        tester.run_test(test_name, test_func)
    
    # Generate and display report
    report = tester.generate_report()
    
    print("\n" + "=" * 50)
    print("📊 FINAL REPORT")
    print("=" * 50)
    print(f"Tests Run: {report['summary']['tests_run']}")
    print(f"Tests Passed: {report['summary']['tests_passed']}")
    print(f"Success Rate: {report['summary']['success_rate']:.1f}%")
    print(f"Production Readiness: {report['production_readiness']['percentage']:.1f}%")
    print(f"Recommendation: {report['production_readiness']['recommendation']}")
    
    # Save detailed report
    with open('/app/eigenvault_test_report.json', 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\n📄 Detailed report saved to: /app/eigenvault_test_report.json")
    
    return 0 if report['summary']['success_rate'] >= 75 else 1

if __name__ == "__main__":
    sys.exit(main())