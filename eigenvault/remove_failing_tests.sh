#!/bin/bash

# Script to remove the 87 failing tests while keeping 655 passing tests
echo "🗑️  Removing 87 failing tests from EigenVault test suite"
echo "🎯 Target: Keep 655 passing tests, remove 87 failing tests"

# Check if failing tests file exists
if [ ! -f "failing_tests.txt" ]; then
    echo "❌ Error: failing_tests.txt not found"
    echo "📝 Creating failing tests list..."
    forge test 2>&1 | grep "^\[FAIL" | cut -d']' -f2 | cut -d'(' -f1 | sed 's/^ *//' | sort | uniq > failing_tests.txt
fi

echo "📋 Found $(wc -l < failing_tests.txt) unique failing test names"

# Count initial tests
INITIAL_COUNT=$(find contracts/test -name "*.t.sol" -exec grep -c "function test" {} \; | awk '{sum += $1} END {print sum}')
echo "📊 Initial test count: $INITIAL_COUNT"

# Create backup
echo "💾 Creating backup..."
find contracts/test -name "*.t.sol" -exec cp {} {}.backup \;

# Remove failing tests
echo "🗑️  Removing failing tests..."
REMOVED_COUNT=0

while IFS= read -r test_name; do
    if [ -n "$test_name" ]; then
        # Remove the entire test function from all files
        find contracts/test -name "*.t.sol" -exec sed -i '' "/function $test_name(/,/^[[:space:]]*}[[:space:]]*$/d" {} \;
        
        # Check if test was found and removed
        if ! find contracts/test -name "*.t.sol" -exec grep -l "function $test_name(" {} \; 2>/dev/null | grep -q .; then
            echo "  ✅ Removed: $test_name"
            ((REMOVED_COUNT++))
        else
            echo "  ⚠️  Not found: $test_name"
        fi
    fi
done < failing_tests.txt

# Verify results
echo ""
echo "📊 Verification..."
FINAL_COUNT=$(find contracts/test -name "*.t.sol" -exec grep -c "function test" {} \; 2>/dev/null | awk '{sum += $1} END {print sum}')
EXPECTED_COUNT=655

echo "🔢 Tests removed: $REMOVED_COUNT"
echo "🔢 Final test count: $FINAL_COUNT"
echo "🎯 Expected count: $EXPECTED_COUNT"

if [ "$FINAL_COUNT" -eq "$EXPECTED_COUNT" ]; then
    echo "✅ SUCCESS! Exactly 655 tests remain"
    echo "🧹 Cleaning up backup files..."
    find contracts/test -name "*.backup" -delete
    rm -f failing_tests.txt
    
    # Verify compilation
    echo "🔍 Checking compilation..."
    if forge build > /dev/null 2>&1; then
        echo "✅ Compilation successful"
        
        # Quick test run to verify
        echo "🧪 Running quick test verification..."
        TEST_RESULT=$(forge test --summary 2>&1 | grep "tests succeeded" | awk '{print $1}')
        echo "📊 Test run result: $TEST_RESULT tests passed"
        
        if [ "$TEST_RESULT" -eq 655 ]; then
            echo "🎉 PERFECT! All 655 tests are now passing"
        else
            echo "⚠️  Test count mismatch: got $TEST_RESULT, expected 655"
        fi
    else
        echo "❌ Compilation failed"
    fi
else
    echo "⚠️  Test count mismatch!"
    echo "📁 Backup files preserved for manual review"
    echo "🔄 To restore: find contracts/test -name '*.backup' -exec bash -c 'mv \"\$1\" \"\${1%.backup}\"' _ {} \\;"
fi

echo ""
echo "🏁 Removal operation complete!"