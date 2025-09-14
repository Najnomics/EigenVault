#!/bin/bash

# Script to fix remaining test files with EigenLayer interface issues

# List of files that still need fixing
FILES=(
    "test/security/AdvancedSecurityTests.t.sol"
    "test/integration/StressTests.t.sol"
    "test/integration/PerformanceTests.t.sol"
    "test/resilience/ProtocolResilienceTests.t.sol"
    "test/hooks/EigenVaultHookWorkingTest.t.sol"
    "test/hooks/EigenVaultHookDirectTest.t.sol"
    "test/hooks/EigenVaultHookCompleteTest.t.sol"
    "test/hooks/EigenVaultHookComprehensive.t.sol"
    "test/hooks/EigenVaultHookUnitTest.t.sol"
)

IMPORTS_TO_ADD='import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import "../mocks/EigenLayerMocks.sol";'

MOCK_DECLARATIONS='
    // Mock contracts
    MockAVSDirectory public mockAVSDirectory;
    MockRewardsCoordinator public mockRewardsCoordinator;
    MockSlashingRegistryCoordinator public mockRegistryCoordinator;
    MockStakeRegistry public mockStakeRegistry;
    MockPermissionController public mockPermissionController;
    MockAllocationManager public mockAllocationManager;'

MOCK_SETUP='        // Deploy mock contracts
        mockAVSDirectory = new MockAVSDirectory();
        mockRewardsCoordinator = new MockRewardsCoordinator();
        mockRegistryCoordinator = new MockSlashingRegistryCoordinator();
        mockStakeRegistry = new MockStakeRegistry();
        mockPermissionController = new MockPermissionController();
        mockAllocationManager = new MockAllocationManager();'

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Fixing $file"
        
        # Add imports after existing imports
        sed -i '' '/import.*Test.sol/a\
'"$IMPORTS_TO_ADD"'
' "$file"
        
        # Add mock declarations after contract declaration  
        sed -i '' '/contract.*Test {/a\
'"$MOCK_DECLARATIONS"'
' "$file"
        
        # Add mock setup at the beginning of setUp function
        sed -i '' '/function setUp() public {/a\
'"$MOCK_SETUP"'
' "$file"
        
        # Replace the AVS constructor calls
        sed -i '' 's/new EigenVaultAVSServiceManager(address(0), address(0), address(0), address(0), address(0), address(0))/new EigenVaultAVSServiceManager(\
            IAVSDirectory(address(mockAVSDirectory)),\
            IRewardsCoordinator(address(mockRewardsCoordinator)),\
            ISlashingRegistryCoordinator(address(mockRegistryCoordinator)),\
            IStakeRegistry(address(mockStakeRegistry)),\
            IPermissionController(address(mockPermissionController)),\
            IAllocationManager(address(mockAllocationManager))\
        )/g' "$file"
        
        echo "Fixed $file"
    else
        echo "File not found: $file"
    fi
done

echo "All remaining files have been processed!"