#!/bin/bash

# OBS Syphon Server Plugin Setup Script
# This script sets up all dependencies required to build the plugin

set -e  # Exit on any error

echo "🔧 Setting up OBS Syphon Server Plugin dependencies..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This plugin is macOS-specific. Syphon Framework only works on macOS."
    exit 1
fi

print_status "Detected macOS system ✓"

# Check if git is available
if ! command -v git &> /dev/null; then
    print_error "Git is required but not installed. Please install git first."
    exit 1
fi

# Check if cmake is available
if ! command -v cmake &> /dev/null; then
    print_warning "CMake not found. You'll need CMake 3.28+ to build this plugin."
    print_status "Install with: brew install cmake"
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

print_status "Working directory: $SCRIPT_DIR"

# Initialize git repository if not already done
if [ ! -d ".git" ]; then
    print_status "Initializing git repository..."
    git init
    print_success "Git repository initialized"
fi

# Add dependencies as submodules
print_status "Setting up project dependencies..."

mkdir -p deps

# Add Syphon Framework as a submodule
print_status "Setting up Syphon Framework dependency..."

SYPHON_DIR="deps/Syphon-Framework"

if [ -d "$SYPHON_DIR" ]; then
    print_warning "Syphon Framework directory already exists"
    print_status "Updating existing submodule..."
    git submodule update --init --recursive "$SYPHON_DIR"
else
    print_status "Adding Syphon Framework as submodule..."
    git submodule add https://github.com/Syphon/Syphon-Framework.git "$SYPHON_DIR"
    git submodule update --init --recursive "$SYPHON_DIR"
fi

print_success "Syphon Framework submodule configured"

# Check if Syphon framework was properly downloaded
if [ ! -f "$SYPHON_DIR/Syphon.h" ]; then
    print_error "Syphon Framework headers not found. Submodule may not have been cloned properly."
    print_status "Trying to update submodules..."
    git submodule update --init --recursive
    
    if [ ! -f "$SYPHON_DIR/Syphon.h" ]; then
        print_error "Failed to download Syphon Framework. Please check your internet connection and try again."
        exit 1
    fi
fi

# Add OBS Studio as a submodule for libobs headers and development
print_status "Setting up OBS Studio dependency..."

OBS_DIR="deps/obs-studio"

if [ -d "$OBS_DIR" ]; then
    print_warning "OBS Studio directory already exists"
    print_status "Updating existing submodule..."
    git submodule update --init --recursive "$OBS_DIR"
else
    print_status "Adding OBS Studio as submodule..."
    git submodule add https://github.com/obsproject/obs-studio.git "$OBS_DIR"
    print_status "Initializing OBS Studio submodule (this may take a while)..."
    git submodule update --init --recursive "$OBS_DIR"
fi

print_success "OBS Studio submodule configured"

# Check if OBS headers were properly downloaded
if [ ! -f "$OBS_DIR/libobs/obs.h" ]; then
    print_error "OBS Studio headers not found. Submodule may not have been cloned properly."
    print_status "Trying to update submodules..."
    git submodule update --init --recursive
    
    if [ ! -f "$OBS_DIR/libobs/obs.h" ]; then
        print_error "Failed to download OBS Studio. Please check your internet connection and try again."
        exit 1
    fi
fi

# Create build directory structure
print_status "Creating build directory structure..."
mkdir -p build
mkdir -p build/Debug
mkdir -p build/Release

print_success "Build directories created"

# Check for Xcode Command Line Tools
print_status "Checking for Xcode Command Line Tools..."
if ! xcode-select -p &> /dev/null; then
    print_warning "Xcode Command Line Tools not found"
    print_status "Installing Xcode Command Line Tools..."
    xcode-select --install
    print_status "Please complete the installation and run this script again"
    exit 1
else
    print_success "Xcode Command Line Tools found"
fi

# Check for Homebrew (optional but recommended)
if command -v brew &> /dev/null; then
    print_success "Homebrew found"
    
    # Check for common dependencies
    print_status "Checking for build dependencies..."
    
    if ! brew list cmake &> /dev/null; then
        print_warning "CMake not installed via Homebrew"
        print_status "Install with: brew install cmake"
    else
        CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
        print_success "CMake $CMAKE_VERSION found"
    fi
    
    if ! brew list ninja &> /dev/null; then
        print_status "Installing Ninja build system (recommended)..."
        brew install ninja
    else
        print_success "Ninja build system found"
    fi
    
else
    print_warning "Homebrew not found. Consider installing it for easier dependency management:"
    print_status "https://brew.sh"
fi

# Function to check if submodule is properly initialized
check_submodule() {
    local submodule_path="$1"
    local key_file="$2"
    local name="$3"
    
    if [ ! -d "$submodule_path" ] || [ ! -f "$submodule_path/$key_file" ]; then
        print_error "$name submodule not properly initialized"
        print_status "Run: git submodule update --init --recursive"
        return 1
    fi
    return 0
}

# Quick dependency check mode
if [ "$1" = "--check" ]; then
    print_status "🔍 Checking dependencies..."
    
    all_good=true
    
    if ! check_submodule "deps/Syphon-Framework" "Syphon.h" "Syphon Framework"; then
        all_good=false
    else
        print_success "Syphon Framework ✓"
    fi
    
    if ! check_submodule "deps/obs-studio" "libobs/obs.h" "OBS Studio"; then
        all_good=false
    else
        print_success "OBS Studio ✓"
    fi
    
    if [ -f "deps/obs-studio/build/libobs/libobs.dylib" ]; then
        print_success "OBS Studio built ✓"
    else
        print_warning "OBS Studio not built yet (run ./build.sh)"
    fi
    
    if $all_good; then
        print_success "🎉 All dependencies ready!"
        exit 0
    else
        print_error "❌ Some dependencies missing. Run ./setup.sh to fix."
        exit 1
    fi
fi

# Generate a comprehensive build script
print_status "Creating build helper script..."

cat > build.sh << 'EOF'
#!/bin/bash

# Build script for OBS Syphon Server Plugin

set -e

BUILD_TYPE=${1:-Debug}
OBS_BUILD_TYPE=${2:-$BUILD_TYPE}

echo "🔨 Building OBS Syphon Server Plugin..."
echo "Plugin Build Type: $BUILD_TYPE"
echo "OBS Build Type: $OBS_BUILD_TYPE"

# Check dependencies first
if [ ! -f "deps/Syphon-Framework/Syphon.h" ]; then
    echo "❌ Syphon Framework not found. Run ./setup.sh first."
    exit 1
fi

if [ ! -f "deps/obs-studio/libobs/obs.h" ]; then
    echo "❌ OBS Studio not found. Run ./setup.sh first."
    exit 1
fi

# Build OBS Studio first if needed
OBS_BUILD_DIR="deps/obs-studio/build"
if [ ! -d "$OBS_BUILD_DIR" ] || [ ! -f "$OBS_BUILD_DIR/libobs/libobs.dylib" ]; then
    echo "📦 Building OBS Studio dependencies..."
    
    cd deps/obs-studio
    
    # Create build directory
    mkdir -p build
    cd build
    
    # Configure OBS Studio with minimal components needed for plugin development
    cmake .. \
        -DCMAKE_BUILD_TYPE="$OBS_BUILD_TYPE" \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DENABLE_UI=OFF \
        -DENABLE_SCRIPTING=OFF \
        -DENABLE_BROWSER=OFF \
        -DENABLE_WEBSOCKET=OFF \
        -DBUILD_TESTS=OFF \
        -DBUILD_FOR_DISTRIBUTION=OFF \
        -G Ninja
    
    # Build only libobs and essential components
    ninja obs-frontend-api libobs
    
    cd ../../../
    echo "✅ OBS Studio built successfully"
else
    echo "✅ OBS Studio already built"
fi

# Now build the plugin
echo "🔌 Building Syphon Server Plugin..."

# Create plugin build directory
mkdir -p "build/$BUILD_TYPE"
cd "build/$BUILD_TYPE"

# Configure plugin with CMake
cmake ../.. \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DSyphon_ROOT="../../deps/Syphon-Framework" \
    -Dlibobs_DIR="../../deps/obs-studio/build/libobs" \
    -DCMAKE_PREFIX_PATH="../../deps/obs-studio/build" \
    -G Ninja

# Build the plugin
ninja

echo "✅ Plugin build complete!"
echo "📍 Plugin binary location: build/$BUILD_TYPE/"
echo ""
echo "📋 Installation:"
echo "   Copy the .plugin bundle to ~/Library/Application Support/obs-studio/plugins/"
echo "   or to /Applications/OBS.app/Contents/PlugIns/ for system-wide installation"
EOF

chmod +x build.sh

print_success "Build script created (./build.sh)"

# Create a cleanup script
print_status "Creating cleanup script..."

cat > clean.sh << 'EOF'
#!/bin/bash

# Cleanup script for OBS Syphon Server Plugin

echo "🧹 Cleaning build artifacts..."

# Remove plugin build directories
rm -rf build/

# Clean OBS Studio build if it exists
if [ -d "deps/obs-studio/build" ]; then
    echo "🧹 Cleaning OBS Studio build artifacts..."
    rm -rf deps/obs-studio/build/
fi

echo "✅ Cleanup complete!"
echo "💡 To rebuild everything from scratch, run ./build.sh"
EOF

chmod +x clean.sh

print_success "Cleanup script created (./clean.sh)"

# Update .gitignore
print_status "Updating .gitignore..."

cat > .gitignore << 'EOF'
# Build artifacts
build/
*.dylib
*.so
*.dll

# CMake
CMakeCache.txt
CMakeFiles/
cmake_install.cmake
Makefile
*.cmake

# IDE files
.vscode/
.idea/
*.xcodeproj/
*.xcworkspace/

# macOS
.DS_Store
*.dSYM/

# Logs
*.log

# Temporary files
*.tmp
*.temp
*~

# Editor backups
*.bak
*.swp
*.swo

# Plugin specific
*.plugin/

# Dependencies (handled as submodules)
# Note: deps/ directory exists but contents are managed by git submodules
deps/*/build/
deps/*/.git/
EOF

print_success ".gitignore updated"

print_success "🎉 Setup complete!"
print_status ""
print_status "📋 Next steps:"
print_status "1. Run ./build.sh to build both OBS Studio and the plugin"
print_status "2. The plugin will be built in build/Debug/ or build/Release/"
print_status "3. Install by copying the .plugin bundle to OBS plugins directory"
print_status ""
print_status "📁 Plugin installation locations:"
print_status "   User: ~/Library/Application Support/obs-studio/plugins/"
print_status "   System: /Applications/OBS.app/Contents/PlugIns/"
print_status ""
print_status "🔧 Build options:"
print_status "   ./build.sh Debug    - Build debug version"
print_status "   ./build.sh Release  - Build release version"
print_status "   ./clean.sh          - Clean all build artifacts"
print_status ""
print_status "📚 Documentation:"
print_status "   README.md contains technical implementation details"
print_status "   See DistroAV plugin for reference patterns"
print_status ""
print_warning "⚠️  Important notes:"
print_warning "   - First build may take 10-15 minutes (building OBS Studio)"
print_warning "   - Subsequent builds will be much faster"
print_warning "   - Make sure you have sufficient disk space (2+ GB for OBS build)"
print_warning "   - Plugin requires OBS Studio 29+ for compatibility"
