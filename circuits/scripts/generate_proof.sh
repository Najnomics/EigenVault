#!/bin/bash

# Proof generation script for EigenVault ZK circuits
# This script generates test proofs to verify circuit functionality

set -e

CIRCUITS_DIR="$(dirname "$0")/.."
BUILD_DIR="$CIRCUITS_DIR/build"

echo "EigenVault Proof Generation Script"
echo "=================================="

# Check if circuits are compiled
if [ ! -f "$BUILD_DIR/order_matching_final.zkey" ]; then
    echo "Circuits not compiled. Running compilation first..."
    ./scripts/compile.sh
fi

# Generate test input for order matching circuit
echo "Generating test input for order matching..."
cat > "$BUILD_DIR/order_matching_input.json" <<EOF
{
    "orderCommitments": [
        "12345678901234567890123456789012345678901234567890123456789012345678",
        "23456789012345678901234567890123456789012345678901234567890123456789",
        "0", "0", "0", "0", "0", "0", "0", "0"
    ],
    "matchResultHash": "34567890123456789012345678901234567890123456789012345678901234567890",
    "poolKey": "1",
    "orderPrices": ["2000", "1999", "0", "0", "0", "0", "0", "0", "0", "0"],
    "orderAmounts": ["100", "100", "0", "0", "0", "0", "0", "0", "0", "0"],
    "orderTypes": ["0", "1", "0", "0", "0", "0", "0", "0", "0", "0"],
    "traderHashes": [
        "11111111111111111111111111111111111111111111111111111111111111111111",
        "22222222222222222222222222222222222222222222222222222222222222222222",
        "0", "0", "0", "0", "0", "0", "0", "0"
    ],
    "orderNonces": ["1001", "1002", "0", "0", "0", "0", "0", "0", "0", "0"],
    "matchedPrice": "1999",
    "matchedAmount": "100",
    "buyOrderIndex": "0",
    "sellOrderIndex": "1"
}
EOF

# Generate witness for order matching
echo "Generating witness for order matching circuit..."
node "$BUILD_DIR/order_matching_js/generate_witness.js" \
    "$BUILD_DIR/order_matching_js/order_matching.wasm" \
    "$BUILD_DIR/order_matching_input.json" \
    "$BUILD_DIR/order_matching_witness.wtns"

# Generate proof for order matching
echo "Generating proof for order matching circuit..."
snarkjs groth16 prove \
    "$BUILD_DIR/order_matching_final.zkey" \
    "$BUILD_DIR/order_matching_witness.wtns" \
    "$BUILD_DIR/order_matching_proof.json" \
    "$BUILD_DIR/order_matching_public.json"

# Verify proof for order matching
echo "Verifying proof for order matching circuit..."
snarkjs groth16 verify \
    "$BUILD_DIR/order_matching_verification_key.json" \
    "$BUILD_DIR/order_matching_public.json" \
    "$BUILD_DIR/order_matching_proof.json"

if [ $? -eq 0 ]; then
    echo "✓ Order matching proof verified successfully"
else
    echo "✗ Order matching proof verification failed"
    exit 1
fi

# Generate test input for privacy proof circuit
echo "Generating test input for privacy proof..."
cat > "$BUILD_DIR/privacy_proof_input.json" <<EOF
{
    "orderCommitments": [
        "12345678901234567890123456789012345678901234567890123456789012345678",
        "23456789012345678901234567890123456789012345678901234567890123456789",
        "0", "0", "0", "0", "0", "0", "0", "0"
    ],
    "validityHash": "45678901234567890123456789012345678901234567890123456789012345678901",
    "timestamp": "1640995200",
    "orderPrices": ["2000", "1999", "0", "0", "0", "0", "0", "0", "0", "0"],
    "orderAmounts": ["100", "100", "0", "0", "0", "0", "0", "0", "0", "0"],
    "orderDeadlines": ["1641081600", "1641081600", "0", "0", "0", "0", "0", "0", "0", "0"],
    "traderHashes": [
        "11111111111111111111111111111111111111111111111111111111111111111111",
        "22222222222222222222222222222222222222222222222222222222222222222222",
        "0", "0", "0", "0", "0", "0", "0", "0"
    ],
    "orderNonces": ["1001", "1002", "0", "0", "0", "0", "0", "0", "0", "0"],
    "minPrice": "1",
    "maxPrice": "1000000",
    "minAmount": "1",
    "maxAmount": "1000000"
}
EOF

# Generate witness for privacy proof
echo "Generating witness for privacy proof circuit..."
node "$BUILD_DIR/privacy_proof_js/generate_witness.js" \
    "$BUILD_DIR/privacy_proof_js/privacy_proof.wasm" \
    "$BUILD_DIR/privacy_proof_input.json" \
    "$BUILD_DIR/privacy_proof_witness.wtns"

# Generate proof for privacy proof
echo "Generating proof for privacy proof circuit..."
snarkjs groth16 prove \
    "$BUILD_DIR/privacy_proof_final.zkey" \
    "$BUILD_DIR/privacy_proof_witness.wtns" \
    "$BUILD_DIR/privacy_proof_proof.json" \
    "$BUILD_DIR/privacy_proof_public.json"

# Verify proof for privacy proof
echo "Verifying proof for privacy proof circuit..."
snarkjs groth16 verify \
    "$BUILD_DIR/privacy_proof_verification_key.json" \
    "$BUILD_DIR/privacy_proof_public.json" \
    "$BUILD_DIR/privacy_proof_proof.json"

if [ $? -eq 0 ]; then
    echo "✓ Privacy proof verified successfully"
else
    echo "✗ Privacy proof verification failed"
    exit 1
fi

echo ""
echo "All proofs generated and verified successfully!"
echo ""
echo "Generated files:"
echo "- $BUILD_DIR/order_matching_proof.json"
echo "- $BUILD_DIR/order_matching_public.json"
echo "- $BUILD_DIR/privacy_proof_proof.json"
echo "- $BUILD_DIR/privacy_proof_public.json"