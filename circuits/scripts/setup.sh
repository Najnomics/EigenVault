#!/bin/bash

# Setup script for EigenVault ZK circuit development environment
# This script installs required dependencies for circuit compilation

set -e

echo "EigenVault Circuit Setup Script"
echo "==============================="

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install Node.js first."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "npm is not installed. Please install npm first."
    exit 1
fi

# Install circom
echo "Installing circom..."
if ! command -v circom &> /dev/null; then
    # Install Rust if not present
    if ! command -v cargo &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
    fi
    
    # Install circom
    git clone https://github.com/iden3/circom.git
    cd circom
    cargo build --release
    cargo install --path circom
    cd ..
    rm -rf circom
    
    echo "✓ Circom installed successfully"
else
    echo "✓ Circom already installed"
fi

# Install snarkjs
echo "Installing snarkjs..."
if ! command -v snarkjs &> /dev/null; then
    npm install -g snarkjs
    echo "✓ SnarkJS installed successfully"
else
    echo "✓ SnarkJS already installed"
fi

# Install circomlib
echo "Installing circomlib..."
if [ ! -d "node_modules/circomlib" ]; then
    npm install circomlib
    echo "✓ Circomlib installed successfully"
else
    echo "✓ Circomlib already installed"
fi

# Install additional dependencies
echo "Installing additional dependencies..."
npm install --save-dev @types/circomlib

# Create build directory
mkdir -p build

# Download powers of tau file for testing
PTAU_FILE="build/powersOfTau28_hez_final_15.ptau"
if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading powers of tau file..."
    wget -O "$PTAU_FILE" https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_15.ptau
    echo "✓ Powers of tau file downloaded"
else
    echo "✓ Powers of tau file already exists"
fi

# Make scripts executable
chmod +x scripts/*.sh

echo ""
echo "Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run './scripts/compile.sh' to compile circuits"
echo "2. Run './scripts/generate_proof.sh' to test proof generation"
echo ""
echo "Available commands:"
echo "- circom: Circuit compiler"
echo "- snarkjs: SNARK JavaScript toolkit"
echo "- node_modules/circomlib: Circuit library"