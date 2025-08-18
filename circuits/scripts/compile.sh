#!/bin/bash

# Circuit compilation script for EigenVault ZK circuits
# This script compiles Circom circuits and generates proving/verification keys

set -e

CIRCUITS_DIR="$(dirname "$0")/.."
BUILD_DIR="$CIRCUITS_DIR/build"
PTAU_FILE="$BUILD_DIR/powersOfTau28_hez_final_15.ptau"

echo "EigenVault Circuit Compilation Script"
echo "======================================"

# Create build directory
mkdir -p "$BUILD_DIR"

# Check if circomlib is available
if [ ! -d "node_modules/circomlib" ]; then
    echo "Installing circomlib..."
    npm install circomlib
fi

# Download powers of tau file if it doesn't exist
if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading powers of tau file..."
    wget -O "$PTAU_FILE" https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_15.ptau
fi

# Compile order matching circuit
echo "Compiling order matching circuit..."
circom "$CIRCUITS_DIR/order_matching.circom" \
    --r1cs \
    --wasm \
    --sym \
    -o "$BUILD_DIR" \
    --include node_modules

if [ $? -eq 0 ]; then
    echo "✓ Order matching circuit compiled successfully"
else
    echo "✗ Failed to compile order matching circuit"
    exit 1
fi

# Compile privacy proof circuit
echo "Compiling privacy proof circuit..."
circom "$CIRCUITS_DIR/privacy_proof.circom" \
    --r1cs \
    --wasm \
    --sym \
    -o "$BUILD_DIR" \
    --include node_modules

if [ $? -eq 0 ]; then
    echo "✓ Privacy proof circuit compiled successfully"
else
    echo "✗ Failed to compile privacy proof circuit"
    exit 1
fi

# Generate proving and verification keys for order matching
echo "Generating keys for order matching circuit..."
snarkjs groth16 setup "$BUILD_DIR/order_matching.r1cs" "$PTAU_FILE" "$BUILD_DIR/order_matching_0000.zkey"
snarkjs zkey contribute "$BUILD_DIR/order_matching_0000.zkey" "$BUILD_DIR/order_matching_0001.zkey" --name="First contribution" -v -e="random entropy"
snarkjs zkey contribute "$BUILD_DIR/order_matching_0001.zkey" "$BUILD_DIR/order_matching_final.zkey" --name="Second contribution" -v -e="more random entropy"
snarkjs zkey export verificationkey "$BUILD_DIR/order_matching_final.zkey" "$BUILD_DIR/order_matching_verification_key.json"

# Generate proving and verification keys for privacy proof
echo "Generating keys for privacy proof circuit..."
snarkjs groth16 setup "$BUILD_DIR/privacy_proof.r1cs" "$PTAU_FILE" "$BUILD_DIR/privacy_proof_0000.zkey"
snarkjs zkey contribute "$BUILD_DIR/privacy_proof_0000.zkey" "$BUILD_DIR/privacy_proof_0001.zkey" --name="First contribution" -v -e="random entropy"
snarkjs zkey contribute "$BUILD_DIR/privacy_proof_0001.zkey" "$BUILD_DIR/privacy_proof_final.zkey" --name="Second contribution" -v -e="more random entropy"
snarkjs zkey export verificationkey "$BUILD_DIR/privacy_proof_final.zkey" "$BUILD_DIR/privacy_proof_verification_key.json"

echo ""
echo "Circuit compilation completed successfully!"
echo "Build artifacts are in: $BUILD_DIR"
echo ""
echo "Files generated:"
echo "- order_matching.r1cs"
echo "- order_matching_js/ (WASM)"
echo "- order_matching_final.zkey"
echo "- order_matching_verification_key.json"
echo "- privacy_proof.r1cs"
echo "- privacy_proof_js/ (WASM)"
echo "- privacy_proof_final.zkey"
echo "- privacy_proof_verification_key.json"