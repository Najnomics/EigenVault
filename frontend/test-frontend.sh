#!/bin/bash

echo "🧪 Testing EigenVault Frontend Setup"
echo "===================================="

# Check if we're in the frontend directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: Please run this script from the frontend directory"
    exit 1
fi

# Check Node.js version
echo "📋 Checking Node.js version..."
NODE_VERSION=$(node --version)
if [[ $NODE_VERSION == v18* ]] || [[ $NODE_VERSION == v19* ]] || [[ $NODE_VERSION == v20* ]]; then
    echo "✅ Node.js version: $NODE_VERSION"
else
    echo "⚠️  Warning: Node.js version $NODE_VERSION detected. Version 18+ recommended."
fi

# Check if dependencies are installed
echo "📦 Checking dependencies..."
if [ -d "node_modules" ]; then
    echo "✅ Dependencies are installed"
else
    echo "❌ Dependencies not found. Installing..."
    yarn install
fi

# Check if Vite is available
echo "⚡ Checking Vite..."
if yarn list vite > /dev/null 2>&1; then
    echo "✅ Vite is installed"
else
    echo "❌ Vite not found. Installing..."
    yarn add -D vite @vitejs/plugin-react
fi

# Check if React is available
echo "⚛️  Checking React..."
if yarn list react > /dev/null 2>&1; then
    echo "✅ React is installed"
else
    echo "❌ React not found. Installing..."
    yarn add react react-dom
fi

# Check if ethers is available
echo "🔗 Checking ethers..."
if yarn list ethers > /dev/null 2>&1; then
    echo "✅ Ethers.js is installed"
else
    echo "❌ Ethers.js not found. Installing..."
    yarn add ethers
fi

# Check configuration files
echo "⚙️  Checking configuration files..."
if [ -f "vite.config.js" ]; then
    echo "✅ Vite config found"
else
    echo "❌ Vite config missing"
fi

if [ -f "index.html" ]; then
    echo "✅ HTML template found"
else
    echo "❌ HTML template missing"
fi

if [ -f "src/main.jsx" ]; then
    echo "✅ Main entry point found"
else
    echo "❌ Main entry point missing"
fi

# Check component files
echo "🧩 Checking component files..."
COMPONENTS=("OrderForm" "VaultStatus" "OperatorList")
for component in "${COMPONENTS[@]}"; do
    if [ -f "src/components/${component}.jsx" ]; then
        echo "✅ ${component} component found"
    else
        echo "❌ ${component} component missing"
    fi
    
    if [ -f "src/components/${component}.css" ]; then
        echo "✅ ${component} styles found"
    else
        echo "❌ ${component} styles missing"
    fi
done

# Test build
echo "🔨 Testing build process..."
if yarn build > /dev/null 2>&1; then
    echo "✅ Build successful"
else
    echo "❌ Build failed"
    echo "Running build with verbose output..."
    yarn build
fi

echo ""
echo "🎉 Frontend setup test completed!"
echo ""
echo "To start the development server:"
echo "  yarn dev"
echo ""
echo "To build for production:"
echo "  yarn build"
echo ""
echo "To preview production build:"
echo "  yarn preview" 