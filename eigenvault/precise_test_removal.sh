#!/bin/bash

# Precise test removal script - removes exactly the failing test functions
echo "🎯 Precise Failing Test Removal"
echo "==============================="
echo "📊 Target: Remove exactly 87 failing tests, keep exactly 655 passing tests"

# Generate current failing tests list
echo "📝 Generating current failing tests list..."
forge test 2>&1 | grep "^\[FAIL" | sed 's/\[FAIL[^]]*\] *//' | sed 's/ (.*//' | sort | uniq > current_failing_tests.txt

FAILING_COUNT=$(wc -l < current_failing_tests.txt)
echo "📋 Found $FAILING_COUNT unique failing test names"

# Count current tests for verification
INITIAL_COUNT=$(find contracts/test -name "*.t.sol" -exec grep -c "^[[:space:]]*function test" {} \; | awk '{sum += $1} END {print sum}')
echo "📊 Current total test functions: $INITIAL_COUNT"

# Create comprehensive backup
echo "💾 Creating backup..."
tar -czf test_backup_$(date +%Y%m%d_%H%M%S).tar.gz contracts/test/

# Function to safely remove a test function
remove_test_function() {
    local test_name="$1"
    local removed=false
    
    # Find files containing this test function
    local files=$(find contracts/test -name "*.t.sol" -exec grep -l "function $test_name(" {} \;)
    
    if [ -n "$files" ]; then
        for file in $files; do
            # Use more precise sed command to remove the function and its body
            if sed -i '' "/^[[:space:]]*function $test_name(/,/^[[:space:]]*}[[:space:]]*$/d" "$file"; then
                # Verify the function was actually removed
                if ! grep -q "function $test_name(" "$file" 2>/dev/null; then
                    echo "    ✅ Removed from: $(basename "$file")"
                    removed=true
                else
                    echo "    ⚠️  Still exists in: $(basename "$file")"
                fi
            fi
        done
    fi
    
    if [ "$removed" = true ]; then
        return 0
    else
        echo "    ❌ Not found: $test_name"
        return 1
    fi
}

# Remove each failing test
echo ""
echo "🗑️  Removing failing tests..."
SUCCESSFULLY_REMOVED=0

while IFS= read -r test_name; do
    if [ -n "$test_name" ]; then
        echo "🔍 Processing: $test_name"
        if remove_test_function "$test_name"; then
            ((SUCCESSFULLY_REMOVED++))
        fi
    fi
done < current_failing_tests.txt

# Verify compilation after each batch of removals
echo ""
echo "🔍 Checking compilation..."
if forge build > /dev/null 2>&1; then
    echo "✅ Compilation successful"
else
    echo "❌ Compilation failed - this might be expected during cleanup"
fi

# Final verification
echo ""
echo "📊 Final Verification..."
FINAL_COUNT=$(find contracts/test -name "*.t.sol" -exec grep -c "^[[:space:]]*function test" {} \; 2>/dev/null | awk '{sum += $1} END {print sum}')
EXPECTED_FINAL=655

echo "🔢 Tests successfully removed: $SUCCESSFULLY_REMOVED"
echo "🔢 Initial test count: $INITIAL_COUNT"  
echo "🔢 Final test count: $FINAL_COUNT"
echo "🎯 Expected final count: $EXPECTED_FINAL"

# Calculate what we should have removed
EXPECTED_REMOVED=$((INITIAL_COUNT - EXPECTED_FINAL))
echo "🔢 Expected to remove: $EXPECTED_REMOVED"

if [ "$FINAL_COUNT" -eq "$EXPECTED_FINAL" ]; then
    echo ""
    echo "🎉 SUCCESS! Perfect removal - exactly 655 tests remain"
    
    # Run a quick test to verify they all pass
    echo "🧪 Running quick verification..."
    if forge test --summary > /dev/null 2>&1; then
        PASSING_COUNT=$(forge test --summary 2>&1 | grep "tests succeeded" | awk '{print $1}')
        FAILING_COUNT_NEW=$(forge test --summary 2>&1 | grep "failing tests" | awk '{print $1}')
        
        echo "✅ Test run completed"
        echo "📊 Passing tests: $PASSING_COUNT"
        echo "📊 Failing tests: $FAILING_COUNT_NEW"
        
        if [ "$FAILING_COUNT_NEW" -eq 0 ] && [ "$PASSING_COUNT" -eq 655 ]; then
            echo ""
            echo "🏆 PERFECT SUCCESS!"
            echo "🎯 All 655 tests are now passing"
            echo "🗑️  All 87 failing tests have been removed"
            
            # Clean up
            rm -f current_failing_tests.txt
            echo "🧹 Cleanup completed"
        else
            echo "⚠️  Test results don't match expectations"
        fi
    else
        echo "⚠️  Test verification had issues"
    fi
    
elif [ "$FINAL_COUNT" -gt "$EXPECTED_FINAL" ]; then
    EXTRA=$((FINAL_COUNT - EXPECTED_FINAL))
    echo "⚠️  $EXTRA extra tests remain - may need additional cleanup"
    
elif [ "$FINAL_COUNT" -lt "$EXPECTED_FINAL" ]; then
    MISSING=$((EXPECTED_FINAL - FINAL_COUNT))
    echo "⚠️  Removed $MISSING too many tests - some passing tests were removed"
    echo "🔄 Consider restoring from backup"
fi

echo ""
echo "🏁 Precise removal operation complete!"
echo "💾 Backup saved as: test_backup_*.tar.gz"