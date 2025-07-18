#!/bin/bash
set -e

echo "🚀 Building Rate Limiter Service..."

# Create directories
mkdir -p third_party build

echo "📦 Installing dependencies..."

# Install system dependencies (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew not found. Please install Homebrew first."
        exit 1
    fi
    
    echo "Installing Redis and hiredis via Homebrew..."
    brew install redis hiredis pkg-config
    
    # Install redis-plus-plus
    if [ ! -d "third_party/redis-plus-plus" ]; then
        echo "Cloning redis-plus-plus..."
        cd third_party
        git clone https://github.com/sewenew/redis-plus-plus.git
        cd redis-plus-plus
        mkdir -p build
        cd build
        cmake -DCMAKE_BUILD_TYPE=Release ..
        make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
        sudo make install
        cd ../../..
    fi
fi

# Download header-only libraries
echo "📥 Downloading header-only libraries..."

# httplib
if [ ! -f "third_party/httplib/httplib.h" ]; then
    mkdir -p third_party/httplib
    curl -L "https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h" \
         -o third_party/httplib/httplib.h
    echo "✓ Downloaded httplib"
fi

# nlohmann/json
if [ ! -d "third_party/json" ]; then
    cd third_party
    git clone --depth 1 --branch v3.11.2 https://github.com/nlohmann/json.git
    cd ..
    echo "✓ Downloaded nlohmann/json"
fi

echo "🔨 Building project..."

# Build the project
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

echo "✅ Build complete!"
echo ""
echo "To run the service:"
echo "  cd build && ./rate_limiter"
echo ""
echo "Make sure Redis is running:"
echo "  redis-server"